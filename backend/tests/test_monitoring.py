"""Monitoring: the drift check, the coverage card and the token meter."""

import asyncio
import uuid
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
import sentry_sdk

from meinimpact.infrastructure import alerts
from meinimpact.infrastructure.ai import usage
from meinimpact.infrastructure.pipeline.drift import find_drift
from meinimpact.infrastructure.pipeline.ingestion import IngestionSummary
from meinimpact.services import ingestion_runs
from meinimpact.services.coverage import CoverageConfig, Light, coverage
from tests.test_opportunity_routes import _OPPORTUNITY

NOW = datetime(2026, 11, 24, 12, 0, tzinfo=UTC)


def _row(source: str, fetched: int, kept: int, error: str | None = None) -> Any:
    return {"source": source, "fetched": fetched, "kept": kept, "error": error}


# --- drift ------------------------------------------------------------------


def test_drift_flags_a_source_that_suddenly_reads_nothing() -> None:
    history = [[_row("weact", 9, 8)], [_row("weact", 11, 9)]]

    assert find_drift([_row("weact", 0, 0)], history) == [
        "weact: 0 gelesen (sonst 10), Seite oder Parser geändert?"
    ]


def test_drift_flags_a_large_drop_in_kept_listings() -> None:
    history = [[_row("portal", 800, 100)], [_row("portal", 790, 90)]]

    [finding] = find_drift([_row("portal", 780, 20)], history)

    assert finding.startswith("portal: 20 behalten (sonst 95)")


def test_drift_ignores_new_small_and_failed_sources() -> None:
    history = [[_row("small", 3, 3)], [_row("small", 4, 4)]]

    assert find_drift([_row("new", 0, 0)], history) == []  # no history yet
    assert find_drift([_row("small", 1, 0)], history) == []  # below baseline
    assert find_drift([_row("small", 0, 0, "Timeout")], history) == []


def test_drift_skips_failed_runs_in_the_history() -> None:
    history = [[_row("weact", 0, 0, "Timeout")], [_row("weact", 9, 9)]]

    assert find_drift([_row("weact", 0, 0)], history) == []  # one good run only


# --- coverage ---------------------------------------------------------------


def _card(n: int, **changes: Any) -> Any:
    return replace(
        _OPPORTUNITY, id=uuid.UUID(int=n), **{"first_seen_at": NOW, **changes}
    )


def test_coverage_counts_per_place_and_names_gaps() -> None:
    cards = [
        _card(1, kind="petition", affected_tags=("Umwelt",)),
        _card(2, kind="decision", source_org="Rat", affected_tags=("Verkehr",)),
        _card(3, kind="survey", source_org="Portal", affected_tags=("Bildung",)),
    ]
    config = CoverageConfig(min_new_per_week=3, min_tags=3)

    by_key = {c.place.key: c for c in coverage(cards, now=NOW, config=config)}
    dresden = by_key["dresden"]

    assert (dresden.cards, dresden.new_this_week, dresden.kinds, dresden.tags) == (
        3,
        3,
        3,
        3,
    )
    assert dresden.gaps == ()
    assert dresden.light is Light.GREEN
    assert by_key["sachsen"].light is Light.RED  # nothing there
    assert "bund" not in by_key and "eu" not in by_key


def test_coverage_flags_one_dominant_source_and_old_cards() -> None:
    old = NOW - timedelta(days=10)
    cards = [_card(n, first_seen_at=old) for n in range(4)]
    config = CoverageConfig(min_new_per_week=1, min_kinds=1, min_tags=1)

    [dresden] = [c for c in coverage(cards, now=NOW, config=config) if c.cards]

    assert dresden.gaps == (
        "0 neue Karten in 7 Tagen (Ziel 1)",
        "100% aus openPetition (höchstens 50%)",
    )
    assert dresden.light is Light.RED


def test_coverage_notes_a_direction_without_blocking() -> None:
    cards = [_card(n, werte_relevanz={"wandel_tradition": -1.0}) for n in range(6)]
    config = CoverageConfig(min_new_per_week=0, min_kinds=1, min_tags=1)

    [dresden] = [c for c in coverage(cards, now=NOW, config=config) if c.cards]

    assert dresden.leans == (("wandel_tradition", -1.0, 6),)


# --- token meter --------------------------------------------------------------


async def test_meters_count_concurrent_tasks_separately() -> None:
    async def call(tokens: int) -> usage.Usage:
        with usage.track() as mine:
            await asyncio.sleep(0)
            usage.record(tokens, 1)
            await asyncio.sleep(0)
            usage.record(tokens, 1)
        return mine

    with usage.track() as total:
        first, second = await asyncio.gather(call(10), call(100))

    assert (first.calls, first.prompt_tokens) == (2, 20)
    assert (second.calls, second.prompt_tokens) == (2, 200)
    assert (total.calls, total.prompt_tokens, total.completion_tokens) == (4, 220, 4)


def test_price_is_per_million_tokens() -> None:
    price = usage.Price(eur_per_m_input=1.5, eur_per_m_output=7.5)

    assert price.cost(usage.Usage(prompt_tokens=2_000_000, completion_tokens=0)) == 3
    assert price.cost(usage.Usage(completion_tokens=100_000)) == 0.75


# --- alerts -------------------------------------------------------------------


def test_run_alerts_name_failed_drifting_and_budget_problems() -> None:
    summary = IngestionSummary(
        failed_sources=["weact: Timeout"],
        drift=["portal: 20 behalten (sonst 95)"],
        budget_reached=True,
        deferred=7,
        cost_eur=2.01,
    )

    assert ingestion_runs._alerts(summary, None) == [
        "Quelle fehlgeschlagen: weact: Timeout",
        "Quelle auffällig: portal: 20 behalten (sonst 95)",
        "Budget erreicht (2.01 €): 7 Einträge warten auf den nächsten Lauf",
    ]
    assert ingestion_runs._alerts(None, "RuntimeError: x") == [
        "Ingestion fehlgeschlagen: RuntimeError: x"
    ]
    assert ingestion_runs._alerts(IngestionSummary(), None) == []


def test_alert_without_sentry_only_logs(caplog: pytest.LogCaptureFixture) -> None:
    alerts.init_sentry(None, "test")

    alerts.alert("weact: 0 gelesen")

    assert "ALERT: weact: 0 gelesen" in caplog.text


def test_sentry_gets_no_personal_data(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, Any] = {}
    monkeypatch.setattr(sentry_sdk, "init", lambda **kw: seen.update(kw))

    alerts.init_sentry("https://key@o1.ingest.de.sentry.io/1", "test")

    assert seen["send_default_pii"] is False
    assert seen["max_request_body_size"] == "never"
    assert seen["include_local_variables"] is False
