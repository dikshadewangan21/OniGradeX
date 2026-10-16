#!/usr/bin/env python3
"""TRAINING ENTRY POINT TEMPLATE. This file does not train anything as shipped.

YOU decide: architecture (PPT says ViT-YOLO; see caveats in ml/README.md), framework, hyperparameters.
Complete the three TODO functions, run, then export with your own code to ml/artifacts/.

    python ml/training/train_template.py --data ml/datasets/onions --out ml/artifacts --version 2026.10.1
"""
import argparse
import json
from pathlib import Path


def build_model(num_classes: int):
    raise NotImplementedError("TODO: construct your detector (e.g. Ultralytics YOLO, or your ViT-YOLO fork)")


def train(model, data_root: Path, epochs: int):
    raise NotImplementedError("TODO: train on <data_root>/train, validate on <data_root>/val. Never touch test/.")


def export_tflite(model, out_dir: Path, img_size: int, int8: bool):
    raise NotImplementedError(
        "TODO: export to out_dir/onion_model.tflite. For INT8 supply a representative dataset drawn "
        "from train/ (not test/). Record output tensor indices for model_metadata.json.")


def write_metadata_skeleton(out_dir: Path, version: str):
    """Writes a metadata file with unfilled fields so validate_artifacts.py fails until you complete it."""
    example = json.loads((Path(__file__).resolve().parents[1] / "contract/model_metadata.EXAMPLE.json").read_text())
    example.pop("_comment", None)
    example["version"] = version
    (out_dir / "model_metadata.json").write_text(json.dumps(example, indent=2))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", default="ml/artifacts")
    ap.add_argument("--version", required=True)
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--img-size", type=int, default=640)
    ap.add_argument("--classes", type=int, default=4)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    model = build_model(a.classes)
    train(model, Path(a.data), a.epochs)
    export_tflite(model, out, a.img_size, int8=True)
    write_metadata_skeleton(out, a.version)
    print("Now fill trained_on/metrics in model_metadata.json from your evaluation, then run "
          "python ml/scripts/validate_artifacts.py")
