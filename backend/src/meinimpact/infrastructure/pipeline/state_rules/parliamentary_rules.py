"""Engagement-state rules for Pipeline 1 (parliamentary, top-down).

Order matters: `RULES` is evaluated first-match-wins by
`state_rules.engine.evaluate_state`. Per specs/data/ingestion-pipeline.md
"State Determination: Parliamentary Actions":

  A #1: a vote is scheduled within 30 days
  A #2: the responsible committee is actively deliberating
  A #3: a Bundestag petition is close to the 50,000-signature quorum
  A #4: committee recommendation (Beschlussempfehlung) is ready — floor
        vote is the next step
  A #5: bill passed the Bundestag and is in a live Bundesrat stage
  B #1: referred to committee, no vote result yet
  B #2: fewer than 2 Fraktionen have documented Stellungnahmen
  B #3: still in 1./2. Beratung, no vote scheduled
  B #4: filed but not yet referred to committee (earliest structural stage)
  C:    Tavily finds quality-media coverage of the Vorgang's title

A #4/A #5 and B #4 were added after `scripts/audit_dip_coverage.py` showed
`DipAdapter.fetch_new_items` was fetching these Vorgänge (once its
beratungsstand allowlist was removed — see that adapter's docstring) but
every one of them fell through to state D by default, since no rule
recognised their status text. Statuses confirmed as fully decided
(`Abgelehnt`, `Verabschiedet`, `Verkündet`, `Für erledigt erklärt`) are
deliberately left unmatched — state D is the correct outcome for those,
not a gap.

State B is an action-level DIP signal, not a per-MdB check — see
`_STATE_B_REASON` and specs/data/ingestion-pipeline.md "State B triggers"
for why the earlier per-MdB-position version of this was replaced.

If none match, the engine defaults to state D and the item is discarded.
Reordering, removing, or adding a trigger is a one-line change to this list
— no other file needs to change.
"""

from meinimpact.infrastructure.pipeline.state_rules.protocol import (
    RuleContext,
    RuleResult,
    StateRule,
)
from meinimpact.infrastructure.pipeline.state_rules.shared_rules import (
    PetitionNearQuorumRule,
)

_VOTE_WINDOW_DAYS = 30
_MIN_FRAKTION_STELLUNGNAHMEN = 2
_STATE_B_REASON = "Positionen noch offen — eine gute Zeit um deinen MdB zu fragen"

# Bundesrat-stage statuses on a Vorgang that has already passed the
# Bundestag but isn't law yet — still a live, time-bound process.
_BUNDESRAT_LIVE_STATUSES = frozenset(
    {
        "1. Durchgang im Bundesrat abgeschlossen",
        "Bundesrat hat zugestimmt",
        "Bundesrat hat Vermittlungsausschuss nicht angerufen",
    }
)

# Earliest structural stages: filed but not yet referred to committee.
_EARLY_FILING_STATUSES = frozenset(
    {
        "Noch nicht beraten",
        "Dem Bundestag zugeleitet - Noch nicht beraten",
        "Einbringung beschlossen",
    }
)


class VoteScheduledRule:
    """State A #1: a vote is scheduled within the next 30 days."""

    name = "vote_scheduled"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        vote_date = context.vote_date
        if vote_date is None:
            return None
        days_until = (vote_date - context.now.date()).days
        if not (0 <= days_until <= _VOTE_WINDOW_DAYS):
            return None
        return RuleResult(
            state="A",
            reason=f"Abstimmung am {vote_date:%d.%m.%Y}",
            rule_name=self.name,
            evidence={"vote_date": vote_date.isoformat(), "days_until": days_until},
        )


class CommitteeActiveRule:
    """State A #2: the item is in committee deliberation and the committee
    has recently met (both conditions resolved upstream by the pipeline
    driver — this rule only interprets them)."""

    name = "committee_active"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        status = context.item.get("status", "")
        if "Ausschussberatung" not in status:
            return None
        if not context.committee_recently_active:
            return None
        return RuleResult(
            state="A",
            reason="Wird aktuell im Ausschuss beraten",
            rule_name=self.name,
            evidence={"status": status},
        )


class BeschlussempfehlungReadyRule:
    """State A #4: the committee has issued its Beschlussempfehlung — a
    floor vote is the next step, same urgency class as 2./3. Beratung."""

    name = "beschlussempfehlung_ready"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        status = context.item.get("status", "")
        if "Beschlussempfehlung liegt vor" not in status:
            return None
        return RuleResult(
            state="A",
            reason="Beschlussempfehlung liegt vor — Abstimmung steht bevor",
            rule_name=self.name,
            evidence={"status": status},
        )


class BundesratStageRule:
    """State A #5: the bill passed the Bundestag and is in a live Bundesrat
    stage — not yet law, still a time-bound process."""

    name = "bundesrat_stage"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        status = context.item.get("status", "")
        if status not in _BUNDESRAT_LIVE_STATUSES:
            return None
        return RuleResult(
            state="A",
            reason="Im Bundesrat — letzte Hürde vor dem Inkrafttreten",
            rule_name=self.name,
            evidence={"status": status},
        )


class CommitteeReferralNoVoteRule:
    """State B #1: referred to committee (Überwiesen), no vote result yet —
    positions are still forming in committee."""

    name = "committee_referral_no_vote"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        if context.item.get("type") not in ("gesetzentwurf", "antrag"):
            return None
        if "Überwiesen" not in context.item.get("status", ""):
            return None
        if context.has_vote_result:
            return None
        return RuleResult(
            state="B",
            reason=_STATE_B_REASON,
            rule_name=self.name,
            evidence={"status": context.item.get("status")},
        )


class InsufficientFraktionPositionsRule:
    """State B #2: fewer than 2 Fraktionen have documented Stellungnahmen —
    cross-party positioning is incomplete."""

    name = "insufficient_fraktion_positions"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        count = context.stellungnahme_fraktion_count
        if count is None or count >= _MIN_FRAKTION_STELLUNGNAHMEN:
            return None
        return RuleResult(
            state="B",
            reason=_STATE_B_REASON,
            rule_name=self.name,
            evidence={"stellungnahme_fraktion_count": count},
        )


class EarlyReadingNoVoteScheduledRule:
    """State B #3: still in 1./2. Beratung with no scheduled namentliche
    Abstimmung — the legislative process is structurally still open."""

    name = "early_reading_no_vote_scheduled"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        status = context.item.get("status", "")
        if "1. Beratung" not in status and "2. Beratung" not in status:
            return None
        if context.vote_date is not None:
            return None
        return RuleResult(
            state="B",
            reason=_STATE_B_REASON,
            rule_name=self.name,
            evidence={"status": status},
        )


class EarlyFilingRule:
    """State B #4: filed but not yet referred to committee — the earliest
    structural stage, positions have not even started forming yet."""

    name = "early_filing"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        if context.item.get("type") not in ("gesetzentwurf", "antrag"):
            return None
        if context.item.get("status", "") not in _EARLY_FILING_STATUSES:
            return None
        return RuleResult(
            state="B",
            reason=_STATE_B_REASON,
            rule_name=self.name,
            evidence={"status": context.item.get("status")},
        )


class MediaCoverageRule:
    """State C: the topic has quality-media coverage in the last 14 days."""

    name = "media_coverage"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        if not context.media_coverage_matched:
            return None
        return RuleResult(
            state="C",
            reason="Das Thema wird aktuell öffentlich diskutiert",
            rule_name=self.name,
            evidence={},
        )


RULES: list[StateRule] = [
    VoteScheduledRule(),
    CommitteeActiveRule(),
    PetitionNearQuorumRule(),
    BeschlussempfehlungReadyRule(),
    BundesratStageRule(),
    CommitteeReferralNoVoteRule(),
    InsufficientFraktionPositionsRule(),
    EarlyReadingNoVoteScheduledRule(),
    EarlyFilingRule(),
    MediaCoverageRule(),
]
