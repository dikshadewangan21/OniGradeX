// ignore_for_file: avoid_print
// Tool / test to verify a real model on an image once installed.
// Run with:
//   flutter test tool/check_model_on_image.dart
//   flutter test tool/check_model_on_image.dart --dart-define=IMAGE=path/to/image.jpg --dart-define=MODEL=app/assets/model/onion_model.tflite --dart-define=METADATA=app/assets/model/model_metadata.json

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:onigrader/ml/detector.dart';
import 'package:onigrader/ml/model_loader.dart';
import 'package:onigrader/ml/postprocess.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Check model on image verification runner', () async {
    const envImage = String.fromEnvironment('IMAGE');
    const envModel = String.fromEnvironment('MODEL', defaultValue: 'assets/model/onion_model.tflite');
    const envMeta = String.fromEnvironment('METADATA', defaultValue: 'assets/model/model_metadata.json');

    final modelPath = envModel.isNotEmpty ? envModel : 'assets/model/onion_model.tflite';
    final metaPath = envMeta.isNotEmpty ? envMeta : 'assets/model/model_metadata.json';
    final imagePath = envImage.isNotEmpty ? envImage : null;

    print('\n========================================');
    print('  OniGrader Model Verification Runner   ');
    print('========================================');
    print('Model target: $modelPath');
    print('Metadata target: $metaPath');
    print('Image target: ${imagePath ?? "(none provided, skipping inference)"}');

    final modelFile = File(modelPath);
    final metaFile = File(metaPath);

    if (!metaFile.existsSync()) {
      print('\n[STATUS: BLOCKED on M6]');
      print('model_metadata.json is not yet present at: $metaPath');
      print('Complete manual step M6, then place the metadata file to enable full model check.\n');
      return;
    }

    if (!modelFile.existsSync()) {
      print('\n[STATUS: BLOCKED on M6]');
      print('onion_model.tflite is not yet present at: $modelPath');
      print('Complete manual step M6, then place the model file to enable full model check.\n');
      return;
    }

    final metaRaw = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    final problems = validateMetadata(metaRaw);
    if (problems.isNotEmpty) {
      print('\n[ERROR] Metadata validation problems:');
      for (final p in problems) {
        print('  - $p');
      }
      fail('Metadata validation failed');
    }
    print('[OK] Metadata schema valid: ${metaRaw['model_name']} v${metaRaw['version']}');

    if (imagePath == null) {
      print('[INFO] Pass --dart-define=IMAGE=<path> to run inference against a real image.');
      return;
    }

    final imgFile = File(imagePath);
    if (!imgFile.existsSync()) {
      fail('Specified image does not exist: $imagePath');
    }

    final bytes = await imgFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) fail('Failed to decode image $imagePath');

    final interp = Interpreter.fromFile(modelFile);
    print('[OK] Interpreter initialized from $modelPath');

    final inputMeta = metaRaw['input'] as Map;
    final w = inputMeta['width'] as int;
    final h = inputMeta['height'] as int;
    final preMeta = metaRaw['preprocessing'] as Map;
    final resized = (preMeta['resize'] == 'letterbox')
        ? _letterbox(decoded, w, h)
        : img.copyResize(decoded, width: w, height: h);

    final norm = preMeta['normalize'] as Map;
    final mean = (norm['mean'] as List).map((e) => (e as num).toDouble()).toList();
    final std = (norm['std'] as List).map((e) => (e as num).toDouble()).toList();
    final scale = (norm['scale'] as num?)?.toDouble() ?? 1.0;
    final bgr = inputMeta['color_order'] == 'BGR';
    final asFloat = inputMeta['dtype'] == 'float32';

    final tensor = asFloat ? Float32List(w * h * 3) : Uint8List(w * h * 3);
    var idx = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final px = resized.getPixel(x, y);
        final ch = bgr ? [px.b, px.g, px.r] : [px.r, px.g, px.b];
        for (var c = 0; c < 3; c++) {
          if (asFloat) {
            (tensor as Float32List)[idx++] = (ch[c].toDouble() * scale - mean[c]) / std[c];
          } else {
            (tensor as Uint8List)[idx++] = ch[c].toInt();
          }
        }
      }
    }

    final inputObj = (tensor as dynamic).reshape([1, h, w, 3]);
    final outTensors = interp.getOutputTensors();
    final buffers = <int, Object>{
      for (var k = 0; k < outTensors.length; k++) k: _alloc(outTensors[k].shape),
    };

    final sw = Stopwatch()..start();
    interp.runForMultipleInputs([inputObj], buffers);
    sw.stop();
    print('[OK] Model inference ran in ${sw.elapsedMilliseconds} ms.');

    final outs = metaRaw['outputs'] as Map;
    final post = metaRaw['postprocess'] as Map? ?? const {};
    final nmsInModel = post['nms_in_model'] as bool? ?? false;
    final nmsIouThreshold = (post['nms_iou_threshold'] as num?)?.toDouble() ?? 0.45;
    final scoreThreshold = (post['score_threshold'] as num?)?.toDouble() ?? 0.25;
    final layout = outs['layout'] as String? ?? (outs.containsKey('unified') ? 'unified' : 'separate');

    List<Detection> dets;
    final classes = (metaRaw['classes'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final classIds = classes.map((c) => c['id'] as int).toList();

    if (layout == 'unified') {
      final uMeta = outs['unified'] as Map? ?? outs;
      final uIdx = uMeta['index'] as int? ?? 0;
      dets = Detector.parseUnifiedOutputs(
        rawValues: _flatten(buffers[uIdx]!),
        shape: outTensors[uIdx].shape,
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
      dets = Detector.parseSeparateOutputs(
        boxes: _flatten(buffers[bIdx]!),
        scores: _flatten(buffers[sIdx]!),
        classIds: _flatten(buffers[cIdx]!),
        format: (outs['boxes'] as Map)['format'] as String,
        scoreThreshold: scoreThreshold,
      );
    }

    if (!nmsInModel) {
      dets = Detector.applyNms(dets, nmsIouThreshold);
    }

    final kept = dets.where((d) => d.score >= scoreThreshold).toList();
    print('\nDetections above threshold ($scoreThreshold): ${kept.length}');
    for (var i = 0; i < kept.length; i++) {
      final d = kept[i];
      final className = classes.firstWhere((c) => c['id'] == d.classId)['name'];
      print('  #$i: $className (id=${d.classId}) conf=${(d.score * 100).toStringAsFixed(1)}% box=${d.box}');
    }

    final summary = summarize(kept, classes, scoreThreshold);
    print('\nBatch Summary:');
    print('  Total: ${summary.onionCount}');
    print('  Fresh: ${summary.freshPct}%');
    print('  Defective: ${summary.defectivePct}%');
    print('  Confidence: ${(summary.batchConfidence * 100).toStringAsFixed(1)}%');
    print('  Details: ${summary.details}');

    interp.close();
  });
}

img.Image _letterbox(img.Image src, int w, int h) {
  final r = (w / src.width) < (h / src.height) ? w / src.width : h / src.height;
  final nw = (src.width * r).round(), nh = (src.height * r).round();
  final scaled = img.copyResize(src, width: nw, height: nh);
  final canvas = img.Image(width: w, height: h);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(canvas, scaled, dstX: (w - nw) ~/ 2, dstY: (h - nh) ~/ 2);
  return canvas;
}

Object _alloc(List<int> shape) {
  if (shape.length == 1) return List<double>.filled(shape[0], 0);
  return List.generate(shape[0], (_) => _alloc(shape.sublist(1)));
}

List<double> _flatten(Object o) {
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
