"""Tests for ml/ tooling using synthetic fixtures. Nothing here trains or runs a real model."""
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
for sub in ("scripts", "inference", "evaluation"):
    sys.path.insert(0, str(ROOT / "ml" / sub))

import evaluate as ev  # noqa: E402
import postprocess as pp  # noqa: E402
import validate_artifacts as va  # noqa: E402
import validate_dataset as vd  # noqa: E402

CLASSES = json.loads((ROOT / "ml/contract/model_metadata.EXAMPLE.json").read_text())["classes"]


# ---------- postprocess (spec shared with Dart) ----------
def test_summarize_basic():
    dets = [{"class_id": 0, "score": .9}] * 6 + [{"class_id": 1, "score": .8}] * 2 + [{"class_id": 2, "score": .7}] * 1 \
        + [{"class_id": 0, "score": .1}]  # below threshold, ignored
    r = pp.summarize(dets, CLASSES, 0.25)
    assert r["onion_count"] == 9
    assert r["fresh_pct"] == pytest.approx(66.67)
    assert r["defective_pct"] == pytest.approx(33.33)
    assert r["details"] == {"rot_pct": 22.22, "sprout_pct": 11.11, "skin_peel_pct": 0.0}
    assert r["batch_confidence"] == pytest.approx((.9 * 6 + .8 * 2 + .7) / 9, abs=1e-4)


@pytest.mark.parametrize("dets,msg", [
    ([], "no onions"),
    ([{"class_id": 0, "score": .1}], "no onions"),
    ([{"class_id": 9, "score": .9}], "unknown class_id"),
    ([{"class_id": 0, "score": 1.5}], "outside"),
    ([{"class_id": 0}], "missing"),
])
def test_summarize_rejects_bad_input(dets, msg):
    with pytest.raises(pp.ContractError, match=msg):
        pp.summarize(dets, CLASSES, 0.25)


def test_vectors_file_matches_reference():
    """ml/contract/postprocess_vectors.json is consumed by the Dart tests too."""
    vec = json.loads((ROOT / "ml/contract/postprocess_vectors.json").read_text())
    assert vec["cases"], "no vectors"
    for case in vec["cases"]:
        if "expect_error" in case:
            with pytest.raises(pp.ContractError):
                pp.summarize(case["detections"], vec["classes"], case["score_threshold"])
        else:
            got = pp.summarize(case["detections"], vec["classes"], case["score_threshold"])
            assert got == case["expect"], case["name"]


# ---------- artifacts validator ----------
def _meta():
    m = json.loads((ROOT / "ml/contract/model_metadata.EXAMPLE.json").read_text())
    m.pop("_comment")
    return m


def test_artifacts_missing(tmp_path):
    probs, _ = va.validate(tmp_path)
    assert probs and "missing" in probs[0]


def test_example_metadata_is_rejected_until_filled(tmp_path):
    m = _meta()
    (tmp_path / "model_metadata.json").write_text(json.dumps(m))
    (tmp_path / "onion_model.tflite").write_bytes(b"x" * 4096)
    probs, _ = va.validate(tmp_path)
    assert any("REPLACE_ME" in p for p in probs)


def test_artifacts_schema_errors(tmp_path):
    m = _meta()
    del m["classes"]
    m["input"]["channels"] = 1
    (tmp_path / "model_metadata.json").write_text(json.dumps(m))
    probs, _ = va.validate(tmp_path)
    assert any("classes" in p for p in probs) and any("channels" in p for p in probs)


def test_artifacts_tiny_model_flagged(tmp_path):
    m = _meta()
    m["model_name"], m["version"], m["trained_on"] = "t", "1", "t"
    (tmp_path / "model_metadata.json").write_text(json.dumps(m))
    (tmp_path / "onion_model.tflite").write_bytes(b"x")
    probs, _ = va.validate(tmp_path)
    assert any("suspiciously small" in p for p in probs)


# ---------- dataset validator ----------
def _mk(root, split, name, lines, img=b"\xff\xd8\xff" + b"0"):
    (root / split / "images").mkdir(parents=True, exist_ok=True)
    (root / split / "labels").mkdir(parents=True, exist_ok=True)
    (root / split / "images" / f"{name}.jpg").write_bytes(img + name.encode())
    if lines is not None:
        (root / split / "labels" / f"{name}.txt").write_text("\n".join(lines))


def test_dataset_ok(tmp_path):
    for s in ("train", "val", "test"):
        _mk(tmp_path, s, f"{s}1", ["0 .5 .5 .2 .2", "1 .3 .3 .1 .1"])
    r = vd.validate(tmp_path, 2)
    assert r["problems"] == [], r["problems"]
    assert r["images_per_split"] == {"train": 1, "val": 1, "test": 1}


def test_dataset_detects_problems(tmp_path):
    _mk(tmp_path, "train", "a", ["5 .5 .5 .2 .2"])               # class out of range
    _mk(tmp_path, "train", "b", ["0 .95 .5 .2 .2"])              # box outside
    _mk(tmp_path, "train", "c", ["0 .5 .5 .2"])                  # malformed
    _mk(tmp_path, "train", "d", None)                            # no label
    _mk(tmp_path, "val", "e", ["0 .5 .5 .2 .2", "1 .5 .5 .2 .2"])
    (tmp_path / "val" / "labels" / "orphan.txt").write_text("0 .5 .5 .1 .1")
    _mk(tmp_path, "test", "dup", ["0 .5 .5 .2 .2", "1 .5 .5 .2 .2"])
    (tmp_path / "val" / "images" / "dup.jpg").write_bytes((tmp_path / "test" / "images" / "dup.jpg").read_bytes())
    (tmp_path / "val" / "labels" / "dup.txt").write_text("0 .5 .5 .2 .2")
    text = "\n".join(vd.validate(tmp_path, 2)["problems"])
    for needle in ("outside 0..1", "extends outside", "expected 5 fields", "without label", "label without image", "leakage"):
        assert needle in text, needle


def test_dataset_missing_dirs(tmp_path):
    assert any("missing images/" in p for p in vd.validate(tmp_path, 2)["problems"])


# ---------- evaluation ----------
def test_evaluate_metrics(tmp_path):
    gt, pr = tmp_path / "gt", tmp_path / "pr"
    gt.mkdir(); pr.mkdir()
    (gt / "i1.txt").write_text("0 .3 .3 .2 .2\n1 .7 .7 .2 .2\n")
    (pr / "i1.txt").write_text("0 .3 .3 .2 .2 .9\n0 .7 .7 .2 .2 .8\n")  # class-1 onion predicted as class 0
    r = ev.evaluate(gt, pr, 2, defect_ids={1})
    assert r["per_class"][0]["tp"] == 1 and r["per_class"][0]["fp"] == 1
    assert r["per_class"][1]["fn"] == 1 and r["per_class"][1]["recall"] == 0.0
    assert r["batch_defective_pct_mae"] == pytest.approx(50.0)


def test_iou():
    assert ev.iou((.5, .5, .2, .2), (.5, .5, .2, .2)) == pytest.approx(1.0)
    assert ev.iou((.1, .1, .1, .1), (.9, .9, .1, .1)) == 0.0


def test_train_template_refuses_to_pretend():
    sys.path.insert(0, str(ROOT / "ml" / "training"))
    import train_template as tt
    with pytest.raises(NotImplementedError):
        tt.build_model(4)
