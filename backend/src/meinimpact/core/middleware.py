"""Security-focused ASGI middleware."""

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response
from starlette.types import ASGIApp


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Adds defensive HTTP response headers."""

    async def dispatch(
        self,
        request: Request,
        call_next: RequestResponseEndpoint,
    ) -> Response:
        """Adds headers after the downstream handler returns."""
        response = await call_next(request)
        response.headers.setdefault("Cache-Control", "no-store")
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'none'; frame-ancestors 'none'",
        )
        response.headers.setdefault(
            "Permissions-Policy",
            "camera=(), microphone=(), geolocation=(), payment=()",
        )
        return response


class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    """Rejects requests with bodies larger than the configured limit."""

    def __init__(self, app: ASGIApp, max_body_bytes: int) -> None:
        """Initializes the middleware."""
        super().__init__(app)
        self._max_body_bytes = max_body_bytes

    async def dispatch(
        self,
        request: Request,
        call_next: RequestResponseEndpoint,
    ) -> Response:
        """Rejects large requests based on the `Content-Length` header."""
        content_length = request.headers.get("content-length")
        if content_length and int(content_length) > self._max_body_bytes:
            return Response("Request body too large.", status_code=413)
        return await call_next(request)
