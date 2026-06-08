"""Dependency factory tests."""

from unittest.mock import AsyncMock, MagicMock, patch

import meinimpact.api.dependencies as _deps
from meinimpact.api.dependencies import get_action_repository, get_ai_generator
from meinimpact.core.config import Settings
from meinimpact.infrastructure.actions.postgres_action_repository import (
    PostgresActionRepository,
)
from meinimpact.infrastructure.ai.mistral_client import MistralTextGenerator


def test_get_ai_generator_uses_mistral_when_api_key_exists() -> None:
    generator = get_ai_generator(
        Settings(
            mistral_api_key="secret",
            mistral_base_url="https://api.example.test/v1",
            mistral_model="model-name",
        )
    )

    assert isinstance(generator, MistralTextGenerator)


def test_get_action_repository_returns_postgres_repository() -> None:
    mock_session = AsyncMock()
    repo = get_action_repository(mock_session)
    assert isinstance(repo, PostgresActionRepository)


async def test_get_db_session_yields_session() -> None:
    mock_session = object()

    async def _fake_session() -> object:
        yield mock_session

    mock_db = MagicMock()
    mock_db.session.return_value = _fake_session()

    original = _deps._db
    try:
        _deps._db = mock_db
        results = [s async for s in _deps.get_db_session(Settings(jwt_secret="s"))]
    finally:
        _deps._db = original

    assert results == [mock_session]


async def test_get_db_session_creates_database_on_first_call() -> None:
    original = _deps._db
    _deps._db = None

    async def _fake_session() -> object:
        yield object()

    with patch("meinimpact.api.dependencies.Database") as MockDB:
        instance = MagicMock()
        instance.session.return_value = _fake_session()
        MockDB.return_value = instance
        _ = [s async for s in _deps.get_db_session(Settings(jwt_secret="s"))]

    assert MockDB.called
    _deps._db = original
