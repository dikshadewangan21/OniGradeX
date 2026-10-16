import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Offline store: issued certificates (with sync state), cached grading rule, cached e-NAM price.
class LocalDb {
  LocalDb._(this._db);
  final Database _db;

  static Future<LocalDb> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'onigrader.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE certificates(
          id TEXT PRIMARY KEY, body TEXT NOT NULL, image_path TEXT,
          synced INTEGER NOT NULL DEFAULT 0, image_synced INTEGER NOT NULL DEFAULT 0,
          last_error TEXT, created_at TEXT NOT NULL)''');
        await db.execute('CREATE INDEX ix_cert_synced ON certificates(synced)');
        await db.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT NOT NULL, updated_at TEXT NOT NULL)');
      },
    );
    return LocalDb._(db);
  }

  Future<void> saveCertificate(Map<String, dynamic> body, String imagePath) => _db.insert(
      'certificates',
      {
        'id': body['id'],
        'body': jsonEncode(body),
        'image_path': imagePath,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort);

  Future<List<Map<String, dynamic>>> certificates() async {
    final rows = await _db.query('certificates', orderBy: 'created_at DESC');
    return rows.map(_decode).toList();
  }

  Future<List<Map<String, dynamic>>> pending() async {
    final rows = await _db.query('certificates', where: 'synced = 0 OR image_synced = 0', orderBy: 'created_at');
    return rows.map(_decode).toList();
  }

  Map<String, dynamic> _decode(Map<String, Object?> r) => {
        'body': jsonDecode(r['body'] as String),
        'image_path': r['image_path'],
        'synced': r['synced'] == 1,
        'image_synced': r['image_synced'] == 1,
        'last_error': r['last_error'],
      };

  Future<void> markSynced(String id) =>
      _db.update('certificates', {'synced': 1, 'last_error': null}, where: 'id = ?', whereArgs: [id]);

  Future<void> markImageSynced(String id) =>
      _db.update('certificates', {'image_synced': 1}, where: 'id = ?', whereArgs: [id]);

  Future<void> markError(String id, String err) =>
      _db.update('certificates', {'last_error': err}, where: 'id = ?', whereArgs: [id]);

  Future<void> putKv(String k, Object v) => _db.insert(
      'kv', {'k': k, 'v': jsonEncode(v), 'updated_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<({dynamic value, DateTime updatedAt})?> getKv(String k) async {
    final r = await _db.query('kv', where: 'k = ?', whereArgs: [k]);
    if (r.isEmpty) return null;
    return (value: jsonDecode(r.first['v'] as String), updatedAt: DateTime.parse(r.first['updated_at'] as String));
  }
}
