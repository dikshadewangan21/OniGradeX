// Run from app/:  flutter test
// NOT RUN in the authoring environment (no Flutter SDK available there).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onigrader/domain/certificate_builder.dart';
import 'package:onigrader/domain/grading.dart';
import 'package:onigrader/ml/model_loader.dart';
import 'package:onigrader/ml/postprocess.dart';

void main() {
  group('postprocess parity with ml/contract/postprocess_vectors.json', () {
    final vec = jsonDecode(File('../ml/contract/postprocess_vectors.json').readAsStringSync()) as Map<String, dynamic>;
    final classes = (vec['classes'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    for (final c in (vec['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final dets = (c['detections'] as List)
            .map((d) => Detection((d['class_id'] as num).toInt(), (d['score'] as num).toDouble()))
            .toList();
        final thr = (c['score_threshold'] as num).toDouble();
        if (c['expect_error'] == true) {
          expect(() => summarize(dets, classes, thr), throwsA(isA<ContractError>()));
          return;
        }
        final got = summarize(dets, classes, thr);
        final want = c['expect'] as Map<String, dynamic>;
        expect(got.onionCount, want['onion_count']);
        expect(got.freshPct, closeTo((want['fresh_pct'] as num).toDouble(), 1e-9));
        expect(got.defectivePct, closeTo((want['defective_pct'] as num).toDouble(), 1e-9));
        expect(got.batchConfidence, closeTo((want['batch_confidence'] as num).toDouble(), 1e-4));
        (want['details'] as Map).forEach((k, v) => expect(got.details[k], closeTo((v as num).toDouble(), 1e-9)));
      });
    }
  });

  group('grading rule evaluation', () {
    final rule = {
      'reject_grade': 'Rejected',
      'grades': [
        {'grade': 'A', 'max_defective_pct': 10},
        {'grade': 'URS', 'max_defective_pct': 30, 'max_rot_pct': 5},
      ]
    };
    test('first matching grade wins', () => expect(evaluateGrade(rule, 5, {}), 'A'));
    test('falls through to next', () => expect(evaluateGrade(rule, 20, {'rot_pct': 2.0}), 'URS'));
    test('missing detail never passes a detail-limited grade', () => expect(evaluateGrade(rule, 20, {}), 'Rejected'));
    test('too defective is rejected', () => expect(evaluateGrade(rule, 60, {'rot_pct': 1.0}), 'Rejected'));
  });

  group('certificate integrity', () {
    CertificateInput input() => CertificateInput(
          mandiId: null, farmerPhone: '9000000003', latitude: 21.25, longitude: 81.63,
          modelVersion: 'v1', ruleVersion: 1, imageSha256: 'a' * 64, grade: 'A', onionCount: 10,
          freshPct: 90, defectivePct: 10, batchConfidence: 0.9, details: {'rot_pct': 10.0},
        );

    test('canonicalJson sorts keys recursively', () {
      expect(canonicalJson({'b': 1, 'a': {'d': 1, 'c': 2}}), '{"a":{"c":2,"d":1},"b":1}');
    });
    test('hash matches payload and detects edits', () {
      final b = buildCertificate(input(), now: DateTime.utc(2026, 10, 12, 9, 0, 0));
      expect(localHashValid(b), isTrue);
      expect(b['captured_at'], '2026-10-12T09:00:00.000Z');
      final tampered = Map<String, dynamic>.from(b);
      tampered['canonical_payload'] = (b['canonical_payload'] as String).replaceAll('"grade":"A"', '"grade":"B"');
      expect(localHashValid(tampered), isFalse);
    });
    test('payload contains every key the server cross-checks', () {
      final b = buildCertificate(input());
      final p = jsonDecode(b['canonical_payload'] as String) as Map;
      for (final k in ['id', 'mandi_id', 'farmer_phone', 'captured_at', 'latitude', 'longitude', 'model_version', 'rule_version',
        'image_sha256', 'grade', 'onion_count', 'fresh_pct', 'defective_pct', 'batch_confidence', 'details', 'scale_weight_kg',
        'estimated_weight_kg', 'rate_per_kg', 'rate_source']) {
        expect(p.containsKey(k), isTrue, reason: k);
      }
    });
  });

  group('metadata validation', () {
    Map<String, dynamic> ok() => {
          'model_name': 'm', 'version': '1', 'task': 'detection',
          'input': {'width': 64, 'height': 64, 'dtype': 'float32', 'layout': 'NHWC'},
          'outputs': {'boxes': {}, 'scores': {}, 'class_ids': {}},
          'preprocessing': {}, 'postprocess': {'score_threshold': 0.25},
          'classes': [
            {'id': 0, 'name': 'fresh', 'role': 'fresh'},
            {'id': 1, 'name': 'rot', 'role': 'defect'}
          ],
        };
    test('valid', () => expect(validateMetadata(ok()), isEmpty));
    test('placeholder rejected', () {
      final m = ok()..['model_name'] = 'REPLACE_ME';
      expect(validateMetadata(m), isNotEmpty);
    });
    test('missing keys', () => expect(validateMetadata({'version': '1'}), isNotEmpty));
  });
}
