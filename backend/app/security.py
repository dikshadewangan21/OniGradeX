import hashlib
import hmac
import json
from datetime import datetime, timedelta, timezone

import bcrypt
from jose import JWTError, jwt

from .config import get_settings

ALGO = "HS256"


def hash_password(pw: str) -> str:
    return bcrypt.hashpw(pw.encode()[:72], bcrypt.gensalt()).decode()


def verify_password(pw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(pw.encode()[:72], hashed.encode())
    except Exception:
        return False


def create_token(user_id: str, role: str) -> str:
    s = get_settings()
    exp = datetime.now(timezone.utc) + timedelta(minutes=s.jwt_expire_minutes)
    return jwt.encode({"sub": user_id, "role": role, "exp": exp}, s.jwt_secret, algorithm=ALGO)


def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, get_settings().jwt_secret, algorithms=[ALGO])
    except JWTError:
        return None


def canonical_payload(fields: dict) -> bytes:
    """Deterministic serialization. The device must build the identical bytes to get a matching hash."""
    return json.dumps(fields, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sign(data: bytes) -> str:
    key = get_settings().certificate_signing_key.encode()
    return hmac.new(key, data, hashlib.sha256).hexdigest()


def verify_signature(data: bytes, signature: str) -> bool:
    return hmac.compare_digest(sign(data), signature)
