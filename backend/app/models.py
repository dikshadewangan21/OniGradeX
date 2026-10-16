import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (JSON, Boolean, DateTime, Enum, Float, ForeignKey, Index,
                        Integer, String, Text, UniqueConstraint)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def new_id() -> str:
    return str(uuid.uuid4())


class Role(str, enum.Enum):
    admin = "admin"
    officer = "officer"
    farmer = "farmer"


class DisputeStatus(str, enum.Enum):
    open = "open"
    reinspection = "reinspection"
    upheld = "upheld"       # original grade stands
    overturned = "overturned"  # grade changed after re-inspection


class Mandi(Base):
    __tablename__ = "mandis"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(200), unique=True)
    state: Mapped[str] = mapped_column(String(100))
    district: Mapped[str] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(200))
    password_hash: Mapped[str] = mapped_column(String(200))
    role: Mapped[Role] = mapped_column(Enum(Role))
    mandi_id: Mapped[str | None] = mapped_column(ForeignKey("mandis.id"), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class GradingRule(Base):
    """Versioned, admin-managed grading policy. Nothing about grade thresholds lives in code."""
    __tablename__ = "grading_rules"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    version: Mapped[int] = mapped_column(Integer, unique=True)
    # {"min_confidence": 0.6, "grades": [{"grade": "A", "max_defective_pct": .., "min_diameter_mm": .., ...}, ...]}
    definition: Mapped[dict] = mapped_column(JSON)
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Certificate(Base):
    __tablename__ = "certificates"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)  # client-generated UUID => idempotent sync
    officer_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    mandi_id: Mapped[str | None] = mapped_column(ForeignKey("mandis.id"), nullable=True, index=True)
    farmer_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    farmer_phone: Mapped[str | None] = mapped_column(String(20), nullable=True, index=True)

    captured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)

    model_version: Mapped[str] = mapped_column(String(64))
    rule_version: Mapped[int] = mapped_column(Integer)
    image_sha256: Mapped[str] = mapped_column(String(64))
    image_path: Mapped[str | None] = mapped_column(String(500), nullable=True)

    grade: Mapped[str] = mapped_column(String(32), index=True)
    onion_count: Mapped[int] = mapped_column(Integer)
    fresh_pct: Mapped[float] = mapped_column(Float)
    defective_pct: Mapped[float] = mapped_column(Float)
    batch_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    details: Mapped[dict] = mapped_column(JSON)  # per-defect pcts, diameters, optional shelf_life_days, volume_cm3...

    scale_weight_kg: Mapped[float | None] = mapped_column(Float, nullable=True)
    estimated_weight_kg: Mapped[float | None] = mapped_column(Float, nullable=True)
    weight_mismatch: Mapped[bool] = mapped_column(Boolean, default=False)

    rate_per_kg: Mapped[float | None] = mapped_column(Float, nullable=True)
    rate_source: Mapped[str | None] = mapped_column(String(100), nullable=True)

    device_hash: Mapped[str] = mapped_column(String(64))  # SHA-256 computed on device
    canonical_payload: Mapped[str] = mapped_column(Text)  # exact bytes the device hashed and server signed
    server_signature: Mapped[str] = mapped_column(String(64))  # HMAC-SHA256 by server
    synced_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    officer = relationship("User", foreign_keys=[officer_id])

    __table_args__ = (Index("ix_cert_officer_captured", "officer_id", "captured_at"),)


class Dispute(Base):
    __tablename__ = "disputes"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    certificate_id: Mapped[str] = mapped_column(ForeignKey("certificates.id"), index=True)
    raised_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    reason: Mapped[str] = mapped_column(Text)
    status: Mapped[DisputeStatus] = mapped_column(Enum(DisputeStatus), default=DisputeStatus.open, index=True)
    resolution_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    resolved_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    __table_args__ = (UniqueConstraint("certificate_id", "raised_by", "status", name="uq_open_dispute"),)


class PriceCache(Base):
    __tablename__ = "price_cache"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    mandi_key: Mapped[str] = mapped_column(String(200), index=True)
    commodity: Mapped[str] = mapped_column(String(50), default="onion")
    modal_price_per_quintal: Mapped[float] = mapped_column(Float)
    price_date: Mapped[str] = mapped_column(String(20))
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    raw: Mapped[dict] = mapped_column(JSON)
