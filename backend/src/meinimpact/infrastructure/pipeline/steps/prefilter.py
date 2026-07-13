"""PrefilterStep — cheap gate before the expensive per-item I/O in
BuildRuleContextStep (3-source MdB check, Tavily media search).
"""

from meinimpact.infrastructure.pipeline.stages import passes_basic_checks
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps


class PrefilterStep:
    """Drops items with too-short or non-German titles."""

    name = "prefilter"

    async def process(self, items: list[ItemState], deps: PipelineDeps) -> list[ItemState]:
        return [item for item in items if passes_basic_checks(item.raw)]
