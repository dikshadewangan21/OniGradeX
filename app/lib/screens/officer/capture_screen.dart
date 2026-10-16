import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../domain/certificate_builder.dart';
import '../../domain/grading.dart';
import '../../ml/detector.dart';
import '../../ml/postprocess.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../certificate_screen.dart';

/// Flow: camera -> location -> on-device inference -> review -> issue certificate (saved locally, synced later).
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  String _stage = 'idle'; // idle | working | review | recapture | error
  String? _error;
  File? _image;
  Uint8List? _bytes;
  Position? _pos;
  DetectionResult? _result;
  final _farmer = TextEditingController(), _weight = TextEditingController();
  double? _rate;
  String? _rateSource, _rateNote;

  Future<void> _capture() async {
    final s = context.read<AppState>();
    setState(() {
      _stage = 'working';
      _error = null;
    });
    try {
      // Camera only (no gallery): a certificate must be backed by a photo taken now, at this place.
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 95);
      if (shot == null) {
        setState(() => _stage = 'idle');
        return;
      }
      _pos = await _locate();
      final dir = await getApplicationDocumentsDirectory();
      final saved = await File(shot.path).copy(p.join(dir.path, 'batch_${DateTime.now().millisecondsSinceEpoch}.jpg'));
      _image = saved;
      _bytes = await saved.readAsBytes();
      final detector = await Detector.create(s.model);
      try {
        _result = await detector.run(_bytes!);
      } finally {
        detector.close();
      }
      final minConf = ((s.rule!['definition'] as Map)['min_confidence'] as num).toDouble();
      if (_result!.summary.batchConfidence < minConf) {
        setState(() => _stage = 'recapture');
        return;
      }
      await _loadRate();
      setState(() => _stage = 'review');
    } on ContractError catch (e) {
      setState(() {
        _stage = 'recapture';
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _stage = 'error';
        _error = e.toString();
      });
    }
  }

  Future<Position> _locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services: certificates must be geo-tagged.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw StateError('Location permission is required to issue a geo-tagged certificate.');
    }
    return Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 20));
  }

  /// Live price when online, cached (<=24h) when not, nothing otherwise. Never a made-up rate.
  Future<void> _loadRate() async {
    final s = context.read<AppState>();
    final mandiName = await _mandiName(s);
    if (mandiName == null) {
      _rateNote = 'No mandi assigned to your account; payout not computed.';
      return;
    }
    try {
      final r = await s.api.enamPrice(mandiName);
      _rate = (r['modal_price_per_quintal'] as num).toDouble() / 100; // quintal -> kg
      _rateSource = 'e-NAM ${r['source']} ${r['price_date']}';
      await s.db.putKv('rate:$mandiName', {'rate': _rate, 'source': _rateSource});
    } on ApiException catch (e) {
      final c = await s.db.getKv('rate:$mandiName');
      if (c != null && DateTime.now().difference(c.updatedAt) < const Duration(hours: 24)) {
        _rate = (c.value['rate'] as num).toDouble();
        _rateSource = '${c.value['source']} (cached)';
        _rateNote = 'Offline: using price cached ${c.updatedAt.toLocal()}';
      } else {
        _rateNote = 'No price available (${e.message}). Certificate will be issued without payout.';
      }
    }
  }

  Future<String?> _mandiName(AppState s) async {
    final id = s.profile?['mandi_id'];
    if (id == null) return null;
    try {
      final list = await s.api.mandis();
      await s.db.putKv('mandis', list);
      return (list.firstWhere((m) => m['id'] == id, orElse: () => null) as Map?)?['name'] as String?;
    } on ApiException {
      final c = await s.db.getKv('mandis');
      if (c == null) return null;
      return ((c.value as List).firstWhere((m) => m['id'] == id, orElse: () => null) as Map?)?['name'] as String?;
    }
  }

  Future<void> _issue() async {
    final s = context.read<AppState>();
    final r = _result!.summary;
    final defn = Map<String, dynamic>.from(s.rule!['definition'] as Map);

    // 5b. Reference-based diameter calculation
    final refSizeMm = (defn['reference_object_size_mm'] as num?)?.toDouble() ?? 25.0;
    final refClasses = s.model.classes
        .where((c) => c['role'] == 'reference' || (c['name'] as String).toLowerCase().contains('reference') || (c['name'] as String).toLowerCase().contains('coin'))
        .map((c) => c['id'] as int)
        .toSet();
    final refDets = _result!.detections.where((d) => refClasses.contains(d.classId)).toList();
    if (refDets.isNotEmpty && refDets.first.box != null) {
      final refBox = refDets.first.box!;
      final refW = (refBox[2] - refBox[0]).abs();
      if (refW > 0.001) {
        final mmPerNormWidth = refSizeMm / refW;
        final onionDiams = <double>[];
        for (final d in _result!.detections) {
          if (d.box != null && !refClasses.contains(d.classId)) {
            final wNorm = (d.box![2] - d.box![0]).abs();
            final hNorm = (d.box![3] - d.box![1]).abs();
            onionDiams.add(((wNorm + hNorm) / 2.0) * mmPerNormWidth);
          }
        }
        if (onionDiams.isNotEmpty) {
          onionDiams.sort();
          r.details['median_diameter_mm'] = double.parse(onionDiams[onionDiams.length ~/ 2].toStringAsFixed(1));
        }
      }
    } else {
      // Refuse to output mm without a detected reference object
      r.details.remove('median_diameter_mm');
    }

    // 5c. Weight check via volume / depth estimate
    double? estimatedWeightKg;
    final density = (defn['density_constant_g_cm3'] as num?)?.toDouble() ?? 0.96;
    if (r.details.containsKey('estimated_volume_cm3')) {
      final vol = (r.details['estimated_volume_cm3'] as num).toDouble();
      estimatedWeightKg = double.parse(((vol * density) / 1000.0).toStringAsFixed(2));
    }

    // 5d. Shelf life only if model metadata declares it
    final outs = s.model.metadata?['outputs'] as Map? ?? const {};
    if (!outs.containsKey('shelf_life')) {
      r.details.remove('shelf_life_days');
    }

    final grade = evaluateGrade(defn, r.defectivePct, r.details);
    final phone = _farmer.text.trim();
    final weight = double.tryParse(_weight.text.trim());

    final body = buildCertificate(CertificateInput(
      mandiId: s.profile?['mandi_id'] as String?,
      farmerPhone: phone.isEmpty ? null : phone,
      latitude: _pos!.latitude,
      longitude: _pos!.longitude,
      modelVersion: s.model.version!,
      ruleVersion: s.rule!['version'] as int,
      imageSha256: sha256.convert(_bytes!).toString(),
      grade: grade,
      onionCount: r.onionCount,
      freshPct: r.freshPct,
      defectivePct: r.defectivePct,
      batchConfidence: r.batchConfidence,
      details: r.details,
      scaleWeightKg: weight,
      estimatedWeightKg: estimatedWeightKg,
      rate: _rate,
      rateSource: _rateSource,
    ));
    await s.db.saveCertificate(body, _image!.path);
    final local = (await s.db.certificates()).firstWhere((c) => (c['body'] as Map)['id'] == body['id']);
    s.syncPending(); // fire and forget; failures leave it queued
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CertificateScreen(local: local)));
  }

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return RegExp(r'^\+?[0-9]{10,15}$').hasMatch(v.trim()) ? null : 'Enter 10–15 digits';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grade a batch'),
        actions: const [LanguageSwitcherAction()],
      ),
      body: switch (_stage) {
        'working' => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Analysing on this device…')])),
        'recapture' => ErrorView(
            message: _error ?? 'Confidence too low for a reliable grade. Retake the photo in better light, closer, with fewer overlapping onions.',
            onRetry: _capture),
        'error' => ErrorView(message: _error ?? 'Something went wrong', onRetry: _capture),
        'review' => _review(s),
        _ => const EmptyView('Take one clear photo of the whole batch.\nNo grade is shown until the on-device model has analysed it.').withAction(
            FilledButton.icon(onPressed: _capture, icon: const Icon(Icons.camera_alt), label: const Text('Open camera'))),
      },
    );
  }

  Widget _review(AppState s) {
    final r = _result!.summary;
    final defn = Map<String, dynamic>.from(s.rule!['definition'] as Map);
    final grade = evaluateGrade(defn, r.defectivePct, r.details);
    final defectIds = {for (final c in s.model.classes) if (c['role'] == 'defect') c['id'] as int};
    final payout = _rate == null ? null : (_rate! * r.freshPct / 100);
    final hasHeatmap = _result?.heatmap != null;

    return ListView(padding: const EdgeInsets.all(16), children: [
      AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(fit: StackFit.expand, children: [
          Image.file(_image!, fit: BoxFit.fill),
          if (hasHeatmap)
            Opacity(opacity: 0.6, child: Image.memory(_result!.heatmap!, fit: BoxFit.fill)),
          CustomPaint(painter: DetectionBoxPainter(_result!.detections, defectIds)),
        ]),
      ),
      const SizedBox(height: 4),
      Text(
        hasHeatmap
            ? 'Heatmap overlay rendered from model heatmap output. Red/green boxes show detections.'
            : 'Red = defective onion, green = fresh. Boxes show what the model detected; no model heatmap output declared.',
        style: const TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 16),
      Text('Grade $grade', style: Theme.of(context).textTheme.headlineMedium),
      Text('${r.onionCount} onions · ${r.freshPct}% fresh · ${r.defectivePct}% defective'),
      for (final e in r.details.entries) Text('${e.key}: ${e.value}'),
      if (!r.details.containsKey('median_diameter_mm'))
        const Text('Median diameter: Not available (no reference object detected in frame)', style: TextStyle(color: Colors.grey)),
      Text('Model confidence (mean): ${(r.batchConfidence * 100).toStringAsFixed(1)}%'),
      const SizedBox(height: 8),
      if (payout != null) Text('Indicative payout: ₹${payout.toStringAsFixed(2)}/kg  ($_rateSource)') else Text(_rateNote ?? 'Payout not computed.'),
      if (_rate != null && _rateNote != null) Text(_rateNote!),
      const SizedBox(height: 16),
      TextFormField(
        controller: _farmer,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Farmer phone (optional, lets them see this certificate)', border: OutlineInputBorder()),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: _validatePhone,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _weight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Scale weight in kg (optional)', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _validatePhone(_farmer.text) == null ? _issue : null,
        child: const Text('Issue certificate'),
      ),
      TextButton(onPressed: _capture, child: const Text('Retake photo')),
    ]);
  }
}

extension on Widget {
  Widget withAction(Widget action) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [this, const SizedBox(height: 12), action]),
      );
}
