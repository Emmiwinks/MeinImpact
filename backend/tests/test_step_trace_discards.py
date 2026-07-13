"""Tests for TraceDiscardsStep."""

from uuid import uuid4

from meinimpact.infrastructure.pipeline.state_rules.protocol import StateTrace
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.pipeline.steps.trace_discards import TraceDiscardsStep


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


def _item(state: str, external_id: str = "1") -> ItemState:
    raw = {
        "external_id": external_id,
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


async def test_does_not_mutate_the_item_list():
    items = [_item("A"), _item("D")]
    step = TraceDiscardsStep()
    result = await step.process(items, _deps())
    assert result == items
    assert len(result) == 2


async def test_calls_sink_only_for_state_d_items():
    sunk: list[str] = []

    async def sink(item: ItemState) -> None:
        sunk.append(item.raw["external_id"])

    items = [_item("A", "1"), _item("D", "2"), _item("C", "3"), _item("D", "4")]
    step = TraceDiscardsStep(sink=sink)
    await step.process(items, _deps())
    assert sunk == ["2", "4"]


async def test_no_sink_configured_does_not_error():
    items = [_item("D")]
    step = TraceDiscardsStep()
    result = await step.process(items, _deps())
    assert len(result) == 1


async def test_items_without_state_trace_are_skipped_safely():
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
    sunk: list[str] = []

    async def sink(item: ItemState) -> None:
        sunk.append("called")

    step = TraceDiscardsStep(sink=sink)
    result = await step.process([item], _deps())
    assert sunk == []
    assert len(result) == 1
