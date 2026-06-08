"""Domain entities for civic recommendations."""

from dataclasses import dataclass
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
    topics: tuple[str, ...]
    region: str | None
    deadline: date | None
    effort_minutes: int
    impact_hint: str
    source_url: str
    urgency: str = "low"


@dataclass(frozen=True)
class NewsItem:
    """A civic news item used as recommendation context."""

    id: str
    title: str
    summary: str
    source: str
    published_at: datetime
    topics: tuple[str, ...]
    url: str


@dataclass(frozen=True)
class UserProfile:
    """The minimum profile data needed by the current recommendation engine."""

    topics: tuple[str, ...]
    value_axes: dict[str, int]
    region: str | None = None

    @property
    def normalized_topics(self) -> set[str]:
        """Returns lower-case topic names for matching."""
        return {topic.strip().lower() for topic in self.topics if topic.strip()}


@dataclass(frozen=True)
class Recommendation:
    """A scored recommendation with explainable reasons."""

    action: CivicAction
    score: int
    reasons: tuple[str, ...]


def utc_now() -> datetime:
    """Returns the current timezone-aware UTC time."""
    return datetime.now(UTC)
