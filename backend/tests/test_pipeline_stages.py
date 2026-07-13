"""Unit tests for pipeline stage pure functions.

`deduplicate()`, `prefilter()`, and `calculate_momentum()` were removed in
the cutover to the state-based pipeline — their replacements are tested in
`test_merge.py` (fingerprint dedup) and `test_step_prefilter.py`
(passes_basic_checks via PrefilterStep).
"""

from datetime import date

from meinimpact.infrastructure.pipeline.stages import (
    effort_minutes_for,
    impact_hint_for,
    map_domain_action_type,
    passes_basic_checks,
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
# passes_basic_checks
# ---------------------------------------------------------------------------


def test_passes_basic_checks_passes_valid_item():
    assert passes_basic_checks(_make_item()) is True


def test_passes_basic_checks_drops_short_title():
    assert passes_basic_checks(_make_item(title="Kurz")) is False


def test_passes_basic_checks_drops_non_german_title():
    item = _make_item(
        title="This is a long English text about some policy that should be dropped"
    )
    assert passes_basic_checks(item) is False


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
