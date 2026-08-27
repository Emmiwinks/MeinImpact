"""Runs a declarative list of `PipelineStep`s in order.

This is the one place orchestration mechanics (looping, per-step timing,
structured logging) live — steps themselves never loop over each other or
log pipeline-level progress. Logging every step transition here, correlated
by `run_id`, gives pipeline-level traceability "for free": for any run you
can see exactly how many items went into and came out of every step,
without touching the steps themselves.
"""

from collections.abc import Sequence

import structlog

from meinimpact.infrastructure.pipeline.step import (
    ItemState,
    PipelineDeps,
    PipelineStep,
)

logger = structlog.get_logger(__name__)


async def run_pipeline(
    steps: Sequence[PipelineStep], deps: PipelineDeps
) -> list[ItemState]:
    """Runs `steps` in order, each receiving the previous step's output."""
    items: list[ItemState] = []
    run_logger = logger.bind(run_id=str(deps.run_id))
    for step in steps:
        items_in = len(items)
        items = await step.process(items, deps)
        run_logger.info(
            "step_completed",
            step=step.name,
            items_in=items_in,
            items_out=len(items),
        )
    return items
