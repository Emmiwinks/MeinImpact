"""TraceDiscardsStep — logs (and optionally persists) every state-D item
before FilterStateDStep removes it.

State-D discards have no other durable record — nothing lands in
civic_actions — so this is the traceability safety net for them. See the
architecture plan, section 5 ("Traceability").
"""

from collections.abc import Awaitable, Callable

import structlog

from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps

logger = structlog.get_logger(__name__)

DiscardSink = Callable[[ItemState], Awaitable[None]]


class TraceDiscardsStep:
    """Logs every state-D item; optionally also persists it via `sink`
    (wired to the `pipeline_run_events` table once it exists)."""

    name = "trace_discards"

    def __init__(self, sink: DiscardSink | None = None) -> None:
        self._sink = sink

    async def process(self, items: list[ItemState], deps: PipelineDeps) -> list[ItemState]:
        run_logger = logger.bind(run_id=str(deps.run_id))
        for item in items:
            trace = item.state_trace
            if trace is None or trace.engagement_state != "D":
                continue
            run_logger.info(
                "state_d_discarded",
                external_id=item.raw.get("external_id"),
                source=item.raw.get("source"),
                rules_checked=trace.rules_checked,
            )
            if self._sink is not None:
                await self._sink(item)
        return items
