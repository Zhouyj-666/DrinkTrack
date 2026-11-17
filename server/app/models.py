import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(40))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    # Reserved for a later SMS/phone login. Unused in v1; stays nullable.
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)

    sessions: Mapped[list["Session"]] = relationship(back_populates="user")
    sync_cursor: Mapped["SyncCursor | None"] = relationship(back_populates="user")


class Session(Base):
    """Opaque-token sessions. Logout sets revoked_at; expiry is expires_at.

    If a later revision switches to signed JWTs, keep this table so tokens can
    still be revoked instead of waiting for expiry.
    """

    __tablename__ = "sessions"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped[User] = relationship(back_populates="sessions")


class SyncCursor(Base):
    """Extension point for a later drink-log sync. Not written in v1.

    HealthKit samples (heart rate, SpO2, precise location trails) must never
    be stored here. A future drink_logs table would live alongside this cursor,
    carrying only the fields the user has agreed to sync.
    """

    __tablename__ = "sync_cursors"
    __table_args__ = (UniqueConstraint("user_id", name="uq_sync_cursors_user_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), primary_key=True)
    last_pull_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_push_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped[User] = relationship(back_populates="sync_cursor")
