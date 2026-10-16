from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .db import get_db
from .models import Role, User
from .security import decode_token

bearer = HTTPBearer(auto_error=False)


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)) -> User:
    if creds is None:
        raise HTTPException(401, "Not authenticated")
    payload = decode_token(creds.credentials)
    if not payload:
        raise HTTPException(401, "Invalid or expired token")
    user = db.get(User, payload["sub"])
    if not user or not user.is_active:
        raise HTTPException(401, "User not found or disabled")
    return user


def require_roles(*roles: Role):
    def dep(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(403, "Insufficient permissions")
        return user
    return dep
