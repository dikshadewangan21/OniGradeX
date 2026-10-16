from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import current_user, require_roles
from ..models import GradingRule, Role, User
from ..schemas import RuleIn, RuleOut

router = APIRouter(prefix="/api/v1/rules", tags=["grading-rules"])


@router.post("", response_model=RuleOut, status_code=201)
def create_rule(body: RuleIn, db: Session = Depends(get_db), admin: User = Depends(require_roles(Role.admin))):
    d = body.definition
    grades = [g.grade for g in d.grades]
    if len(set(grades)) != len(grades):
        raise HTTPException(422, "Duplicate grade names")
    if d.reject_grade in grades:
        raise HTTPException(422, "reject_grade must not also appear in grades (it is the catch-all)")
    version = (db.scalar(select(func.max(GradingRule.version))) or 0) + 1
    if body.activate:
        db.execute(update(GradingRule).values(is_active=False))
    r = GradingRule(version=version, definition=d.model_dump(), is_active=body.activate, created_by=admin.id)
    db.add(r)
    db.commit()
    return r


@router.get("/active", response_model=RuleOut)
def active_rule(db: Session = Depends(get_db), _: User = Depends(current_user)):
    r = db.scalar(select(GradingRule).where(GradingRule.is_active.is_(True)))
    if not r:
        raise HTTPException(404, "No grading rules configured. An admin must publish them first.")
    return r


@router.get("", response_model=list[RuleOut])
def list_rules(db: Session = Depends(get_db), _: User = Depends(require_roles(Role.admin))):
    return db.scalars(select(GradingRule).order_by(GradingRule.version.desc())).all()
