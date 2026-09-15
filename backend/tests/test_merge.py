"""Tests for merge_and_deduplicate — URL dedup + topic assignment.

No more winner-picking here (see merge.py's module docstring for why
TYPE_PRIORITY/STATE_RANK were removed) — these tests assert that
fingerprint-matched items all survive and share a topic_id, instead of one
being discarded.
"""

from typing import Any

from meinimpact.infrastructure.pipeline.merge import (
    ExistingFingerprint,
    merge_and_deduplicate,
)
from meinimpact.infrastructure.pipeline.state_rules.protocol import StateTrace
from meinimpact.infrastructure.pipeline.step import ItemState
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


# ---------------------------------------------------------------------------
# Exact URL dedup (unchanged intent)
# ---------------------------------------------------------------------------


def test_drops_item_matching_existing_url() -> None:
    item = _state_item("A", source_url="https://example.com/1")
    result = merge_and_deduplicate(
        [item], [], existing_urls={"https://example.com/1"}, existing=[]
    )
    assert result == []


def test_keeps_item_with_new_url() -> None:
    item = _state_item("A", source_url="https://example.com/2")
    result = merge_and_deduplicate(
        [item], [], existing_urls={"https://example.com/1"}, existing=[]
    )
    assert len(result) == 1


# ---------------------------------------------------------------------------
# Topic assignment: fingerprint match keeps BOTH items, shares topic_id
# ---------------------------------------------------------------------------


def test_bundestag_petition_and_civil_petition_both_kept_same_topic() -> None:
    bundestag = _state_item(
        "A",
        external_id="1",
        source_url="https://dip.bundestag.de/vorgang/1",
        type="petition",
        source="dip",
        title="Petition für mehr Klimaschutz",
    )
    civil = _state_item(
        "A",
        external_id="2",
        source_url="https://weact.campact.de/p/2",
        type="petition",
        source="weact",
        title="Petition für mehr Klimaschutz",
    )
    result = merge_and_deduplicate(
        [bundestag], [civil], existing_urls=set(), existing=[]
    )
    assert len(result) == 2
    assert result[0].topic_id == result[1].topic_id
    assert result[0].topic_id is not None


def test_brief_and_anfrage_both_kept_same_topic() -> None:
    brief = _state_item(
        "A",
        external_id="1",
        source_url="https://dip.bundestag.de/vorgang/1",
        type="antrag",
        title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
    )
    anfrage = _state_item(
        "A",
        external_id="2",
        source_url="https://dip.bundestag.de/vorgang/2",
        type="antrag",
        title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
    )
    result = merge_and_deduplicate([brief], [anfrage], existing_urls=set(), existing=[])
    assert len(result) == 2
    assert result[0].topic_id == result[1].topic_id


def test_different_states_both_kept_same_topic_each_state_untouched() -> None:
    """Different engagement_state per option is fine and expected — a
    petition can be state A (near quorum) while its Vorgang counterpart is
    state C, and both should surface with their own honest state."""
    a_item = _state_item(
        "A", external_id="1", source_url="https://dip.bundestag.de/vorgang/1"
    )
    c_item = _state_item(
        "C", external_id="2", source_url="https://dip.bundestag.de/vorgang/2"
    )
    result = merge_and_deduplicate([a_item], [c_item], existing_urls=set(), existing=[])
    assert len(result) == 2
    assert result[0].topic_id == result[1].topic_id
    states = {r.state_trace.engagement_state for r in result if r.state_trace}
    assert states == {"A", "C"}


# ---------------------------------------------------------------------------
# Fingerprint match via descriptor vs via fuzzy title
# ---------------------------------------------------------------------------


def test_matches_via_shared_descriptor_even_with_different_titles() -> None:
    item_a = _state_item(
        "A",
        external_id="1",
        source_url="https://dip.bundestag.de/vorgang/1",
        title="Klimaschutzgesetz Novelle",
        descriptor=["Klimaschutz", "Energie"],
    )
    item_b = _state_item(
        "C",
        external_id="2",
        source_url="https://dip.bundestag.de/vorgang/2",
        title="Completely different phrasing here",
        descriptor=["Klimaschutz"],
    )
    result = merge_and_deduplicate([item_a], [item_b], existing_urls=set(), existing=[])
    assert len(result) == 2
    assert result[0].topic_id == result[1].topic_id


def test_matches_via_fuzzy_title_without_shared_descriptor() -> None:
    item_a = _state_item(
        "A",
        external_id="1",
        source_url="https://dip.bundestag.de/vorgang/1",
        title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
    )
    item_b = _state_item(
        "C",
        external_id="2",
        source_url="https://dip.bundestag.de/vorgang/2",
        title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes 2024",
    )
    result = merge_and_deduplicate([item_a], [item_b], existing_urls=set(), existing=[])
    assert len(result) == 2
    assert result[0].topic_id == result[1].topic_id


def test_distinct_titles_and_no_shared_descriptor_get_different_topics() -> None:
    item_a = _state_item(
        "A",
        external_id="1",
        source_url="https://dip.bundestag.de/vorgang/1",
        title="Klimaschutzgesetz Novelle",
        descriptor=["Klimaschutz"],
    )
    item_b = _state_item(
        "C",
        external_id="2",
        source_url="https://dip.bundestag.de/vorgang/2",
        title="Digitalpakt Schule Verlängerung",
        descriptor=["Bildung"],
    )
    result = merge_and_deduplicate([item_a], [item_b], existing_urls=set(), existing=[])
    assert len(result) == 2
    assert result[0].topic_id != result[1].topic_id


# ---------------------------------------------------------------------------
# Cross-run topic continuity (new — existing_titles was previously unused)
# ---------------------------------------------------------------------------


def test_new_item_joins_existing_topic_via_fuzzy_title_match() -> None:
    existing = [
        ExistingFingerprint(
            id="old-1",
            topic_id="topic-klimaschutz",
            title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
        )
    ]
    new_item = _state_item(
        "A",
        external_id="9",
        source_url="https://weact.campact.de/p/9",
        title="Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes 2024",
    )
    result = merge_and_deduplicate(
        [], [new_item], existing_urls=set(), existing=existing
    )
    assert len(result) == 1
    assert result[0].topic_id == "topic-klimaschutz"


def test_new_item_with_no_match_starts_a_new_topic() -> None:
    existing = [
        ExistingFingerprint(
            id="old-1", topic_id="topic-klimaschutz", title="Klimaschutzgesetz Novelle"
        )
    ]
    new_item = _state_item(
        "A",
        external_id="9",
        source_url="https://weact.campact.de/p/9",
        title="Digitalpakt Schule Verlängerung",
    )
    result = merge_and_deduplicate(
        [], [new_item], existing_urls=set(), existing=existing
    )
    assert len(result) == 1
    assert result[0].topic_id != "topic-klimaschutz"
    assert result[0].topic_id
