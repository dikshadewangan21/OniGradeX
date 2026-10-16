import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Result of trying to load the installed model artifacts. Never fabricates a version.
class ModelStatus {
  ModelStatus.ready(this.metadata)
      : ready = true,
        problems = const [];
  ModelStatus.unavailable(this.problems)
      : ready = false,
        metadata = null;

  final bool ready;
  final List<String> problems;
  final Map<String, dynamic>? metadata;

  String? get version => metadata?['version'] as String?;
  List<Map<String, dynamic>> get classes =>
      (metadata!['classes'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  double get scoreThreshold => ((metadata!['postprocess'] as Map)['score_threshold'] as num).toDouble();
}

const modelAsset = 'assets/model/onion_model.tflite';
const metadataAsset = 'assets/model/model_metadata.json';

/// Light structural validation mirroring the JSON schema's required fields. The authoritative check is
/// `python ml/scripts/validate_artifacts.py` at install time; this protects the app from crashing.
List<String> validateMetadata(Map<String, dynamic> m) {
  final problems = <String>[];
  for (final k in ['model_name', 'version', 'task', 'input', 'outputs', 'preprocessing', 'classes', 'postprocess']) {
    if (!m.containsKey(k)) problems.add('metadata missing "$k"');
  }
  if (problems.isNotEmpty) return problems;
  if (m['task'] != 'detection') problems.add('task must be "detection"');
  final input = m['input'] as Map;
  for (final k in ['width', 'height', 'dtype', 'layout']) {
    if (!input.containsKey(k)) problems.add('input.$k missing');
  }
  final outs = m['outputs'] as Map;
  final layout = outs['layout'] as String? ?? (outs.containsKey('unified') ? 'unified' : 'separate');
  if (layout == 'unified') {
    if (!outs.containsKey('unified')) problems.add('outputs.unified missing');
  } else {
    for (final k in ['boxes', 'scores', 'class_ids']) {
      if (!outs.containsKey(k)) problems.add('outputs.$k missing');
    }
  }
  final classes = m['classes'] as List;
  final ids = classes.map((c) => (c as Map)['id']).toList();
  if (ids.toSet().length != ids.length) problems.add('duplicate class ids');
  if (!classes.any((c) => (c as Map)['role'] == 'fresh')) problems.add('no "fresh" class');
  if (!classes.any((c) => (c as Map)['role'] == 'defect')) problems.add('no "defect" class');
  if (m.toString().contains('REPLACE_ME')) problems.add('metadata still contains REPLACE_ME');
  return problems;
}

Future<ModelStatus> loadModelStatus() async {
  try {
    await rootBundle.load(modelAsset);
  } catch (_) {
    return ModelStatus.unavailable(['Model file not installed (assets/model/onion_model.tflite)']);
  }
  try {
    final raw = await rootBundle.loadString(metadataAsset);
    final meta = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final problems = validateMetadata(meta);
    if (problems.isNotEmpty) return ModelStatus.unavailable(problems);
    return ModelStatus.ready(meta);
  } on FormatException {
    return ModelStatus.unavailable(['model_metadata.json is not valid JSON']);
  } catch (_) {
    return ModelStatus.unavailable(['model_metadata.json not installed (assets/model/model_metadata.json)']);
  }
}
