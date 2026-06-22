"""Unit tests for pipeline stage pure functions."""

from datetime import date, timedelta

import pytest

from meinimpact.infrastructure.pipeline.stages import (
    calculate_momentum,
    deduplicate,
    effort_minutes_for,
    impact_hint_for,
    map_domain_action_type,
    prefilter,
)
from meinimpact.infrastructure.sources.protocol import RawSourceItem

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_item(
    *,
    title: str = "Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
    description: str = "Dieser Antrag behandelt die Änderung des Klimaschutzgesetzes.",
    source_url: str = "https://dip.bundestag.de/vorgang/1",
    type: str = "antrag",
    status: str = "Noch nicht beraten",
    deadline: date | None = None,
    signature_count: int | None = None,
    source: str = "dip",
) -> RawSourceItem:
    item: RawSourceItem = {
        "external_id": "1",
        "title": title,
        "type": type,
        "status": status,
        "deadline": deadline,
        "source_url": source_url,
        "description": description,
        "initiated_by": "CDU/CSU",
        "source": source,
    }
    if signature_count is not None:
        item["signature_count"] = signature_count
    return item


# ---------------------------------------------------------------------------
# deduplicate
# ---------------------------------------------------------------------------


def test_deduplicate_removes_exact_url_match():
    item = _make_item(source_url="https://example.com/1")
    result = deduplicate(
        [item], existing_urls={"https://example.com/1"}, existing_titles=[]
    )
    assert result == []


def test_deduplicate_passes_new_url():
    item = _make_item(source_url="https://example.com/2")
    result = deduplicate(
        [item], existing_urls={"https://example.com/1"}, existing_titles=[]
    )
    assert len(result) == 1


def test_deduplicate_fuzzy_title_match():
    existing_title = "Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes"
    # Slightly different phrasing — fuzz.ratio should be >85
    near_duplicate = _make_item(
        title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes 2024",
        source_url="https://example.com/3",
    )
    result = deduplicate(
        [near_duplicate], existing_urls=set(), existing_titles=[existing_title]
    )
    assert result == []


def test_deduplicate_distinct_title_passes():
    item = _make_item(
        title="Digitalpakt Schule Verlängerung", source_url="https://example.com/4"
    )
    result = deduplicate(
        [item],
        existing_urls=set(),
        existing_titles=["Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes"],
    )
    assert len(result) == 1


def test_deduplicate_deduplicates_within_batch():
    item_a = _make_item(source_url="https://example.com/5")
    item_b = _make_item(source_url="https://example.com/6")  # same title, different URL
    result = deduplicate([item_a, item_b], existing_urls=set(), existing_titles=[])
    assert len(result) == 1


# ---------------------------------------------------------------------------
# prefilter
# ---------------------------------------------------------------------------


def test_prefilter_passes_valid_item():
    item = _make_item()
    result = prefilter([item])
    assert len(result) == 1


def test_prefilter_drops_short_title():
    item = _make_item(title="Kurz")  # 4 chars < 10
    result = prefilter([item])
    assert result == []


def test_prefilter_drops_petition_with_past_deadline():
    item = _make_item(
        type="petition", deadline=date.today() - timedelta(days=1), signature_count=600
    )
    result = prefilter([item])
    assert result == []


def test_prefilter_passes_antrag_with_past_deadline():
    # Bundestag items use deadline as activity date, not expiry — should not be dropped
    item = _make_item(type="antrag", deadline=date.today() - timedelta(days=1))
    result = prefilter([item])
    assert len(result) == 1


def test_prefilter_passes_petition_with_future_deadline():
    item = _make_item(
        type="petition", deadline=date.today() + timedelta(days=10), signature_count=600
    )
    result = prefilter([item])
    assert len(result) == 1


def test_prefilter_drops_petition_below_threshold():
    item = _make_item(type="petition", signature_count=100)
    result = prefilter([item])
    assert result == []


def test_prefilter_passes_petition_above_threshold():
    item = _make_item(type="petition", signature_count=600)
    result = prefilter([item])
    assert len(result) == 1


def test_prefilter_passes_petition_without_signature_count():
    # Sammelübersicht items from Petitionsausschuss have no individual count
    item = _make_item(type="petition")  # no signature_count key
    result = prefilter([item])
    assert len(result) == 1


def test_prefilter_drops_non_german_title():
    item = _make_item(
        title="This is a long English text about some policy that should be dropped"
    )
    result = prefilter([item])
    assert result == []


# ---------------------------------------------------------------------------
# calculate_momentum
# ---------------------------------------------------------------------------


def test_momentum_baseline():
    assert calculate_momentum(0) == pytest.approx(0.3)


def test_momentum_low_news():
    assert calculate_momentum(3) == pytest.approx(0.45)


def test_momentum_high_news():
    assert calculate_momentum(10) == pytest.approx(0.6)


def test_momentum_high_velocity():
    assert calculate_momentum(0, signature_velocity=2000) == pytest.approx(0.6)


def test_momentum_capped_at_1():
    # base 0.3 + news boost 0.3 + velocity boost 0.3 = 0.9; cap is 1.0
    assert calculate_momentum(10, signature_velocity=2000) == pytest.approx(0.9)


def test_momentum_no_velocity():
    assert calculate_momentum(5, signature_velocity=None) == pytest.approx(0.6)


# ---------------------------------------------------------------------------
# map_domain_action_type
# ---------------------------------------------------------------------------


def test_map_uses_action_types_list():
    item = {"action_types": ["petition"], "type": "antrag"}
    assert map_domain_action_type(item) == "petition_signature"


def test_map_falls_back_to_raw_type():
    item = {"action_types": [], "type": "gesetzentwurf"}
    assert map_domain_action_type(item) == "representative_letter"


def test_map_unknown_type_defaults_to_letter():
    item = {"action_types": [], "type": "unknown_type"}
    assert map_domain_action_type(item) == "representative_letter"


# ---------------------------------------------------------------------------
# effort_minutes_for / impact_hint_for
# ---------------------------------------------------------------------------


def test_effort_minutes_petition():
    assert effort_minutes_for("petition_signature") == 5


def test_effort_minutes_letter():
    assert effort_minutes_for("representative_letter") == 15


def test_effort_minutes_unknown_defaults():
    assert effort_minutes_for("something_else") == 15


def test_impact_hint_high():
    hint = impact_hint_for("high")
    assert "Abstimmung" in hint or "Frist" in hint


def test_impact_hint_unknown_returns_string():
    hint = impact_hint_for("unknown")
    assert isinstance(hint, str) and len(hint) > 0
