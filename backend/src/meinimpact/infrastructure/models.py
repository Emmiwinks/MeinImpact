"""SQLAlchemy table models for persistent repositories."""

import uuid
from datetime import UTC, date, datetime
from uuid import uuid4

from sqlalchemy import Date, DateTime, ForeignKey, Integer, String, Text
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
    topics: Mapped[list[str]] = mapped_column(JSONB, nullable=False)
    value_axes: Mapped[dict[str, int]] = mapped_column(JSONB, nullable=False)
    region: Mapped[str | None] = mapped_column(String(length=80), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )


class CivicActionRecord(Base):
    """Persistent civic action record."""

    __tablename__ = "civic_actions"

    id: Mapped[str] = mapped_column(String(length=120), primary_key=True)
    title: Mapped[str] = mapped_column(String(length=240), nullable=False)
    action_type: Mapped[str] = mapped_column(String(length=80), nullable=False)
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    topics: Mapped[list[str]] = mapped_column(JSONB, nullable=False)
    region: Mapped[str | None] = mapped_column(String(length=80), nullable=True)
    deadline: Mapped[date | None] = mapped_column(Date, nullable=True)
    effort_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    impact_hint: Mapped[str] = mapped_column(Text, nullable=False)
    source_url: Mapped[str] = mapped_column(String(length=500), nullable=False)
    urgency: Mapped[str] = mapped_column(
        String(length=10), nullable=False, default="low"
    )


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
    topics: Mapped[list[str]] = mapped_column(JSONB, nullable=False)
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
