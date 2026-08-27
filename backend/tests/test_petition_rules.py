"""Table-driven, zero-mocking tests for Pipeline 2's engagement-state rules."""

from datetime import date, datetime, timedelta

from meinimpact.infrastructure.pipeline.state_rules.engine import evaluate_state
from meinimpact.infrastructure.pipeline.state_rules.petition_rules import (
    RULES,
    ActiveWithMediaCoverageRule,
    MomentumRule,
    NearGoalRule,
)
from meinimpact.infrastructure.pipeline.state_rules.protocol import RuleContext
from meinimpact.infrastructure.sources.protocol import RawSourceItem

_NOW = datetime(2026, 6, 1)


def _make_item(
    *,
    signature_count: int | None = None,
    deadline: date | None = None,
) -> RawSourceItem:
    item: RawSourceItem = {
        "external_id": "1",
        "title": "Petition für mehr Klimaschutz",
        "type": "petition",
        "status": "offen",
        "deadline": deadline,
        "source_url": "https://weact.campact.de/petitions/1",
        "description": "...",
        "initiated_by": "Zivilgesellschaft",
        "source": "weact",
    }
    if signature_count is not None:
        item["signature_count"] = signature_count
    return item


# ---------------------------------------------------------------------------
# NearGoalRule
# ---------------------------------------------------------------------------


def test_near_goal_matches_above_80_percent_with_deadline_soon() -> None:
    item = _make_item(
        signature_count=8_500, deadline=(_NOW + timedelta(days=10)).date()
    )
    ctx = RuleContext(item=item, now=_NOW, signature_goal=10_000)
    result = NearGoalRule().evaluate(ctx)
    assert result is not None
    assert result.state == "A"


def test_near_goal_does_not_match_below_80_percent() -> None:
    item = _make_item(
        signature_count=7_000, deadline=(_NOW + timedelta(days=10)).date()
    )
    ctx = RuleContext(item=item, now=_NOW, signature_goal=10_000)
    assert NearGoalRule().evaluate(ctx) is None


def test_near_goal_does_not_match_when_deadline_too_far() -> None:
    item = _make_item(
        signature_count=9_000, deadline=(_NOW + timedelta(days=45)).date()
    )
    ctx = RuleContext(item=item, now=_NOW, signature_goal=10_000)
    assert NearGoalRule().evaluate(ctx) is None


def test_near_goal_does_not_match_without_goal() -> None:
    item = _make_item(
        signature_count=9_000, deadline=(_NOW + timedelta(days=10)).date()
    )
    ctx = RuleContext(item=item, now=_NOW, signature_goal=None)
    assert NearGoalRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# MomentumRule
# ---------------------------------------------------------------------------


def test_momentum_matches_above_threshold() -> None:
    item = _make_item(signature_count=5_000)
    ctx = RuleContext(item=item, now=_NOW, previous_signature_count=3_500)
    result = MomentumRule().evaluate(ctx)
    assert result is not None
    assert result.state == "A"


def test_momentum_does_not_match_at_threshold() -> None:
    item = _make_item(signature_count=4_500)
    ctx = RuleContext(item=item, now=_NOW, previous_signature_count=3_500)
    assert MomentumRule().evaluate(ctx) is None


def test_momentum_does_not_match_without_previous_count() -> None:
    item = _make_item(signature_count=5_000)
    ctx = RuleContext(item=item, now=_NOW, previous_signature_count=None)
    assert MomentumRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# ActiveWithMediaCoverageRule
# ---------------------------------------------------------------------------


def test_active_with_media_coverage_matches() -> None:
    item = _make_item(signature_count=600, deadline=(_NOW + timedelta(days=10)).date())
    ctx = RuleContext(item=item, now=_NOW, media_coverage_matched=True)
    result = ActiveWithMediaCoverageRule().evaluate(ctx)
    assert result is not None
    assert result.state == "C"


def test_active_with_media_coverage_does_not_match_when_expired() -> None:
    item = _make_item(signature_count=600, deadline=(_NOW - timedelta(days=1)).date())
    ctx = RuleContext(item=item, now=_NOW, media_coverage_matched=True)
    assert ActiveWithMediaCoverageRule().evaluate(ctx) is None


def test_active_with_media_coverage_does_not_match_below_signature_floor() -> None:
    item = _make_item(signature_count=400)
    ctx = RuleContext(item=item, now=_NOW, media_coverage_matched=True)
    assert ActiveWithMediaCoverageRule().evaluate(ctx) is None


def test_active_with_media_coverage_does_not_match_without_coverage() -> None:
    item = _make_item(signature_count=600)
    ctx = RuleContext(item=item, now=_NOW, media_coverage_matched=False)
    assert ActiveWithMediaCoverageRule().evaluate(ctx) is None


def test_active_with_media_coverage_matches_with_no_deadline() -> None:
    item = _make_item(signature_count=600, deadline=None)
    ctx = RuleContext(item=item, now=_NOW, media_coverage_matched=True)
    assert ActiveWithMediaCoverageRule().evaluate(ctx) is not None


# ---------------------------------------------------------------------------
# Full RULES list
# ---------------------------------------------------------------------------


def test_no_trigger_defaults_to_d() -> None:
    item = _make_item(signature_count=100)
    ctx = RuleContext(item=item, now=_NOW)
    trace = evaluate_state(ctx, RULES)
    assert trace.engagement_state == "D"


def test_near_goal_wins_over_active_with_media_coverage() -> None:
    item = _make_item(signature_count=8_500, deadline=(_NOW + timedelta(days=5)).date())
    ctx = RuleContext(
        item=item, now=_NOW, signature_goal=10_000, media_coverage_matched=True
    )
    trace = evaluate_state(ctx, RULES)
    assert trace.engagement_state == "A"
    assert trace.matched_rule == "near_goal"
