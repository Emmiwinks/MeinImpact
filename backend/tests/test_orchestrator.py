"""Tests for the orchestrator's composition logic: concurrency and fault
tolerance between the two pipelines, and the pure state-counting helper.

`run_ingestion_pipeline` itself needs a real Postgres connection (Database,
session factory) — that's covered by the `test_pipeline_persist.py`
integration tests. This file tests the parts that don't need a DB.
"""

import asyncio
import time
from unittest.mock import patch
from uuid import uuid4

import pytest

from meinimpact.infrastructure.pipeline.orchestrator import (
    _count_states,
    _run_both_pipelines,
)
from meinimpact.infrastructure.pipeline.state_rules.protocol import StateTrace
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.sources.protocol import RawSourceItem


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


async def _noop_discard(item: ItemState) -> None:
    pass


def _item_with_state(state: str) -> ItemState:
    raw: RawSourceItem = {
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


def test_count_states_tallies_by_engagement_state() -> None:
    items = [_item_with_state("A"), _item_with_state("A"), _item_with_state("B")]
    counts = _count_states(items)
    assert counts["A"] == 2
    assert counts["B"] == 1
    assert counts["C"] == 0


def test_count_states_ignores_items_without_trace() -> None:
    item = ItemState(raw=_item_with_state("A").raw)
    counts = _count_states([item])
    assert sum(counts.values()) == 0


# ---------------------------------------------------------------------------
# _run_both_pipelines: concurrency + fail-loud behavior
# ---------------------------------------------------------------------------


async def test_both_pipelines_run_concurrently_not_sequentially() -> None:
    async def slow_parliamentary(
        deps: PipelineDeps, discard_sink: object
    ) -> list[ItemState]:
        await asyncio.sleep(0.05)
        return [_item_with_state("A")]

    async def slow_petition(
        deps: PipelineDeps, discard_sink: object, previous_signature_lookup: object
    ) -> list[ItemState]:
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
            _deps(), _noop_discard, lambda item: None
        )
        elapsed = time.monotonic() - start

    # If run sequentially, elapsed would be >= 0.10s; concurrent stays near 0.05s.
    assert elapsed < 0.09
    assert len(parliamentary_items) == 1
    assert len(petition_items) == 1


async def test_one_pipeline_failing_aborts_the_whole_run() -> None:
    """This is a prototype still being verified end-to-end — a broken
    source must surface as a hard failure, not "0 items found". Isolating
    pipeline failures (letting the other one's results persist) is a
    resilience feature for a system already known to work; right now it
    would hide exactly the kind of bug this behavior is meant to catch."""

    async def failing_parliamentary(
        deps: PipelineDeps, discard_sink: object
    ) -> list[ItemState]:
        raise RuntimeError("DIP API down")

    async def working_petition(
        deps: PipelineDeps, discard_sink: object, previous_signature_lookup: object
    ) -> list[ItemState]:
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
        pytest.raises(RuntimeError, match="DIP API down"),
    ):
        await _run_both_pipelines(_deps(), _noop_discard, lambda item: None)
