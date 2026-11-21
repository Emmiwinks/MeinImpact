"""Dependency factory tests."""

from unittest.mock import AsyncMock, MagicMock, patch

import meinimpact.api.dependencies as _deps
from meinimpact.api.dependencies import get_ai_generator, get_opportunity_repository
from meinimpact.core.config import Settings
from meinimpact.infrastructure.ai.mistral_client import MistralTextGenerator
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
)


def test_get_ai_generator_uses_mistral_when_api_key_exists() -> None:
    generator = get_ai_generator(
        Settings(
            mistral_api_key="secret",
            mistral_base_url="https://api.example.test/v1",
            mistral_model="model-name",
        )
    )

    assert isinstance(generator, MistralTextGenerator)


def test_get_opportunity_repository_returns_postgres_repository() -> None:
    mock_session = AsyncMock()
    repo = get_opportunity_repository(mock_session)
    assert isinstance(repo, PostgresOpportunityRepository)


async def test_get_db_session_yields_session() -> None:
    mock_session = object()

    async def _fake_session() -> object:
        yield mock_session

    mock_db = MagicMock()
    mock_db.session.return_value = _fake_session()

    results = [s async for s in _deps.get_db_session(mock_db)]

    assert results == [mock_session]


def test_get_database_creates_database_once() -> None:
    original = _deps._db
    _deps._db = None
    try:
        with patch("meinimpact.api.dependencies.Database") as MockDB:
            first = _deps.get_database(Settings(jwt_secret="s"))
            second = _deps.get_database(Settings(jwt_secret="s"))
    finally:
        _deps._db = original

    assert MockDB.call_count == 1
    assert first is second
