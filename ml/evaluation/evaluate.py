#!/usr/bin/env python3
"""Detection + grading evaluation on YOUR held-out test split.

    python ml/evaluation/evaluate.py --gt <labels_dir> --pred <pred_dir> --classes 4

--gt  : YOLO labels (class cx cy w h)
--pred: same format with a 6th column = confidence (one .txt per image, same stem)
Outputs per-class precision/recall/F1 at IoU>=0.5 (greedy score-ordered matching) and, if you pass
--metadata, batch-level agreement between predicted and ground-truth defective_pct per image.
This is a simple, auditable matcher, not COCO mAP. Use Ultralytics/pycocotools for paper-grade mAP.
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path


def iou(a, b):
    ax1, ay1, ax2, ay2 = a[0] - a[2] / 2, a[1] - a[3] / 2, a[0] + a[2] / 2, a[1] + a[3] / 2
    bx1, by1, bx2, by2 = b[0] - b[2] / 2, b[1] - b[3] / 2, b[0] + b[2] / 2, b[1] + b[3] / 2
    iw, ih = max(0, min(ax2, bx2) - max(ax1, bx1)), max(0, min(ay2, by2) - max(ay1, by1))
    inter = iw * ih
    union = a[2] * a[3] + b[2] * b[3] - inter
    return inter / union if union > 0 else 0.0


def read(path: Path, with_conf: bool):
    out = []
    if path.is_file():
        for line in path.read_text().splitlines():
            p = line.split()
            if not p:
                continue
            out.append((int(p[0]), tuple(map(float, p[1:5])), float(p[5]) if with_conf and len(p) > 5 else 1.0))
    return out


def evaluate(gt_dir: Path, pred_dir: Path, n_classes: int, iou_thr=0.5, conf_thr=0.0, defect_ids=None):
    tp, fp, fn = defaultdict(int), defaultdict(int), defaultdict(int)
    batch_errs = []
    for gp in sorted(gt_dir.glob("*.txt")):
        gt = read(gp, False)
        pr = sorted((p for p in read(pred_dir / gp.name, True) if p[2] >= conf_thr), key=lambda p: -p[2])
        used = set()
        for cid, box, _ in pr:
            best, bj = 0.0, -1
            for j, (gc, gb, _) in enumerate(gt):
                if j in used or gc != cid:
                    continue
                v = iou(box, gb)
                if v > best:
                    best, bj = v, j
            if best >= iou_thr:
                tp[cid] += 1
                used.add(bj)
            else:
                fp[cid] += 1
        for j, (gc, _, _) in enumerate(gt):
            if j not in used:
                fn[gc] += 1
        if defect_ids is not None and gt:
            gd = 100 * sum(1 for g in gt if g[0] in defect_ids) / len(gt)
            pd = 100 * sum(1 for p in pr if p[0] in defect_ids) / len(pr) if pr else None
            batch_errs.append(None if pd is None else abs(gd - pd))
    per_class = {}
    for c in range(n_classes):
        p = tp[c] / (tp[c] + fp[c]) if tp[c] + fp[c] else None
        r = tp[c] / (tp[c] + fn[c]) if tp[c] + fn[c] else None
        f1 = 2 * p * r / (p + r) if p and r else (0.0 if p is not None and r is not None else None)
        per_class[c] = {"precision": p, "recall": r, "f1": f1, "tp": tp[c], "fp": fp[c], "fn": fn[c]}
    res = {"per_class": per_class, "iou_threshold": iou_thr}
    if defect_ids is not None:
        ok = [e for e in batch_errs if e is not None]
        res["batch_defective_pct_mae"] = sum(ok) / len(ok) if ok else None
        res["images_with_no_predictions"] = batch_errs.count(None)
    return res


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--gt", required=True)
    ap.add_argument("--pred", required=True)
    ap.add_argument("--classes", type=int, required=True)
    ap.add_argument("--metadata", help="model_metadata.json; enables batch-level defective_pct error")
    ap.add_argument("--iou", type=float, default=0.5)
    ap.add_argument("--conf", type=float, default=0.25)
    a = ap.parse_args()
    defect = None
    if a.metadata:
        defect = {c["id"] for c in json.loads(Path(a.metadata).read_text())["classes"] if c["role"] == "defect"}
    print(json.dumps(evaluate(Path(a.gt), Path(a.pred), a.classes, a.iou, a.conf, defect), indent=2))
