/// Port of ml/inference/postprocess.py. Must match ml/contract/postprocess_vectors.json.
class ContractError implements Exception {
  ContractError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Detection {
  const Detection(this.classId, this.score, [this.box]);
  final int classId;
  final double score;

  /// Normalised [x1, y1, x2, y2] if the model supplied boxes (used only for drawing).
  final List<double>? box;
}

class BatchSummary {
  BatchSummary(this.onionCount, this.freshPct, this.defectivePct, this.batchConfidence, this.details);
  final int onionCount;
  final double freshPct;
  final double defectivePct;
  final double batchConfidence;
  final Map<String, double> details;
}

double _round(double v, int digits) {
  final m = _pow10(digits);
  return (v * m).roundToDouble() / m;
}

double _pow10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

BatchSummary summarize(List<Detection> detections, List<Map<String, dynamic>> classes, double scoreThreshold) {
  final byId = {for (final c in classes) c['id'] as int: c};
  final kept = <Detection>[];
  for (var i = 0; i < detections.length; i++) {
    final d = detections[i];
    if (d.score < scoreThreshold) continue; // padded/low-confidence slots are ignored first
    if (!byId.containsKey(d.classId)) throw ContractError('detection $i has unknown class_id ${d.classId}');
    if (d.score > 1) throw ContractError('detection $i score ${d.score} outside [0,1]');
    kept.add(d);
  }
  final n = kept.length;
  if (n == 0) throw ContractError('no onions detected above threshold; re-capture required');
  double pct(int k) => ((k * 20000 + n) ~/ (2 * n)) / 100; // integer half-up, matches Python

  final fresh = kept.where((d) => byId[d.classId]!['role'] == 'fresh').length;
  final defect = kept.where((d) => byId[d.classId]!['role'] == 'defect').length;
  final details = <String, double>{};
  for (final c in classes) {
    if (c['role'] == 'defect' && c['detail_key'] != null) {
      details[c['detail_key'] as String] = pct(kept.where((d) => d.classId == c['id']).length);
    }
  }
  final meanScore = kept.fold<double>(0, (a, d) => a + d.score) / n;
  return BatchSummary(n, pct(fresh), pct(defect), _round(meanScore, 4), details);
}
