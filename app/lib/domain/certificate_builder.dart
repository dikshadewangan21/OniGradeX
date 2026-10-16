import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// Recursively sorted-key JSON. The exact string produced here is what gets hashed AND sent to
/// the server as `canonical_payload`, so server and device never disagree about formatting.
String canonicalJson(Object? v) => jsonEncode(_sorted(v));

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return v.map(_sorted).toList();
  return v;
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

class CertificateInput {
  CertificateInput({
    required this.mandiId,
    required this.farmerPhone,
    required this.latitude,
    required this.longitude,
    required this.modelVersion,
    required this.ruleVersion,
    required this.imageSha256,
    required this.grade,
    required this.onionCount,
    required this.freshPct,
    required this.defectivePct,
    required this.batchConfidence,
    required this.details,
    this.scaleWeightKg,
    this.estimatedWeightKg,
    this.rate,
    this.rateSource,
  });
  final String? mandiId;
  final String? farmerPhone;
  final double latitude, longitude;
  final String modelVersion;
  final int ruleVersion;
  final String imageSha256;
  final String grade;
  final int onionCount;
  final double freshPct, defectivePct, batchConfidence;
  final Map<String, dynamic> details;
  final double? scaleWeightKg;
  final double? estimatedWeightKg;
  final double? rate;
  final String? rateSource;
}

/// Builds the body accepted by POST /api/v1/certificates/sync.
Map<String, dynamic> buildCertificate(CertificateInput c, {DateTime? now}) {
  final t = (now ?? DateTime.now()).toUtc();
  final ts = DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second).toIso8601String(); // second precision, ends in Z
  final core = <String, dynamic>{
    'id': const Uuid().v4(),
    'mandi_id': c.mandiId,
    'farmer_phone': c.farmerPhone,
    'captured_at': ts,
    'latitude': c.latitude,
    'longitude': c.longitude,
    'model_version': c.modelVersion,
    'rule_version': c.ruleVersion,
    'image_sha256': c.imageSha256,
    'grade': c.grade,
    'onion_count': c.onionCount,
    'fresh_pct': c.freshPct,
    'defective_pct': c.defectivePct,
    'batch_confidence': c.batchConfidence,
    'details': c.details,
    'scale_weight_kg': c.scaleWeightKg,
    'estimated_weight_kg': c.estimatedWeightKg,
    'rate_per_kg': c.rate,
    'rate_source': c.rateSource,
  };
  final payload = canonicalJson(core);
  return {...core, 'device_hash': sha256Hex(utf8.encode(payload)), 'canonical_payload': payload};
}

/// Local tamper-evidence check for a stored record (detects edits to the saved body).
bool localHashValid(Map<String, dynamic> body) =>
    sha256Hex(utf8.encode(body['canonical_payload'] as String)) == body['device_hash'];
