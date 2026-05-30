"""Draft service tests."""

import pytest

from meinimpact.domain.entities import ActionType, CivicAction, UserProfile
from meinimpact.infrastructure.ai.dummy_generator import DummyTextGenerator
from meinimpact.services.draft_service import DraftService


@pytest.mark.asyncio
async def test_draft_service_streams_dummy_text() -> None:
    service = DraftService(DummyTextGenerator())
    chunks = [
        chunk
        async for chunk in service.stream_draft(
            action=CivicAction(
                id="action",
                title="Action title",
                action_type=ActionType.REPRESENTATIVE_LETTER,
                summary="Action summary",
                topics=("democracy",),
                region=None,
                deadline=None,
                effort_minutes=3,
                impact_hint="Track a response.",
                source_url="https://example.org",
            ),
            profile=UserProfile(topics=("democracy",), value_axes={}),
            personal_context=None,
            tone="respectful",
        )
    ]
    assert "Dear " in "".join(chunks)
