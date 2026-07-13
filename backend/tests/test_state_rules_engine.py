"""Unit tests for the pure state-rule engine — zero mocking, zero I/O."""

from dataclasses import dataclass
from datetime import datetime

from meinimpact.infrastructure.pipeline.state_rules.engine import evaluate_state
from meinimpact.infrastructure.pipeline.state_rules.protocol import (
    RuleContext,
    RuleResult,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_context() -> RuleContext:
    return RuleContext(
        item={
            "external_id": "1",
            "title": "Test Vorgang",
            "type": "antrag",
            "status": "Ausschussberatung",
            "deadline": None,
            "source_url": "https://example.com/1",
            "description": "...",
            "initiated_by": "CDU/CSU",
            "source": "dip",
        },
        now=datetime(2026, 6, 1),
    )


@dataclass(frozen=True)
class _FakeRule:
    """A StateRule stand-in that always returns a fixed result (or None)."""

    name: str
    result: RuleResult | None

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        return self.result


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_first_match_wins():
    ctx = _make_context()
    rules = [
        _FakeRule("never_fires", None),
        _FakeRule("fires_b", RuleResult("B", "reason b", "fires_b")),
        _FakeRule("would_also_fire", RuleResult("A", "reason a", "would_also_fire")),
    ]
    trace = evaluate_state(ctx, rules)
    assert trace.engagement_state == "B"
    assert trace.matched_rule == "fires_b"
    assert trace.state_reason == "reason b"


def test_rules_checked_includes_every_rule_up_to_and_including_the_match():
    ctx = _make_context()
    rules = [
        _FakeRule("first", None),
        _FakeRule("second", RuleResult("C", "reason", "second")),
        _FakeRule("third_never_checked", None),
    ]
    trace = evaluate_state(ctx, rules)
    assert trace.rules_checked == ["first", "second"]


def test_no_rule_matches_defaults_to_state_d():
    ctx = _make_context()
    rules = [_FakeRule("a", None), _FakeRule("b", None)]
    trace = evaluate_state(ctx, rules)
    assert trace.engagement_state == "D"
    assert trace.matched_rule == "none"
    assert trace.rules_checked == ["a", "b"]


def test_empty_rule_list_defaults_to_state_d():
    trace = evaluate_state(_make_context(), [])
    assert trace.engagement_state == "D"
    assert trace.rules_checked == []


def test_evidence_is_carried_from_matched_rule():
    ctx = _make_context()
    rules = [_FakeRule("a", RuleResult("A", "r", "a", evidence={"key": "value"}))]
    trace = evaluate_state(ctx, rules)
    assert trace.evidence == {"key": "value"}
