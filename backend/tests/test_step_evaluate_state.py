"""Tests for EvaluateStateStep — fake rule list, asserts delegation to the
pure state_rules engine."""

from datetime import datetime
from uuid import uuid4

import pytest

from meinimpact.infrastructure.pipeline.state_rules.protocol import RuleContext, RuleResult
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.pipeline.steps.evaluate_state import EvaluateStateStep


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


class _FixedRule:
    name = "fixed"

    def __init__(self, result: RuleResult | None) -> None:
        self._result = result

    def evaluate(self, context: RuleContext) -> RuleResult | None:
        return self._result


def _item_with_context() -> ItemState:
    raw = {
        "external_id": "1",
        "title": "x",
        "type": "antrag",
        "status": "x",
        "deadline": None,
        "source_url": "https://x",
        "description": "x",
        "initiated_by": "x",
        "source": "dip",
    }
    return ItemState(raw=raw, rule_context=RuleContext(item=raw, now=datetime(2026, 1, 1)))


async def test_attaches_state_trace_from_matching_rule():
    rules = [_FixedRule(RuleResult("A", "reason", "fixed"))]
    step = EvaluateStateStep(rules)
    result = await step.process([_item_with_context()], _deps())
    assert result[0].state_trace.engagement_state == "A"


async def test_defaults_to_d_when_no_rule_matches():
    step = EvaluateStateStep([_FixedRule(None)])
    result = await step.process([_item_with_context()], _deps())
    assert result[0].state_trace.engagement_state == "D"


async def test_raises_if_rule_context_missing():
    item = ItemState(
        raw={
            "external_id": "1",
            "title": "x",
            "type": "antrag",
            "status": "x",
            "deadline": None,
            "source_url": "https://x",
            "description": "x",
            "initiated_by": "x",
            "source": "dip",
        }
    )
    step = EvaluateStateStep([])
    with pytest.raises(ValueError):
        await step.process([item], _deps())


async def test_returns_same_number_of_items():
    step = EvaluateStateStep([_FixedRule(RuleResult("C", "r", "fixed"))])
    result = await step.process([_item_with_context(), _item_with_context()], _deps())
    assert len(result) == 2
