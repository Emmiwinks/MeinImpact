"""Table-driven tests for FilterStateDStep."""

from uuid import uuid4

from meinimpact.infrastructure.pipeline.state_rules.protocol import StateTrace
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.pipeline.steps.filter_state_d import FilterStateDStep


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


def _item(state: str) -> ItemState:
    raw = {
        "external_id": state,
        "title": "x",
        "type": "antrag",
        "status": "x",
        "deadline": None,
        "source_url": "https://x",
        "description": "x",
        "initiated_by": "x",
        "source": "dip",
    }
    trace = StateTrace(
        engagement_state=state,  # type: ignore[arg-type]
        state_reason="reason",
        matched_rule="rule",
        rules_checked=["rule"],
        evidence={},
    )
    return ItemState(raw=raw, state_trace=trace)


async def test_mixed_batch_keeps_only_non_d_items():
    items = [_item("A"), _item("B"), _item("C"), _item("D")]
    step = FilterStateDStep()
    result = await step.process(items, _deps())
    assert [i.raw["external_id"] for i in result] == ["A", "B", "C"]


async def test_all_state_d_returns_empty():
    items = [_item("D"), _item("D")]
    step = FilterStateDStep()
    result = await step.process(items, _deps())
    assert result == []


async def test_no_state_d_returns_all():
    items = [_item("A"), _item("B")]
    step = FilterStateDStep()
    result = await step.process(items, _deps())
    assert len(result) == 2


async def test_item_without_state_trace_is_dropped():
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
    step = FilterStateDStep()
    result = await step.process([item], _deps())
    assert result == []
