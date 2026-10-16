"""Server-side re-evaluation of grading rules.

The device produces the grade. The server re-applies the *same admin-managed rule version* to the
submitted metrics and rejects a certificate whose grade does not follow from its own numbers.
This catches tampering/bugs; it does not prove the model produced the metrics.
"""
from typing import Any


def evaluate_grade(defn: dict, defective_pct: float, details: dict[str, Any]) -> str:
    for g in defn["grades"]:
        if g.get("max_defective_pct") is not None and defective_pct > g["max_defective_pct"]:
            continue
        if g.get("max_rot_pct") is not None:
            rot = details.get("rot_pct")
            if rot is None or rot > g["max_rot_pct"]:
                continue
        if g.get("max_sprout_pct") is not None:
            sp = details.get("sprout_pct")
            if sp is None or sp > g["max_sprout_pct"]:
                continue
        if g.get("min_diameter_mm") is not None:
            d = details.get("median_diameter_mm")
            if d is None or d < g["min_diameter_mm"]:
                continue
        return g["grade"]
    return defn["reject_grade"]


def approx_equal(a: Any, b: Any, tol: float = 1e-3) -> bool:
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) <= tol
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(approx_equal(a[k], b[k], tol) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(approx_equal(x, y, tol) for x, y in zip(a, b))
    return a == b
