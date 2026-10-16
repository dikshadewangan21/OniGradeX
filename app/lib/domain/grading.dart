/// Port of backend/app/services/grading.py evaluate_grade. The server re-applies the same rule
/// version and rejects certificates whose grade doesn't follow, so these must stay identical.
String evaluateGrade(Map<String, dynamic> defn, double defectivePct, Map<String, dynamic> details) {
  for (final g in (defn['grades'] as List)) {
    final m = Map<String, dynamic>.from(g as Map);
    final maxDef = m['max_defective_pct'];
    if (maxDef != null && defectivePct > (maxDef as num)) continue;
    final maxRot = m['max_rot_pct'];
    if (maxRot != null) {
      final rot = details['rot_pct'];
      if (rot == null || (rot as num) > (maxRot as num)) continue;
    }
    final maxSprout = m['max_sprout_pct'];
    if (maxSprout != null) {
      final sp = details['sprout_pct'];
      if (sp == null || (sp as num) > (maxSprout as num)) continue;
    }
    final minDia = m['min_diameter_mm'];
    if (minDia != null) {
      final d = details['median_diameter_mm'];
      if (d == null || (d as num) < (minDia as num)) continue;
    }
    return m['grade'] as String;
  }
  return defn['reject_grade'] as String;
}
