"""Engagement-state rules for Pipeline 2 (petition, bottom-up).

Order matters — first-match-wins, per
specs/data/ingestion-pipeline.md "State Determination: Petition Actions":

  A #1: signature count > 80% of goal AND deadline within 30 days
  A #2: a Bundestag petition is close to the 50,000-signature quorum
  A #3: momentum — more than 1,000 new signatures in the last 7 days
  C:    active, >= 500 signatures, and Tavily finds quality-media coverage

State B does not apply to petitions — there is no committee-referral or
Fraktion-Stellungnahme concept for a citizen petition, so none of
`parliamentary_rules.py`'s state-B rules have an equivalent here. If none
match, the engine defaults to state D and the item is discarded.
"""

from meinimpact.infrastructure.pipeline.state_rules.protocol import (
    RuleContext,
    RuleResult,
    StateRule,
)
from meinimpact.infrastructure.pipeline.state_rules.shared_rules import (
    PetitionNearQuorumRule,
)

_NEAR_GOAL_RATIO = 0.8
_NEAR_GOAL_DEADLINE_DAYS = 30
_MOMENTUM_THRESHOLD = 1_000
_ACTIVE_MIN_SIGNATURES = 500


class NearGoalRule:
    """State A #1: close to the stated goal, with the deadline approaching."""

    name = "near_goal"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        goal = context.signature_goal
        count = context.item.get("signature_count")
        deadline = context.item.get("deadline")
        if goal is None or count is None or deadline is None:
            return None
        if count < goal * _NEAR_GOAL_RATIO:
            return None
        days_left = (deadline - context.now.date()).days
        if not (0 <= days_left <= _NEAR_GOAL_DEADLINE_DAYS):
            return None
        return RuleResult(
            state="A",
            reason=f"Kurz vor dem Ziel: {count} von {goal} — noch {days_left} Tage",
            rule_name=self.name,
            evidence={"signature_count": count, "goal": goal, "days_left": days_left},
        )


class MomentumRule:
    """State A #3: more than 1,000 new signatures since the last pipeline run."""

    name = "momentum"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        previous = context.previous_signature_count
        count = context.item.get("signature_count")
        if previous is None or count is None:
            return None
        if (count - previous) <= _MOMENTUM_THRESHOLD:
            return None
        return RuleResult(
            state="A",
            reason="Über 1.000 neue Unterschriften diese Woche",
            rule_name=self.name,
            evidence={"previous_signature_count": previous, "signature_count": count},
        )


class ActiveWithMediaCoverageRule:
    """State C: active, has meaningful traction, and is in the news."""

    name = "active_with_media_coverage"

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        deadline = context.item.get("deadline")
        if deadline is not None and deadline < context.now.date():
            return None
        count = context.item.get("signature_count")
        if count is None or count < _ACTIVE_MIN_SIGNATURES:
            return None
        if not context.media_coverage_matched:
            return None
        return RuleResult(
            state="C",
            reason="Läuft — und das Thema ist gerade in der Diskussion",
            rule_name=self.name,
            evidence={"signature_count": count},
        )


RULES: list[StateRule] = [
    NearGoalRule(),
    PetitionNearQuorumRule(),
    MomentumRule(),
    ActiveWithMediaCoverageRule(),
]
