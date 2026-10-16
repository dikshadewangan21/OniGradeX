import hashlib
import json
from datetime import timezone
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db import get_db
from ..deps import current_user, require_roles
from ..models import Certificate, GradingRule, Mandi, Role, User
from ..schemas import CertificateIn, CertificateOut, VerifyOut
from ..security import sha256_hex, sign, verify_signature
from ..services import model_registry
from ..services.grading import approx_equal, evaluate_grade

router = APIRouter(prefix="/api/v1", tags=["certificates"])

# Keys the device must include in canonical_payload, and that the server cross-checks.
CORE_KEYS = [
    "id", "mandi_id", "farmer_phone", "captured_at", "latitude", "longitude", "model_version",
    "rule_version", "image_sha256", "grade", "onion_count", "fresh_pct", "defective_pct",
    "batch_confidence", "details", "scale_weight_kg", "estimated_weight_kg", "rate_per_kg", "rate_source",
]


def _signing_input(cert_id: str, officer_id: str, canonical_payload: str) -> bytes:
    return f"{cert_id}|{officer_id}|{canonical_payload}".encode()


def to_out(c: Certificate) -> CertificateOut:
    payout = round(c.rate_per_kg * c.fresh_pct / 100, 2) if c.rate_per_kg is not None else None
    return CertificateOut(
        id=c.id, officer_id=c.officer_id, mandi_id=c.mandi_id, farmer_phone=c.farmer_phone,
        captured_at=c.captured_at, latitude=c.latitude, longitude=c.longitude,
        model_version=c.model_version, rule_version=c.rule_version, image_sha256=c.image_sha256,
        has_image=bool(c.image_path), grade=c.grade, onion_count=c.onion_count, fresh_pct=c.fresh_pct,
        defective_pct=c.defective_pct, details=c.details, scale_weight_kg=c.scale_weight_kg,
        estimated_weight_kg=c.estimated_weight_kg, weight_mismatch=c.weight_mismatch,
        rate_per_kg=c.rate_per_kg, rate_source=c.rate_source, payout_per_kg=payout,
        device_hash=c.device_hash, server_signature=c.server_signature, synced_at=c.synced_at,
    )


def _visible(user: User):
    if user.role == Role.admin:
        return None
    if user.role == Role.officer:
        return Certificate.officer_id == user.id
    return or_(Certificate.farmer_id == user.id, Certificate.farmer_phone == user.phone)


def can_view(user: User, c: Certificate) -> bool:
    cond = _visible(user)
    if cond is None:
        return True
    if user.role == Role.officer:
        return c.officer_id == user.id
    return c.farmer_id == user.id or c.farmer_phone == user.phone


from ..services.rate_limiter import check_rate_limit


@router.post("/certificates/sync", response_model=CertificateOut)
def sync_certificate(body: CertificateIn, db: Session = Depends(get_db),
                     officer: User = Depends(require_roles(Role.officer, Role.admin))):
    """Idempotent upload of an offline-issued certificate. Safe to retry."""
    s = get_settings()
    check_rate_limit(f"sync:{officer.id}", s.rate_limit_sync, resource_name="certificate sync")

    existing = db.get(Certificate, body.id)
    if existing:
        if existing.device_hash != body.device_hash:
            raise HTTPException(409, "Certificate id already exists with different content")
        if existing.officer_id != officer.id and officer.role != Role.admin:
            raise HTTPException(403, "Certificate belongs to another officer")
        return to_out(existing)

    # 1. Integrity of what the device claims to have hashed.
    if sha256_hex(body.canonical_payload.encode()) != body.device_hash:
        raise HTTPException(422, "device_hash does not match canonical_payload")
    try:
        payload = json.loads(body.canonical_payload)
    except json.JSONDecodeError:
        raise HTTPException(422, "canonical_payload is not valid JSON")
    submitted = body.model_dump(mode="json")
    for k in CORE_KEYS:
        if k not in payload:
            raise HTTPException(422, f"canonical_payload missing '{k}'")
        a, b = payload[k], submitted[k]
        if k == "captured_at":
            from datetime import datetime
            try:
                a_dt = datetime.fromisoformat(str(a).replace("Z", "+00:00"))
                b_dt = body.captured_at
                if a_dt.tzinfo is None or b_dt.tzinfo is None or abs((a_dt - b_dt).total_seconds()) > 1:
                    raise ValueError
            except ValueError:
                raise HTTPException(422, "captured_at differs from canonical_payload (timezone required)")
        elif not approx_equal(a, b):
            raise HTTPException(422, f"Field '{k}' differs from canonical_payload")

    # 2. Model compatibility
    reg = model_registry.registered_version()
    if reg is None:
        raise HTTPException(409, "No valid model is registered on the server; cannot accept certificates yet")
    if body.model_version != reg:
        raise HTTPException(409, f"Model version mismatch: server registers '{reg}', certificate has '{body.model_version}'")

    # 3. Grade must follow from the stated rule version
    rule = db.scalar(select(GradingRule).where(GradingRule.version == body.rule_version))
    if not rule:
        raise HTTPException(422, f"Unknown rule_version {body.rule_version}")
    if body.batch_confidence is not None and body.batch_confidence < rule.definition["min_confidence"]:
        raise HTTPException(422, "Confidence below rule threshold; re-capture required, certificate not issued")
    expected = evaluate_grade(rule.definition, body.defective_pct, body.details)
    if expected != body.grade:
        raise HTTPException(422, f"Grade '{body.grade}' does not follow from rule v{rule.version} (expected '{expected}')")

    # 4. References
    mandi_id = body.mandi_id or officer.mandi_id
    if mandi_id and not db.get(Mandi, mandi_id):
        raise HTTPException(422, "Unknown mandi_id")
    farmer = None
    if body.farmer_phone:
        farmer = db.scalar(select(User).where(User.phone == body.farmer_phone, User.role == Role.farmer))

    # 5. Weight cross-check
    mismatch = False
    if body.scale_weight_kg and body.estimated_weight_kg:
        diff = abs(body.scale_weight_kg - body.estimated_weight_kg) / body.scale_weight_kg * 100
        mismatch = diff > s.weight_mismatch_tolerance_pct

    cert = Certificate(
        id=body.id, officer_id=officer.id, mandi_id=mandi_id, farmer_id=farmer.id if farmer else None,
        farmer_phone=body.farmer_phone, captured_at=body.captured_at.astimezone(timezone.utc),
        latitude=body.latitude, longitude=body.longitude, model_version=body.model_version,
        rule_version=body.rule_version, image_sha256=body.image_sha256, grade=body.grade,
        onion_count=body.onion_count, fresh_pct=body.fresh_pct, defective_pct=body.defective_pct,
        batch_confidence=body.batch_confidence, details=body.details,
        scale_weight_kg=body.scale_weight_kg, estimated_weight_kg=body.estimated_weight_kg,
        weight_mismatch=mismatch, rate_per_kg=body.rate_per_kg, rate_source=body.rate_source,
        device_hash=body.device_hash, canonical_payload=body.canonical_payload,
        server_signature=sign(_signing_input(body.id, officer.id, body.canonical_payload)),
    )
    db.add(cert)
    db.commit()
    return to_out(cert)


@router.get("/certificates")
def list_certificates(
    db: Session = Depends(get_db), user: User = Depends(current_user),
    page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
    grade: str | None = None, mandi_id: str | None = None, officer_id: str | None = None,
    sort: str = Query("-captured_at", pattern=r"^-?(captured_at|synced_at|fresh_pct)$"),
):
    conds = []
    vis = _visible(user)
    if vis is not None:
        conds.append(vis)
    if grade:
        conds.append(Certificate.grade == grade)
    if mandi_id:
        conds.append(Certificate.mandi_id == mandi_id)
    if officer_id and user.role == Role.admin:
        conds.append(Certificate.officer_id == officer_id)
    where = and_(*conds) if conds else True
    total = db.scalar(select(func.count()).select_from(Certificate).where(where)) or 0
    col = getattr(Certificate, sort.lstrip("-"))
    q = select(Certificate).where(where).order_by(col.desc() if sort.startswith("-") else col.asc())
    rows = db.scalars(q.offset((page - 1) * page_size).limit(page_size)).all()
    return {"items": [to_out(r).model_dump(mode="json") for r in rows],
            "total": total, "page": page, "page_size": page_size}


@router.get("/certificates/{cert_id}", response_model=CertificateOut)
def get_certificate(cert_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    c = db.get(Certificate, cert_id)
    # 404 (not 403) so IDs of other people's certificates are not confirmable.
    if not c or not can_view(user, c):
        raise HTTPException(404, "Certificate not found")
    return to_out(c)


ALLOWED_MAGIC = {b"\xff\xd8\xff": "image/jpeg", b"\x89PNG\r\n\x1a\n": "image/png"}


@router.post("/certificates/{cert_id}/image", status_code=201)
async def upload_image(cert_id: str, file: UploadFile = File(...), db: Session = Depends(get_db),
                       user: User = Depends(require_roles(Role.officer, Role.admin))):
    s = get_settings()
    c = db.get(Certificate, cert_id)
    if not c or (user.role != Role.admin and c.officer_id != user.id):
        raise HTTPException(404, "Certificate not found")
    if file.content_type not in s.allowed_image_types.split(","):
        raise HTTPException(415, "Only JPEG or PNG images are accepted")
    data = await file.read(s.max_upload_bytes + 1)
    if len(data) > s.max_upload_bytes:
        raise HTTPException(413, "Image too large")
    if not any(data.startswith(m) for m in ALLOWED_MAGIC):
        raise HTTPException(415, "File content is not a JPEG/PNG")
    if hashlib.sha256(data).hexdigest() != c.image_sha256:
        raise HTTPException(422, "Image does not match the image_sha256 on the certificate")
    d = Path(s.upload_dir)
    d.mkdir(parents=True, exist_ok=True)
    ext = "jpg" if data.startswith(b"\xff\xd8") else "png"
    path = d / f"{c.id}.{ext}"
    path.write_bytes(data)
    c.image_path = str(path)
    db.commit()
    return {"certificate_id": c.id, "stored": True}


@router.get("/certificates/{cert_id}/image")
def get_image(cert_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    c = db.get(Certificate, cert_id)
    if not c or not can_view(user, c) or not c.image_path or not Path(c.image_path).is_file():
        raise HTTPException(404, "Image not found")
    return FileResponse(c.image_path)


@router.get("/verify/{cert_id}", response_model=VerifyOut, tags=["public"])
def verify(cert_id: str, db: Session = Depends(get_db)):
    """Public: used by the QR code. Returns validity only, no personal data."""
    c = db.get(Certificate, cert_id)
    if not c:
        return VerifyOut(certificate_id=cert_id, valid=False, reason="No such certificate")
    payload = c.canonical_payload
    if payload is None:
        return VerifyOut(certificate_id=cert_id, valid=False, reason="Stored payload missing")
    if sha256_hex(payload.encode()) != c.device_hash:
        return VerifyOut(certificate_id=cert_id, valid=False, reason="Stored record no longer matches its hash")
    if not verify_signature(_signing_input(c.id, c.officer_id, payload), c.server_signature):
        return VerifyOut(certificate_id=cert_id, valid=False, reason="Server signature invalid")
    # Also confirm queryable columns still agree with the signed payload (catches direct DB edits).
    signed = json.loads(payload)
    for col in ("grade", "fresh_pct", "defective_pct", "onion_count", "image_sha256", "rule_version"):
        if not approx_equal(signed[col], getattr(c, col)):
            return VerifyOut(certificate_id=cert_id, valid=False, reason=f"Column '{col}' differs from signed payload")
    return VerifyOut(certificate_id=cert_id, valid=True, reason="Signature and contents verified")
