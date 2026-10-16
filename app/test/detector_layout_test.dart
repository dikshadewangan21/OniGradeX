import 'package:flutter_test/flutter_test.dart';
import 'package:onigrader/ml/detector.dart';
import 'package:onigrader/ml/postprocess.dart';

void main() {
  group('Phase 4: Detector layout & NMS unit tests', () {
    test('computeIoU calculates precise intersection over union', () {
      // 1. Identical boxes
      expect(Detector.computeIoU([0.1, 0.1, 0.5, 0.5], [0.1, 0.1, 0.5, 0.5]), closeTo(1.0, 1e-6));

      // 2. Disjoint boxes
      expect(Detector.computeIoU([0.0, 0.0, 0.2, 0.2], [0.5, 0.5, 0.8, 0.8]), 0.0);

      // 3. Known overlap:
      // Box A: [0.0, 0.0, 0.4, 0.4] -> area = 0.16
      // Box B: [0.2, 0.0, 0.6, 0.4] -> area = 0.16
      // Intersection: [0.2, 0.0, 0.4, 0.4] -> w = 0.2, h = 0.4, area = 0.08
      // Union = 0.16 + 0.16 - 0.08 = 0.24
      // IoU = 0.08 / 0.24 = 1/3 ~ 0.333333
      expect(Detector.computeIoU([0.0, 0.0, 0.4, 0.4], [0.2, 0.0, 0.6, 0.4]), closeTo(1.0 / 3.0, 1e-5));
    });

    test('applyNms suppresses overlapping candidates of the same class', () {
      final candidates = <Detection>[
        const Detection(0, 0.95, [0.1, 0.1, 0.5, 0.5]), // High confidence
        const Detection(0, 0.80, [0.12, 0.12, 0.52, 0.52]), // Heavily overlapping duplicate (>0.8 IoU)
        const Detection(0, 0.90, [0.6, 0.6, 0.9, 0.9]), // Separate onion
        const Detection(1, 0.70, [0.1, 0.1, 0.5, 0.5]), // Different class (rot) on same location
      ];

      final kept = Detector.applyNms(candidates, 0.45);

      // Should keep the 0.95 (class 0), 0.90 (class 0), and 0.70 (class 1)
      // The 0.80 duplicate of class 0 should be suppressed.
      expect(kept.length, 3);
      expect(kept.any((d) => d.score == 0.95 && d.classId == 0), isTrue);
      expect(kept.any((d) => d.score == 0.90 && d.classId == 0), isTrue);
      expect(kept.any((d) => d.score == 0.70 && d.classId == 1), isTrue);
      expect(kept.any((d) => d.score == 0.80), isFalse);
    });

    test('parseUnifiedOutputs parses standard [1, N, 5+C] tensor (with objectness)', () {
      // 2 candidates, 2 classes (id 0 = fresh, id 1 = defect)
      // Features: [cx, cy, w, h, obj, p0, p1] -> length 7
      // Candidate 0: center (0.3, 0.3), w=0.2, h=0.2, obj=1.0, p0=0.9, p1=0.1
      // Candidate 1: center (0.7, 0.7), w=0.2, h=0.2, obj=0.9, p0=0.1, p1=0.8
      final raw = <double>[
        0.3, 0.3, 0.2, 0.2, 1.0, 0.9, 0.1,
        0.7, 0.7, 0.2, 0.2, 0.9, 0.1, 0.8,
      ];
      final shape = [1, 2, 7];
      final unifiedMeta = {
        'index': 0,
        'format': 'xywh_norm',
        'has_objectness': true,
        'transposed': false,
      };

      final dets = Detector.parseUnifiedOutputs(
        rawValues: raw,
        shape: shape,
        unifiedMeta: unifiedMeta,
        inputWidth: 640,
        inputHeight: 640,
        scoreThreshold: 0.25,
        classIds: [0, 1],
      );

      expect(dets.length, 2);
      expect(dets[0].classId, 0);
      expect(dets[0].score, closeTo(0.9, 1e-4));
      expect(dets[0].box![0], closeTo(0.2, 1e-4)); // x1 = 0.3 - 0.1 = 0.2
      expect(dets[0].box![2], closeTo(0.4, 1e-4)); // x2 = 0.3 + 0.1 = 0.4

      expect(dets[1].classId, 1);
      expect(dets[1].score, closeTo(0.72, 1e-4)); // 0.9 * 0.8 = 0.72
    });

    test('parseUnifiedOutputs parses transposed [1, 4+C, N] tensor (YOLOv8 style, no objectness)', () {
      // 2 candidates, 2 classes (4+2 = 6 features)
      // Transposed layout: [1, 6, 2] -> raw is ordered by features:
      // f0 (cx): [0.3, 0.7]
      // f1 (cy): [0.3, 0.7]
      // f2 (w):  [0.2, 0.2]
      // f3 (h):  [0.2, 0.2]
      // f4 (p0): [0.92, 0.05]
      // f5 (p1): [0.03, 0.88]
      final raw = <double>[
        0.3, 0.7, // cx
        0.3, 0.7, // cy
        0.2, 0.2, // w
        0.2, 0.2, // h
        0.92, 0.05, // class 0
        0.03, 0.88, // class 1
      ];
      final shape = [1, 6, 2];
      final unifiedMeta = {
        'index': 0,
        'format': 'xywh_norm',
        'has_objectness': false,
        'transposed': true,
      };

      final dets = Detector.parseUnifiedOutputs(
        rawValues: raw,
        shape: shape,
        unifiedMeta: unifiedMeta,
        inputWidth: 640,
        inputHeight: 640,
        scoreThreshold: 0.25,
        classIds: [0, 1],
      );

      expect(dets.length, 2);
      expect(dets[0].classId, 0);
      expect(dets[0].score, closeTo(0.92, 1e-4));
      expect(dets[1].classId, 1);
      expect(dets[1].score, closeTo(0.88, 1e-4));
    });

    test('parseSeparateOutputs parses separate boxes, scores, class_ids', () {
      final boxes = <double>[
        0.1, 0.1, 0.3, 0.3, // xyxy_norm
        0.5, 0.5, 0.8, 0.8,
      ];
      final scores = <double>[0.91, 0.85];
      final classIds = <double>[0, 1];

      final dets = Detector.parseSeparateOutputs(
        boxes: boxes,
        scores: scores,
        classIds: classIds,
        format: 'xyxy_norm',
        scoreThreshold: 0.25,
      );

      expect(dets.length, 2);
      expect(dets[0].classId, 0);
      expect(dets[0].score, 0.91);
      expect(dets[0].box, [0.1, 0.1, 0.3, 0.3]);
      expect(dets[1].classId, 1);
      expect(dets[1].score, 0.85);
      expect(dets[1].box, [0.5, 0.5, 0.8, 0.8]);
    });
  });
}
