import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'model_loader.dart';
import 'postprocess.dart';

class DetectionResult {
  DetectionResult(this.detections, this.summary, {this.heatmap});
  final List<Detection> detections;
  final BatchSummary summary;
  final Uint8List? heatmap;
}

/// Runs the installed TFLite model per ml/contract.
/// Supports both separate tensors (boxes, scores, class_ids) and unified tensors
/// (YOLOv5/v7/v8/v11 styles: [1, N, 5+C], [1, N, 4+C], [1, 5+C, N], [1, 4+C, N]) with on-device NMS.
class Detector {
  Detector._(this._interp, this._status);
  final Interpreter _interp;
  final ModelStatus _status;

  static Future<Detector> create(ModelStatus status) async {
    if (!status.ready) throw StateError('Model not installed: ${status.problems.join('; ')}');
    final interp = await Interpreter.fromAsset(modelAsset);
    return Detector._(interp, status);
  }

  void close() => _interp.close();

  Future<DetectionResult> run(Uint8List jpegOrPng) async {
    final meta = _status.metadata!;
    final input = meta['input'] as Map;
    final w = input['width'] as int, h = input['height'] as int;
    final decoded = img.decodeImage(jpegOrPng);
    if (decoded == null) throw StateError('Could not decode image');
    final pre = meta['preprocessing'] as Map;
    var src = img.bakeOrientation(decoded);
    final resized = (pre['resize'] == 'letterbox') ? _letterbox(src, w, h) : img.copyResize(src, width: w, height: h);

    final norm = pre['normalize'] as Map;
    final mean = (norm['mean'] as List).map((e) => (e as num).toDouble()).toList();
    final std = (norm['std'] as List).map((e) => (e as num).toDouble()).toList();
    final scale = (norm['scale'] as num?)?.toDouble() ?? 1.0;
    final bgr = input['color_order'] == 'BGR';
    final asFloat = input['dtype'] == 'float32';

    final tensor = asFloat ? Float32List(w * h * 3) : Uint8List(w * h * 3);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final px = resized.getPixel(x, y);
        final ch = bgr ? [px.b, px.g, px.r] : [px.r, px.g, px.b];
        for (var c = 0; c < 3; c++) {
          if (asFloat) {
            (tensor as Float32List)[i++] = (ch[c].toDouble() * scale - mean[c]) / std[c];
          } else {
            (tensor as Uint8List)[i++] = ch[c].toInt();
          }
        }
      }
    }
    final inputObj = (tensor as dynamic).reshape([1, h, w, 3]);

    final outs = meta['outputs'] as Map;
    final outTensors = _interp.getOutputTensors();
    final buffers = <int, Object>{
      for (var k = 0; k < outTensors.length; k++) k: _alloc(outTensors[k].shape),
    };
    _interp.runForMultipleInputs([inputObj], buffers);

    final post = meta['postprocess'] as Map? ?? const {};
    final nmsInModel = post['nms_in_model'] as bool? ?? false;
    final nmsIouThreshold = (post['nms_iou_threshold'] as num?)?.toDouble() ?? 0.45;
    final scoreThreshold = _status.scoreThreshold;

    final layout = outs['layout'] as String? ?? (outs.containsKey('unified') ? 'unified' : 'separate');
    List<Detection> dets;

    if (layout == 'unified') {
      final uMeta = outs['unified'] as Map? ?? outs;
      final uIdx = uMeta['index'] as int? ?? 0;
      final uShape = outTensors[uIdx].shape;
      final rawValues = _flatten(buffers[uIdx]!);
      final classIds = _status.classes.map((c) => c['id'] as int).toList();
      dets = parseUnifiedOutputs(
        rawValues: rawValues,
        shape: uShape,
        unifiedMeta: Map<String, dynamic>.from(uMeta),
        inputWidth: w,
        inputHeight: h,
        scoreThreshold: scoreThreshold,
        classIds: classIds,
      );
    } else {
      final bIdx = (outs['boxes'] as Map)['index'] as int;
      final sIdx = (outs['scores'] as Map)['index'] as int;
      final cIdx = (outs['class_ids'] as Map)['index'] as int;
      final boxes = _flatten(buffers[bIdx]!);
      final scores = _flatten(buffers[sIdx]!);
      final classIds = _flatten(buffers[cIdx]!);
      final format = (outs['boxes'] as Map)['format'] as String;
      dets = parseSeparateOutputs(
        boxes: boxes,
        scores: scores,
        classIds: classIds,
        format: format,
        scoreThreshold: scoreThreshold,
      );
    }

    if (!nmsInModel) {
      dets = applyNms(dets, nmsIouThreshold);
    }

    Uint8List? heatmapBytes;
    if (outs.containsKey('heatmap')) {
      final hIdx = (outs['heatmap'] as Map)['index'] as int?;
      if (hIdx != null && buffers.containsKey(hIdx)) {
        heatmapBytes = _generateHeatmapOverlay(_flatten(buffers[hIdx]!), outTensors[hIdx].shape, w, h);
      }
    }

    final kept = dets.where((d) => d.score >= scoreThreshold).toList();
    final summary = summarize(kept, _status.classes, scoreThreshold);
    return DetectionResult(kept, summary, heatmap: heatmapBytes);
  }

  /// Greedy Non-Maximum Suppression (NMS) per class.
  static List<Detection> applyNms(List<Detection> detections, double iouThreshold) {
    if (detections.length <= 1) return detections;
    final sorted = List<Detection>.from(detections)..sort((a, b) => b.score.compareTo(a.score));
    final kept = <Detection>[];
    final byClass = <int, List<Detection>>{};
    for (final d in sorted) {
      byClass.putIfAbsent(d.classId, () => []).add(d);
    }
    for (final classDets in byClass.values) {
      final classKept = <Detection>[];
      for (final d in classDets) {
        if (d.box == null) {
          classKept.add(d);
          continue;
        }
        var suppress = false;
        for (final k in classKept) {
          if (k.box != null && computeIoU(k.box!, d.box!) > iouThreshold) {
            suppress = true;
            break;
          }
        }
        if (!suppress) classKept.add(d);
      }
      kept.addAll(classKept);
    }
    return kept;
  }

  /// Calculates IoU between two normalised boxes [x1, y1, x2, y2].
  static double computeIoU(List<double> boxA, List<double> boxB) {
    final x1 = math.max(boxA[0], boxB[0]);
    final y1 = math.max(boxA[1], boxB[1]);
    final x2 = math.min(boxA[2], boxB[2]);
    final y2 = math.min(boxA[3], boxB[3]);
    final interW = math.max(0.0, x2 - x1);
    final interH = math.max(0.0, y2 - y1);
    final interArea = interW * interH;
    final areaA = math.max(0.0, boxA[2] - boxA[0]) * math.max(0.0, boxA[3] - boxA[1]);
    final areaB = math.max(0.0, boxB[2] - boxB[0]) * math.max(0.0, boxB[3] - boxB[1]);
    final unionArea = areaA + areaB - interArea;
    if (unionArea <= 0) return 0.0;
    return interArea / unionArea;
  }

  /// Parses unified YOLO output tensors ([1, N, 4+C], [1, N, 5+C], [1, 4+C, N], [1, 5+C, N]).
  static List<Detection> parseUnifiedOutputs({
    required List<double> rawValues,
    required List<int> shape,
    required Map<String, dynamic> unifiedMeta,
    required int inputWidth,
    required int inputHeight,
    required double scoreThreshold,
    required List<int> classIds,
  }) {
    if (shape.isEmpty) return const [];
    final effectiveShape = shape.length == 3 && shape[0] == 1 ? shape.sublist(1) : shape;
    if (effectiveShape.length != 2) {
      throw StateError('Unified tensor expected rank 2 or rank 3 with batch=1, got shape $shape');
    }

    final d0 = effectiveShape[0], d1 = effectiveShape[1];
    final bool isTransposed = unifiedMeta.containsKey('transposed')
        ? (unifiedMeta['transposed'] == true)
        : (d0 < d1 && d0 <= (classIds.length + 5));

    final int numCandidates = isTransposed ? d1 : d0;
    final int numFeatures = isTransposed ? d0 : d1;
    final bool hasObjectness = unifiedMeta['has_objectness'] == true;
    final String format = unifiedMeta['format'] as String? ?? 'xywh_norm';

    final int classCount = classIds.length;
    final int classStartIndex = hasObjectness ? 5 : 4;
    final dets = <Detection>[];

    for (var k = 0; k < numCandidates; k++) {
      double getFeature(int f) {
        final idx = isTransposed ? (f * numCandidates + k) : (k * numFeatures + f);
        return rawValues[idx];
      }

      final double obj = hasObjectness ? getFeature(4) : 1.0;
      if (obj <= 0) continue;

      int bestClassIdx = -1;
      double bestScore = -1.0;

      for (var c = 0; c < classCount; c++) {
        if (classStartIndex + c >= numFeatures) break;
        final rawProb = getFeature(classStartIndex + c);
        final score = obj * rawProb;
        if (score > bestScore) {
          bestScore = score;
          bestClassIdx = c;
        }
      }

      if (bestClassIdx >= 0 && bestScore >= scoreThreshold) {
        final b = [getFeature(0), getFeature(1), getFeature(2), getFeature(3)];
        final box = _toXyxy(b, format, inputWidth, inputHeight);
        dets.add(Detection(classIds[bestClassIdx], bestScore, box));
      }
    }

    return dets;
  }

  /// Parses separate boxes, scores, and class_ids tensors.
  static List<Detection> parseSeparateOutputs({
    required List<double> boxes,
    required List<double> scores,
    required List<double> classIds,
    required String format,
    required double scoreThreshold,
  }) {
    if (scores.length != classIds.length || boxes.length != scores.length * 4) {
      throw StateError('Model output shapes disagree with metadata (boxes ${boxes.length}, '
          'scores ${scores.length}, class_ids ${classIds.length}). Re-check outputs indices.');
    }
    final dets = <Detection>[];
    for (var k = 0; k < scores.length; k++) {
      final score = scores[k];
      final b = boxes.sublist(k * 4, k * 4 + 4);
      final box = _toXyxy(b, format, 1, 1);
      dets.add(Detection(classIds[k].round(), score, box));
    }
    return dets;
  }

  static List<double> _toXyxy(List<double> b, String format, int imgW, int imgH) {
    double x1, y1, x2, y2;
    switch (format) {
      case 'xywh_norm':
        x1 = b[0] - b[2] / 2;
        y1 = b[1] - b[3] / 2;
        x2 = b[0] + b[2] / 2;
        y2 = b[1] + b[3] / 2;
        break;
      case 'xywh_abs':
        x1 = (b[0] - b[2] / 2) / imgW;
        y1 = (b[1] - b[3] / 2) / imgH;
        x2 = (b[0] + b[2] / 2) / imgW;
        y2 = (b[1] + b[3] / 2) / imgH;
        break;
      case 'xyxy_abs':
        x1 = b[0] / imgW;
        y1 = b[1] / imgH;
        x2 = b[2] / imgW;
        y2 = b[3] / imgH;
        break;
      case 'yxyx_norm':
        x1 = b[1];
        y1 = b[0];
        x2 = b[3];
        y2 = b[2];
        break;
      case 'xyxy_norm':
      default:
        x1 = b[0];
        y1 = b[1];
        x2 = b[2];
        y2 = b[3];
        break;
    }
    return [
      x1.clamp(0.0, 1.0),
      y1.clamp(0.0, 1.0),
      x2.clamp(0.0, 1.0),
      y2.clamp(0.0, 1.0),
    ];
  }

  static Uint8List? _generateHeatmapOverlay(List<double> flatValues, List<int> shape, int targetW, int targetH) {
    if (flatValues.isEmpty || shape.isEmpty) return null;
    final int h = shape.length >= 2 ? shape[shape.length - 2] : 1;
    final int w = shape.isNotEmpty ? shape.last : 1;
    if (w * h != flatValues.length) return null;

    var minVal = flatValues.first, maxVal = flatValues.first;
    for (final v in flatValues) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }
    final range = (maxVal - minVal) <= 0.00001 ? 1.0 : (maxVal - minVal);

    final rawHeatmap = img.Image(width: w, height: h);
    var idx = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final norm = ((flatValues[idx++] - minVal) / range).clamp(0.0, 1.0);
        // Jet-like colormap: blue -> cyan -> yellow -> red
        final r = (255 * (norm > 0.5 ? (norm - 0.5) * 2 : 0)).round();
        final g = (255 * (norm > 0.25 && norm < 0.75 ? 1.0 - (norm - 0.5).abs() * 4 : (norm >= 0.75 ? (1.0 - norm) * 4 : norm * 4))).round();
        final b = (255 * (norm < 0.5 ? (0.5 - norm) * 2 : 0)).round();
        final alpha = (140 * norm).round();
        rawHeatmap.setPixelRgba(x, y, r, g, b, alpha);
      }
    }
    final scaled = img.copyResize(rawHeatmap, width: targetW, height: targetH, interpolation: img.Interpolation.linear);
    return Uint8List.fromList(img.encodePng(scaled));
  }

  static img.Image _letterbox(img.Image src, int w, int h) {
    final r = (w / src.width) < (h / src.height) ? w / src.width : h / src.height;
    final nw = (src.width * r).round(), nh = (src.height * r).round();
    final scaled = img.copyResize(src, width: nw, height: nh);
    final canvas = img.Image(width: w, height: h);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    img.compositeImage(canvas, scaled, dstX: (w - nw) ~/ 2, dstY: (h - nh) ~/ 2);
    return canvas;
  }

  static Object _alloc(List<int> shape) {
    if (shape.length == 1) return List<double>.filled(shape[0], 0);
    return List.generate(shape[0], (_) => _alloc(shape.sublist(1)));
  }

  static List<double> _flatten(Object o) {
    if (o is List) {
      final out = <double>[];
      for (final e in o) {
        if (e is List) {
          out.addAll(_flatten(e));
        } else {
          out.add((e as num).toDouble());
        }
      }
      return out;
    }
    return [(o as num).toDouble()];
  }
}
