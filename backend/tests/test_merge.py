"""Tests for merge_and_deduplicate — table-driven fingerprint dedup cases."""

from typing import Any, cast

from meinimpact.infrastructure.pipeline.merge import merge_and_deduplicate
from meinimpact.infrastructure.pipeline.state_rules.protocol import StateTrace
from meinimpact.infrastructure.pipeline.step import ItemState
from meinimpact.infrastructure.pipeline.types import ClassifiedAction
from meinimpact.infrastructure.sources.protocol import RawSourceItem


def _raw(
    *,
    external_id: str = "1",
    title: str = "Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
    source_url: str = "https://dip.bundestag.de/vorgang/1",
    type: str = "antrag",
    source: str = "dip",
    descriptor: list[str] | None = None,
) -> RawSourceItem:
    item: RawSourceItem = {
        "external_id": external_id,
        "title": title,
        "type": type,
        "status": "x",
        "deadline": None,
        "source_url": source_url,
        "description": "...",
        "initiated_by": "x",
        "source": source,
    }
    if descriptor is not None:
        item["descriptor"] = descriptor
    return item


def _state_item(state: str, **raw_kwargs: Any) -> ItemState:
    trace = StateTrace(
        engagement_state=state,  # type: ignore[arg-type]
        state_reason="r",
        matched_rule="rule",
        rules_checked=["rule"],
        evidence={},
    )
    return ItemState(raw=_raw(**raw_kwargs), state_trace=trace)


def _trace(item: ItemState) -> StateTrace:
    assert item.state_trace is not None
    return item.state_trace


# ---------------------------------------------------------------------------
# Exact URL dedup
# ---------------------------------------------------------------------------


def test_drops_item_matching_existing_url() -> None:
    item = _state_item("A", source_url="https://example.com/1")
    result = merge_and_deduplicate([item], [], existing_urls={"https://example.com/1"}, existing_titles=[])
    assert result == []


def test_keeps_item_with_new_url() -> None:
    item = _state_item("A", source_url="https://example.com/2")
    result = merge_and_deduplicate([item], [], existing_urls={"https://example.com/1"}, existing_titles=[])
    assert len(result) == 1


# ---------------------------------------------------------------------------
# Fingerprint dedup: same state, different type priority
# ---------------------------------------------------------------------------


def test_same_state_bundestag_petition_wins_over_civil_petition() -> None:
    bundestag = _state_item(
        "A", external_id="1", source_url="https://dip.bundestag.de/vorgang/1",
        type="petition", source="dip",
    )
    civil = _state_item(
        "A", external_id="2", source_url="https://weact.campact.de/p/2",
        type="petition", source="weact",
    )
    result = merge_and_deduplicate([bundestag], [civil], existing_urls=set(), existing_titles=[])
    assert len(result) == 1
    assert result[0].raw["source"] == "dip"


def test_same_state_brief_wins_over_anfrage() -> None:
    brief = _state_item("A", external_id="1", source_url="https://dip.bundestag.de/vorgang/1", type="antrag")
    anfrage = _state_item("A", external_id="2", source_url="https://dip.bundestag.de/vorgang/2", type="antrag")
    anfrage.classified = cast(ClassifiedAction, {"action_types": ["anfrage"]})
    result = merge_and_deduplicate([brief], [anfrage], existing_urls=set(), existing_titles=[])
    assert len(result) == 1
    assert result[0] is brief


# ---------------------------------------------------------------------------
# Fingerprint dedup: different state — higher state wins regardless of order
# ---------------------------------------------------------------------------


def test_state_a_wins_over_state_c_when_a_seen_first() -> None:
    a_item = _state_item("A", external_id="1", source_url="https://dip.bundestag.de/vorgang/1")
    c_item = _state_item("C", external_id="2", source_url="https://dip.bundestag.de/vorgang/2")
    result = merge_and_deduplicate([a_item], [c_item], existing_urls=set(), existing_titles=[])
    assert len(result) == 1
    assert _trace(result[0]).engagement_state == "A"


def test_state_a_wins_over_state_c_when_c_seen_first() -> None:
    a_item = _state_item("A", external_id="1", source_url="https://dip.bundestag.de/vorgang/1")
    c_item = _state_item("C", external_id="2", source_url="https://dip.bundestag.de/vorgang/2")
    # Reverse order: c_item is in the "parliamentary" slot, a_item in "petition"
    result = merge_and_deduplicate([c_item], [a_item], existing_urls=set(), existing_titles=[])
    assert len(result) == 1
    assert _trace(result[0]).engagement_state == "A"


# ---------------------------------------------------------------------------
# Fingerprint match via descriptor vs via fuzzy title
# ---------------------------------------------------------------------------


def test_matches_via_shared_descriptor_even_with_different_titles() -> None:
    item_a = _state_item(
        "A", external_id="1", source_url="https://dip.bundestag.de/vorgang/1",
        title="Klimaschutzgesetz Novelle", descriptor=["Klimaschutz", "Energie"],
    )
    item_b = _state_item(
        "C", external_id="2", source_url="https://dip.bundestag.de/vorgang/2",
        title="Completely different phrasing here", descriptor=["Klimaschutz"],
    )
    result = merge_and_deduplicate([item_a], [item_b], existing_urls=set(), existing_titles=[])
    assert len(result) == 1
    assert _trace(result[0]).engagement_state == "A"


def test_matches_via_fuzzy_title_without_shared_descriptor() -> None:
    item_a = _state_item(
        "A", external_id="1", source_url="https://dip.bundestag.de/vorgang/1",
        title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
    )
    item_b = _state_item(
        "C", external_id="2", source_url="https://dip.bundestag.de/vorgang/2",
        title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes 2024",
    )
    result = merge_and_deduplicate([item_a], [item_b], existing_urls=set(), existing_titles=[])
    assert len(result) == 1


def test_distinct_titles_and_no_shared_descriptor_are_kept_separate() -> None:
    item_a = _state_item(
        "A", external_id="1", source_url="https://dip.bundestag.de/vorgang/1",
        title="Klimaschutzgesetz Novelle", descriptor=["Klimaschutz"],
    )
    item_b = _state_item(
        "C", external_id="2", source_url="https://dip.bundestag.de/vorgang/2",
        title="Digitalpakt Schule Verlängerung", descriptor=["Bildung"],
    )
    result = merge_and_deduplicate([item_a], [item_b], existing_urls=set(), existing_titles=[])
    assert len(result) == 2
