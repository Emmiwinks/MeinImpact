"""FetchStep — wraps any SourceAdapter, appending its output to the item list.

Chainable: a pipeline can use multiple FetchStep instances in a row (e.g. the
petition pipeline fetches from both the Bundestag petition portal and civil
society sources) — each just appends, never replaces.
"""

from datetime import UTC, datetime, timedelta

from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.sources.protocol import SourceAdapter

_DEFAULT_LOOKBACK_DAYS = 30


class FetchStep:
    """Fetches new items from one SourceAdapter and appends them to the list."""

    def __init__(
        self,
        adapter: SourceAdapter,
        *,
        lookback_days: int = _DEFAULT_LOOKBACK_DAYS,
        name: str | None = None,
    ) -> None:
        self._adapter = adapter
        self._lookback_days = lookback_days
        self.name = name or f"fetch_{type(adapter).__name__}"

    async def process(self, items: list[ItemState], deps: PipelineDeps) -> list[ItemState]:
        since = datetime.now(UTC) - timedelta(days=self._lookback_days)
        new_items = await self._adapter.fetch_new_items(since)
        return items + [ItemState(raw=raw) for raw in new_items]
