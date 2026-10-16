from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import current_user, require_roles
from ..models import Certificate, Dispute, DisputeStatus, Role, User
from ..schemas import DisputeIn, DisputeOut, DisputeResolveIn
from .certificates import can_view

router = APIRouter(prefix="/api/v1/disputes", tags=["disputes"])


@router.post("", response_model=DisputeOut, status_code=201)
def raise_dispute(body: DisputeIn, db: Session = Depends(get_db), user: User = Depends(require_roles(Role.farmer))):
    c = db.get(Certificate, body.certificate_id)
    if not c or not can_view(user, c):
        raise HTTPException(404, "Certificate not found")
    already = db.scalar(select(Dispute).where(
        Dispute.certificate_id == c.id, Dispute.raised_by == user.id,
        Dispute.status.in_([DisputeStatus.open, DisputeStatus.reinspection])))
    if already:
        raise HTTPException(409, "You already have an unresolved dispute for this certificate")
    d = Dispute(certificate_id=c.id, raised_by=user.id, reason=body.reason)
    db.add(d)
    db.commit()
    return d


@router.get("")
def list_disputes(db: Session = Depends(get_db), user: User = Depends(current_user),
                  status: DisputeStatus | None = None,
                  page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100)):
    if user.role == Role.officer:
        raise HTTPException(403, "Officers cannot list disputes")
    q = select(Dispute)
    cq = select(func.count()).select_from(Dispute)
    if user.role == Role.farmer:
        q, cq = q.where(Dispute.raised_by == user.id), cq.where(Dispute.raised_by == user.id)
    if status:
        q, cq = q.where(Dispute.status == status), cq.where(Dispute.status == status)
    rows = db.scalars(q.order_by(Dispute.created_at.desc()).offset((page - 1) * page_size).limit(page_size)).all()
    return {"items": [DisputeOut.model_validate(r).model_dump(mode="json") for r in rows],
            "total": db.scalar(cq) or 0, "page": page, "page_size": page_size}


@router.post("/{dispute_id}/resolve", response_model=DisputeOut)
def resolve(dispute_id: str, body: DisputeResolveIn, db: Session = Depends(get_db),
            admin: User = Depends(require_roles(Role.admin))):
    d = db.get(Dispute, dispute_id)
    if not d:
        raise HTTPException(404, "Dispute not found")
    if d.status in (DisputeStatus.upheld, DisputeStatus.overturned):
        raise HTTPException(409, "Dispute already resolved")
    d.status, d.resolution_note, d.resolved_by = body.status, body.resolution_note, admin.id
    db.commit()
    return d
