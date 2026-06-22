"""Add spec-required columns to civic_actions and create new tables.

Adds: external_id, pro_argumente, contra_argumente, action_types,
is_controversial, position_required, tavily_context, momentum_score,
active, updated_at to civic_actions.

Creates: beta_tokens, push_subscriptions, action_stats, tracking_events,
feedback, api_spend, mdb_statements, pipeline_runs.
"""

import uuid
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202606080005"
down_revision: str | None = "202606080004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_ACTION_TYPE_MAP = {
    "representative_letter": ["brief"],
    "public_question": ["anfrage"],
    "petition_signature": ["petition"],
}

_SEED_IDS = [
    "bundesbau-wohnungsbau-brief",
    "bundestag-solar-petition",
    "kohleausstieg-anfrage",
    "bafoeg-reform-brief",
    "krankenhausreform-brief",
    "deutsche-bahn-petition",
    "kita-ausbau-brief",
    "fahrradinfrastruktur-anfrage",
    "gebaeudeenergiegesetz-brief",
    "wahlrecht-16-petition",
]


def upgrade() -> None:
    """Adds spec-required columns and creates new tables."""

    # ── civic_actions: new columns ────────────────────────────────────────────
    op.add_column(
        "civic_actions",
        sa.Column("external_id", sa.Text(), nullable=True),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "pro_argumente",
            sa.ARRAY(sa.Text()),
            nullable=False,
            server_default="{}",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "contra_argumente",
            sa.ARRAY(sa.Text()),
            nullable=False,
            server_default="{}",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "action_types",
            sa.ARRAY(sa.Text()),
            nullable=False,
            server_default="{}",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "is_controversial",
            sa.Boolean(),
            nullable=False,
            server_default="false",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "position_required",
            sa.Boolean(),
            nullable=False,
            server_default="false",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column("tavily_context", sa.Text(), nullable=True),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "momentum_score",
            sa.Float(),
            nullable=False,
            server_default="0.3",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "active",
            sa.Boolean(),
            nullable=False,
            server_default="true",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )

    # Backfill action_types from existing action_type column
    for action_type, action_types in _ACTION_TYPE_MAP.items():
        types_literal = "{" + ",".join(action_types) + "}"
        op.execute(
            sa.text(
                "UPDATE civic_actions SET action_types = CAST(:at AS text[]) "
                "WHERE action_type = :action_type"
            ).bindparams(at=types_literal, action_type=action_type)
        )

    # ── beta_tokens ───────────────────────────────────────────────────────────
    op.create_table(
        "beta_tokens",
        sa.Column(
            "token",
            sa.dialects.postgresql.UUID(as_uuid=True),
            primary_key=True,
            default=uuid.uuid4,
        ),
        sa.Column("used", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("activated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("idx_beta_tokens_used", "beta_tokens", ["used"])

    # Seed one development beta token for testing
    op.execute(
        sa.text(
            "INSERT INTO beta_tokens (token) "
            "VALUES ('00000000-0000-0000-0000-000000000001')"
        )
    )

    # ── push_subscriptions ────────────────────────────────────────────────────
    op.create_table(
        "push_subscriptions",
        sa.Column("push_token", sa.Text(), primary_key=True),
        sa.Column(
            "action_ids",
            sa.ARRAY(sa.Text()),
            nullable=False,
            server_default="{}",
        ),
        sa.Column("platform", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index(
        "idx_push_action_ids",
        "push_subscriptions",
        ["action_ids"],
        postgresql_using="gin",
    )

    # ── action_stats ──────────────────────────────────────────────────────────
    op.create_table(
        "action_stats",
        sa.Column("action_id", sa.Text(), primary_key=True),
        sa.Column(
            "completion_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["action_id"],
            ["civic_actions.id"],
            ondelete="CASCADE",
        ),
    )
    # Seed action_stats rows for existing actions
    for action_id in _SEED_IDS:
        op.execute(
            sa.text(
                "INSERT INTO action_stats (action_id) VALUES (:id) "
                "ON CONFLICT DO NOTHING"
            ).bindparams(id=action_id)
        )

    # ── tracking_events ───────────────────────────────────────────────────────
    op.create_table(
        "tracking_events",
        sa.Column(
            "id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("action_id", sa.Text(), nullable=False),
        sa.Column("event_type", sa.Text(), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("outcome", sa.Text(), nullable=True),
        sa.Column("source_url", sa.Text(), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["action_id"],
            ["civic_actions.id"],
            ondelete="CASCADE",
        ),
    )
    op.create_index("idx_tracking_action", "tracking_events", ["action_id"])
    op.create_index(
        "idx_tracking_occurred",
        "tracking_events",
        [sa.text("occurred_at DESC")],
    )

    # ── mdb_statements ────────────────────────────────────────────────────────
    op.create_table(
        "mdb_statements",
        sa.Column(
            "id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("action_id", sa.Text(), nullable=False),
        sa.Column("mdb_name", sa.Text(), nullable=False),
        sa.Column("mdb_aw_id", sa.Integer(), nullable=True),
        sa.Column("found", sa.Boolean(), nullable=False),
        sa.Column("statement_summary", sa.Text(), nullable=True),
        sa.Column("source_url", sa.Text(), nullable=True),
        sa.Column(
            "searched_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["action_id"],
            ["civic_actions.id"],
            ondelete="CASCADE",
        ),
    )
    op.create_index("idx_mdb_statements_action", "mdb_statements", ["action_id"])
    op.create_index(
        "idx_mdb_statements_searched",
        "mdb_statements",
        [sa.text("searched_at DESC")],
    )
    op.create_unique_constraint(
        "idx_mdb_statements_action_mdb",
        "mdb_statements",
        ["action_id", "mdb_name"],
    )

    # ── feedback ──────────────────────────────────────────────────────────────
    op.create_table(
        "feedback",
        sa.Column(
            "id",
            sa.dialects.postgresql.UUID(as_uuid=True),
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
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("idx_feedback_action", "feedback", ["action_id"])
    op.create_index(
        "idx_feedback_created",
        "feedback",
        [sa.text("created_at DESC")],
    )

    # ── api_spend ─────────────────────────────────────────────────────────────
    op.create_table(
        "api_spend",
        sa.Column(
            "id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("provider", sa.Text(), nullable=False),
        sa.Column("endpoint", sa.Text(), nullable=True),
        sa.Column("tokens_used", sa.Integer(), nullable=True),
        sa.Column(
            "cost_eur",
            sa.Numeric(10, 6),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("idx_api_spend_date", "api_spend", [sa.text("date DESC")])
    op.create_index("idx_api_spend_provider", "api_spend", ["provider", "date"])

    # ── pipeline_runs ─────────────────────────────────────────────────────────
    op.create_table(
        "pipeline_runs",
        sa.Column(
            "id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("fetched_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "deduplicated_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "prefiltered_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "classified_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "inserted_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "errors",
            sa.ARRAY(sa.Text()),
            nullable=False,
            server_default="{}",
        ),
        sa.Column("duration_seconds", sa.Float(), nullable=True),
        sa.Column("ai_cost_eur", sa.Numeric(10, 6), nullable=True),
        sa.Column(
            "ran_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("idx_pipeline_ran_at", "pipeline_runs", [sa.text("ran_at DESC")])


def downgrade() -> None:
    """Removes all spec-added tables and columns."""
    op.drop_table("pipeline_runs")
    op.drop_table("api_spend")
    op.drop_table("feedback")
    op.drop_table("mdb_statements")
    op.drop_table("tracking_events")
    op.drop_table("action_stats")
    op.drop_table("push_subscriptions")
    op.drop_table("beta_tokens")

    for col in [
        "updated_at",
        "active",
        "momentum_score",
        "tavily_context",
        "position_required",
        "is_controversial",
        "action_types",
        "contra_argumente",
        "pro_argumente",
        "external_id",
    ]:
        op.drop_column("civic_actions", col)
