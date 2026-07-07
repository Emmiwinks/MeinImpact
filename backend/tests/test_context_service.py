"""Tests for the AI-powered context generation service."""

from collections.abc import AsyncIterator
from datetime import date

from meinimpact.api.schemas import ActionContextRequest
from meinimpact.domain.entities import ActionType, CivicAction
from meinimpact.services.context_service import ContextService


class _StreamingStub:
    """Yields a fixed response for any prompt."""

    async def stream_text(self, prompt: str) -> AsyncIterator[str]:
        yield "Als Elternteil in Bayern "
        yield "betrifft dich diese Aktion direkt."


_SOLAR_ACTION = CivicAction(
    id="solar-test",
    title="Petition: Solaranlagen auf allen Bundesgebäuden",
    action_type=ActionType.PETITION_SIGNATURE,
    summary="Eine Bundestag-Petition fordert Solarpflicht ab 2027.",
    region="Germany",
    deadline=date(2026, 6, 28),
    effort_minutes=2,
    impact_hint="Bei 50.000 Unterschriften muss der Bundestag beraten.",
    source_url="https://epetitionen.bundestag.de/",
    urgency="mid",
)


async def test_context_service_returns_combined_tokens() -> None:
    service = ContextService(_StreamingStub())
    request = ActionContextRequest(
        lebenssituation=["elternteil"],
        plz_prefix="8",
    )
    result = await service.generate(_SOLAR_ACTION, request)
    assert "Bayern" in result
    assert len(result) > 10


async def test_context_service_handles_empty_demographics() -> None:
    service = ContextService(_StreamingStub())
    request = ActionContextRequest()
    result = await service.generate(_SOLAR_ACTION, request)
    assert len(result) > 0


def test_context_service_prompt_contains_title() -> None:
    service = ContextService(_StreamingStub())
    request = ActionContextRequest(sektor="gesundheit", wohnsituation="mieter")
    prompt = service._build_prompt(_SOLAR_ACTION, request)
    assert _SOLAR_ACTION.title in prompt
    assert "gesundheit" in prompt
    assert "mieter" in prompt


def test_context_service_prompt_uses_region_from_plz_first_digit() -> None:
    service = ContextService(_StreamingStub())
    request = ActionContextRequest(plz_prefix="99")
    prompt = service._build_prompt(_SOLAR_ACTION, request)
    # "9" maps to "Bayern/Thüringen/Sachsen"
    assert "Bayern" in prompt
