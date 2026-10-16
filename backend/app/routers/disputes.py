from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import current_user, require_roles
from ..models import Certificate, Dispute, DisputeStatus, Notification, Role, User
from ..schemas import (
    DisputeAssignIn,
    DisputeIn,
    DisputeOut,
    DisputeReinspectionResultIn,
    DisputeResolveIn,
    NotificationOut,
)
from .certificates import can_view

router = APIRouter(prefix="/api/v1", tags=["disputes"])


@router.post("/disputes", response_model=DisputeOut, status_code=201)
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

    # In-app notification for farmer acknowledging dispute
    db.add(Notification(
        user_id=user.id,
        title="Dispute Submitted",
        message=f"Dispute raised for certificate {c.id[:8]}... It will be reviewed by an admin.",
        dispute_id=d.id,
    ))
    db.commit()
    return d


@router.get("/disputes")
def list_disputes(db: Session = Depends(get_db), user: User = Depends(current_user),
                  status: DisputeStatus | None = None,
                  page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100)):
    if user.role == Role.officer:
        raise HTTPException(403, "Officers cannot list all disputes. Use /disputes/assigned for assigned re-inspections.")
    q = select(Dispute)
    cq = select(func.count()).select_from(Dispute)
    if user.role == Role.farmer:
        q, cq = q.where(Dispute.raised_by == user.id), cq.where(Dispute.raised_by == user.id)
    if status:
        q, cq = q.where(Dispute.status == status), cq.where(Dispute.status == status)
    rows = db.scalars(q.order_by(Dispute.created_at.desc()).offset((page - 1) * page_size).limit(page_size)).all()
    return {"items": [DisputeOut.model_validate(r).model_dump(mode="json") for r in rows],
            "total": db.scalar(cq) or 0, "page": page, "page_size": page_size}


@router.get("/disputes/assigned", response_model=list[DisputeOut])
def list_assigned_disputes(db: Session = Depends(get_db), officer: User = Depends(require_roles(Role.officer))):
    """Officer sees disputes assigned to them for re-inspection."""
    disputes = db.scalars(
        select(Dispute)
        .where(Dispute.assigned_officer_id == officer.id)
        .order_by(Dispute.created_at.desc())
    ).all()
    return disputes


@router.post("/disputes/{dispute_id}/assign", response_model=DisputeOut)
def assign_dispute(dispute_id: str, body: DisputeAssignIn, db: Session = Depends(get_db),
                   admin: User = Depends(require_roles(Role.admin))):
    """Admin assigns a dispute to a named officer for re-inspection."""
    d = db.get(Dispute, dispute_id)
    if not d:
        raise HTTPException(404, "Dispute not found")
    if d.status in (DisputeStatus.upheld, DisputeStatus.overturned):
        raise HTTPException(409, "Dispute already resolved")

    target_officer = db.get(User, body.officer_id)
    if not target_officer or target_officer.role != Role.officer:
        raise HTTPException(422, "Named user is not an officer")

    d.assigned_officer_id = target_officer.id
    d.status = DisputeStatus.reinspection

    # 1. Notify the assigned officer
    db.add(Notification(
        user_id=target_officer.id,
        title="Re-inspection Assigned",
        message=f"You have been assigned to re-inspect certificate {d.certificate_id[:8]}... Reason: {d.reason}",
        dispute_id=d.id,
    ))
    # 2. Notify the farmer who raised the dispute
    db.add(Notification(
        user_id=d.raised_by,
        title="Dispute Assigned for Re-inspection",
        message=f"Your dispute on certificate {d.certificate_id[:8]}... has been assigned to officer {target_officer.name} for re-inspection.",
        dispute_id=d.id,
    ))
    db.commit()
    return d


@router.post("/disputes/{dispute_id}/reinspect", response_model=DisputeOut)
def submit_reinspection_result(dispute_id: str, body: DisputeReinspectionResultIn,
                               db: Session = Depends(get_db),
                               officer: User = Depends(require_roles(Role.officer, Role.admin))):
    """Officer submits the re-inspection certificate result, linking back to the dispute."""
    d = db.get(Dispute, dispute_id)
    if not d:
        raise HTTPException(404, "Dispute not found")
    if d.status in (DisputeStatus.upheld, DisputeStatus.overturned):
        raise HTTPException(409, "Dispute already resolved")
    if officer.role == Role.officer and d.assigned_officer_id != officer.id:
        raise HTTPException(403, "You are not the assigned officer for this dispute")

    re_cert = db.get(Certificate, body.certificate_id)
    if not re_cert:
        raise HTTPException(404, "Re-inspection certificate not found")

    d.reinspection_certificate_id = re_cert.id
    if body.notes:
        d.resolution_note = f"Officer Note: {body.notes}"

    # Notify farmer that re-inspection was completed
    db.add(Notification(
        user_id=d.raised_by,
        title="Re-inspection Completed",
        message=f"Re-inspection completed for certificate {d.certificate_id[:8]}... Re-inspected grade: {re_cert.grade}. Pending admin final review.",
        dispute_id=d.id,
    ))
    db.commit()
    return d


@router.post("/disputes/{dispute_id}/resolve", response_model=DisputeOut)
def resolve(dispute_id: str, body: DisputeResolveIn, db: Session = Depends(get_db),
            admin: User = Depends(require_roles(Role.admin))):
    d = db.get(Dispute, dispute_id)
    if not d:
        raise HTTPException(404, "Dispute not found")
    if d.status in (DisputeStatus.upheld, DisputeStatus.overturned):
        raise HTTPException(409, "Dispute already resolved")
    d.status, d.resolution_note, d.resolved_by = body.status, body.resolution_note, admin.id

    # Notify the farmer of the resolution
    db.add(Notification(
        user_id=d.raised_by,
        title=f"Dispute {body.status.value.title()}",
        message=f"Dispute on certificate {d.certificate_id[:8]}... was marked {body.status.value}. Note: {body.resolution_note}",
        dispute_id=d.id,
    ))
    db.commit()
    return d


@router.get("/notifications", response_model=list[NotificationOut])
def list_notifications(db: Session = Depends(get_db), user: User = Depends(current_user)):
    """In-app notifications for the authenticated user."""
    notes = db.scalars(
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc())
        .limit(100)
    ).all()
    return notes


@router.post("/notifications/{notification_id}/read", response_model=NotificationOut)
def mark_notification_read(notification_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    note = db.get(Notification, notification_id)
    if not note or note.user_id != user.id:
        raise HTTPException(404, "Notification not found")
    note.is_read = True
    db.commit()
    return note
