from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field, field_validator

from .models import DisputeStatus, Role


class RegisterIn(BaseModel):
    phone: str = Field(pattern=r"^\+?[0-9]{10,15}$")
    name: str = Field(min_length=2, max_length=200)
    password: str = Field(min_length=8, max_length=72)
    role: Role = Role.farmer  # self-registration is farmer-only; enforced in router
    mandi_id: str | None = None


class LoginIn(BaseModel):
    phone: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: Role
    user_id: str


class UserOut(BaseModel):
    id: str
    phone: str
    name: str
    role: Role
    mandi_id: str | None
    model_config = {"from_attributes": True}


class MandiIn(BaseModel):
    name: str = Field(min_length=2)
    state: str
    district: str


class MandiOut(MandiIn):
    id: str
    model_config = {"from_attributes": True}


class GradeThreshold(BaseModel):
    grade: str = Field(min_length=1, max_length=32)
    max_defective_pct: float | None = Field(default=None, ge=0, le=100)
    max_rot_pct: float | None = Field(default=None, ge=0, le=100)
    max_sprout_pct: float | None = Field(default=None, ge=0, le=100)
    min_diameter_mm: float | None = Field(default=None, ge=0)


class RuleDefinition(BaseModel):
    min_confidence: float = Field(ge=0, le=1)
    # Evaluated in order, first match wins; the last entry should be the reject catch-all.
    grades: list[GradeThreshold] = Field(min_length=1)
    reject_grade: str


class RuleIn(BaseModel):
    definition: RuleDefinition
    activate: bool = True


class RuleOut(BaseModel):
    id: str
    version: int
    definition: dict
    is_active: bool
    created_at: datetime
    model_config = {"from_attributes": True}


class CertificateIn(BaseModel):
    id: str = Field(pattern=r"^[0-9a-fA-F-]{36}$")
    mandi_id: str | None = None
    farmer_phone: str | None = Field(default=None, pattern=r"^\+?[0-9]{10,15}$")
    captured_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    model_version: str
    rule_version: int
    image_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    grade: str
    onion_count: int = Field(ge=1)
    fresh_pct: float = Field(ge=0, le=100)
    defective_pct: float = Field(ge=0, le=100)
    batch_confidence: float | None = Field(default=None, ge=0, le=1)
    details: dict[str, Any] = {}
    scale_weight_kg: float | None = Field(default=None, gt=0)
    estimated_weight_kg: float | None = Field(default=None, gt=0)
    rate_per_kg: float | None = Field(default=None, ge=0)
    rate_source: str | None = None
    device_hash: str = Field(pattern=r"^[0-9a-f]{64}$")
    # Exact string the device hashed (sha256(utf8(canonical_payload)) == device_hash).
    # Sent verbatim so server and device never disagree on JSON number formatting.
    canonical_payload: str = Field(min_length=2, max_length=100_000)

    @field_validator("defective_pct")
    @classmethod
    def _sum_ok(cls, v, info):
        fresh = info.data.get("fresh_pct")
        if fresh is not None and fresh + v > 100.01:
            raise ValueError("fresh_pct + defective_pct cannot exceed 100")
        return v


class CertificateOut(BaseModel):
    id: str
    officer_id: str
    mandi_id: str | None
    farmer_phone: str | None
    captured_at: datetime
    latitude: float
    longitude: float
    model_version: str
    rule_version: int
    image_sha256: str
    has_image: bool
    grade: str
    onion_count: int
    fresh_pct: float
    defective_pct: float
    details: dict
    scale_weight_kg: float | None
    estimated_weight_kg: float | None
    weight_mismatch: bool
    rate_per_kg: float | None
    rate_source: str | None
    payout_per_kg: float | None
    device_hash: str
    server_signature: str
    synced_at: datetime


class Page(BaseModel):
    items: list[Any]
    total: int
    page: int
    page_size: int


class VerifyOut(BaseModel):
    certificate_id: str
    valid: bool
    reason: str


class DisputeIn(BaseModel):
    certificate_id: str
    reason: str = Field(min_length=10, max_length=2000)


class DisputeResolveIn(BaseModel):
    status: DisputeStatus
    resolution_note: str = Field(min_length=3, max_length=2000)

    @field_validator("status")
    @classmethod
    def _allowed(cls, v):
        if v == DisputeStatus.open:
            raise ValueError("cannot move a dispute back to open")
        return v


class DisputeAssignIn(BaseModel):
    officer_id: str


class DisputeReinspectionResultIn(BaseModel):
    certificate_id: str
    notes: str | None = None


class DisputeOut(BaseModel):
    id: str
    certificate_id: str
    raised_by: str
    reason: str
    status: DisputeStatus
    resolution_note: str | None
    assigned_officer_id: str | None = None
    reinspection_certificate_id: str | None = None
    created_at: datetime
    updated_at: datetime
    model_config = {"from_attributes": True}


class NotificationOut(BaseModel):
    id: str
    user_id: str
    title: str
    message: str
    dispute_id: str | None
    is_read: bool
    created_at: datetime
    model_config = {"from_attributes": True}

