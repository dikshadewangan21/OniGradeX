// Phase 3 Fixture-based integration test
// PROVES PLUMBING ONLY, NOT THE MODEL.
// Feeds hand-written detection lists through:
// summarize -> evaluateGrade -> buildCertificate -> POST /certificates/sync -> GET /verify/{id}
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onigrader/data/api_client.dart';
import 'package:onigrader/domain/certificate_builder.dart';
import 'package:onigrader/domain/grading.dart';
import 'package:onigrader/ml/postprocess.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock secure storage platform channel for tests
  final Map<String, String> secureStorage = {};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = call.arguments as Map?;
      final key = args?['key'] as String?;
      switch (call.method) {
        case 'write':
          if (key != null) secureStorage[key] = args!['value'] as String;
          return null;
        case 'read':
          return key != null ? secureStorage[key] : null;
        case 'deleteAll':
          secureStorage.clear();
          return null;
        default:
          return null;
      }
    },
  );

  group('Phase 3: Fixture-based plumbing integration test (PROVES PLUMBING, NOT MODEL)', () {
    const baseUrl = 'http://127.0.0.1:8009';
    late final ApiClient api;

    setUpAll(() async {
      HttpOverrides.global = null;
      api = ApiClient(baseUrl);
    });

    test('Full plumbing roundtrip: summarize -> evaluateGrade -> buildCertificate -> POST /certificates/sync -> GET /verify/{id}', () async {
      // 1. Hand-written detection list (TEST FIXTURE ONLY - no fake model inference)
      // 9 fresh onions (class 0) + 1 rot onion (class 1)
      final detections = <Detection>[
        const Detection(0, 0.95),
        const Detection(0, 0.94),
        const Detection(0, 0.93),
        const Detection(0, 0.96),
        const Detection(0, 0.92),
        const Detection(0, 0.95),
        const Detection(0, 0.91),
        const Detection(0, 0.97),
        const Detection(0, 0.93),
        const Detection(1, 0.90), // defect: rot
      ];

      final classes = <Map<String, dynamic>>[
        {'id': 0, 'name': 'fresh', 'role': 'fresh'},
        {'id': 1, 'name': 'rot', 'role': 'defect', 'detail_key': 'rot_pct'},
      ];

      const scoreThreshold = 0.25;

      // 2. summarize detections
      final summary = summarize(detections, classes, scoreThreshold);
      expect(summary.onionCount, 10);
      expect(summary.freshPct, 90.0);
      expect(summary.defectivePct, 10.0);
      expect(summary.details['rot_pct'], 10.0);
      expect(summary.batchConfidence, greaterThan(0.90));

      // 3. evaluateGrade against rule definition
      final ruleDefinition = <String, dynamic>{
        'min_confidence': 0.5,
        'reject_grade': 'Rejected',
        'grades': [
          {'grade': 'A', 'max_defective_pct': 10},
          {'grade': 'URS', 'max_defective_pct': 30, 'max_rot_pct': 5},
        ],
      };

      final grade = evaluateGrade(ruleDefinition, summary.defectivePct, summary.details);
      expect(grade, 'A');

      // 4. buildCertificate
      final certInput = CertificateInput(
        mandiId: null,
        farmerPhone: '9000000002',
        latitude: 20.0,
        longitude: 74.0,
        modelVersion: 'test-fixture-v1', // Declared in app/test/fixtures/model_metadata.json
        ruleVersion: 1,
        imageSha256: 'a' * 64,
        grade: grade,
        onionCount: summary.onionCount,
        freshPct: summary.freshPct,
        defectivePct: summary.defectivePct,
        batchConfidence: summary.batchConfidence,
        details: summary.details,
      );

      final certPayload = buildCertificate(certInput);
      expect(certPayload['device_hash'], isNotNull);
      expect(certPayload['canonical_payload'], isNotNull);

      // Verify local hash integrity
      expect(localHashValid(certPayload), isTrue);

      // 5. Authenticate with test backend as officer
      final session = await api.login('9000000003', 'officerpassword123');
      expect(session.role, 'officer');

      // 6. POST /api/v1/certificates/sync
      final syncResult = await api.syncCertificate(certPayload);
      expect(syncResult['id'], certPayload['id']);
      expect(syncResult['grade'], 'A');
      expect(syncResult['server_signature'], isNotNull);
      expect((syncResult['server_signature'] as String).length, 64);

      // 7. GET /api/v1/verify/{id} (public verification, no personal data)
      final verifyClient = ApiClient(baseUrl);
      final verifyResult = await verifyClient.verify(certPayload['id'] as String);

      expect(verifyResult['valid'], isTrue);
      expect(verifyResult['certificate_id'], certPayload['id']);
    });
  });
}
