"""Domain entities for civic recommendations."""

import uuid
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from enum import StrEnum


class ActionType(StrEnum):
    """Supported civic action types."""

    REPRESENTATIVE_LETTER = "representative_letter"
    PUBLIC_QUESTION = "public_question"
    PETITION_SIGNATURE = "petition_signature"
    EU_CONSULTATION = "eu_consultation"
    LOCAL_LETTER = "local_letter"
    PLANNING_COMMENT = "planning_comment"
    BALLOT_INITIATIVE = "ballot_initiative"
    DRAFT_LAW_COMMENT = "draft_law_comment"


@dataclass(frozen=True)
class CivicAction:
    """A concrete civic action that can be recommended to a user."""

    id: str
    title: str
    action_type: ActionType
    summary: str
    region: str | None
    deadline: date | None
    effort_minutes: int
    impact_hint: str
    source_url: str
    urgency: str = "low"
    werte_relevanz: dict[str, float] = field(default_factory=dict)
    # Spec-added fields
    pro_argumente: tuple[str, ...] = field(default_factory=tuple)
    contra_argumente: tuple[str, ...] = field(default_factory=tuple)
    action_types: tuple[str, ...] = field(default_factory=tuple)
    is_controversial: bool = False
    position_required: bool = False
    active: bool = True
    tavily_context: str | None = None
    # Topic grouping — internal fingerprint-grouping key, not a taxonomy.
    # Actions sharing a topic_id are different engagement options (petition,
    # letter) for the same real-world topic. Defaults to "" only for
    # construction sites that don't care (e.g. dummy/demo data); the real
    # pipeline always assigns a real value (see pipeline/merge.py).
    topic_id: str = ""
    # Engagement-state fields — replace momentum_score
    engagement_state: str = "C"
    state_reason: str | None = None
    pipeline_source: str = "parliamentary"
    previous_signature_count: int | None = None


@dataclass(frozen=True)
class TrackingEvent:
    """A civic outcome event for a tracked action."""

    id: uuid.UUID
    action_id: str
    event_type: str
    title: str
    description: str
    outcome: str | None
    source_url: str | None
    occurred_at: datetime


@dataclass(frozen=True)
class MdbStatement:
    """Cached MdB public statement result for a tracked action."""

    mdb_name: str
    found: bool
    statement_summary: str | None
    source_url: str | None
    searched_at: datetime
    source: str | None = None


@dataclass(frozen=True)
class NewsItem:
    """A civic news item used as recommendation context."""

    id: str
    title: str
    summary: str
    source: str
    published_at: datetime
    url: str


@dataclass(frozen=True)
class UserProfile:
    """The minimum profile data needed by the current recommendation engine."""

    value_axes: dict[str, int]
    region: str | None = None


@dataclass(frozen=True)
class Recommendation:
    """A scored recommendation with explainable reasons."""

    action: CivicAction
    score: int
    reasons: tuple[str, ...]


def utc_now() -> datetime:
    """Returns the current timezone-aware UTC time."""
    return datetime.now(UTC)
