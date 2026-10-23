import re
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db import get_db
from ..deps import current_user, require_roles
from ..models import Mandi, Role, User
from ..schemas import LoginIn, MandiIn, MandiOut, RegisterIn, TokenOut, UserOut
from ..security import create_token, hash_password, verify_password
from ..services.rate_limiter import check_rate_limit

router = APIRouter(prefix="/api/v1", tags=["auth"])


def normalize_phone(phone: str) -> str:
    cleaned = re.sub(r"[\s\-\(\)]", "", str(phone).strip())
    if cleaned.startswith("+91"):
        cleaned = cleaned[3:]
    elif cleaned.startswith("91") and len(cleaned) == 12:
        cleaned = cleaned[2:]
    elif cleaned.startswith("0") and len(cleaned) == 11:
        cleaned = cleaned[1:]
    return cleaned


@router.post("/auth/register", response_model=UserOut, status_code=201)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    """Public self-registration creates farmers only. Officers/admins are created by an admin."""
    if body.role != Role.farmer:
        raise HTTPException(403, "Only farmer accounts can self-register")
    phone = normalize_phone(body.phone)
    if db.scalar(select(User).where(User.phone == phone)):
        raise HTTPException(409, "Phone already registered")
    u = User(phone=phone, name=body.name, password_hash=hash_password(body.password), role=Role.farmer)
    db.add(u)
    db.commit()
    return u


@router.post("/auth/login", response_model=TokenOut)
def login(body: LoginIn, db: Session = Depends(get_db)):
    phone = normalize_phone(body.phone)
    s = get_settings()
    check_rate_limit(f"login:{phone}", s.rate_limit_login, resource_name="login")
    u = db.scalar(select(User).where(User.phone == phone))
    # Same error for unknown user / wrong password.
    if not u or not u.is_active or not verify_password(body.password, u.password_hash):
        raise HTTPException(401, "Invalid phone or password")
    role_str = u.role.value if hasattr(u.role, "value") else str(u.role)
    return TokenOut(access_token=create_token(u.id, role_str), role=u.role, user_id=u.id)


@router.get("/auth/me", response_model=UserOut)
def me(user: User = Depends(current_user)):
    return user


@router.post("/admin/users", response_model=UserOut, status_code=201)
def admin_create_user(body: RegisterIn, db: Session = Depends(get_db), _: User = Depends(require_roles(Role.admin))):
    phone = normalize_phone(body.phone)
    if db.scalar(select(User).where(User.phone == phone)):
        raise HTTPException(409, "Phone already registered")
    if body.mandi_id and not db.get(Mandi, body.mandi_id):
        raise HTTPException(422, "Unknown mandi_id")
    u = User(phone=phone, name=body.name, password_hash=hash_password(body.password),
             role=body.role, mandi_id=body.mandi_id)
    db.add(u)
    db.commit()
    return u


@router.post("/mandis", response_model=MandiOut, status_code=201)
def create_mandi(body: MandiIn, db: Session = Depends(get_db), _: User = Depends(require_roles(Role.admin))):
    if db.scalar(select(Mandi).where(Mandi.name == body.name)):
        raise HTTPException(409, "Mandi already exists")
    m = Mandi(**body.model_dump())
    db.add(m)
    db.commit()
    return m


@router.get("/mandis", response_model=list[MandiOut])
def list_mandis(db: Session = Depends(get_db), _: User = Depends(current_user)):
    return db.scalars(select(Mandi).order_by(Mandi.name)).all()
