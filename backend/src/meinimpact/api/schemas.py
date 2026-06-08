"""Pydantic schemas for the public HTTP API."""

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, Field

from meinimpact.domain.entities import (
    CivicAction,
    NewsItem,
    Recommendation,
    UserProfile,
)


class HealthResponse(BaseModel):
    """Health endpoint response."""

    status: str
    service: str
    version: str


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


class UserProfileRequest(BaseModel):
    """User profile fragment needed for recommendations."""

    topics: list[str] = Field(min_length=1, max_length=20)
    value_axes: dict[str, int] = Field(default_factory=dict)
    region: str | None = Field(default=None, max_length=80)

    def to_domain(self) -> UserProfile:
        """Converts the request into a domain profile."""
        return UserProfile(
            topics=tuple(self.topics),
            value_axes=dict(self.value_axes),
            region=self.region,
        )


class ActionResponse(BaseModel):
    """Public civic action representation."""

    id: str
    title: str
    action_type: str
    summary: str
    topics: list[str]
    region: str | None
    deadline: date | None
    effort_minutes: int
    impact_hint: str
    source_url: str

    @classmethod
    def from_domain(cls, action: CivicAction) -> ActionResponse:
        """Builds an API response from a domain action."""
        return cls(
            id=action.id,
            title=action.title,
            action_type=action.action_type.value,
            summary=action.summary,
            topics=list(action.topics),
            region=action.region,
            deadline=action.deadline,
            effort_minutes=action.effort_minutes,
            impact_hint=action.impact_hint,
            source_url=action.source_url,
        )


class ActionPoolItemResponse(BaseModel):
    """One action in the device-side scoring pool."""

    id: str
    title: str
    action_type: str
    summary: str
    topics: list[str]
    region: str | None
    deadline: date | None
    effort_minutes: int
    impact_hint: str
    source_url: str
    urgency: str = "low"
    werte_relevanz: dict[str, float] = Field(default_factory=dict)

    @classmethod
    def from_domain(cls, action: CivicAction) -> ActionPoolItemResponse:
        """Builds a pool item from a domain action."""
        return cls(
            id=action.id,
            title=action.title,
            action_type=action.action_type.value,
            summary=action.summary,
            topics=list(action.topics),
            region=action.region,
            deadline=action.deadline,
            effort_minutes=action.effort_minutes,
            impact_hint=action.impact_hint,
            source_url=action.source_url,
            urgency=action.urgency,
        )


class ActionPoolResponse(BaseModel):
    """Full action pool for device-side scoring."""

    actions: list[ActionPoolItemResponse]
    version: str


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


class NewsItemResponse(BaseModel):
    """Public news item representation."""

    id: str
    title: str
    summary: str
    source: str
    published_at: datetime
    topics: list[str]
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
            topics=list(news_item.topics),
            url=news_item.url,
        )


class NewsResponse(BaseModel):
    """News list response."""

    news: list[NewsItemResponse]


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
