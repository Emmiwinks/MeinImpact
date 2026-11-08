"""Draft service tests."""

import uuid
from datetime import UTC, date, datetime

from meinimpact.domain.entities import Opportunity
from meinimpact.infrastructure.ai.dummy_generator import DummyTextGenerator
from meinimpact.services.draft_service import DraftService, build_prompt

DECISION = Opportunity(
    id=uuid.UUID(int=7),
    source_org="Ratsinformationssystem Dresden",
    source_url="https://ratsinfo.dresden.de/vo0050.asp?__kvonr=1",
    kind="decision",
    status="open",
    region="dresden",
    locality="Landeshauptstadt Dresden",
    organizer="Ausschuss für Stadtentwicklung",
    title="Soll der Radweg an der Bautzner Straße gebaut werden?",
    summary="Die Stadt will einen geschützten Radweg bauen.",
    affected_tags=("Verkehr",),
    lebenslagen=(),
    werte_relevanz={},
    pro_argumente=("Sicherer für Radfahrende",),
    contra_argumente=("Weniger Parkplätze",),
    personal_impact_snippets={},
    everyday_relevance=4,
    accessibility=4,
    districts=("Radeberger Vorstadt",),
    opens_on=None,
    closes_on=date(2026, 11, 26),
    support_count=None,
    support_goal=None,
    support_count_as_of=None,
    first_seen_at=datetime(2026, 11, 8, tzinfo=UTC),
)


def test_prompt_carries_the_decision_and_the_users_notes() -> None:
    prompt = build_prompt(DECISION, "  Ich fahre dort täglich zur Arbeit.  ")

    assert "„Ausschuss für Stadtentwicklung“" in prompt
    assert "am 26.11.2026" in prompt
    assert "Soll der Radweg an der Bautzner Straße gebaut werden?" in prompt
    assert "Sicherer für Radfahrende" in prompt
    assert "Weniger Parkplätze" in prompt
    assert "<<<\nIch fahre dort täglich zur Arbeit.\n>>>" in prompt


def test_prompt_without_notes_asks_for_a_neutral_letter() -> None:
    for notes in (None, "   "):
        prompt = build_prompt(DECISION, notes)
        assert "<<<" not in prompt
        assert "Bleib neutral" in prompt


async def test_draft_service_streams_tokens() -> None:
    service = DraftService(DummyTextGenerator())

    chunks = [chunk async for chunk in service.stream_letter(DECISION, None)]

    assert "".join(chunks).strip()
