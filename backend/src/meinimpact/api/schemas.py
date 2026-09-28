"""Pydantic schemas for the public HTTP API."""

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, Field

from meinimpact.domain.entities import (
    CivicAction,
    MdbStatement,
    NewsItem,
    Opportunity,
    Recommendation,
    TrackingEvent,
    UserProfile,
)

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


# ── MdB lookup ────────────────────────────────────────────────────────────────


class MdbOption(BaseModel):
    """One Wahlkreis/MdB match for a PLZ lookup."""

    wahlkreis_nr: int
    wahlkreis_name: str
    mdb_name: str
    mdb_party: str
    mdb_link: str | None = None


class MdbResponse(BaseModel):
    """Response for GET /v1/mdb?plz={plz}."""

    plz: str
    results: list[MdbOption]


# ── Admin ─────────────────────────────────────────────────────────────────────


class IngestionRunResponse(BaseModel):
    """Live summary of one manually-triggered ingestion run — not
    persisted (see `IngestionSummary`'s docstring)."""

    fetched: int
    actionable: int
    inserted: int
    refreshed: int
    errors: list[str]


# ── Health ────────────────────────────────────────────────────────────────────


class HealthResponse(BaseModel):
    """Health endpoint response."""

    status: str
    service: str
    version: str
    pool_version: str | None = None
    app_version_min: str | None = None


# ── User profile ──────────────────────────────────────────────────────────────


class UserProfileRequest(BaseModel):
    """User profile fragment needed for recommendations."""

    value_axes: dict[str, int] = Field(default_factory=dict)
    region: str | None = Field(default=None, max_length=80)

    def to_domain(self) -> UserProfile:
        """Converts the request into a domain profile."""
        return UserProfile(
            value_axes=dict(self.value_axes),
            region=self.region,
        )


# ── Actions ───────────────────────────────────────────────────────────────────


class ActionResponse(BaseModel):
    """Public civic action representation."""

    id: str
    title: str
    action_type: str
    summary: str
    region: str | None
    deadline: date | None
    effort_minutes: int
    impact_hint: str
    source_url: str
    topic_id: str

    @classmethod
    def from_domain(cls, action: CivicAction) -> ActionResponse:
        """Builds an API response from a domain action."""
        return cls(
            id=action.id,
            title=action.title,
            action_type=action.action_type.value,
            summary=action.summary,
            region=action.region,
            deadline=action.deadline,
            effort_minutes=action.effort_minutes,
            impact_hint=action.impact_hint,
            source_url=action.source_url,
            topic_id=action.topic_id,
        )


class ActionPoolItemResponse(BaseModel):
    """One action in the device-side scoring pool."""

    id: str
    title: str
    action_type: str
    summary: str
    region: str | None
    deadline: date | None
    effort_minutes: int
    impact_hint: str
    source_url: str
    topic_id: str
    urgency: str = "low"
    werte_relevanz: dict[str, float] = Field(default_factory=dict)
    pro_argumente: list[str] = Field(default_factory=list)
    contra_argumente: list[str] = Field(default_factory=list)
    action_types: list[str] = Field(default_factory=list)
    is_controversial: bool = False
    position_required: bool = False
    engagement_state: str = "C"
    state_reason: str | None = None
    pipeline_source: str = "parliamentary"
    created_at: datetime | None = None

    @classmethod
    def from_domain(cls, action: CivicAction) -> ActionPoolItemResponse:
        """Builds a pool item from a domain action."""
        return cls(
            id=action.id,
            title=action.title,
            action_type=action.action_type.value,
            summary=action.summary,
            region=action.region,
            deadline=action.deadline,
            effort_minutes=action.effort_minutes,
            impact_hint=action.impact_hint,
            source_url=action.source_url,
            topic_id=action.topic_id,
            urgency=action.urgency,
            werte_relevanz=dict(action.werte_relevanz),
            pro_argumente=list(action.pro_argumente),
            contra_argumente=list(action.contra_argumente),
            action_types=list(action.action_types),
            is_controversial=action.is_controversial,
            position_required=action.position_required,
            engagement_state=action.engagement_state,
            state_reason=action.state_reason,
            pipeline_source=action.pipeline_source,
        )


class ActionPoolResponse(BaseModel):
    """Full action pool for device-side scoring."""

    actions: list[ActionPoolItemResponse]
    version: str
    generated_at: datetime


# ── Opportunities ─────────────────────────────────────────────────────────────


class OpportunityResponse(BaseModel):
    """One civic opportunity — the unit shown on a feed card and its
    detail popup. No topic/option grouping (see `Opportunity`'s
    docstring) — this is the whole thing the device needs for both
    views, no follow-up request required."""

    id: UUID
    source_org: str
    decision_object: str
    plain_language_title: str
    plain_language_summary: str
    affected_tags: list[str]
    region: str
    werte_relevanz: dict[str, float]
    deadline: date | None
    support_count: int | None
    support_count_as_of: datetime | None
    content_published_at: date | None
    retrieved_at: datetime
    source_url: str
    action_types: list[str]
    pro_argumente: list[str]
    contra_argumente: list[str]
    personal_impact_snippets: dict[str, str]

    @classmethod
    def from_domain(cls, opportunity: Opportunity) -> OpportunityResponse:
        """Builds an API response from a domain opportunity."""
        return cls(
            id=opportunity.id,
            source_org=opportunity.source_org,
            decision_object=opportunity.decision_object,
            plain_language_title=opportunity.plain_language_title,
            plain_language_summary=opportunity.plain_language_summary,
            affected_tags=list(opportunity.affected_tags),
            region=opportunity.region,
            werte_relevanz=dict(opportunity.werte_relevanz),
            deadline=opportunity.deadline,
            support_count=opportunity.support_count,
            support_count_as_of=opportunity.support_count_as_of,
            content_published_at=opportunity.content_published_at,
            retrieved_at=opportunity.retrieved_at,
            source_url=opportunity.source_url,
            action_types=list(opportunity.action_types),
            pro_argumente=list(opportunity.pro_argumente),
            contra_argumente=list(opportunity.contra_argumente),
            personal_impact_snippets=dict(opportunity.personal_impact_snippets),
        )


class OpportunityPoolResponse(BaseModel):
    """The current run's opportunities — see
    `OpportunityRepository.list_current_run`. Ordering is not
    meaningful server-side; the device sorts by on-device relevance
    (Betroffenheitsprofil match, then Werteprofil alignment) since the
    server never sees either profile."""

    opportunities: list[OpportunityResponse]
    generated_at: datetime


# ── Recommendations ───────────────────────────────────────────────────────────


class RecommendationResponse(BaseModel):
    """Recommended action with transparent scoring reasons."""

    action: ActionResponse
    score: int
    reasons: list[str]

    @classmethod
    def from_domain(cls, recommendation: Recommendation) -> RecommendationResponse:
        """Builds an API response from a domain recommendation."""
        return cls(
            action=ActionResponse.from_domain(recommendation.action),
            score=recommendation.score,
            reasons=list(recommendation.reasons),
        )


class RecommendationsRequest(BaseModel):
    """Recommendation request body."""

    profile: UserProfileRequest
    limit: int = Field(default=5, ge=1, le=20)


class RecommendationsResponse(BaseModel):
    """Recommendation list response."""

    recommendations: list[RecommendationResponse]


# ── Action context ────────────────────────────────────────────────────────────


class ActionContextRequest(BaseModel):
    """Demographics for personalised action context generation."""

    lebenssituation: list[str] = Field(default_factory=list)
    sektor: str | None = None
    plz_prefix: str | None = Field(default=None, max_length=2)
    wohnsituation: str | None = None


class ActionContextResponse(BaseModel):
    """AI-generated personalised context for an action."""

    action_id: str
    context: str


# ── Action completion ─────────────────────────────────────────────────────────


class ActionCompleteRequest(BaseModel):
    """Request to record that a user completed an action."""

    action_type: str = Field(pattern=r"^(brief|petition|anfrage)$")


class ActionCompleteResponse(BaseModel):
    """Response after recording an action completion."""

    ok: bool
    completion_count: int


# ── Tracking ──────────────────────────────────────────────────────────────────


class TrackingEventResponse(BaseModel):
    """One civic outcome event."""

    id: UUID
    event_type: str
    title: str
    description: str
    outcome: str | None
    source_url: str | None
    occurred_at: datetime

    @classmethod
    def from_domain(cls, event: TrackingEvent) -> TrackingEventResponse:
        return cls(
            id=event.id,
            event_type=event.event_type,
            title=event.title,
            description=event.description,
            outcome=event.outcome,
            source_url=event.source_url,
            occurred_at=event.occurred_at,
        )


class MdbStatementResponse(BaseModel):
    """One cached MdB statement result."""

    mdb_name: str
    found: bool
    source: str | None = None
    statement_summary: str | None
    source_url: str | None
    searched_at: datetime

    @classmethod
    def from_domain(cls, stmt: MdbStatement) -> MdbStatementResponse:
        return cls(
            mdb_name=stmt.mdb_name,
            found=stmt.found,
            source=stmt.source,
            statement_summary=stmt.statement_summary,
            source_url=stmt.source_url,
            searched_at=stmt.searched_at,
        )


class ActionTrackingResponse(BaseModel):
    """Tracking events and MdB statements for an action."""

    action_id: str
    events: list[TrackingEventResponse]
    mdb_statements: list[MdbStatementResponse]


# ── Push notifications ────────────────────────────────────────────────────────


class PushRegisterRequest(BaseModel):
    """Push token registration."""

    push_token: str = Field(min_length=1, max_length=500)
    platform: str = Field(pattern=r"^(fcm|apns)$")


class PushSubscribeRequest(BaseModel):
    """Subscribe or unsubscribe a push token to an action."""

    push_token: str = Field(min_length=1, max_length=500)
    action_id: str = Field(min_length=1, max_length=120)


class OkResponse(BaseModel):
    """Generic success response."""

    ok: bool = True


# ── Feedback ──────────────────────────────────────────────────────────────────


class FeedbackRequest(BaseModel):
    """Anonymous in-app feedback submission."""

    action_id: str | None = Field(default=None, max_length=120)
    rating: int | None = Field(default=None, ge=1, le=5)
    comment: str | None = Field(default=None, max_length=500)


# ── Beta token ────────────────────────────────────────────────────────────────


class BetaActivateRequest(BaseModel):
    """Beta token activation request."""

    token: str = Field(min_length=1, max_length=40)


class BetaActivateResponse(BaseModel):
    """Beta token activation response."""

    valid: bool


# ── News ──────────────────────────────────────────────────────────────────────


class NewsItemResponse(BaseModel):
    """Public news item representation."""

    id: str
    title: str
    summary: str
    source: str
    published_at: datetime
    url: str

    @classmethod
    def from_domain(cls, news_item: NewsItem) -> NewsItemResponse:
        """Builds an API response from a domain news item."""
        return cls(
            id=news_item.id,
            title=news_item.title,
            summary=news_item.summary,
            source=news_item.source,
            published_at=news_item.published_at,
            url=news_item.url,
        )


class NewsResponse(BaseModel):
    """News list response."""

    news: list[NewsItemResponse]


# ── Letters ───────────────────────────────────────────────────────────────────


class LetterRequest(BaseModel):
    """Request for a streaming letter or public question draft."""

    action_id: str = Field(min_length=1, max_length=120)
    type: str = Field(pattern=r"^(brief|anfrage)$")
    recipient_name: str = Field(min_length=1, max_length=120)
    recipient_party: str = Field(min_length=1, max_length=60)
    recipient_wahlkreis: str | None = Field(default=None, max_length=120)
    tone_descriptors: list[str] = Field(default_factory=list)
    lebenssituation: list[str] = Field(default_factory=list)
    sektor: str | None = None
    plz_prefix: str | None = Field(default=None, max_length=2)
    wohnsituation: str | None = None
