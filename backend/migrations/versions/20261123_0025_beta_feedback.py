"""Beta feedback: why a card was thrown away, and free-text messages.

`card_feedback` keeps the reason a tester gave for throwing a card away,
together with the score parts the app's ranker gave that card, so the
ranking can be recalibrated. `beta_feedback` keeps free-text messages from
the profile. Both identify a tester only by a keyed hash of the
installation id and keep the day, not the time. Rows are deleted after
`feedback_retention_days`.

Replaces the legacy `feedback` table (action ratings), unused since its
route was removed.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "202611230025"
down_revision: str | None = "202611210024"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_table("feedback")

    op.create_table(
        "card_feedback",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("created_on", sa.Date(), nullable=False),
        sa.Column("tester", sa.String(length=16), nullable=False),
        sa.Column(
            "opportunity_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("opportunities.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("enrichment_input_hash", sa.String(length=64), nullable=True),
        sa.Column("reason", sa.String(length=40), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column(
            "ranking",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("app_version", sa.String(length=40), nullable=False),
    )
    op.create_index("ix_card_feedback_created_on", "card_feedback", ["created_on"])
    op.create_index(
        "ix_card_feedback_opportunity_id", "card_feedback", ["opportunity_id"]
    )

    op.create_table(
        "beta_feedback",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("created_on", sa.Date(), nullable=False),
        sa.Column("tester", sa.String(length=16), nullable=False),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("screen", sa.String(length=60), nullable=True),
        sa.Column("app_version", sa.String(length=40), nullable=False),
        sa.Column("platform", sa.String(length=20), nullable=False),
        sa.Column("handled", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index("ix_beta_feedback_created_on", "beta_feedback", ["created_on"])


def downgrade() -> None:
    op.drop_table("beta_feedback")
    op.drop_table("card_feedback")
    op.create_table(
        "feedback",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("action_id", sa.Text(), nullable=True),
        sa.Column(
            "rating",
            sa.SmallInteger(),
            sa.CheckConstraint("rating BETWEEN 1 AND 5"),
            nullable=True,
        ),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_index("idx_feedback_action", "feedback", ["action_id"])
    op.create_index("idx_feedback_created", "feedback", [sa.text("created_at DESC")])
