"""Unit tests for the pipeline executor — fake steps, no real I/O."""

from collections.abc import Callable
from dataclasses import dataclass
from uuid import uuid4

import structlog.testing

from meinimpact.infrastructure.pipeline.executor import run_pipeline
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps


def _make_deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


def _make_item(external_id: str) -> ItemState:
    return ItemState(
        raw={
            "external_id": external_id,
            "title": "Test",
            "type": "antrag",
            "status": "Noch nicht beraten",
            "deadline": None,
            "source_url": f"https://example.com/{external_id}",
            "description": "...",
            "initiated_by": "CDU/CSU",
            "source": "dip",
        }
    )


@dataclass
class _RecordingStep:
    """A fake step that records that it ran and can add/remove items."""

    name: str
    call_log: list[str]
    transform: Callable[[list[ItemState]], list[ItemState]] | None = None

    async def process(self, items: list[ItemState], deps: PipelineDeps) -> list[ItemState]:
        self.call_log.append(self.name)
        if self.transform is not None:
            return self.transform(items)
        return items


async def test_runs_steps_in_order() -> None:
    call_log: list[str] = []
    steps = [
        _RecordingStep("first", call_log),
        _RecordingStep("second", call_log),
        _RecordingStep("third", call_log),
    ]
    await run_pipeline(steps, _make_deps())
    assert call_log == ["first", "second", "third"]


async def test_passes_output_of_one_step_as_input_to_next() -> None:
    steps = [
        _RecordingStep("fetch", [], transform=lambda items: [_make_item("1"), _make_item("2")]),
        _RecordingStep("filter", [], transform=lambda items: items[:1]),
    ]
    result = await run_pipeline(steps, _make_deps())
    assert len(result) == 1
    assert result[0].raw["external_id"] == "1"


async def test_starts_with_empty_item_list() -> None:
    seen_inputs: list[int] = []

    def record_and_pass_through(items: list[ItemState]) -> list[ItemState]:
        seen_inputs.append(len(items))
        return items

    steps = [_RecordingStep("first", [], transform=record_and_pass_through)]
    await run_pipeline(steps, _make_deps())
    assert seen_inputs == [0]


async def test_logs_one_step_completed_event_per_step_with_counts() -> None:
    steps = [
        _RecordingStep("fetch", [], transform=lambda items: [_make_item("1"), _make_item("2")]),
        _RecordingStep("filter", [], transform=lambda items: items[:1]),
    ]
    with structlog.testing.capture_logs() as logs:
        await run_pipeline(steps, _make_deps())

    step_events = [log for log in logs if log["event"] == "step_completed"]
    assert [e["step"] for e in step_events] == ["fetch", "filter"]
    assert step_events[0]["items_in"] == 0
    assert step_events[0]["items_out"] == 2
    assert step_events[1]["items_in"] == 2
    assert step_events[1]["items_out"] == 1


async def test_empty_step_list_returns_empty_items() -> None:
    result = await run_pipeline([], _make_deps())
    assert result == []
