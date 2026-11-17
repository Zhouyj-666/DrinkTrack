from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import require_user
from ..models import Session as AuthSession
from ..models import User
from ..schemas import AuthResponse, LoginRequest, MessageResponse, RegisterRequest, UserOut
from ..services import login_user, logout_session, register_user

router = APIRouter(prefix="/v1/auth", tags=["auth"])

# Later methods (not implemented in v1, and not exposed as dead UI buttons):
# - Sign in with Apple, after the owner joins the Apple Developer Program
# - Phone number + SMS OTP, after a company SMS qualification is available


@router.post("/register", response_model=AuthResponse)
def register(body: RegisterRequest, db: Session = Depends(get_db)) -> AuthResponse:
    user, token = register_user(db, body.email, body.password, body.display_name)
    return AuthResponse(token=token, user=UserOut.model_validate(user))


@router.post("/login", response_model=AuthResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)) -> AuthResponse:
    user, token = login_user(db, body.email, body.password)
    return AuthResponse(token=token, user=UserOut.model_validate(user))


@router.post("/logout", response_model=MessageResponse)
def logout(
    current: tuple[User, AuthSession] = Depends(require_user),
    db: Session = Depends(get_db),
) -> MessageResponse:
    _user, session = current
    logout_session(db, session)
    return MessageResponse(code="logged_out", message="已退出登录")


@router.get("/me", response_model=UserOut)
def me(current: tuple[User, AuthSession] = Depends(require_user)) -> UserOut:
    user, _session = current
    return UserOut.model_validate(user)
