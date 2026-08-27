"""EvaluateStateStep — pure, wraps state_rules.engine.evaluate_state per item."""

from collections.abc import Sequence

from meinimpact.infrastructure.pipeline.state_rules.engine import evaluate_state
from meinimpact.infrastructure.pipeline.state_rules.protocol import StateRule
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps


class EvaluateStateStep:
    """Runs the given rule list against each item's `RuleContext`."""

    name = "evaluate_state"

    def __init__(self, rules: Sequence[StateRule]) -> None:
        self._rules = rules

    async def process(
        self, items: list[ItemState], deps: PipelineDeps
    ) -> list[ItemState]:
        for item in items:
            if item.rule_context is None:
                raise ValueError(
                    "BuildRuleContextStep must run before EvaluateStateStep "
                    f"(item {item.raw.get('external_id')!r} has no rule_context)"
                )
            item.state_trace = evaluate_state(item.rule_context, self._rules)
        return items
