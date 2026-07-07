"""Draft service tests."""

from meinimpact.api.schemas import LetterRequest
from meinimpact.domain.entities import ActionType, CivicAction
from meinimpact.infrastructure.ai.dummy_generator import DummyTextGenerator
from meinimpact.services.draft_service import DraftService


async def test_draft_service_streams_tokens_for_brief() -> None:
    service = DraftService(DummyTextGenerator())
    request = LetterRequest(
        action_id="action",
        type="brief",
        recipient_name="Test MdB",
        recipient_party="Test Party",
        tone_descriptors=["balanced"],
    )
    action = CivicAction(
        id="action",
        title="Testmaßnahme",
        action_type=ActionType.REPRESENTATIVE_LETTER,
        summary="Eine Zusammenfassung.",
        region=None,
        deadline=None,
        effort_minutes=3,
        impact_hint="Wird nachverfolgt.",
        source_url="https://example.org",
    )
    chunks = [chunk async for chunk in service.stream_letter(request, action)]
    assert len(chunks) > 0
    assert "".join(chunks).strip()


async def test_draft_service_streams_tokens_for_anfrage() -> None:
    service = DraftService(DummyTextGenerator())
    request = LetterRequest(
        action_id="action",
        type="anfrage",
        recipient_name="Test MdB",
        recipient_party="Test Party",
        tone_descriptors=["reform-minded"],
    )
    action = CivicAction(
        id="action",
        title="Anfragethema",
        action_type=ActionType.PUBLIC_QUESTION,
        summary="Eine öffentliche Anfrage.",
        region=None,
        deadline=None,
        effort_minutes=3,
        impact_hint="Antwort öffentlich einsehbar.",
        source_url="https://example.org",
    )
    chunks = [chunk async for chunk in service.stream_letter(request, action)]
    assert len(chunks) > 0
