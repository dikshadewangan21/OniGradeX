import json
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db import get_db
from ..deps import current_user, require_roles
from ..models import PriceCache, Role, User
from ..services import model_registry

router = APIRouter(prefix="/api/v1", tags=["system"])


@router.get("/health")
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok"}


@router.get("/model/status")
def model_status(_: User = Depends(require_roles(Role.admin, Role.officer))):
    st = model_registry.read_status()
    if not st["ready"]:
        st["message"] = "Real grading is unavailable until a trained model and metadata are installed in ml/artifacts/."
    return st


@router.get("/prices/enam")
def enam_price(mandi: str = Query(min_length=2), db: Session = Depends(get_db), _: User = Depends(current_user)):
    """Live e-NAM modal price. Falls back to the last cached value for up to enam_cache_hours."""
    s = get_settings()
    now = datetime.now(timezone.utc)
    cached = db.scalar(select(PriceCache).where(PriceCache.mandi_key == mandi.lower())
                       .order_by(PriceCache.fetched_at.desc()))

    def cached_response(stale_reason: str | None):
        if not cached:
            return None
        fetched = cached.fetched_at if cached.fetched_at.tzinfo else cached.fetched_at.replace(tzinfo=timezone.utc)
        if now - fetched > timedelta(hours=s.enam_cache_hours):
            return None
        return {"mandi": mandi, "modal_price_per_quintal": cached.modal_price_per_quintal,
                "price_date": cached.price_date, "source": "cache", "fetched_at": fetched.isoformat(),
                "stale_reason": stale_reason}

    if not s.enam_api_url:
        r = cached_response("ENAM_API_URL not configured")
        if r:
            return r
        raise HTTPException(503, "e-NAM integration is not configured (set ENAM_API_URL / ENAM_API_KEY)")
    try:
        resp = httpx.get(s.enam_api_url, params={"mandi": mandi, "commodity": "onion"},
                         headers={"Authorization": f"Bearer {s.enam_api_key}"} if s.enam_api_key else {}, timeout=8)
        resp.raise_for_status()
        data = resp.json()
        # Adapter point: map your e-NAM response to these two fields.
        price, price_date = float(data["modal_price"]), str(data["date"])
    except (httpx.HTTPError, ValueError, KeyError, json.JSONDecodeError) as e:
        r = cached_response(f"e-NAM fetch failed: {type(e).__name__}")
        if r:
            return r
        raise HTTPException(503, "e-NAM unavailable and no fresh cached price")
    db.add(PriceCache(mandi_key=mandi.lower(), modal_price_per_quintal=price, price_date=price_date, raw=data))
    db.commit()
    return {"mandi": mandi, "modal_price_per_quintal": price, "price_date": price_date,
            "source": "live", "fetched_at": now.isoformat(), "stale_reason": None}
