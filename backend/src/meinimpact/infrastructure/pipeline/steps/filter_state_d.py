"""FilterStateDStep — drops state-D items.

Must run after EvaluateStateStep (and, if discard traceability matters,
after TraceDiscardsStep — which reads the trace before it's gone).
"""

from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps


class FilterStateDStep:
    """Removes items whose engagement_state resolved to 'D'."""

    name = "filter_state_d"

    async def process(
        self, items: list[ItemState], deps: PipelineDeps
    ) -> list[ItemState]:
        return [
            item
            for item in items
            if item.state_trace is not None and item.state_trace.engagement_state != "D"
        ]
