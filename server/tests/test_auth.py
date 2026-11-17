from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.config import get_settings
from app.db import get_engine
from app.models import Session as AuthSession
from app.security import hash_token, verify_password


def test_health_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"


def test_register_and_me(client):
    response = client.post(
        "/v1/auth/register",
        json={"email": "You@Example.com", "password": "secret-123", "display_name": " 小酌 "},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["token"]
    assert body["user"]["email"] == "you@example.com"
    assert body["user"]["display_name"] == "小酌"

    me = client.get("/v1/auth/me", headers={"Authorization": f"Bearer {body['token']}"})
    assert me.status_code == 200
    assert me.json()["email"] == "you@example.com"


def test_register_duplicate_email(client):
    payload = {"email": "dup@example.com", "password": "secret-123"}
    assert client.post("/v1/auth/register", json=payload).status_code == 200
    response = client.post("/v1/auth/register", json=payload)
    assert response.status_code == 409
    assert response.json() == {"code": "email_taken", "message": "该邮箱已注册"}


def test_invalid_email_message(client):
    response = client.post(
        "/v1/auth/register",
        json={"email": "not-an-email", "password": "secret-123"},
    )
    assert response.status_code == 422
    assert response.json()["message"] == "邮箱格式不正确"


def test_short_password_message(client):
    response = client.post(
        "/v1/auth/register",
        json={"email": "short@example.com", "password": "123"},
    )
    assert response.status_code == 422
    assert response.json()["message"] == "密码至少 8 位"


def test_login_success_and_wrong_password(client):
    client.post("/v1/auth/register", json={"email": "login@example.com", "password": "secret-123"})
    ok = client.post("/v1/auth/login", json={"email": "login@example.com", "password": "secret-123"})
    assert ok.status_code == 200
    assert ok.json()["user"]["email"] == "login@example.com"

    bad = client.post("/v1/auth/login", json={"email": "login@example.com", "password": "wrong-pass"})
    assert bad.status_code == 401
    assert bad.json() == {"code": "invalid_credentials", "message": "邮箱或密码不正确"}

    missing = client.post("/v1/auth/login", json={"email": "nobody@example.com", "password": "secret-123"})
    assert missing.status_code == 401
    assert missing.json()["message"] == "邮箱或密码不正确"


def test_password_is_hashed_not_stored_plain(client):
    client.post("/v1/auth/register", json={"email": "hash@example.com", "password": "secret-123"})
    from app.models import User

    with get_engine().connect() as connection:
        user = connection.execute(select(User)).first()
    # The raw row is easier via a session; re-query through the client-created tables.
    from sqlalchemy.orm import Session

    from app.models import User as UserModel

    with Session(get_engine()) as db:
        user = db.scalar(select(UserModel).where(UserModel.email == "hash@example.com"))
        assert user is not None
        assert user.password_hash != "secret-123"
        assert user.password_hash.startswith("$argon2")
        assert verify_password("secret-123", user.password_hash)


def test_logout_revokes_token(client):
    registered = client.post(
        "/v1/auth/register",
        json={"email": "out@example.com", "password": "secret-123"},
    ).json()
    token = registered["token"]
    headers = {"Authorization": f"Bearer {token}"}
    assert client.get("/v1/auth/me", headers=headers).status_code == 200

    logged_out = client.post("/v1/auth/logout", headers=headers)
    assert logged_out.status_code == 200
    assert logged_out.json()["message"] == "已退出登录"

    me = client.get("/v1/auth/me", headers=headers)
    assert me.status_code == 401
    assert me.json()["message"] == "登录已过期，请重新登录"

    # The raw token must not be stored; only its hash, and that row is revoked.
    from sqlalchemy.orm import Session

    with Session(get_engine()) as db:
        session = db.scalar(
            select(AuthSession).where(AuthSession.token_hash == hash_token(token, get_settings().api_secret))
        )
        assert session is not None
        assert session.revoked_at is not None


def test_me_requires_auth(client):
    response = client.get("/v1/auth/me")
    assert response.status_code == 401
    assert response.json()["message"] == "请先登录"


def test_default_display_name_from_email(client):
    body = client.post(
        "/v1/auth/register",
        json={"email": "sipper@example.com", "password": "secret-123"},
    ).json()
    assert body["user"]["display_name"] == "sipper"
