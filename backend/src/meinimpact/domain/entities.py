"""Domain entities for civic opportunities."""

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime


@dataclass(frozen=True)
class OpportunityBundle:
    """The card an opportunity shares with others on the same matter: the
    shared texts, and this option's label and how it differs."""

    id: uuid.UUID
    header: str
    title: str
    summary: str
    label: str
    difference: str


@dataclass(frozen=True)
class Opportunity:
    """An open way to participate, as shown in the app.

    Registry facts (kind, dates, support, source) come straight from the
    publishing registry; title, summary, tags, werte axes, arguments and
    personal-impact snippets come from enrichment. Only relevant, active,
    not-yet-closed opportunities are ever served.
    """

    id: uuid.UUID
    source_org: str
    source_url: str
    kind: str
    status: str
    region: str
    locality: str | None
    organizer: str | None
    title: str
    summary: str
    affected_tags: tuple[str, ...]
    # Lebenslagen catalog ids this concerns (ai/lebenslagen.py); the app
    # matches them against the groups the user picked on their device
    lebenslagen: tuple[str, ...]
    # Questionnaire key -> -1 / +1: supporters agree with its left / right
    # statement (taxonomy.WERTE_AUSSAGEN)
    werte_relevanz: dict[str, float]
    pro_argumente: tuple[str, ...]
    contra_argumente: tuple[str, ...]
    personal_impact_snippets: dict[str, str]
    # 1-5 enrichment scores; the app ranks easy, everyday cards first
    everyday_relevance: int | None
    accessibility: int | None
    # City districts concerned; empty = the whole city or region
    districts: tuple[str, ...]
    opens_on: date | None
    closes_on: date | None
    support_count: int | None
    support_goal: int | None
    support_count_as_of: datetime | None
    first_seen_at: datetime
    # Decisions: OParl bodies whose members a letter goes to
    recipient_bodies: tuple[str, ...] = ()
    # Enrichment's reading of where it matters (geo/locality.py): reach
    # ("nachbarschaft", "ort", "stadt", "umland") and the places it names
    reach: str | None = None
    places: tuple[str, ...] = ()
    # (budget area, +1 more / -1 less money) if supporters get their way
    geld: tuple[tuple[str, int], ...] = ()
    # Why it is on the table now, from the source text
    anlass: str | None = None
    bundle: OpportunityBundle | None = None


def utc_now() -> datetime:
    """Returns the current timezone-aware UTC time."""
    return datetime.now(UTC)
