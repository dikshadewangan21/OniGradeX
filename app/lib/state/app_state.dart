import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/api_client.dart';
import '../data/local_db.dart';
import '../ml/model_loader.dart';

class AppState extends ChangeNotifier {
  late final ApiClient api;
  late final LocalDb db;
  Session? session;
  ModelStatus model = ModelStatus.unavailable(['Not loaded yet']);
  Map<String, dynamic>? rule; // active grading rule {version, definition}
  String? ruleNote; // why rule is missing
  Map<String, dynamic>? profile;
  bool ready = false;
  bool syncing = false;
  int pendingCount = 0;
  String? lastSyncError;
  StreamSubscription? _conn;
  Locale currentLocale = const Locale('en');

  void setLocale(Locale loc) {
    currentLocale = loc;
    notifyListeners();
  }

  Future<void> init() async {
    db = await LocalDb.open();
    if (AppConfig.isConfigured) {
      api = ApiClient(AppConfig.apiBaseUrl);
      session = await api.restore();
    }
    model = await loadModelStatus();
    if (session != null) await refreshContext();
    ready = true;
    notifyListeners();
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) syncPending();
    });
  }

  @override
  void dispose() {
    _conn?.cancel();
    super.dispose();
  }

  String get role => session?.role ?? '';

  Future<void> login(String phone, String password) async {
    session = await api.login(phone, password);
    await refreshContext();
    notifyListeners();
  }

  Future<void> logout() async {
    await api.logout();
    session = null;
    profile = null;
    rule = null;
    notifyListeners();
  }

  /// Fetch profile + active rule when online; fall back to the cached copies when offline.
  Future<void> refreshContext() async {
    try {
      profile = await api.me();
      await db.putKv('profile', profile!);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await logout();
        return;
      }
      final c = await db.getKv('profile');
      if (c != null) profile = Map<String, dynamic>.from(c.value as Map);
    }
    try {
      rule = await api.activeRule();
      ruleNote = null;
      await db.putKv('rule', rule!);
    } on ApiException catch (e) {
      final c = await db.getKv('rule');
      if (c != null) {
        rule = Map<String, dynamic>.from(c.value as Map);
        ruleNote = e.isNetwork ? 'Offline: using grading rules cached ${c.updatedAt.toLocal()}' : null;
      } else {
        rule = null;
        ruleNote = e.status == 404
            ? 'No grading rules have been published by the admin yet.'
            : 'Grading rules unavailable: ${e.message}. Connect once to download them.';
      }
    }
    await _countPending();
    notifyListeners();
  }

  Future<void> _countPending() async {
    pendingCount = (await db.pending()).length;
  }

  /// Uploads every unsynced certificate, then its image. Idempotent; safe to call repeatedly.
  Future<void> syncPending() async {
    if (syncing || session == null || !(role == 'officer' || role == 'admin')) return;
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    try {
      for (final rec in await db.pending()) {
        final body = Map<String, dynamic>.from(rec['body'] as Map);
        final id = body['id'] as String;
        try {
          if (!(rec['synced'] as bool)) {
            await api.syncCertificate(body);
            await db.markSynced(id);
          }
          if (!(rec['image_synced'] as bool)) {
            final path = rec['image_path'] as String?;
            if (path != null && File(path).existsSync()) {
              await api.uploadImage(id, path);
            }
            await db.markImageSynced(id);
          }
        } on ApiException catch (e) {
          if (e.isNetwork) {
            lastSyncError = e.message;
            break; // offline: stop, retry on next connectivity change
          }
          await db.markError(id, e.message); // server rejected this one; keep going with the rest
          lastSyncError = 'Some certificates were rejected by the server.';
        }
      }
    } finally {
      await _countPending();
      syncing = false;
      notifyListeners();
    }
  }
}
