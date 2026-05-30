"""SQLAlchemy table models for future persistent repositories."""

import uuid
from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import DateTime, Integer, String, Text
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
    topics: Mapped[dict[str, object]] = mapped_column(JSONB, nullable=False)
    value_axes: Mapped[dict[str, object]] = mapped_column(JSONB, nullable=False)
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
    topics: Mapped[dict[str, object]] = mapped_column(JSONB, nullable=False)
    region: Mapped[str | None] = mapped_column(String(length=80), nullable=True)
    effort_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    source_url: Mapped[str] = mapped_column(String(length=500), nullable=False)
