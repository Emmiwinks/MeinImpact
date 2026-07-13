"""Tests for the orchestrator's composition logic: concurrency and fault
tolerance between the two pipelines, and the pure state-counting helper.

`run_ingestion_pipeline` itself needs a real Postgres connection (Database,
session factory) — that's covered by the `test_pipeline_persist.py`
integration tests. This file tests the parts that don't need a DB.
"""

import asyncio
import time
from uuid import uuid4
from unittest.mock import patch

from meinimpact.infrastructure.pipeline.orchestrator import (
    _count_states,
    _run_both_pipelines,
    _unwrap_pipeline_result,
)
from meinimpact.infrastructure.pipeline.state_rules.protocol import StateTrace
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


def _item_with_state(state: str) -> ItemState:
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
    trace = StateTrace(
        engagement_state=state,  # type: ignore[arg-type]
        state_reason="r",
        matched_rule="rule",
        rules_checked=["rule"],
        evidence={},
    )
    return ItemState(raw=raw, state_trace=trace)


# ---------------------------------------------------------------------------
# _count_states
# ---------------------------------------------------------------------------


def test_count_states_tallies_by_engagement_state():
    items = [_item_with_state("A"), _item_with_state("A"), _item_with_state("B")]
    counts = _count_states(items)
    assert counts["A"] == 2
    assert counts["B"] == 1
    assert counts["C"] == 0


def test_count_states_ignores_items_without_trace():
    item = ItemState(raw=_item_with_state("A").raw)
    counts = _count_states([item])
    assert sum(counts.values()) == 0


# ---------------------------------------------------------------------------
# _unwrap_pipeline_result
# ---------------------------------------------------------------------------


def test_unwrap_pipeline_result_passes_through_list():
    items = [_item_with_state("A")]
    errors: list[str] = []
    result = _unwrap_pipeline_result(items, "parliamentary", errors)
    assert result == items
    assert errors == []


def test_unwrap_pipeline_result_records_error_on_exception():
    errors: list[str] = []
    result = _unwrap_pipeline_result(RuntimeError("boom"), "petition", errors)
    assert result == []
    assert len(errors) == 1
    assert "petition" in errors[0]
    assert "boom" in errors[0]


# ---------------------------------------------------------------------------
# _run_both_pipelines: concurrency + fault tolerance
# ---------------------------------------------------------------------------


async def test_both_pipelines_run_concurrently_not_sequentially():
    async def slow_parliamentary(deps, discard_sink):
        await asyncio.sleep(0.05)
        return [_item_with_state("A")]

    async def slow_petition(deps, discard_sink, previous_signature_lookup):
        await asyncio.sleep(0.05)
        return [_item_with_state("C")]

    with (
        patch(
            "meinimpact.infrastructure.pipeline.orchestrator.run_parliamentary_pipeline",
            side_effect=slow_parliamentary,
        ),
        patch(
            "meinimpact.infrastructure.pipeline.orchestrator.run_petition_pipeline",
            side_effect=slow_petition,
        ),
    ):
        start = time.monotonic()
        parliamentary_items, petition_items = await _run_both_pipelines(
            _deps(), lambda item: None, lambda item: None
        )
        elapsed = time.monotonic() - start

    # If run sequentially, elapsed would be >= 0.10s; concurrent stays near 0.05s.
    assert elapsed < 0.09
    assert len(parliamentary_items) == 1
    assert len(petition_items) == 1


async def test_one_pipeline_failing_does_not_block_the_other():
    async def failing_parliamentary(deps, discard_sink):
        raise RuntimeError("DIP API down")

    async def working_petition(deps, discard_sink, previous_signature_lookup):
        return [_item_with_state("C")]

    with (
        patch(
            "meinimpact.infrastructure.pipeline.orchestrator.run_parliamentary_pipeline",
            side_effect=failing_parliamentary,
        ),
        patch(
            "meinimpact.infrastructure.pipeline.orchestrator.run_petition_pipeline",
            side_effect=working_petition,
        ),
    ):
        deps = _deps()
        parliamentary_items, petition_items = await _run_both_pipelines(
            deps, lambda item: None, lambda item: None
        )

    assert parliamentary_items == []
    assert len(petition_items) == 1
    assert len(deps.errors) == 1
    assert "parliamentary" in deps.errors[0]
