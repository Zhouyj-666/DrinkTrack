import os

# Must be set before the app package reads settings.
os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///:memory:")
os.environ.setdefault("API_SECRET", "test-secret")
os.environ.setdefault("TOKEN_TTL_DAYS", "30")

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.db import init_engine, reset_engine
from app.main import create_app


@pytest.fixture
def client():
    get_settings.cache_clear()
    reset_engine()
    init_engine(get_settings())
    application = create_app()
    with TestClient(application) as test_client:
        yield test_client
    reset_engine()
    get_settings.cache_clear()
