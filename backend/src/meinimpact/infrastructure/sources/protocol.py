"""Shared types for the ingestion pipeline source adapters."""

from dataclasses import dataclass
from datetime import date, datetime
from typing import NotRequired, Protocol, TypedDict


class RawSourceItem(TypedDict):
    """Unclassified item produced by a source adapter, passed to the pipeline."""

    external_id: str
    title: str
    type: str  # "abstimmung" | "petition" | "gesetzentwurf" | "antrag"
    status: str
    deadline: date | None
    source_url: str
    description: str  # Full text for AI classification
    initiated_by: str
    source: str  # Adapter name, e.g. "dip" or "weact"
    # Optional fields added by specific adapters or pipeline stages:
    signature_count: NotRequired[int]  # WeAct only
    tavily_context: NotRequired[str]  # Added in Stage 4
    imminence_score: NotRequired[float]  # 0.0–1.0, from DIP beratungsstand scoring
    descriptor: NotRequired[list[str]]  # DIP Sachgebiet/Deskriptor tags, used for
    # topic-fingerprint deduplication (merge.py) — same descriptor set across
    # sources implies the same real-world action even with a differently
    # phrased title.


class SourceAdapter(Protocol):
    """Protocol all pool-item source adapters must satisfy."""

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]: ...

    async def fetch_item_detail(self, external_id: str) -> RawSourceItem: ...


@dataclass(frozen=True)
class MdbTarget:
    """Identifies an MdB across the 3 systems used for position checks.

    Not every field is available for every MdB — adapters that need an
    unavailable field return `found=False` rather than erroring, per
    specs/data/sources-federal.md "Source 6: MdB Public Statements".
    """

    name: str
    aw_politician_id: int | None = None
    dip_person_id: str | None = None
    nachname: str | None = None
    vorname: str | None = None


@dataclass(frozen=True)
class PositionCheckResult:
    """Result of one MdB-position source check (state B determination)."""

    found: bool
    source: str  # "abgeordnetenwatch" | "dip_reden" | "bundestag_rss"
    statement_summary: str | None = None
    source_url: str | None = None


class PositionCheckAdapter(Protocol):
    """Adapters that check whether an MdB has stated a position on a topic.

    Distinct from `SourceAdapter`: these answer a found/not-found question
    rather than producing pool items, so they don't implement
    `fetch_new_items`/`fetch_item_detail`.
    """

    async def check_position(
        self, mdb: MdbTarget, descriptors: list[str], since: datetime
    ) -> PositionCheckResult: ...


@dataclass(frozen=True)
class MediaCoverageResult:
    """Result of a Tavily quality-media check (state C determination)."""

    matched: bool
    article_count: int = 0
    distinct_domains: int = 0
