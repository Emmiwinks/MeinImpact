"""Table-driven, zero-mocking tests for Pipeline 1's engagement-state rules.

This is where the spec's "unverified beratungsstand" risk (see
specs/data/ingestion-pipeline.md Open Questions) gets pinned down cheaply:
these tests are fast and safe to re-run once real DIP values are confirmed.
"""

from datetime import datetime, timedelta
from typing import Any

from meinimpact.infrastructure.pipeline.state_rules.engine import evaluate_state
from meinimpact.infrastructure.pipeline.state_rules.parliamentary_rules import (
    RULES,
    BeschlussempfehlungReadyRule,
    BundesratStageRule,
    CommitteeActiveRule,
    CommitteeReferralNoVoteRule,
    EarlyFilingRule,
    EarlyReadingNoVoteScheduledRule,
    InsufficientFraktionPositionsRule,
    MediaCoverageRule,
)
from meinimpact.infrastructure.pipeline.state_rules.protocol import RuleContext
from meinimpact.infrastructure.pipeline.state_rules.shared_rules import (
    PetitionNearQuorumRule,
)
from meinimpact.infrastructure.sources.protocol import RawSourceItem

_NOW = datetime(2026, 6, 1)


def _make_item(
    *,
    type: str = "antrag",
    status: str = "Noch nicht beraten",
    signature_count: int | None = None,
) -> RawSourceItem:
    item: RawSourceItem = {
        "external_id": "1",
        "title": "Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
        "type": type,
        "status": status,
        "deadline": None,
        "source_url": "https://dip.bundestag.de/vorgang/1",
        "description": "...",
        "initiated_by": "CDU/CSU",
        "source": "dip",
    }
    if signature_count is not None:
        item["signature_count"] = signature_count
    return item


def _ctx(**kwargs: Any) -> RuleContext:
    return RuleContext(item=_make_item(), now=_NOW, **kwargs)


# ---------------------------------------------------------------------------
# VoteScheduledRule (via full RULES list, since it's first)
# ---------------------------------------------------------------------------


def test_vote_in_29_days_matches() -> None:
    ctx = RuleContext(
        item=_make_item(), now=_NOW, vote_date=(_NOW + timedelta(days=29)).date()
    )
    trace = evaluate_state(ctx, RULES)
    assert trace.engagement_state == "A"
    assert trace.matched_rule == "vote_scheduled"


def test_vote_in_31_days_does_not_match() -> None:
    ctx = RuleContext(
        item=_make_item(), now=_NOW, vote_date=(_NOW + timedelta(days=31)).date()
    )
    trace = evaluate_state(ctx, RULES)
    assert trace.matched_rule != "vote_scheduled"


def test_vote_exactly_30_days_matches() -> None:
    ctx = RuleContext(
        item=_make_item(), now=_NOW, vote_date=(_NOW + timedelta(days=30)).date()
    )
    trace = evaluate_state(ctx, RULES)
    assert trace.engagement_state == "A"
    assert trace.matched_rule == "vote_scheduled"


def test_vote_in_the_past_does_not_match() -> None:
    ctx = RuleContext(
        item=_make_item(), now=_NOW, vote_date=(_NOW - timedelta(days=1)).date()
    )
    trace = evaluate_state(ctx, RULES)
    assert trace.matched_rule != "vote_scheduled"


def test_no_vote_date_does_not_match() -> None:
    ctx = _ctx()
    trace = evaluate_state(ctx, RULES)
    assert trace.matched_rule != "vote_scheduled"


# ---------------------------------------------------------------------------
# CommitteeActiveRule
# ---------------------------------------------------------------------------


def test_committee_active_matches_when_status_and_recent_activity() -> None:
    item = _make_item(status="Ausschussberatung")
    ctx = RuleContext(item=item, now=_NOW, committee_recently_active=True)
    result = CommitteeActiveRule().evaluate(ctx)
    assert result is not None
    assert result.state == "A"


def test_committee_active_does_not_match_without_recent_activity() -> None:
    item = _make_item(status="Ausschussberatung")
    ctx = RuleContext(item=item, now=_NOW, committee_recently_active=False)
    assert CommitteeActiveRule().evaluate(ctx) is None


def test_committee_active_does_not_match_wrong_status() -> None:
    item = _make_item(status="2. Beratung")
    ctx = RuleContext(item=item, now=_NOW, committee_recently_active=True)
    assert CommitteeActiveRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# PetitionNearQuorumRule (shared)
# ---------------------------------------------------------------------------


def test_petition_near_quorum_matches_above_threshold() -> None:
    item = _make_item(type="petition", signature_count=45_000)
    ctx = RuleContext(item=item, now=_NOW)
    result = PetitionNearQuorumRule().evaluate(ctx)
    assert result is not None
    assert result.state == "A"
    assert "45000" in result.reason


def test_petition_near_quorum_does_not_match_at_threshold() -> None:
    item = _make_item(type="petition", signature_count=40_000)
    ctx = RuleContext(item=item, now=_NOW)
    assert PetitionNearQuorumRule().evaluate(ctx) is None


def test_petition_near_quorum_does_not_match_non_petition() -> None:
    item = _make_item(type="antrag", signature_count=45_000)
    ctx = RuleContext(item=item, now=_NOW)
    assert PetitionNearQuorumRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# BeschlussempfehlungReadyRule (state A #4)
# ---------------------------------------------------------------------------


def test_beschlussempfehlung_ready_matches() -> None:
    item = _make_item(status="Beschlussempfehlung liegt vor")
    ctx = RuleContext(item=item, now=_NOW)
    result = BeschlussempfehlungReadyRule().evaluate(ctx)
    assert result is not None
    assert result.state == "A"


def test_beschlussempfehlung_ready_does_not_match_other_status() -> None:
    item = _make_item(status="Ausschussberatung")
    ctx = RuleContext(item=item, now=_NOW)
    assert BeschlussempfehlungReadyRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# BundesratStageRule (state A #5)
# ---------------------------------------------------------------------------


def test_bundesrat_stage_matches_each_live_status() -> None:
    for status in (
        "1. Durchgang im Bundesrat abgeschlossen",
        "Bundesrat hat zugestimmt",
        "Bundesrat hat Vermittlungsausschuss nicht angerufen",
    ):
        item = _make_item(status=status)
        ctx = RuleContext(item=item, now=_NOW)
        result = BundesratStageRule().evaluate(ctx)
        assert result is not None, f"Expected a match for status={status!r}"
        assert result.state == "A"


def test_bundesrat_stage_does_not_match_decided_status() -> None:
    item = _make_item(status="Verkündet")
    ctx = RuleContext(item=item, now=_NOW)
    assert BundesratStageRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# CommitteeReferralNoVoteRule (state B #1)
# ---------------------------------------------------------------------------


def test_committee_referral_matches_antrag_ueberwiesen_no_vote_result() -> None:
    item = _make_item(type="antrag", status="Überwiesen")
    ctx = RuleContext(item=item, now=_NOW, has_vote_result=False)
    result = CommitteeReferralNoVoteRule().evaluate(ctx)
    assert result is not None
    assert result.state == "B"


def test_committee_referral_does_not_match_with_vote_result() -> None:
    item = _make_item(type="antrag", status="Überwiesen")
    ctx = RuleContext(item=item, now=_NOW, has_vote_result=True)
    assert CommitteeReferralNoVoteRule().evaluate(ctx) is None


def test_committee_referral_does_not_match_wrong_status() -> None:
    item = _make_item(type="antrag", status="Ausschussberatung")
    ctx = RuleContext(item=item, now=_NOW, has_vote_result=False)
    assert CommitteeReferralNoVoteRule().evaluate(ctx) is None


def test_committee_referral_does_not_match_petition() -> None:
    item = _make_item(type="petition", status="Überwiesen")
    ctx = RuleContext(item=item, now=_NOW, has_vote_result=False)
    assert CommitteeReferralNoVoteRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# InsufficientFraktionPositionsRule (state B #2)
# ---------------------------------------------------------------------------


def test_insufficient_fraktion_positions_matches_below_threshold() -> None:
    ctx = RuleContext(item=_make_item(), now=_NOW, stellungnahme_fraktion_count=1)
    result = InsufficientFraktionPositionsRule().evaluate(ctx)
    assert result is not None
    assert result.state == "B"


def test_insufficient_fraktion_positions_does_not_match_at_threshold() -> None:
    ctx = RuleContext(item=_make_item(), now=_NOW, stellungnahme_fraktion_count=2)
    assert InsufficientFraktionPositionsRule().evaluate(ctx) is None


def test_insufficient_fraktion_positions_does_not_match_when_unknown() -> None:
    ctx = RuleContext(item=_make_item(), now=_NOW, stellungnahme_fraktion_count=None)
    assert InsufficientFraktionPositionsRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# EarlyReadingNoVoteScheduledRule (state B #3)
# ---------------------------------------------------------------------------


def test_early_reading_matches_first_reading_no_vote_scheduled() -> None:
    item = _make_item(status="1. Beratung")
    ctx = RuleContext(item=item, now=_NOW, vote_date=None)
    result = EarlyReadingNoVoteScheduledRule().evaluate(ctx)
    assert result is not None
    assert result.state == "B"


def test_early_reading_matches_second_reading_no_vote_scheduled() -> None:
    item = _make_item(status="2. Beratung")
    ctx = RuleContext(item=item, now=_NOW, vote_date=None)
    result = EarlyReadingNoVoteScheduledRule().evaluate(ctx)
    assert result is not None


def test_early_reading_does_not_match_when_vote_scheduled() -> None:
    item = _make_item(status="1. Beratung")
    ctx = RuleContext(item=item, now=_NOW, vote_date=(_NOW + timedelta(days=10)).date())
    assert EarlyReadingNoVoteScheduledRule().evaluate(ctx) is None


def test_early_reading_does_not_match_other_status() -> None:
    item = _make_item(status="Ausschussberatung")
    ctx = RuleContext(item=item, now=_NOW, vote_date=None)
    assert EarlyReadingNoVoteScheduledRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# EarlyFilingRule (state B #4)
# ---------------------------------------------------------------------------


def test_early_filing_matches_each_status() -> None:
    for status in (
        "Noch nicht beraten",
        "Dem Bundestag zugeleitet - Noch nicht beraten",
        "Einbringung beschlossen",
    ):
        item = _make_item(type="antrag", status=status)
        ctx = RuleContext(item=item, now=_NOW)
        result = EarlyFilingRule().evaluate(ctx)
        assert result is not None, f"Expected a match for status={status!r}"
        assert result.state == "B"


def test_early_filing_does_not_match_petition() -> None:
    item = _make_item(type="petition", status="Noch nicht beraten")
    ctx = RuleContext(item=item, now=_NOW)
    assert EarlyFilingRule().evaluate(ctx) is None


def test_early_filing_does_not_match_other_status() -> None:
    item = _make_item(type="antrag", status="Überwiesen")
    ctx = RuleContext(item=item, now=_NOW)
    assert EarlyFilingRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# MediaCoverageRule
# ---------------------------------------------------------------------------


def test_media_coverage_matches_when_flagged() -> None:
    ctx = RuleContext(item=_make_item(), now=_NOW, media_coverage_matched=True)
    result = MediaCoverageRule().evaluate(ctx)
    assert result is not None
    assert result.state == "C"


def test_media_coverage_does_not_match_when_not_flagged() -> None:
    ctx = RuleContext(item=_make_item(), now=_NOW, media_coverage_matched=False)
    assert MediaCoverageRule().evaluate(ctx) is None


# ---------------------------------------------------------------------------
# Full RULES list: first-match-wins ordering
# ---------------------------------------------------------------------------


def test_vote_scheduled_wins_over_state_b_when_both_apply() -> None:
    item = _make_item(type="antrag", status="Überwiesen")
    ctx = RuleContext(
        item=item,
        now=_NOW,
        vote_date=(_NOW + timedelta(days=10)).date(),
        has_vote_result=False,
    )
    trace = evaluate_state(ctx, RULES)
    assert trace.engagement_state == "A"
    assert trace.matched_rule == "vote_scheduled"


def test_state_b_wins_over_media_coverage_when_both_apply() -> None:
    item = _make_item(type="antrag", status="Überwiesen")
    ctx = RuleContext(
        item=item, now=_NOW, has_vote_result=False, media_coverage_matched=True
    )
    trace = evaluate_state(ctx, RULES)
    assert trace.engagement_state == "B"
    assert trace.matched_rule == "committee_referral_no_vote"


def test_nothing_matches_defaults_to_d() -> None:
    """A fully decided Vorgang (per scripts/audit_dip_coverage.py: Verabschiedet,
    Verkündet, Abgelehnt, Für erledigt erklärt) has no engagement hook —
    state D is the correct outcome, not a gap. Note: _make_item()'s own
    default status ("Noch nicht beraten") now matches early_filing, so this
    test must use a status no rule recognises."""
    item = _make_item(status="Verabschiedet")
    ctx = RuleContext(item=item, now=_NOW)
    trace = evaluate_state(ctx, RULES)
    assert trace.engagement_state == "D"
