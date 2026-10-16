import pytest
from app.services.rate_limiter import reset_rate_limits
from conftest import build_cert, make_user, login


@pytest.fixture(autouse=True)
def clean_rate_limits():
    reset_rate_limits()
    yield
    reset_rate_limits()


def test_login_rate_limiting(client):
    from app.config import get_settings
    settings = get_settings()
    orig = settings.rate_limit_login
    settings.rate_limit_login = "5/minute"
    phone = "9888888888"
    try:
        # Settings allow 5 attempts per minute
        for _ in range(5):
            r = client.post("/api/v1/auth/login", json={"phone": phone, "password": "wrongpassword"})
            assert r.status_code == 401

        # 6th attempt should be blocked by rate limiter with 429
        r6 = client.post("/api/v1/auth/login", json={"phone": phone, "password": "wrongpassword"})
        assert r6.status_code == 429
        assert "Rate limit exceeded" in r6.json()["detail"]
        assert "Retry-After" in r6.headers
    finally:
        settings.rate_limit_login = orig


def test_certificate_sync_rate_limiting(client, officer, rule):
    # Set tight limit on officer sync for test
    from app.config import get_settings
    settings = get_settings()
    orig_limit = settings.rate_limit_sync
    settings.rate_limit_sync = "3/minute"
    try:
        # Sync 3 certificates
        for i in range(3):
            cid = f"00000000-0000-0000-0000-00000000000{i}"
            c = build_cert(cid=cid, grade="A", fresh_pct=90.0, defective_pct=10.0)
            res = client.post("/api/v1/certificates/sync", json=c, headers=officer)
            assert res.status_code == 200

        # 4th certificate sync should be rate limited
        cid4 = "00000000-0000-0000-0000-000000000009"
        c4 = build_cert(cid=cid4, grade="A", fresh_pct=90.0, defective_pct=10.0)
        res4 = client.post("/api/v1/certificates/sync", json=c4, headers=officer)
        assert res4.status_code == 429
        assert "Rate limit exceeded" in res4.json()["detail"]
    finally:
        settings.rate_limit_sync = orig_limit


def test_admin_dispute_workflow_and_notifications(client, admin, farmer, officer, rule):
    # 1. Sync certificate for farmer
    cert = build_cert(farmer_phone="9000000003", grade="A", defective=5.0)
    cid = cert["id"]
    res = client.post("/api/v1/certificates/sync", json=cert, headers=officer)
    assert res.status_code == 200

    # 2. Farmer raises dispute
    d_res = client.post("/api/v1/disputes", json={"certificate_id": cid, "reason": "Grade appears wrong for this batch"}, headers=farmer)
    assert d_res.status_code == 201
    dispute_id = d_res.json()["id"]

    # Check farmer got in-app notification
    notifs = client.get("/api/v1/notifications", headers=farmer).json()
    assert len(notifs) >= 1
    assert notifs[0]["title"] == "Dispute Submitted"
    assert not notifs[0]["is_read"]

    # 3. Admin assigns re-inspection to named officer
    officer_id = client.get("/api/v1/auth/me", headers=officer).json()["id"]
    assign_res = client.post(f"/api/v1/disputes/{dispute_id}/assign", json={"officer_id": officer_id}, headers=admin)
    assert assign_res.status_code == 200
    assert assign_res.json()["status"] == "reinspection"
    assert assign_res.json()["assigned_officer_id"] == officer_id

    # 4. Officer sees assigned dispute in /disputes/assigned
    assigned_list = client.get("/api/v1/disputes/assigned", headers=officer).json()
    assert any(d["id"] == dispute_id for d in assigned_list)

    # Officer got notification
    off_notifs = client.get("/api/v1/notifications", headers=officer).json()
    assert any(n["title"] == "Re-inspection Assigned" for n in off_notifs)

    # 5. Officer issues re-inspection certificate and links it
    re_cert = build_cert(farmer_phone="9000000003", grade="A", defective=8.0)
    re_cid = re_cert["id"]
    client.post("/api/v1/certificates/sync", json=re_cert, headers=officer)

    link_res = client.post(f"/api/v1/disputes/{dispute_id}/reinspect", json={"certificate_id": re_cid, "notes": "Re-inspection confirms higher defect rate"}, headers=officer)
    assert link_res.status_code == 200
    assert link_res.json()["reinspection_certificate_id"] == re_cid

    # 6. Admin resolves dispute as overturned
    resolve_res = client.post(f"/api/v1/disputes/{dispute_id}/resolve", json={"status": "overturned", "resolution_note": "Re-inspection grade B accepted"}, headers=admin)
    assert resolve_res.status_code == 200
    assert resolve_res.json()["status"] == "overturned"

    # Farmer got resolution notification
    farmer_notifs = client.get("/api/v1/notifications", headers=farmer).json()
    res_notif = next(n for n in farmer_notifs if "Overturned" in n["title"])
    assert "Re-inspection grade B accepted" in res_notif["message"]

    # Farmer marks notification read
    read_res = client.post(f"/api/v1/notifications/{res_notif['id']}/read", headers=farmer)
    assert read_res.status_code == 200
    assert read_res.json()["is_read"] is True
