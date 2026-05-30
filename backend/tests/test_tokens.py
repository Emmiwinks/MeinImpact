"""Token service tests."""

from datetime import UTC, datetime

import jwt
import pytest

from meinimpact.infrastructure.security.tokens import TokenError, TokenService


def test_token_service_creates_and_verifies_anonymous_session() -> None:
    service = TokenService(
        secret="test-secret-with-at-least-thirty-two-bytes",
        issuer="issuer",
        audience="audience",
        access_token_minutes=15,
        clock=lambda: datetime.now(UTC),
    )
    token_pair = service.create_anonymous_session(
        installation_id="installation-1",
        app_version="0.1.0",
    )
    principal = service.verify_access_token(token_pair.access_token)
    assert principal.subject == "installation:installation-1"
    assert principal.installation_id == "installation-1"
    assert principal.scopes == ("anonymous",)
    assert token_pair.expires_in_seconds == 900


def test_token_service_rejects_invalid_token() -> None:
    service = TokenService(
        secret="test-secret-with-at-least-thirty-two-bytes",
        issuer="issuer",
        audience="audience",
        access_token_minutes=15,
    )
    with pytest.raises(TokenError):
        service.verify_access_token("not-a-token")


def test_token_service_rejects_token_without_subject_claims() -> None:
    service = TokenService(
        secret="test-secret-with-at-least-thirty-two-bytes",
        issuer="issuer",
        audience="audience",
        access_token_minutes=15,
    )
    now = datetime.now(UTC)
    encoded_token = jwt.encode(
        {
            "iss": "issuer",
            "aud": "audience",
            "iat": int(now.timestamp()),
            "nbf": int(now.timestamp()),
            "exp": int(now.timestamp()) + 60,
        },
        "test-secret-with-at-least-thirty-two-bytes",
        algorithm="HS256",
    )
    token = (
        encoded_token.decode("utf-8")
        if isinstance(encoded_token, bytes)
        else encoded_token
    )

    with pytest.raises(TokenError):
        service.verify_access_token(token)
