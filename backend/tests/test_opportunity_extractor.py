"""Tests for Mistral-based opportunity extraction."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime
from types import TracebackType

import httpx
import pytest

from meinimpact.infrastructure.ai.opportunity_extractor import (
    OpportunityExtractor,
    _normalize_extraction,
)
from meinimpact.infrastructure.sources.tavily_opportunity_adapter import (
    RawOpportunityItem,
)


def _item(content: str = "Ein Testinhalt.") -> RawOpportunityItem:
    return RawOpportunityItem(
        title="Testpetition",
        url="https://openpetition.de/petition/online/test",
        domain="openpetition.de",
        source_org="openPetition",
        content=content,
        region="bund",
    )


class _FakeResponse:
    def __init__(self, body: dict[str, object], status: int = 200) -> None:
        self._body = body
        self.status_code = status

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise httpx.HTTPStatusError("boom", request=None, response=self)  # type: ignore[arg-type]

    def json(self) -> dict[str, object]:
        return self._body


def _chat_response(content_json: dict[str, object]) -> dict[str, object]:
    return {"choices": [{"message": {"content": json.dumps(content_json)}}]}


def _fake_client_returning(content_json: dict[str, object] | None, status: int = 200):
    class _Client:
        def __init__(self, timeout: float) -> None:
            del timeout

        async def __aenter__(self) -> _Client:
            return self

        async def __aexit__(
            self,
            exc_type: type[BaseException] | None,
            exc: BaseException | None,
            traceback: TracebackType | None,
        ) -> None:
            del exc_type, exc, traceback

        async def post(
            self, url: str, headers: dict[str, str], json: dict[str, object]
        ):
            del url, headers, json
            body = _chat_response(content_json or {})
            return _FakeResponse(body, status=status)

    return _Client


@pytest.mark.asyncio
async def test_extract_returns_none_when_not_actionable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        httpx, "AsyncClient", _fake_client_returning({"is_actionable": False})
    )
    extractor = OpportunityExtractor(
        api_key="k", base_url="https://x.test/v1", model="m"
    )

    result = await extractor.extract(_item())

    assert result is None


@pytest.mark.asyncio
async def test_extract_returns_none_on_http_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(httpx, "AsyncClient", _fake_client_returning(None, status=500))
    extractor = OpportunityExtractor(
        api_key="k", base_url="https://x.test/v1", model="m"
    )

    result = await extractor.extract(_item())

    assert result is None


@pytest.mark.asyncio
async def test_extract_parses_full_valid_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    payload = {
        "is_actionable": True,
        "decision_object": "Mietendeckel einführen",
        "plain_language_title": "Soll ein Mietendeckel eingeführt werden?",
        "plain_language_summary": "Zusammenfassung.",
        "affected_tags": ["Wohnen/Miete"],
        "werte_relevanz": {"equality_markets": -0.8},
        "deadline": "2026-12-01",
        "support_count": 12345,
        "support_count_as_of": "2026-09-27",
        "content_published_at": None,
        "pro_argumente": ["Argument 1"],
        "contra_argumente": ["Gegenargument 1"],
        "personal_impact_snippets": {"wohnsituation:mieter": "Betrifft dich direkt."},
        "action_types": ["petition"],
    }
    monkeypatch.setattr(httpx, "AsyncClient", _fake_client_returning(payload))
    extractor = OpportunityExtractor(
        api_key="k", base_url="https://x.test/v1", model="m"
    )

    result = await extractor.extract(_item())

    assert result is not None
    assert result["decision_object"] == "Mietendeckel einführen"
    assert result["affected_tags"] == ["Wohnen/Miete"]
    assert result["werte_relevanz"] == {"equality_markets": -0.8}
    assert result["deadline"] == date(2026, 12, 1)
    assert result["support_count"] == 12345
    assert result["support_count_as_of"] == datetime(2026, 9, 27, tzinfo=UTC)
    assert result["content_published_at"] is None
    assert result["personal_impact_snippets"] == {
        "wohnsituation:mieter": "Betrifft dich direkt."
    }
    assert result["action_types"] == ["petition"]


def test_normalize_strips_axes_not_relevant_to_detected_tags() -> None:
    raw = {
        "affected_tags": ["Umwelt/Natur"],  # no axis per TAG_AXES
        "werte_relevanz": {"tradition_progress": 0.8, "equality_markets": 0.0},
        "personal_impact_snippets": {},
    }
    normalized = _normalize_extraction(raw)
    assert normalized["werte_relevanz"] == {}


def test_normalize_keeps_only_axes_matching_the_tag() -> None:
    raw = {
        "affected_tags": ["Wohnen/Miete"],  # equality_markets only
        "werte_relevanz": {"equality_markets": -0.5, "liberty_authority": 0.9},
        "personal_impact_snippets": {},
    }
    normalized = _normalize_extraction(raw)
    assert normalized["werte_relevanz"] == {"equality_markets": -0.5}


def test_normalize_drops_unknown_tags() -> None:
    raw = {
        "affected_tags": ["Not A Real Tag", "Wohnen/Miete"],
        "werte_relevanz": {},
        "personal_impact_snippets": {},
    }
    normalized = _normalize_extraction(raw)
    assert normalized["affected_tags"] == ["Wohnen/Miete"]


def test_normalize_drops_malformed_snippet_entries() -> None:
    raw = {
        "affected_tags": ["Wohnen/Miete"],
        "werte_relevanz": {},
        "personal_impact_snippets": {
            "wohnsituation:mieter": "Ein guter Satz.",
            "wohnsituation:eigentuemer": True,  # bool value, not a sentence
            "unknown_key:true": "Sollte auch verworfen werden.",
            "hat_kinder": "Fehlendes :wert im Key.",
        },
    }
    normalized = _normalize_extraction(raw)
    assert normalized["personal_impact_snippets"] == {
        "wohnsituation:mieter": "Ein guter Satz."
    }
