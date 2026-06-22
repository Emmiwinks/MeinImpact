"""Shared types for the ingestion pipeline source adapters."""

from datetime import date, datetime
from typing import NotRequired, Protocol, TypedDict


class RawSourceItem(TypedDict):
    """Unclassified item produced by a source adapter, passed to the pipeline."""

    external_id: str
    title: str
    type: str          # "abstimmung" | "petition" | "gesetzentwurf" | "antrag"
    status: str
    deadline: date | None
    source_url: str
    description: str   # Full text for AI classification
    initiated_by: str
    source: str        # Adapter name, e.g. "dip" or "weact"
    # Optional fields added by specific adapters or pipeline stages:
    signature_count: NotRequired[int]   # WeAct only
    tavily_context: NotRequired[str]    # Added in Stage 4


class SourceAdapter(Protocol):
    """Protocol all source adapters must satisfy."""

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]: ...

    async def fetch_item_detail(self, external_id: str) -> RawSourceItem: ...
