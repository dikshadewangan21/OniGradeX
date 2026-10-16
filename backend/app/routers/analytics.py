from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db import get_db
from ..deps import current_user, require_roles
from ..models import Certificate, Dispute, DisputeStatus, GradingRule, Mandi, Role, User

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])


@router.get("/summary")
def summary(db: Session = Depends(get_db), _: User = Depends(require_roles(Role.admin))):
    total = db.scalar(select(func.count()).select_from(Certificate)) or 0
    by_grade = {g: n for g, n in db.execute(select(Certificate.grade, func.count()).group_by(Certificate.grade))}
    avg_fresh = db.scalar(select(func.avg(Certificate.fresh_pct)))
    by_mandi = [
        {"mandi_id": mid, "mandi": name, "certificates": n, "avg_fresh_pct": round(af, 2) if af is not None else None}
        for mid, name, n, af in db.execute(
            select(Certificate.mandi_id, Mandi.name, func.count(), func.avg(Certificate.fresh_pct))
            .join(Mandi, Mandi.id == Certificate.mandi_id, isouter=True)
            .group_by(Certificate.mandi_id, Mandi.name))
    ]
    open_disputes = db.scalar(select(func.count()).select_from(Dispute)
                              .where(Dispute.status.in_([DisputeStatus.open, DisputeStatus.reinspection]))) or 0
    return {"total_certificates": total, "by_grade": by_grade,
            "avg_fresh_pct": round(avg_fresh, 2) if avg_fresh is not None else None,
            "by_mandi": by_mandi, "open_disputes": open_disputes,
            "weight_mismatches": db.scalar(select(func.count()).select_from(Certificate)
                                           .where(Certificate.weight_mismatch.is_(True))) or 0}


@router.get("/trends")
def trends(days: int = Query(30, ge=1, le=365), db: Session = Depends(get_db),
           _: User = Depends(require_roles(Role.admin))):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = db.execute(select(Certificate.captured_at, Certificate.fresh_pct, Certificate.grade)
                      .where(Certificate.captured_at >= since)).all()
    buckets: dict[str, dict] = {}
    for ts, fresh, grade in rows:  # bucketed in Python: portable across SQLite/Postgres
        k = ts.date().isoformat()
        b = buckets.setdefault(k, {"date": k, "count": 0, "_fresh": 0.0, "by_grade": {}})
        b["count"] += 1
        b["_fresh"] += fresh
        b["by_grade"][grade] = b["by_grade"].get(grade, 0) + 1
    return [{"date": b["date"], "count": b["count"], "avg_fresh_pct": round(b["_fresh"] / b["count"], 2),
             "by_grade": b["by_grade"]} for b in sorted(buckets.values(), key=lambda x: x["date"])]


@router.get("/stock-health")
def stock_health(db: Session = Depends(get_db), _: User = Depends(require_roles(Role.admin))):
    """Lowest shelf-life first. Only certificates whose model output included shelf_life_days appear."""
    rows = db.scalars(select(Certificate).order_by(Certificate.synced_at.desc()).limit(500)).all()
    items = [{"certificate_id": c.id, "mandi_id": c.mandi_id, "grade": c.grade,
              "shelf_life_days": c.details["shelf_life_days"], "captured_at": c.captured_at.isoformat()}
             for c in rows if isinstance(c.details, dict) and c.details.get("shelf_life_days") is not None]
    items.sort(key=lambda x: x["shelf_life_days"])
    return {"items": items, "note": None if items else "No certificate contains a shelf-life estimate yet."}


@router.get("/flags")
def officer_flags(db: Session = Depends(get_db), _: User = Depends(require_roles(Role.admin))):
    """Rule-based alerts. Thresholds come from settings; flags are leads for audit, not accusations."""
    s = get_settings()
    flags = []
    rule = db.scalar(select(GradingRule).where(GradingRule.is_active.is_(True)))
    top_grade = rule.definition["grades"][0]["grade"] if rule else None
    if top_grade is None:
        return {"flags": [], "note": "No active grading rule; cannot determine top grade."}
    for officer_id, name, n in db.execute(
            select(Certificate.officer_id, User.name, func.count())
            .join(User, User.id == Certificate.officer_id).group_by(Certificate.officer_id, User.name)):
        if n < s.flag_min_batches:
            continue
        a = db.scalar(select(func.count()).select_from(Certificate)
                      .where(Certificate.officer_id == officer_id, Certificate.grade == top_grade)) or 0
        bad_a = db.scalar(select(func.count()).select_from(Certificate)
                          .where(Certificate.officer_id == officer_id, Certificate.grade == top_grade,
                                 Certificate.defective_pct > s.flag_grade_a_max_defective_pct)) or 0
        wm = db.scalar(select(func.count()).select_from(Certificate)
                       .where(Certificate.officer_id == officer_id, Certificate.weight_mismatch.is_(True))) or 0
        reasons = []
        if a / n >= s.flag_grade_a_share:
            reasons.append(f"{a}/{n} certificates are top grade")
        if bad_a:
            reasons.append(f"{bad_a} top-grade certificates exceed {s.flag_grade_a_max_defective_pct}% defective")
        if wm:
            reasons.append(f"{wm} weight mismatches")
        if reasons:
            flags.append({"officer_id": officer_id, "officer": name, "certificates": n, "reasons": reasons})
    return {"flags": flags, "note": None}
