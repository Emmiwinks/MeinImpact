"""The normalized record every listing source produces.

This is the contract between the source side (one adapter per registry) and
everything downstream (filtering, extraction, persistence). Sources report
what the registry says, and nothing more: no relevance judgement, no topic
tags, no political framing. Those belong to later steps.
"""

from dataclasses import dataclass, field
from datetime import date, datetime
from enum import StrEnum


class Region(StrEnum):
    """Coverage areas of the app, from widest to most specific."""

    EU = "eu"
    BUND = "bund"
    SACHSEN = "sachsen"
    DRESDEN = "dresden"


class ActionKind(StrEnum):
    """What a citizen actually does with a listing."""

    PETITION = "petition"
    CONSULTATION = "consultation"
    PUBLIC_DISPLAY = "public_display"  # Öffentliche Auslegung (Bauleitplanung)
    SURVEY = "survey"
    EVENT = "event"
    DECISION = "decision"  # upcoming council vote: write to its members
    NOTICE = "notice"  # Bekanntmachung, Beschluss: informational only
    OTHER = "other"


class ListingStatus(StrEnum):
    OPEN = "open"
    ANNOUNCED = "announced"
    CLOSED = "closed"
    UNKNOWN = "unknown"


@dataclass(frozen=True, slots=True)
class Support:
    """Participation signals, exactly as the registry exposes them.

    `recent_activity` holds timestamps only. Registries like WeAct publish
    first names next to them; those are never stored.
    """

    count: int | None = None
    goal: int | None = None
    partner_count: int | None = None
    recent_activity: tuple[datetime, ...] = ()


@dataclass(frozen=True, slots=True)
class Listing:
    """One open (or announced) way to participate, as listed by a registry.

    `region` is the coverage bucket this listing belongs to, or None when the
    registry lists it but it lies outside the app's coverage (e.g. another
    Saxon municipality). `locality` keeps the registry's own, finer label.
    """

    source_id: str
    external_id: str
    url: str
    title: str
    kind: ActionKind
    status: ListingStatus
    region: Region | None
    observed_at: datetime
    locality: str | None = None
    organizer: str | None = None
    summary: str | None = None
    opens_on: date | None = None
    closes_on: date | None = None
    support: Support = field(default_factory=Support)
    source_labels: tuple[str, ...] = ()

    @property
    def key(self) -> tuple[str, str]:
        """Identity within the source registry."""
        return (self.source_id, self.external_id)
