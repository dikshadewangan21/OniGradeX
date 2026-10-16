#!/usr/bin/env python3
"""Check that ml/artifacts/ is a valid, installable model. Run before copying into the app/backend.

    python ml/scripts/validate_artifacts.py [--artifacts ml/artifacts]

Checks: metadata validates against the schema, model file exists, class ids unique, and (if a TFLite
interpreter is installed) the model's input shape/dtype and output count match the metadata.
Exit code 0 = OK, 1 = problems. Never prints success without actually checking.
"""
import argparse
import json
import sys
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]


def validate(art_dir: Path) -> tuple[list[str], list[str]]:
    problems, notes = [], []
    meta_p, model_p = art_dir / "model_metadata.json", art_dir / "onion_model.tflite"
    if not meta_p.is_file():
        return [f"missing {meta_p}"], notes
    try:
        meta = json.loads(meta_p.read_text())
    except json.JSONDecodeError as e:
        return [f"metadata is not valid JSON: {e}"], notes
    schema = json.loads((ROOT / "ml/contract/model_metadata.schema.json").read_text())
    for e in jsonschema.Draft202012Validator(schema).iter_errors(meta):
        problems.append(f"metadata {'/'.join(map(str, e.path)) or '<root>'}: {e.message}")
    if problems:
        return problems, notes
    ids = [c["id"] for c in meta["classes"]]
    if len(set(ids)) != len(ids):
        problems.append("duplicate class ids")
    if not any(c["role"] == "fresh" for c in meta["classes"]):
        problems.append("no class with role 'fresh'")
    if not any(c["role"] == "defect" for c in meta["classes"]):
        problems.append("no class with role 'defect'")
    for c in meta["classes"]:
        if c["role"] == "defect" and not c.get("detail_key"):
            notes.append(f"defect class '{c['name']}' has no detail_key; it counts toward defective_pct only")
    if "REPLACE_ME" in json.dumps(meta):
        problems.append("metadata still contains REPLACE_ME placeholders")
    if not model_p.is_file():
        problems.append(f"missing {model_p}")
        return problems, notes
    if model_p.stat().st_size < 1024:
        problems.append("model file is suspiciously small (<1 KB)")
    interp_cls = None
    try:
        from ai_edge_litert.interpreter import Interpreter as interp_cls  # type: ignore
    except ImportError:
        try:
            from tflite_runtime.interpreter import Interpreter as interp_cls  # type: ignore
        except ImportError:
            try:
                import tensorflow as tf  # type: ignore
                interp_cls = tf.lite.Interpreter
            except ImportError:
                notes.append("no TFLite runtime installed: tensor shapes NOT verified (pip install ai-edge-litert)")
    if interp_cls:
        it = interp_cls(model_path=str(model_p))
        it.allocate_tensors()
        inp = it.get_input_details()[0]
        want = [1, meta["input"]["height"], meta["input"]["width"], 3]
        if list(inp["shape"]) != want:
            problems.append(f"model input shape {list(inp['shape'])} != metadata {want}")
        if meta["input"]["dtype"] not in str(inp["dtype"]):
            problems.append(f"model input dtype {inp['dtype']} != metadata {meta['input']['dtype']}")
        n_out = len(it.get_output_details())
        layout = meta["outputs"].get("layout", "unified" if "unified" in meta["outputs"] else "separate")
        if layout == "unified":
            u_idx = meta["outputs"]["unified"]["index"]
            if u_idx >= n_out:
                problems.append(f"outputs.unified.index out of range (model has {n_out} outputs)")
        else:
            for k in ("boxes", "scores", "class_ids"):
                if meta["outputs"][k]["index"] >= n_out:
                    problems.append(f"outputs.{k}.index out of range (model has {n_out} outputs)")
        if not problems:
            notes.append("TFLite input/output tensors match metadata")
    return problems, notes


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--artifacts", default=str(ROOT / "ml/artifacts"))
    a = ap.parse_args()
    probs, notes = validate(Path(a.artifacts))
    for n in notes:
        print("note:", n)
    for p in probs:
        print("PROBLEM:", p)
    print("OK" if not probs else f"{len(probs)} problem(s)")
    sys.exit(1 if probs else 0)
