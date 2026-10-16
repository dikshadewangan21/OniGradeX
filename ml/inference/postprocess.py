"""Reference batch summarisation: detections -> certificate metrics.

This is the executable SPEC for the Flutter implementation (app/lib/ml/postprocess.dart). Both must
produce the same numbers for ml/contract/postprocess_vectors.json.

Definitions (count-based, per detected onion):
  onion_count      = number of detections with score >= score_threshold
  defective_pct    = 100 * (#detections whose class role == "defect") / onion_count
  fresh_pct        = 100 * (#role == "fresh") / onion_count
  details[<detail_key>] = 100 * (#detections of that class) / onion_count
  batch_confidence = mean score of the kept detections
Count-based percentages are NOT the 'rot area %' the PPT mentions. Area-based metrics need
segmentation masks; if you train a segmenter, extend this contract rather than reusing these names.
"""
from __future__ import annotations


class ContractError(ValueError):
    pass


def summarize(detections: list[dict], classes: list[dict], score_threshold: float) -> dict:
    """detections: [{"class_id": int, "score": float}, ...]. Raises ContractError on invalid input."""
    by_id = {c["id"]: c for c in classes}
    kept = []
    for i, d in enumerate(detections):
        if "class_id" not in d or "score" not in d:
            raise ContractError(f"detection {i} missing class_id/score")
        if d["score"] < score_threshold:
            continue  # padded/low-confidence slots are ignored before further validation
        if d["class_id"] not in by_id:
            raise ContractError(f"detection {i} has unknown class_id {d['class_id']}")
        if d["score"] > 1.0:
            raise ContractError(f"detection {i} score {d['score']} outside [0,1]")
        kept.append(d)
    n = len(kept)
    if n == 0:
        raise ContractError("no onions detected above threshold; re-capture required")

    def pct(k: int) -> float:
        # Integer arithmetic, round-half-up to 2 decimals: identical in Python and Dart (no float tie drift).
        return ((k * 20000 + n) // (2 * n)) / 100

    fresh = sum(1 for d in kept if by_id[d["class_id"]]["role"] == "fresh")
    defect = sum(1 for d in kept if by_id[d["class_id"]]["role"] == "defect")
    details = {}
    for c in classes:
        if c["role"] == "defect" and c.get("detail_key"):
            details[c["detail_key"]] = pct(sum(1 for d in kept if d["class_id"] == c["id"]))
    return {
        "onion_count": n,
        "fresh_pct": pct(fresh),
        "defective_pct": pct(defect),
        "batch_confidence": round(sum(d["score"] for d in kept) / n, 4),
        "details": details,
    }
