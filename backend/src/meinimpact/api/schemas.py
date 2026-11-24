"""Pydantic schemas for the public HTTP API."""

from datetime import date, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from meinimpact.domain.entities import Opportunity
from meinimpact.infrastructure.feedback.postgres_feedback_repository import (
    CardReason,
    MessageKind,
)
from meinimpact.infrastructure.geo.locality import Locality
from meinimpact.infrastructure.usage.postgres_usage_repository import UsageEvent

# ── Auth ──────────────────────────────────────────────────────────────────────


class AnonymousSessionRequest(BaseModel):
    """Request to create an anonymous installation session."""

    installation_id: UUID
    app_version: str = Field(min_length=1, max_length=32)


class TokenResponse(BaseModel):
    """Anonymous session token response."""

    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in_seconds: int


# ── Location ──────────────────────────────────────────────────────────────────


class MdbOption(BaseModel):
    """One Wahlkreis/MdB match for a PLZ lookup."""

    wahlkreis_nr: int
    wahlkreis_name: str
    mdb_name: str
    mdb_party: str
    mdb_link: str | None = None


class LocationRequest(BaseModel):
    """A PLZ to locate. In the body, so no access log line carries it."""

    plz: str = Field(pattern=r"^\d{5}$")


class LocationResponse(BaseModel):
    """Where a PLZ lies: what the app keeps on the device instead of it.

    `kreis` is the only part it sends again (to narrow the pool); the
    point stays for ranking by distance. `wahlkreise` lists the PLZ's
    members of the Bundestag, several where it straddles Wahlkreise, and
    is empty while the Bundestag data is unavailable. `coverage` says
    whether there are topics from the city or Kreis ("local"), only from
    the Land ("land") or only Bund and EU ("none"), so the app can say so
    when the PLZ is entered."""

    kreis: str
    lat: float
    lon: float
    wahlkreise: list[MdbOption]
    coverage: str


# ── Admin ─────────────────────────────────────────────────────────────────────


class IngestionRunResponse(BaseModel):
    """Acknowledges a started background ingestion run."""

    status: str


# ── Health ────────────────────────────────────────────────────────────────────


class HealthResponse(BaseModel):
    """Health endpoint response."""

    status: str
    service: str
    version: str
    pool_version: str | None = None
    app_version_min: str | None = None


# ── Opportunities ─────────────────────────────────────────────────────────────


class AreaResponse(BaseModel):
    lat: float
    lon: float
    km: float


class GeldResponse(BaseModel):
    """A budget area (taxonomy.GELD_BEREICHE) and whether it gets more (+1)
    or less (-1) money if supporters get their way."""

    bereich: str
    richtung: int


class BundleResponse(BaseModel):
    """The card this opportunity shares with others on the same matter:
    shared header, title and summary, and this option's label and the
    sentence saying how it differs from the others."""

    id: UUID
    header: str
    title: str
    summary: str
    label: str
    difference: str


class OpportunityResponse(BaseModel):
    """One open opportunity: everything the feed card and its detail view
    need, no follow-up request required.

    `gebiet`, `reichweite` and `umkreis` say whom it concerns as a place
    (`geo/locality.py`): the AGS prefix of everyone concerned ("" for Bund
    and EU), and for a city's matters the area around a centre, city-wide
    or one neighbourhood's, that the app ranks by distance from."""

    id: UUID
    source_org: str
    source_url: str
    kind: str
    status: str
    region: str
    locality: str | None
    organizer: str | None
    title: str
    summary: str
    affected_tags: list[str]
    lebenslagen: list[str]
    # Questionnaire key -> -1 / +1: supporters agree with its left / right
    # statement; only statements that directly predict support
    werte_relevanz: dict[str, float]
    geld: list[GeldResponse]
    # Why it is on the table now, one sentence from the source; null if
    # the source doesn't say
    anlass: str | None
    pro_argumente: list[str]
    contra_argumente: list[str]
    personal_impact_snippets: dict[str, str]
    everyday_relevance: int | None
    accessibility: int | None
    districts: list[str]
    opens_on: date | None
    closes_on: date | None
    support_count: int | None
    support_goal: int | None
    support_count_as_of: datetime | None
    first_seen_at: datetime
    gebiet: str
    reichweite: str | None
    umkreis: AreaResponse | None
    bundle: BundleResponse | None = None

    @classmethod
    def from_domain(
        cls, opportunity: Opportunity, locality: Locality
    ) -> OpportunityResponse:
        """Builds an API response from a domain opportunity and where it
        lies."""
        area = locality.area
        bundle = opportunity.bundle
        return cls(
            bundle=(
                BundleResponse(
                    id=bundle.id,
                    header=bundle.header,
                    title=bundle.title,
                    summary=bundle.summary,
                    label=bundle.label,
                    difference=bundle.difference,
                )
                if bundle
                else None
            ),
            gebiet=locality.gebiet,
            reichweite=locality.reach.value if locality.reach else None,
            umkreis=(
                AreaResponse(lat=area.centre.lat, lon=area.centre.lon, km=area.km)
                if area
                else None
            ),
            id=opportunity.id,
            source_org=opportunity.source_org,
            source_url=opportunity.source_url,
            kind=opportunity.kind,
            status=opportunity.status,
            region=opportunity.region,
            locality=opportunity.locality,
            organizer=opportunity.organizer,
            title=opportunity.title,
            summary=opportunity.summary,
            affected_tags=list(opportunity.affected_tags),
            lebenslagen=list(opportunity.lebenslagen),
            werte_relevanz=dict(opportunity.werte_relevanz),
            geld=[
                GeldResponse(bereich=area, richtung=direction)
                for area, direction in opportunity.geld
            ],
            anlass=opportunity.anlass,
            pro_argumente=list(opportunity.pro_argumente),
            contra_argumente=list(opportunity.contra_argumente),
            personal_impact_snippets=dict(opportunity.personal_impact_snippets),
            everyday_relevance=opportunity.everyday_relevance,
            accessibility=opportunity.accessibility,
            districts=list(opportunity.districts),
            opens_on=opportunity.opens_on,
            closes_on=opportunity.closes_on,
            support_count=opportunity.support_count,
            support_goal=opportunity.support_goal,
            support_count_as_of=opportunity.support_count_as_of,
            first_seen_at=opportunity.first_seen_at,
        )


class RecipientMemberResponse(BaseModel):
    name: str
    fraktion: str | None


class RecipientOfficeResponse(BaseModel):
    fraktion: str
    email: str | None


class RecipientsResponse(BaseModel):
    """Who a letter about a council decision goes to. `offices` is empty for
    district and village councils (names only for now) and when no members
    are known yet; the app then leaves "An" to the user."""

    bodies: list[str]
    members: list[RecipientMemberResponse]
    offices: list[RecipientOfficeResponse]


class OpportunityPoolResponse(BaseModel):
    """All open opportunities. Ordering is not meaningful server-side; the
    device ranks on-device (Betroffenheitsprofil match, then Werteprofil
    alignment), since the server never sees either profile."""

    opportunities: list[OpportunityResponse]
    generated_at: datetime


class OpportunityPreviewItemResponse(BaseModel):
    """One action for the landing page, with what the app's card shows on
    both faces. `topic_index` is the main topic's position in the topic list
    (None for an untagged one), so the page draws and colours it like the
    app does. `for_you` is one of its personal impact sentences."""

    title: str
    kind: str
    region: str
    source_org: str
    summary: str
    opens_on: date | None
    closes_on: date | None
    topic_index: int | None
    for_you: str | None
    pro_argumente: list[str]
    contra_argumente: list[str]
    support_count: int | None
    support_goal: int | None
    place: str | None
    districts: list[str]


class OpportunityPreviewResponse(BaseModel):
    """A public taste of the pool for meinimpact.de: counts and a few easy
    questions, no session needed."""

    total: int
    by_region: dict[str, int]
    items: list[OpportunityPreviewItemResponse]
    generated_at: datetime


class OkResponse(BaseModel):
    """Generic success response."""

    ok: bool = True


# ── Tracking and usage ────────────────────────────────────────────────────────


class TrackedRequest(BaseModel):
    """The app's anonymous "someone did this" mark.

    The id travels in the body so access logs never show which opportunity
    was done.
    """

    opportunity_id: UUID


class RecipientsRequest(BaseModel):
    """Which council decision a letter is about.

    In the body, like `TrackedRequest`: in the URL, the access log would
    show which decision an IP drafted a letter on.
    """

    model_config = ConfigDict(extra="forbid")

    opportunity_id: UUID


class UsageRequest(BaseModel):
    """One anonymous usage event: only its name, counted per day."""

    event: UsageEvent


# ── Beta feedback ─────────────────────────────────────────────────────────────


class CardRanking(BaseModel):
    """The score parts the app's ranker gave a card: never profile data.

    Each part is what it added to the card's blended score
    (opportunity_relevance_ranker.dart); `haltung` is the Werteprofil and
    Stadthaushalt part, negative where the card goes against the user.
    """

    model_config = ConfigDict(extra="forbid")

    position: int = Field(ge=0, le=500)
    score: float = Field(ge=-100, le=100)
    appeal: float = Field(ge=-100, le=100)
    situation: float = Field(ge=-100, le=100)
    interest: float = Field(ge=-100, le=100)
    locality: float = Field(ge=-100, le=100)
    haltung: float = Field(ge=-100, le=100)
    # The card took an exploration slot (a topic with no learned interest yet)
    exploration: bool = False


class CardFeedbackRequest(BaseModel):
    """Why the tester threw a card away. The id travels in the body so access
    logs never show which card."""

    opportunity_id: UUID
    reason: CardReason
    note: str | None = Field(default=None, max_length=500)
    ranking: CardRanking
    app_version: str = Field(min_length=1, max_length=40)


class BetaFeedbackRequest(BaseModel):
    kind: MessageKind
    message: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)
    ]
    screen: str | None = Field(default=None, max_length=60)
    app_version: str = Field(min_length=1, max_length=40)
    platform: Literal["android", "ios", "web"]


class ImpactNewsItemResponse(BaseModel):
    # "exact"/"issue": about the action's concrete matter; "background":
    # the overarching topic, shown as background only
    level: str
    # "news" or "statement" (also "social", "other")
    kind: str
    title: str
    url: str
    snippet: str
    published_on: date | None


class ImpactNewsEntryResponse(BaseModel):
    opportunity_id: UUID
    checked_at: datetime
    # Empty: searched, nothing found ("Noch keine Berichte")
    items: list[ImpactNewsItemResponse]


class ImpactNewsFeedResponse(BaseModel):
    """News for every tracked opportunity searched so far.

    One feed for everyone: the app picks its own actions on the device, so
    no request names an action the caller did.
    """

    opportunities: list[ImpactNewsEntryResponse]


# ── Letters ───────────────────────────────────────────────────────────────────


class LetterRequest(BaseModel):
    """Request for a streaming letter on an upcoming council decision.

    `notes` is what the user typed for the AI: their stance, their own
    situation, points to make. Nothing from the on-device profile is sent.
    """

    opportunity_id: UUID
    notes: str | None = Field(default=None, max_length=1000)
