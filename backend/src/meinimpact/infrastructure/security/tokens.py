"""JWT access token creation and verification."""

import secrets
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt


class TokenError(ValueError):
    """Raised when a token cannot be trusted."""


@dataclass(frozen=True)
class Principal:
    """Authenticated API principal."""

    subject: str
    installation_id: str
    scopes: tuple[str, ...]


@dataclass(frozen=True)
class TokenPair:
    """Access and refresh token pair."""

    access_token: str
    refresh_token: str
    expires_in_seconds: int


class TokenService:
    """Creates and verifies signed API access tokens."""

    def __init__(
        self,
        secret: str,
        issuer: str,
        audience: str,
        access_token_minutes: int,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        """Initializes the token service."""
        self._secret = secret
        self._issuer = issuer
        self._audience = audience
        self._access_token_minutes = access_token_minutes
        self._clock = clock or (lambda: datetime.now(UTC))

    def create_anonymous_session(
        self,
        installation_id: str,
        app_version: str,
    ) -> TokenPair:
        """Creates an anonymous installation-scoped token pair."""
        now = self._clock()
        expires_at = now + timedelta(minutes=self._access_token_minutes)
        subject = f"installation:{installation_id}"
        claims = {
            "iss": self._issuer,
            "aud": self._audience,
            "sub": subject,
            "iat": int(now.timestamp()),
            "nbf": int(now.timestamp()),
            "exp": int(expires_at.timestamp()),
            "installation_id": installation_id,
            "app_version": app_version,
            "scope": "anonymous",
        }
        encoded_token = jwt.encode(claims, self._secret, algorithm="HS256")
        access_token = (
            encoded_token.decode("utf-8")
            if isinstance(encoded_token, bytes)
            else encoded_token
        )
        return TokenPair(
            access_token=access_token,
            refresh_token=secrets.token_urlsafe(32),
            expires_in_seconds=self._access_token_minutes * 60,
        )

    def verify_access_token(self, token: str) -> Principal:
        """Verifies a signed access token and returns its principal."""
        try:
            claims: dict[str, Any] = jwt.decode(
                token,
                self._secret,
                algorithms=["HS256"],
                issuer=self._issuer,
                audience=self._audience,
            )
        except jwt.InvalidTokenError as error:
            raise TokenError("Token verification failed.") from error
        subject = claims.get("sub")
        installation_id = claims.get("installation_id")
        scope = claims.get("scope", "")
        if not isinstance(subject, str) or not isinstance(installation_id, str):
            raise TokenError("Token subject claims are invalid.")
        scopes = tuple(part for part in scope.split(" ") if part)
        return Principal(
            subject=subject,
            installation_id=installation_id,
            scopes=scopes,
        )
