"""Pure state-evaluation engine — no I/O.

Runs an ordered list of `StateRule`s against a `RuleContext`, first match
wins. If no rule matches, the item resolves to state 'D' (no engagement
hook right now) — the pipeline discards it before classification.
"""

from collections.abc import Sequence

from meinimpact.infrastructure.pipeline.state_rules.protocol import (
    EngagementState,
    RuleContext,
    StateRule,
    StateTrace,
)

_DEFAULT_STATE: EngagementState = "D"
_DEFAULT_REASON = "Kein aktueller Anknuepfungspunkt fuer Engagement"
_DEFAULT_RULE_NAME = "none"


def evaluate_state(context: RuleContext, rules: Sequence[StateRule]) -> StateTrace:
    """Evaluates `rules` in order against `context`, returning the full trace."""
    checked: list[str] = []
    for rule in rules:
        checked.append(rule.name)
        result = rule.evaluate(context)
        if result is not None:
            return StateTrace(
                engagement_state=result.state,
                state_reason=result.reason,
                matched_rule=result.rule_name,
                rules_checked=checked,
                evidence=result.evidence,
            )
    return StateTrace(
        engagement_state=_DEFAULT_STATE,
        state_reason=_DEFAULT_REASON,
        matched_rule=_DEFAULT_RULE_NAME,
        rules_checked=checked,
        evidence={},
    )
