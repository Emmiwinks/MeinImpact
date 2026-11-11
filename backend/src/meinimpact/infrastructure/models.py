"""SQLAlchemy table models for persistent repositories."""

import uuid
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import (
    ARRAY,
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Identity,
    Integer,
    Numeric,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    """Base class for SQLAlchemy models."""


class UserProfileRecord(Base):
    """Persistent user profile record."""

    __tablename__ = "user_profiles"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid4,
    )
    installation_id: Mapped[str] = mapped_column(
        String(length=120),
        index=True,
        nullable=False,
    )
    value_axes: Mapped[dict[str, int]] = mapped_column(JSONB, nullable=False)
    region: Mapped[str | None] = mapped_column(String(length=80), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class CivicActionRecord(Base):
    """Persistent civic action record.

    Status (2026-09-27): the `civic_actions` table itself was dropped by
    migration 202609270010 (retired DIP-sourced pipeline, replaced by
    `OpportunityRecord`/`opportunities` below). This class is left in place
    only because `postgres_action_repository.py` still imports it for the
    old `/v1/actions/*` read endpoints — those will 500 until that read
    side is rewired onto `opportunities` (a later, deliberate step, not an
    oversight). Don't add new code against this table.
    """

    __tablename__ = "civic_actions"

    id: Mapped[str] = mapped_column(String(length=120), primary_key=True)
    title: Mapped[str] = mapped_column(String(length=240), nullable=False)
    action_type: Mapped[str] = mapped_column(String(length=80), nullable=False)
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    region: Mapped[str | None] = mapped_column(String(length=80), nullable=True)
    deadline: Mapped[date | None] = mapped_column(Date, nullable=True)
    effort_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    impact_hint: Mapped[str] = mapped_column(Text, nullable=False)
    source_url: Mapped[str] = mapped_column(
        String(length=500), nullable=False, unique=True
    )
    urgency: Mapped[str] = mapped_column(
        String(length=10), nullable=False, default="low"
    )
    werte_relevanz: Mapped[dict[str, float]] = mapped_column(
        JSONB, nullable=False, server_default="{}"
    )
    # Spec-added columns (migration 0005)
    external_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    pro_argumente: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    contra_argumente: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    action_types: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    is_controversial: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false"
    )
    position_required: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false"
    )
    tavily_context: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Topic grouping (migration 0009) — internal fingerprint-grouping key,
    # not a taxonomy. Rows sharing a topic_id are different engagement
    # options (petition, letter) for the same real-world topic.
    topic_id: Mapped[str] = mapped_column(String(length=120), nullable=False)
    # Engagement-state columns (migration 0008) — replace momentum_score
    engagement_state: Mapped[str] = mapped_column(
        String(length=1), nullable=False, server_default="C"
    )
    state_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    pipeline_source: Mapped[str] = mapped_column(
        String(length=20), nullable=False, server_default="parliamentary"
    )
    previous_signature_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class OpportunityRecord(Base):
    """A participation opportunity read from a registry, plus its enrichment.

    Registry facts (`infrastructure/listings`) are refreshed on every run.
    Enrichment (relevance decision and plain-language framing) is computed
    once per registry text version, tracked by `enrichment_input_hash`, so
    unchanged listings never cost another LLM call. A row stays `active`
    while its registry still lists it.
    """

    __tablename__ = "opportunities"

    __table_args__ = (
        UniqueConstraint(
            "source_id", "external_id", name="uq_opportunities_registry_entry"
        ),
        CheckConstraint(
            "(support_count IS NULL) = (support_count_as_of IS NULL)",
            name="chk_support_count_as_of_pairing",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid4
    )

    # Registry facts
    source_id: Mapped[str] = mapped_column(String(length=60), nullable=False)
    external_id: Mapped[str] = mapped_column(Text, nullable=False)
    source_url: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(String(length=40), nullable=False)
    status: Mapped[str] = mapped_column(String(length=20), nullable=False)
    registry_region: Mapped[str | None] = mapped_column(
        String(length=20), nullable=True
    )
    locality: Mapped[str | None] = mapped_column(Text, nullable=True)
    organizer: Mapped[str | None] = mapped_column(Text, nullable=True)
    registry_title: Mapped[str] = mapped_column(Text, nullable=False)
    registry_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_labels: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    # Decisions: OParl organization URLs whose members a letter goes to
    recipient_bodies: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    opens_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    closes_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    support_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    support_goal: Mapped[int | None] = mapped_column(Integer, nullable=True)
    support_count_as_of: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    first_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    # Day someone first marked this done in the app. Only this one mark,
    # no count, no device, no person: it decides what Mein Impact follows.
    tracked_since: Mapped[date | None] = mapped_column(Date, nullable=True)
    # When the news ladder last ran for this opportunity (OpportunityNewsRecord)
    news_checked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Enrichment (all null/empty until enriched)
    enrichment_input_hash: Mapped[str | None] = mapped_column(
        String(length=64), nullable=True
    )
    enriched_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    is_relevant: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    relevance_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    region: Mapped[str | None] = mapped_column(String(length=20), nullable=True)
    everyday_relevance: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    accessibility: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    # City districts concerned (names from geo/data), [] = whole city/region
    districts: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    # Free topic label, for taxonomy maintenance (scripts/topic_report.py)
    free_topic: Mapped[str | None] = mapped_column(Text, nullable=True)
    topic_candidate: Mapped[str | None] = mapped_column(Text, nullable=True)
    title: Mapped[str | None] = mapped_column(Text, nullable=True)
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    affected_tags: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    # Lebenslagen catalog ids, and the model's own label for a missing group
    # (scripts/topic_report.py)
    lebenslagen: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    lebenslage_frei: Mapped[str | None] = mapped_column(Text, nullable=True)
    werte_relevanz: Mapped[dict[str, float]] = mapped_column(
        JSONB, nullable=False, server_default="{}"
    )
    pro_argumente: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    contra_argumente: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    personal_impact_snippets: Mapped[dict[str, str]] = mapped_column(
        JSONB, nullable=False, server_default="{}"
    )


class CouncilMemberRecord(Base):
    """A current voting member of a council body, with their Fraktion.

    Read from OParl and replaced wholesale per source on every sync. Only
    public facts about office holders: name, body, Fraktion.
    """

    __tablename__ = "council_members"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    source_id: Mapped[str] = mapped_column(String(length=60), nullable=False)
    organization_url: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    organization_name: Mapped[str] = mapped_column(Text, nullable=False)
    person_url: Mapped[str] = mapped_column(Text, nullable=False)
    person_name: Mapped[str] = mapped_column(Text, nullable=False)
    fraktion_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    fraktion_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    synced_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class SupportSnapshotRecord(Base):
    """One observed support count, so momentum can be computed across runs
    for registries that don't expose it themselves (openPetition)."""

    __tablename__ = "opportunity_support_snapshots"

    __table_args__ = (
        UniqueConstraint(
            "opportunity_id", "observed_at", name="uq_support_snapshot_observation"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid4
    )
    opportunity_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("opportunities.id", ondelete="CASCADE"),
        nullable=False,
    )
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    support_count: Mapped[int] = mapped_column(Integer, nullable=False)


class OpportunityNewsRecord(Base):
    """A hit the news ladder judged relevant for a tracked opportunity.

    Accumulates across runs; a URL is stored once per opportunity.
    """

    __tablename__ = "opportunity_news"

    __table_args__ = (
        UniqueConstraint("opportunity_id", "url", name="uq_opportunity_news_url"),
        CheckConstraint(
            "level IN ('exact', 'issue', 'background')",
            name="opportunity_news_level",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(), primary_key=True, autoincrement=True
    )
    opportunity_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("opportunities.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Ladder rung that found it (news_ladder.LEVELS)
    level: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    url: Mapped[str] = mapped_column(Text, nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    snippet: Mapped[str] = mapped_column(Text, nullable=False)
    published_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    # The judge's one-sentence verdict, for review
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    found_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class NewsItemRecord(Base):
    """Persistent civic news item record."""

    __tablename__ = "news_items"

    id: Mapped[str] = mapped_column(String(length=120), primary_key=True)
    title: Mapped[str] = mapped_column(String(length=240), nullable=False)
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    source: Mapped[str] = mapped_column(String(length=120), nullable=False)
    published_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    url: Mapped[str] = mapped_column(String(length=500), nullable=False)


class ActionTrackingRecord(Base):
    """Persistent record of an installation action state."""

    __tablename__ = "action_tracking"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid4,
    )
    installation_id: Mapped[str] = mapped_column(
        String(length=120),
        index=True,
        nullable=False,
    )
    action_id: Mapped[str] = mapped_column(
        ForeignKey("civic_actions.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    status: Mapped[str] = mapped_column(String(length=40), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class BetaTokenRecord(Base):
    """MVP access-control beta token."""

    __tablename__ = "beta_tokens"

    token: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid4,
    )
    used: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    activated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class PushSubscriptionRecord(Base):
    """Anonymous push notification subscription."""

    __tablename__ = "push_subscriptions"

    push_token: Mapped[str] = mapped_column(Text, primary_key=True)
    action_ids: Mapped[list[str]] = mapped_column(
        ARRAY(Text()), nullable=False, server_default="{}"
    )
    platform: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class ActionStatsRecord(Base):
    """Anonymous completion counter per civic action."""

    __tablename__ = "action_stats"

    action_id: Mapped[str] = mapped_column(
        ForeignKey("civic_actions.id", ondelete="CASCADE"),
        primary_key=True,
    )
    completion_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class TrackingEventRecord(Base):
    """Civic outcome event for a tracked action."""

    __tablename__ = "tracking_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid4,
    )
    action_id: Mapped[str] = mapped_column(
        ForeignKey("civic_actions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    event_type: Mapped[str] = mapped_column(Text, nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    outcome: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class MdbStatementRecord(Base):
    """Cached MdB public statement search result."""

    __tablename__ = "mdb_statements"

    __table_args__ = (
        UniqueConstraint("action_id", "mdb_name", name="idx_mdb_statements_action_mdb"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid4,
    )
    action_id: Mapped[str] = mapped_column(
        ForeignKey("civic_actions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    mdb_name: Mapped[str] = mapped_column(Text, nullable=False)
    mdb_aw_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    found: Mapped[bool] = mapped_column(Boolean, nullable=False)
    source: Mapped[str | None] = mapped_column(Text, nullable=True)
    statement_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    searched_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class FeedbackRecord(Base):
    """Anonymous in-app feedback entry."""

    __tablename__ = "feedback"

    __table_args__ = (CheckConstraint("rating BETWEEN 1 AND 5", name="chk_rating"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid4,
    )
    action_id: Mapped[str | None] = mapped_column(Text, nullable=True, index=True)
    rating: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class ApiSpendRecord(Base):
    """Operational AI API cost tracking."""

    __tablename__ = "api_spend"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid4,
    )
    date: Mapped[date] = mapped_column(Date, nullable=False)
    provider: Mapped[str] = mapped_column(Text, nullable=False)
    endpoint: Mapped[str | None] = mapped_column(Text, nullable=True)
    tokens_used: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cost_eur: Mapped[Decimal] = mapped_column(Numeric(10, 6), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )
