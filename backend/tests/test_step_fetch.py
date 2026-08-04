"""Tests for FetchStep."""

from datetime import datetime
from uuid import uuid4

from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.pipeline.steps.fetch import FetchStep
from meinimpact.infrastructure.sources.protocol import RawSourceItem


class _FakeAdapter:
    def __init__(self, items: list[RawSourceItem]) -> None:
        self._items = items
        self.calls: list[datetime] = []

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]:
        self.calls.append(since)
        return self._items

    async def fetch_item_detail(self, external_id: str) -> RawSourceItem:
        raise NotImplementedError


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


def _item(external_id: str) -> RawSourceItem:
    return {
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


async def test_appends_fetched_items_to_empty_list() -> None:
    adapter = _FakeAdapter([_item("1"), _item("2")])
    step = FetchStep(adapter)
    result = await step.process([], _deps())
    assert [i.raw["external_id"] for i in result] == ["1", "2"]


async def test_appends_without_replacing_existing_items() -> None:
    adapter = _FakeAdapter([_item("2")])
    step = FetchStep(adapter)
    existing = [ItemState(raw=_item("1"))]
    result = await step.process(existing, _deps())
    assert [i.raw["external_id"] for i in result] == ["1", "2"]


async def test_chaining_two_fetch_steps() -> None:
    step_a = FetchStep(_FakeAdapter([_item("1")]))
    step_b = FetchStep(_FakeAdapter([_item("2")]))
    deps = _deps()
    items = await step_a.process([], deps)
    items = await step_b.process(items, deps)
    assert [i.raw["external_id"] for i in items] == ["1", "2"]


async def test_default_lookback_is_30_days() -> None:
    adapter = _FakeAdapter([])
    step = FetchStep(adapter)
    await step.process([], _deps())
    assert len(adapter.calls) == 1


async def test_step_name_defaults_to_adapter_class_name() -> None:
    step = FetchStep(_FakeAdapter([]))
    assert "FakeAdapter" in step.name


async def test_custom_name_is_used() -> None:
    step = FetchStep(_FakeAdapter([]), name="custom")
    assert step.name == "custom"
