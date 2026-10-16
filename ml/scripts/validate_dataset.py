#!/usr/bin/env python3
"""Validate a YOLO-format detection dataset against ml/datasets/dataset_schema.yaml.

    python ml/scripts/validate_dataset.py --root ml/datasets/onions --classes 4

Layout expected:  <root>/{train,val,test}/{images,labels}/   (label file per image, same stem)
Label line: <class_id> <cx> <cy> <w> <h>   all coords normalised to [0,1].
Reports: missing/orphan labels, malformed lines, class ids out of range, boxes outside image,
duplicate files across splits (leakage by filename/hash), per-split class counts.
"""
import argparse
import hashlib
import sys
from collections import Counter, defaultdict
from pathlib import Path

IMG_EXT = {".jpg", ".jpeg", ".png"}


def validate(root: Path, n_classes: int) -> dict:
    problems: list[str] = []
    counts: dict[str, Counter] = {}
    hashes: dict[str, list[str]] = defaultdict(list)
    sizes = {}
    for split in ("train", "val", "test"):
        img_dir, lbl_dir = root / split / "images", root / split / "labels"
        if not img_dir.is_dir() or not lbl_dir.is_dir():
            problems.append(f"[{split}] missing images/ or labels/ directory")
            continue
        images = {p.stem: p for p in img_dir.iterdir() if p.suffix.lower() in IMG_EXT}
        labels = {p.stem: p for p in lbl_dir.glob("*.txt")}
        sizes[split] = len(images)
        if not images:
            problems.append(f"[{split}] no images")
        for stem in images.keys() - labels.keys():
            problems.append(f"[{split}] image without label file: {images[stem].name}")
        for stem in labels.keys() - images.keys():
            problems.append(f"[{split}] label without image: {labels[stem].name}")
        c = Counter()
        for stem, lp in labels.items():
            for ln, line in enumerate(lp.read_text().splitlines(), 1):
                if not line.strip():
                    continue
                parts = line.split()
                where = f"[{split}] {lp.name}:{ln}"
                if len(parts) != 5:
                    problems.append(f"{where} expected 5 fields, got {len(parts)} (polygon/segmentation labels not supported)")
                    continue
                try:
                    cid = int(parts[0])
                    cx, cy, w, h = map(float, parts[1:])
                except ValueError:
                    problems.append(f"{where} non-numeric value")
                    continue
                if not 0 <= cid < n_classes:
                    problems.append(f"{where} class id {cid} outside 0..{n_classes - 1}")
                if not (0 <= cx <= 1 and 0 <= cy <= 1 and 0 < w <= 1 and 0 < h <= 1):
                    problems.append(f"{where} coordinates not normalised to [0,1]")
                elif cx - w / 2 < -1e-6 or cx + w / 2 > 1 + 1e-6 or cy - h / 2 < -1e-6 or cy + h / 2 > 1 + 1e-6:
                    problems.append(f"{where} box extends outside image")
                c[cid] += 1
        counts[split] = c
        for p in images.values():
            hashes[hashlib.sha256(p.read_bytes()).hexdigest()].append(f"{split}/{p.name}")
    for h, files in hashes.items():
        if len({f.split("/")[0] for f in files}) > 1:
            problems.append(f"identical image appears in multiple splits (leakage): {files}")
    for split, c in counts.items():
        for cid in range(n_classes):
            if sizes.get(split) and c[cid] == 0:
                problems.append(f"[{split}] class {cid} has zero instances")
    return {"problems": problems, "images_per_split": sizes,
            "instances_per_split": {k: dict(sorted(v.items())) for k, v in counts.items()}}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--classes", type=int, required=True)
    a = ap.parse_args()
    r = validate(Path(a.root), a.classes)
    print("images per split:", r["images_per_split"])
    print("instances per split:", r["instances_per_split"])
    for p in r["problems"][:200]:
        print("PROBLEM:", p)
    print("OK" if not r["problems"] else f"{len(r['problems'])} problem(s)")
    sys.exit(1 if r["problems"] else 0)
