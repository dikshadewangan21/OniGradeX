import hashlib
import json

from conftest import RULE, build_cert, login, make_user


# ---------- auth / access control ----------
def test_health(client):
    assert client.get("/api/v1/health").json() == {"status": "ok"}


def test_unauthenticated_rejected(client):
    assert client.get("/api/v1/certificates").status_code == 401
    assert client.get("/api/v1/rules/active").status_code == 401


def test_self_register_cannot_be_officer_or_admin(client):
    for role in ("officer", "admin"):
        r = client.post("/api/v1/auth/register",
                        json={"phone": "9111111111", "name": "Evil", "password": "password123", "role": role})
        assert r.status_code == 403


def test_bad_login_and_validation(client, farmer):
    assert client.post("/api/v1/auth/login", json={"phone": "9000000003", "password": "wrong"}).status_code == 401
    assert client.post("/api/v1/auth/register", json={"phone": "abc", "name": "x", "password": "short"}).status_code == 422


def test_admin_only_endpoints(client, officer, farmer):
    for h in (officer, farmer):
        assert client.post("/api/v1/rules", json=RULE, headers=h).status_code == 403
        assert client.get("/api/v1/analytics/summary", headers=h).status_code == 403
        assert client.post("/api/v1/mandis", json={"name": "M", "state": "S", "district": "D"}, headers=h).status_code == 403


# ---------- rules ----------
def test_no_rule_configured_is_explicit(client, admin):
    r = client.get("/api/v1/rules/active", headers=admin)
    assert r.status_code == 404 and "No grading rules" in r.json()["detail"]


def test_rule_versioning_and_validation(client, admin, rule):
    assert rule["version"] == 1 and rule["is_active"]
    r2 = client.post("/api/v1/rules", json=RULE, headers=admin).json()
    assert r2["version"] == 2
    assert client.get("/api/v1/rules/active", headers=admin).json()["version"] == 2
    bad = {"definition": {**RULE["definition"], "reject_grade": "A"}}
    assert client.post("/api/v1/rules", json=bad, headers=admin).status_code == 422


# ---------- model registry ----------
def test_model_status_ready_with_fixture(client, officer):
    st = client.get("/api/v1/model/status", headers=officer).json()
    assert st["ready"] and st["version"] == "fixture-1"


def test_model_status_reports_missing_artifacts(client, officer, env):
    env["model"].unlink()
    env["meta"].write_text("{not json")
    st = client.get("/api/v1/model/status", headers=officer).json()
    assert not st["ready"] and st["version"] is None
    assert any("valid JSON" in p for p in st["problems"]) and "unavailable" in st["message"]


def test_metadata_missing_keys(client, officer, env):
    env["meta"].write_text(json.dumps({"version": "x"}))
    st = client.get("/api/v1/model/status", headers=officer).json()
    assert not st["ready"] and any("metadata invalid" in p for p in st["problems"])


# ---------- certificate sync ----------
def test_sync_and_verify_roundtrip(client, officer, rule):
    body = build_cert()
    r = client.post("/api/v1/certificates/sync", json=body, headers=officer)
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["grade"] == "A" and out["payout_per_kg"] == 19.0 and out["server_signature"]
    v = client.get(f"/api/v1/verify/{body['id']}").json()  # public, no auth
    assert v["valid"] is True


def test_sync_is_idempotent_and_conflicts_on_different_content(client, officer, rule):
    body = build_cert()
    a = client.post("/api/v1/certificates/sync", json=body, headers=officer).json()
    b = client.post("/api/v1/certificates/sync", json=body, headers=officer).json()
    assert a["server_signature"] == b["server_signature"]
    other = build_cert(defective=25.0, grade="URS")
    other["id"], other["canonical_payload"] = body["id"], other["canonical_payload"]
    assert client.post("/api/v1/certificates/sync", json=other, headers=officer).status_code == 409


def test_tampered_payload_rejected(client, officer, rule):
    body = build_cert()
    body["onion_count"] = 500  # edited after hashing; passes schema, must fail payload cross-check
    r = client.post("/api/v1/certificates/sync", json=body, headers=officer)
    assert r.status_code == 422 and "differs" in r.json()["detail"]


def test_hash_mismatch_rejected(client, officer, rule):
    body = build_cert()
    body["device_hash"] = "0" * 64
    assert client.post("/api/v1/certificates/sync", json=body, headers=officer).status_code == 422


def test_grade_must_follow_rule(client, officer, rule):
    body = build_cert(defective=40.0, grade="A")  # 40% defective cannot be Grade A
    r = client.post("/api/v1/certificates/sync", json=body, headers=officer)
    assert r.status_code == 422 and "does not follow" in r.json()["detail"]
    ok = build_cert(defective=40.0, grade="Rejected")
    assert client.post("/api/v1/certificates/sync", json=ok, headers=officer).status_code == 200


def test_low_confidence_not_issued(client, officer, rule):
    r = client.post("/api/v1/certificates/sync", json=build_cert(confidence=0.2), headers=officer)
    assert r.status_code == 422 and "re-capture" in r.json()["detail"]


def test_model_version_mismatch_and_missing_model(client, officer, rule, env):
    r = client.post("/api/v1/certificates/sync", json=build_cert(model_version="other"), headers=officer)
    assert r.status_code == 409 and "mismatch" in r.json()["detail"]
    env["model"].unlink()
    r = client.post("/api/v1/certificates/sync", json=build_cert(), headers=officer)
    assert r.status_code == 409 and "No valid model" in r.json()["detail"]


def test_unknown_rule_version(client, officer, rule):
    assert client.post("/api/v1/certificates/sync", json=build_cert(rule_version=99), headers=officer).status_code == 422


def test_farmer_cannot_sync(client, farmer, rule):
    assert client.post("/api/v1/certificates/sync", json=build_cert(), headers=farmer).status_code == 403


def test_invalid_schema(client, officer, rule):
    body = build_cert()
    body["latitude"] = 500
    assert client.post("/api/v1/certificates/sync", json=body, headers=officer).status_code == 422


def test_weight_mismatch_flagged(client, officer, rule):
    body = build_cert(scale_weight_kg=100.0, estimated_weight_kg=60.0)
    assert client.post("/api/v1/certificates/sync", json=body, headers=officer).json()["weight_mismatch"] is True
    body2 = build_cert(scale_weight_kg=100.0, estimated_weight_kg=95.0)
    assert client.post("/api/v1/certificates/sync", json=body2, headers=officer).json()["weight_mismatch"] is False


def test_direct_db_edit_detected_by_verify(client, officer, rule):
    body = build_cert()
    client.post("/api/v1/certificates/sync", json=body, headers=officer)
    from app import db
    from app.models import Certificate
    s = next(db.get_db())
    c = s.get(Certificate, body["id"])
    c.grade = "Rejected"
    s.commit()
    v = client.get(f"/api/v1/verify/{body['id']}").json()
    assert v["valid"] is False and "grade" in v["reason"]


def test_verify_unknown(client):
    assert client.get("/api/v1/verify/does-not-exist").json()["valid"] is False


# ---------- visibility / pagination ----------
def test_visibility_rules(client, admin, officer, farmer, rule):
    mine = build_cert()
    stranger = build_cert(farmer_phone="9555555555")
    for b in (mine, stranger):
        assert client.post("/api/v1/certificates/sync", json=b, headers=officer).status_code == 200
    f = client.get("/api/v1/certificates", headers=farmer).json()
    assert f["total"] == 1 and f["items"][0]["id"] == mine["id"]
    assert client.get(f"/api/v1/certificates/{stranger['id']}", headers=farmer).status_code == 404
    assert client.get("/api/v1/certificates", headers=admin).json()["total"] == 2
    # another officer sees nothing
    make_user("officer", "9000000009")
    o2 = login(client, "9000000009")
    assert client.get("/api/v1/certificates", headers=o2).json()["total"] == 0


def test_pagination_filter_sort(client, officer, rule):
    for d in (5, 6, 7):
        client.post("/api/v1/certificates/sync", json=build_cert(defective=float(d)), headers=officer)
    client.post("/api/v1/certificates/sync", json=build_cert(defective=50.0, grade="Rejected"), headers=officer)
    r = client.get("/api/v1/certificates?page=1&page_size=2&sort=-fresh_pct", headers=officer).json()
    assert r["total"] == 4 and len(r["items"]) == 2
    assert r["items"][0]["fresh_pct"] >= r["items"][1]["fresh_pct"]
    assert client.get("/api/v1/certificates?grade=Rejected", headers=officer).json()["total"] == 1
    assert client.get("/api/v1/certificates?sort=bogus", headers=officer).status_code == 422


# ---------- image upload ----------
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 100


def test_image_upload_validations(client, officer, rule):
    body = build_cert(image_sha=hashlib.sha256(JPEG).hexdigest())
    client.post("/api/v1/certificates/sync", json=body, headers=officer)
    url = f"/api/v1/certificates/{body['id']}/image"
    ok = client.post(url, files={"file": ("a.jpg", JPEG, "image/jpeg")}, headers=officer)
    assert ok.status_code == 201
    assert client.get(url, headers=officer).content == JPEG
    assert client.post(url, files={"file": ("a.jpg", JPEG + b"x", "image/jpeg")}, headers=officer).status_code == 422
    assert client.post(url, files={"file": ("a.txt", b"hi", "text/plain")}, headers=officer).status_code == 415
    assert client.post(url, files={"file": ("a.jpg", b"not an image", "image/jpeg")}, headers=officer).status_code == 415


# ---------- disputes ----------
def test_dispute_flow(client, admin, officer, farmer, rule):
    b = build_cert()
    client.post("/api/v1/certificates/sync", json=b, headers=officer)
    r = client.post("/api/v1/disputes", json={"certificate_id": b["id"], "reason": "Heatmap marks healthy onions"}, headers=farmer)
    assert r.status_code == 201
    did = r.json()["id"]
    assert client.post("/api/v1/disputes", json={"certificate_id": b["id"], "reason": "again again again"}, headers=farmer).status_code == 409
    assert client.get("/api/v1/disputes", headers=admin).json()["total"] == 1
    assert client.get("/api/v1/disputes", headers=officer).status_code == 403
    assert client.post(f"/api/v1/disputes/{did}/resolve", json={"status": "upheld", "resolution_note": "ok"}, headers=farmer).status_code == 403
    assert client.post(f"/api/v1/disputes/{did}/resolve", json={"status": "open", "resolution_note": "ok"}, headers=admin).status_code == 422
    res = client.post(f"/api/v1/disputes/{did}/resolve", json={"status": "overturned", "resolution_note": "Re-inspected"}, headers=admin)
    assert res.status_code == 200 and res.json()["status"] == "overturned"
    assert client.post(f"/api/v1/disputes/{did}/resolve", json={"status": "upheld", "resolution_note": "nope"}, headers=admin).status_code == 409


def test_dispute_on_foreign_certificate_hidden(client, officer, farmer, rule):
    b = build_cert(farmer_phone="9555555555")
    client.post("/api/v1/certificates/sync", json=b, headers=officer)
    r = client.post("/api/v1/disputes", json={"certificate_id": b["id"], "reason": "not mine but trying"}, headers=farmer)
    assert r.status_code == 404


# ---------- analytics ----------
def test_analytics_from_real_rows(client, admin, officer, rule):
    assert client.get("/api/v1/analytics/summary", headers=admin).json()["total_certificates"] == 0
    for d, g in ((5, "A"), (6, "A"), (7, "A")):
        client.post("/api/v1/certificates/sync", json=build_cert(defective=float(d), grade=g), headers=officer)
    s = client.get("/api/v1/analytics/summary", headers=admin).json()
    assert s["total_certificates"] == 3 and s["by_grade"] == {"A": 3}
    assert round(s["avg_fresh_pct"], 1) == 94.0
    flags = client.get("/api/v1/analytics/flags", headers=admin).json()["flags"]
    assert flags and "3/3" in flags[0]["reasons"][0]
    assert client.get("/api/v1/analytics/stock-health", headers=admin).json()["items"] == []


def test_stock_health_only_uses_model_provided_shelf_life(client, admin, officer, rule):
    b = build_cert(details={"rot_pct": 1.0, "shelf_life_days": 12})
    client.post("/api/v1/certificates/sync", json=b, headers=officer)
    items = client.get("/api/v1/analytics/stock-health", headers=admin).json()["items"]
    assert items[0]["shelf_life_days"] == 12


# ---------- prices ----------
def test_enam_not_configured_is_503_not_fake(client, officer):
    r = client.get("/api/v1/prices/enam?mandi=Raipur", headers=officer)
    assert r.status_code == 503 and "not configured" in r.json()["detail"]


# ---------- error hygiene ----------
def test_404_has_no_internals(client, officer):
    r = client.get("/api/v1/certificates/xyz", headers=officer)
    assert r.status_code == 404 and "Traceback" not in r.text
