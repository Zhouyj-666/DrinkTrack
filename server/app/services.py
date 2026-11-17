from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .config import Settings, get_settings
from .errors import APIError
from .models import Session as AuthSession
from .models import User
from .security import expiry_at, hash_password, hash_token, new_session_token, verify_password


def normalize_email(email: str) -> str:
    return email.strip().lower()


def normalize_display_name(display_name: str | None, email: str) -> str:
    if display_name is not None:
        trimmed = display_name.strip()
        if trimmed:
            return trimmed[:40]
    local = email.split("@", 1)[0].strip()
    return local[:40] if local else "酒友"


def create_session(db: Session, user: User, settings: Settings | None = None) -> tuple[str, AuthSession]:
    settings = settings or get_settings()
    token = new_session_token()
    row = AuthSession(
        user_id=user.id,
        token_hash=hash_token(token, settings.api_secret),
        expires_at=expiry_at(settings.token_ttl_days),
    )
    db.add(row)
    db.flush()
    return token, row


def get_valid_session(db: Session, token: str, settings: Settings | None = None) -> AuthSession | None:
    settings = settings or get_settings()
    if not token.strip():
        return None
    token_hash = hash_token(token, settings.api_secret)
    session = db.scalar(select(AuthSession).where(AuthSession.token_hash == token_hash))
    if session is None or session.revoked_at is not None:
        return None
    now = datetime.now(timezone.utc)
    expires_at = session.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at <= now:
        return None
    return session


def register_user(db: Session, email: str, password: str, display_name: str | None) -> tuple[User, str]:
    email = normalize_email(email)
    existing = db.scalar(select(User).where(func.lower(User.email) == email))
    if existing is not None:
        raise APIError(409, "email_taken", "该邮箱已注册")
    user = User(
        email=email,
        password_hash=hash_password(password),
        display_name=normalize_display_name(display_name, email),
    )
    db.add(user)
    db.flush()
    token, _session = create_session(db, user)
    db.commit()
    db.refresh(user)
    return user, token


def login_user(db: Session, email: str, password: str) -> tuple[User, str]:
    email = normalize_email(email)
    user = db.scalar(select(User).where(func.lower(User.email) == email))
    # Same message for missing user and bad password so we do not leak which it is.
    if user is None or not verify_password(password, user.password_hash):
        raise APIError(401, "invalid_credentials", "邮箱或密码不正确")
    token, _session = create_session(db, user)
    db.commit()
    db.refresh(user)
    return user, token


def logout_session(db: Session, session: AuthSession) -> None:
    if session.revoked_at is None:
        session.revoked_at = datetime.now(timezone.utc)
        db.add(session)
        db.commit()
