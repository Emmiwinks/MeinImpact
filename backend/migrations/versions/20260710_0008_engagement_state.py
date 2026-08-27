"""Replace momentum_score with the engagement-state model.

Per specs/data/ingestion-pipeline.md: the weighted hotness score is
replaced by an `engagement_state` (A/B/C) assigned by the two-pipeline
state-rule engine. `pipeline_runs` columns are replaced with per-pipeline/
per-state counts. `mdb_statements` gains a `source` field recording which
of the 3 MdB-position sources found a match (tracking use only — state B
no longer depends on any MdB check, see ingestion-pipeline.md).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202607100008"
down_revision: str | None = "202606240007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # civic_actions: engagement-state columns replace momentum_score
    op.add_column(
        "civic_actions",
        sa.Column(
            "engagement_state", sa.String(length=1), nullable=False, server_default="C"
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column("state_reason", sa.Text(), nullable=True),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "pipeline_source",
            sa.String(length=20),
            nullable=False,
            server_default="parliamentary",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column("previous_signature_count", sa.Integer(), nullable=True),
    )
    op.create_index(
        "idx_actions_engagement_state",
        "civic_actions",
        ["engagement_state"],
        postgresql_where=sa.text("active = true"),
    )
    op.drop_column("civic_actions", "momentum_score")

    # mdb_statements: source field for tracking (which of the 3 position
    # sources found the match) — not used for state B determination.
    op.add_column(
        "mdb_statements",
        sa.Column("source", sa.Text(), nullable=True),
    )

    # pipeline_runs: per-pipeline/per-state counts replace the old
    # fetched/deduplicated/prefiltered/classified counts.
    op.add_column(
        "pipeline_runs",
        sa.Column(
            "parliamentary_actions_found",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "pipeline_runs",
        sa.Column(
            "petition_actions_found", sa.Integer(), nullable=False, server_default="0"
        ),
    )
    op.add_column(
        "pipeline_runs",
        sa.Column("state_a_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "pipeline_runs",
        sa.Column("state_b_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "pipeline_runs",
        sa.Column("state_c_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "pipeline_runs",
        sa.Column(
            "state_d_discarded", sa.Integer(), nullable=False, server_default="0"
        ),
    )
    op.drop_column("pipeline_runs", "fetched_count")
    op.drop_column("pipeline_runs", "deduplicated_count")
    op.drop_column("pipeline_runs", "prefiltered_count")
    op.drop_column("pipeline_runs", "classified_count")


def downgrade() -> None:
    op.add_column(
        "pipeline_runs",
        sa.Column("classified_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "pipeline_runs",
        sa.Column(
            "prefiltered_count", sa.Integer(), nullable=False, server_default="0"
        ),
    )
    op.add_column(
        "pipeline_runs",
        sa.Column(
            "deduplicated_count", sa.Integer(), nullable=False, server_default="0"
        ),
    )
    op.add_column(
        "pipeline_runs",
        sa.Column("fetched_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.drop_column("pipeline_runs", "state_d_discarded")
    op.drop_column("pipeline_runs", "state_c_count")
    op.drop_column("pipeline_runs", "state_b_count")
    op.drop_column("pipeline_runs", "state_a_count")
    op.drop_column("pipeline_runs", "petition_actions_found")
    op.drop_column("pipeline_runs", "parliamentary_actions_found")

    op.drop_column("mdb_statements", "source")

    op.add_column(
        "civic_actions",
        sa.Column("momentum_score", sa.Float(), nullable=False, server_default="0.3"),
    )
    op.drop_index(
        "idx_actions_engagement_state", table_name="civic_actions", if_exists=True
    )
    op.drop_column("civic_actions", "previous_signature_count")
    op.drop_column("civic_actions", "pipeline_source")
    op.drop_column("civic_actions", "state_reason")
    op.drop_column("civic_actions", "engagement_state")
