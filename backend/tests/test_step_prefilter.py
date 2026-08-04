"""Tests for PrefilterStep — zero mocking, reuses stages.py pure helpers."""

from uuid import uuid4

from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.pipeline.steps.prefilter import PrefilterStep


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


def _item(title: str) -> ItemState:
    return ItemState(
        raw={
            "external_id": "1",
            "title": title,
            "type": "antrag",
            "status": "Noch nicht beraten",
            "deadline": None,
            "source_url": "https://example.com/1",
            "description": "...",
            "initiated_by": "CDU/CSU",
            "source": "dip",
        }
    )


async def test_passes_valid_german_title() -> None:
    step = PrefilterStep()
    result = await step.process(
        [_item("Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes")], _deps()
    )
    assert len(result) == 1


async def test_drops_short_title() -> None:
    step = PrefilterStep()
    result = await step.process([_item("Kurz")], _deps())
    assert result == []


async def test_drops_non_german_title() -> None:
    step = PrefilterStep()
    result = await step.process(
        [_item("This is a long English text about some policy that should be dropped")], _deps()
    )
    assert result == []


async def test_mixed_batch_keeps_only_passing_items() -> None:
    step = PrefilterStep()
    items = [
        _item("Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes"),
        _item("Kurz"),
    ]
    result = await step.process(items, _deps())
    assert len(result) == 1
