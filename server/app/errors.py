from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class APIError(Exception):
    def __init__(self, status_code: int, code: str, message: str):
        self.status_code = status_code
        self.code = code
        self.message = message
        super().__init__(message)

    def as_response(self) -> JSONResponse:
        return JSONResponse(
            status_code=self.status_code,
            content={"code": self.code, "message": self.message},
        )


def api_error_handler(_request: Request, exc: APIError) -> JSONResponse:
    return exc.as_response()


def validation_error_handler(_request: Request, exc: RequestValidationError) -> JSONResponse:
    """Map FastAPI/Pydantic validation errors to the Chinese copy the app shows."""
    for err in exc.errors():
        loc = err.get("loc") or ()
        typ = err.get("type") or ""
        if "email" in loc:
            if typ == "string_too_short" or typ == "missing":
                return APIError(422, "invalid_email", "请填写邮箱").as_response()
            return APIError(422, "invalid_email", "邮箱格式不正确").as_response()
        if "password" in loc:
            if typ in {"string_too_short", "missing"}:
                return APIError(422, "weak_password", "密码至少 8 位").as_response()
            if typ == "string_too_long":
                return APIError(422, "weak_password", "密码太长了，请控制在 128 位以内").as_response()
            return APIError(422, "weak_password", "密码至少 8 位").as_response()
        if "display_name" in loc:
            return APIError(422, "invalid_display_name", "显示名太长了，请控制在 40 个字以内").as_response()
    return APIError(422, "invalid_request", "请检查填写的内容").as_response()
