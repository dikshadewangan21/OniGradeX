"""Test fixtures. Everything here is a TEST FIXTURE: the 'model' files are placeholders used only to
exercise registry/compat logic. No inference happens and nothing here is a real model."""
import json
import os
import sys
import uuid
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))


@pytest.fixture()
def env(tmp_path, monkeypatch):
    meta = tmp_path / "model_metadata.json"
    model = tmp_path / "onion_model.tflite"
    model.write_bytes(b"TEST-FIXTURE-NOT-A-MODEL")
    meta.write_text(json.dumps({
        "model_name": "fixture", "version": "fixture-1", "task": "detection",
        "input": {"width": 64, "height": 64, "channels": 3, "dtype": "float32", "layout": "NHWC"},
        "preprocessing": {"resize": "stretch", "normalize": {"mean": [0, 0, 0], "std": [1, 1, 1]}},
        "outputs": {"boxes": {"index": 0, "format": "xyxy_norm"}, "scores": {"index": 1}, "class_ids": {"index": 2}},
        "classes": [{"id": 0, "name": "fresh", "role": "fresh"}, {"id": 1, "name": "rot", "role": "defect", "detail_key": "rot_pct"}],
        "postprocess": {"score_threshold": 0.25, "nms_in_model": True},
        "trained_on": "n/a (test fixture)", "metrics": {}}))
    # Set TEST_DATABASE_URL to run the suite against PostgreSQL (tables are dropped/recreated per test).
    monkeypatch.setenv("DATABASE_URL", os.environ.get("TEST_DATABASE_URL") or f"sqlite:///{tmp_path/'t.db'}")
    monkeypatch.setenv("JWT_SECRET", "test-jwt-secret")
    monkeypatch.setenv("CERTIFICATE_SIGNING_KEY", "test-signing-key")
    monkeypatch.setenv("MODEL_METADATA_PATH", str(meta))
    monkeypatch.setenv("MODEL_FILE_PATH", str(model))
    monkeypatch.setenv("UPLOAD_DIR", str(tmp_path / "up"))
    monkeypatch.setenv("RATE_LIMIT", "10000/minute")
    monkeypatch.setenv("RATE_LIMIT_LOGIN", "10000/minute")
    monkeypatch.setenv("RATE_LIMIT_SYNC", "10000/minute")
    monkeypatch.setenv("FLAG_MIN_BATCHES", "2")
    from app import config, db
    from app.services.rate_limiter import reset_rate_limits
    reset_rate_limits()
    config.get_settings.cache_clear()
    db.reset_engine()
    return {"meta": meta, "model": model, "tmp": tmp_path}


@pytest.fixture()
def client(env):
    from fastapi.testclient import TestClient
    from app import db, models
    from app.main import create_app
    db.Base.metadata.drop_all(db.get_engine())
    db.Base.metadata.create_all(db.get_engine())
    return TestClient(create_app())


def make_user(role, phone, name="Test User", password="password123", mandi_id=None):
    from app import db
    from app.models import User, Role
    from app.security import hash_password
    s = next(db.get_db())
    u = User(phone=phone, name=name, password_hash=hash_password(password), role=Role(role), mandi_id=mandi_id)
    s.add(u)
    s.commit()
    return u.id


def login(client, phone, password="password123"):
    r = client.post("/api/v1/auth/login", json={"phone": phone, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture()
def admin(client):
    make_user("admin", "9000000001")
    return login(client, "9000000001")


@pytest.fixture()
def officer(client):
    make_user("officer", "9000000002")
    return login(client, "9000000002")


@pytest.fixture()
def farmer(client):
    r = client.post("/api/v1/auth/register", json={"phone": "9000000003", "name": "Farmer F", "password": "password123"})
    assert r.status_code == 201
    return login(client, "9000000003")


RULE = {"definition": {
    "min_confidence": 0.5, "reject_grade": "Rejected",
    "grades": [{"grade": "A", "max_defective_pct": 10}, {"grade": "URS", "max_defective_pct": 30}]},
    "activate": True}


@pytest.fixture()
def rule(client, admin):
    r = client.post("/api/v1/rules", json=RULE, headers=admin)
    assert r.status_code == 201
    return r.json()


def build_cert(rule_version=1, defective=5.0, grade="A", farmer_phone="9000000003", model_version="fixture-1",
               image_sha="a" * 64, confidence=0.9, **over):
    """Builds a certificate body the way a device would, including canonical payload + SHA-256."""
    import hashlib
    cid = str(uuid.uuid4())
    core = {
        "id": cid, "mandi_id": None, "farmer_phone": farmer_phone, "captured_at": "2026-10-12T09:00:00Z",
        "latitude": 21.25, "longitude": 81.63, "model_version": model_version, "rule_version": rule_version,
        "image_sha256": image_sha, "grade": grade, "onion_count": 52, "fresh_pct": round(100 - defective, 2),
        "defective_pct": defective, "batch_confidence": confidence, "details": {"rot_pct": 2.0},
        "scale_weight_kg": None, "estimated_weight_kg": None, "rate_per_kg": 20.0, "rate_source": "test-fixture",
    }
    core.update(over)
    payload = json.dumps(core, sort_keys=True, separators=(",", ":"))
    return {**core, "device_hash": hashlib.sha256(payload.encode()).hexdigest(), "canonical_payload": payload}
