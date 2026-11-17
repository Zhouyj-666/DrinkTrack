from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .db import get_db
from .errors import APIError
from .models import Session as AuthSession
from .models import User
from .services import get_valid_session

_bearer = HTTPBearer(auto_error=False)


def require_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> tuple[User, AuthSession]:
    if credentials is None or not credentials.credentials:
        raise APIError(401, "unauthenticated", "请先登录")
    session = get_valid_session(db, credentials.credentials)
    if session is None:
        raise APIError(401, "unauthenticated", "登录已过期，请重新登录")
    return session.user, session
