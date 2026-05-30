"""Initial persistent schema."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "202605300001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Applies the migration."""
    op.create_table(
        "civic_actions",
        sa.Column("id", sa.String(length=120), nullable=False),
        sa.Column("title", sa.String(length=240), nullable=False),
        sa.Column("action_type", sa.String(length=80), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("topics", postgresql.JSONB(), nullable=False),
        sa.Column("region", sa.String(length=80), nullable=True),
        sa.Column("deadline", sa.Date(), nullable=True),
        sa.Column("effort_minutes", sa.Integer(), nullable=False),
        sa.Column("impact_hint", sa.Text(), nullable=False),
        sa.Column("source_url", sa.String(length=500), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "news_items",
        sa.Column("id", sa.String(length=120), nullable=False),
        sa.Column("title", sa.String(length=240), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("source", sa.String(length=120), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("topics", postgresql.JSONB(), nullable=False),
        sa.Column("url", sa.String(length=500), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "user_profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("installation_id", sa.String(length=120), nullable=False),
        sa.Column("topics", postgresql.JSONB(), nullable=False),
        sa.Column("value_axes", postgresql.JSONB(), nullable=False),
        sa.Column("region", sa.String(length=80), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_user_profiles_installation_id",
        "user_profiles",
        ["installation_id"],
        unique=False,
    )
    op.create_table(
        "action_tracking",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("installation_id", sa.String(length=120), nullable=False),
        sa.Column("action_id", sa.String(length=120), nullable=False),
        sa.Column("status", sa.String(length=40), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["action_id"], ["civic_actions.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_action_tracking_action_id",
        "action_tracking",
        ["action_id"],
        unique=False,
    )
    op.create_index(
        "ix_action_tracking_installation_id",
        "action_tracking",
        ["installation_id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverts the migration."""
    op.drop_index("ix_action_tracking_installation_id", table_name="action_tracking")
    op.drop_index("ix_action_tracking_action_id", table_name="action_tracking")
    op.drop_table("action_tracking")
    op.drop_index("ix_user_profiles_installation_id", table_name="user_profiles")
    op.drop_table("user_profiles")
    op.drop_table("news_items")
    op.drop_table("civic_actions")
