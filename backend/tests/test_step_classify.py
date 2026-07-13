"""Tests for ClassifyStep — mocked MistralClassifier, no real API calls."""

from unittest.mock import AsyncMock
from uuid import uuid4

from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.pipeline.steps.classify import ClassifyStep


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


def _item(external_id: str) -> ItemState:
    return ItemState(
        raw={
            "external_id": external_id,
            "title": "x",
            "type": "antrag",
            "status": "x",
            "deadline": None,
            "source_url": f"https://x/{external_id}",
            "description": "x",
            "initiated_by": "x",
            "source": "dip",
        }
    )


def _classified(external_id: str) -> dict:
    return {"external_id": external_id, "urgency": "low"}


async def test_attaches_classification_result():
    classifier = AsyncMock()
    classifier.classify = AsyncMock(return_value=_classified("1"))
    step = ClassifyStep(classifier)
    result = await step.process([_item("1")], _deps())
    assert result[0].classified == {"external_id": "1", "urgency": "low"}


async def test_drops_items_where_classification_returns_none():
    classifier = AsyncMock()
    classifier.classify = AsyncMock(side_effect=[_classified("1"), None])
    step = ClassifyStep(classifier)
    result = await step.process([_item("1"), _item("2")], _deps())
    assert [i.raw["external_id"] for i in result] == ["1"]


async def test_classification_error_is_recorded_and_item_dropped():
    classifier = AsyncMock()
    classifier.classify = AsyncMock(side_effect=[RuntimeError("boom")])
    deps = _deps()
    step = ClassifyStep(classifier)
    result = await step.process([_item("1")], deps)
    assert result == []
    assert len(deps.errors) == 1
    assert "boom" in deps.errors[0]


async def test_all_items_classified_returns_all():
    classifier = AsyncMock()
    classifier.classify = AsyncMock(side_effect=[_classified("1"), _classified("2")])
    step = ClassifyStep(classifier)
    result = await step.process([_item("1"), _item("2")], _deps())
    assert len(result) == 2


async def test_empty_input_returns_empty():
    classifier = AsyncMock()
    step = ClassifyStep(classifier)
    result = await step.process([], _deps())
    assert result == []
    classifier.classify.assert_not_called()
