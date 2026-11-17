from collections.abc import Generator

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from .config import Settings
from .models import Base

_engine: Engine | None = None
_SessionLocal: sessionmaker[Session] | None = None


def _is_sqlite(url: str) -> bool:
    return url.startswith("sqlite")


def init_engine(settings: Settings) -> Engine:
    global _engine, _SessionLocal
    connect_args = {}
    engine_kwargs: dict = {"future": True, "pool_pre_ping": True}
    if _is_sqlite(settings.database_url):
        # :memory: is a new empty database per connection unless we pin one pool.
        connect_args["check_same_thread"] = False
        engine_kwargs["poolclass"] = StaticPool
    engine_kwargs["connect_args"] = connect_args
    _engine = create_engine(settings.database_url, **engine_kwargs)
    if _is_sqlite(settings.database_url):
        @event.listens_for(_engine, "connect")
        def _set_sqlite_fk(dbapi_connection, _connection_record):  # type: ignore[no-untyped-def]
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

    _SessionLocal = sessionmaker(bind=_engine, autoflush=False, autocommit=False, future=True)
    Base.metadata.create_all(_engine)
    return _engine


def get_engine() -> Engine:
    if _engine is None:
        raise RuntimeError("Database engine is not initialized")
    return _engine


def get_db() -> Generator[Session, None, None]:
    if _SessionLocal is None:
        raise RuntimeError("Database engine is not initialized")
    db = _SessionLocal()
    try:
        yield db
    finally:
        db.close()


def reset_engine() -> None:
    """Used by tests to swap the in-memory database between cases."""
    global _engine, _SessionLocal
    if _engine is not None:
        _engine.dispose()
    _engine = None
    _SessionLocal = None
