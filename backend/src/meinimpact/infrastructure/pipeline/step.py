"""Core types for the generic Step/Pipeline framework.

Both the parliamentary and petition pipelines are declarative lists of
`PipelineStep`s run by the shared `executor.run_pipeline`. Orchestration
mechanics (looping, per-step logging) live once, in the executor — not
duplicated per pipeline — and no single step does more than one job.
See specs/data/ingestion-pipeline.md and the architecture plan for the
full rationale.
"""

from dataclasses import dataclass
from typing import Protocol
from uuid import UUID

from meinimpact.core.config import Settings
from meinimpact.infrastructure.pipeline.state_rules.protocol import (
    RuleContext,
    StateTrace,
)
from meinimpact.infrastructure.pipeline.types import ClassifiedAction
from meinimpact.infrastructure.sources.protocol import RawSourceItem


@dataclass
class ItemState:
    """Carries one candidate item through the pipeline, accumulating results
    as it passes through steps. Steps read what they need and attach what
    they produce — nothing is mutated behind a step's back."""

    raw: RawSourceItem
    rule_context: RuleContext | None = None
    state_trace: StateTrace | None = None
    classified: ClassifiedAction | None = None
    pipeline_source: str | None = (
        None  # "parliamentary" | "petition", tagged in merge.py
    )


@dataclass(frozen=True)
class PipelineDeps:
    """Read-only dependency bag injected into every step: settings, run_id,
    and the shared error list. No step reaches into global state."""

    settings: Settings
    run_id: UUID
    errors: list[str]


class PipelineStep(Protocol):
    """One step in a pipeline. Steps are composed into a plain list — see
    `parliamentary_pipeline.py` / `petition_pipeline.py` — and run in order
    by `executor.run_pipeline`."""

    name: str

    async def process(
        self, items: list[ItemState], deps: PipelineDeps
    ) -> list[ItemState]: ...
