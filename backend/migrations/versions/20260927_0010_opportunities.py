"""Replace civic_actions/pipeline_runs with opportunities.

Full rebuild, not a migration of the old data — per the DIP-to-Tavily
pivot (see project memory `project_dip_to_tavily_pivot.md` and
`project_tavily_retrieval_calibration.md`), the DIP-sourced ingestion
pipeline and its `engagement_state`/`topic_id`/`pipeline_source` schema
are retired. `civic_actions` and `pipeline_runs` are dropped outright, not
altered column-by-column — there is no new pipeline writing to them yet
and no reason to preserve their shape.

Scope note: only `civic_actions` and `pipeline_runs` are touched. Tables
that merely reference `civic_actions.id` by foreign key (`action_tracking`,
`action_stats`, `tracking_events`, `mdb_statements`) are NOT dropped —
their own data and features (beta access, feedback, push, tracking) are
unrelated to this pipeline change. Dropping `civic_actions` removes their
FK constraint (via CASCADE) but leaves those tables and rows intact; any
existing rows become orphaned references, which is an acceptable,
temporary side effect of resetting the action pool, not something this
migration needs to clean up.

`opportunities` is the new one-table, one-retrieval-mechanism model (see
the rebuild plan in conversation, and `dryrun_retrieval.py` /
`dryrun_extraction.py` for the calibration work that shaped its fields).
`embedding` uses pgvector (cosine distance, HNSW index) for
decision_object de-duplication only — not clustering/adjudication.

`postgres_action_repository.py` and the `/v1/actions/*` read endpoints
still reference the now-dropped `civic_actions` table via
`CivicActionRecord` — they will error until that read side is rewired
onto `opportunities`, a later, deliberate step (see
`infrastructure/models.py`'s `CivicActionRecord` docstring).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector

revision: str = "202609270010"
down_revision: str | None = "202608270009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    # CASCADE drops the FK constraints on action_tracking/action_stats/
    # tracking_events/mdb_statements (see module docstring) — it does NOT
    # drop those tables or their rows.
    op.execute("DROP TABLE IF EXISTS civic_actions CASCADE")
    op.execute("DROP TABLE IF EXISTS pipeline_runs CASCADE")

    op.create_table(
        "opportunities",
        sa.Column(
            "id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("source_org", sa.Text(), nullable=False),
        sa.Column("decision_object", sa.Text(), nullable=False),
        sa.Column("plain_language_title", sa.Text(), nullable=False),
        sa.Column("plain_language_summary", sa.Text(), nullable=False),
        sa.Column(
            "affected_tags",
            sa.ARRAY(sa.Text()),
            nullable=False,
            server_default="{}",
        ),
        sa.Column("region", sa.String(length=40), nullable=False),
        sa.Column(
            "werte_relevanz",
            sa.dialects.postgresql.JSONB(),
            nullable=False,
            server_default="{}",
        ),
        sa.Column("deadline", sa.Date(), nullable=True),
        sa.Column("support_count", sa.Integer(), nullable=True),
        sa.Column("support_count_as_of", sa.DateTime(timezone=True), nullable=True),
        sa.Column("content_published_at", sa.Date(), nullable=True),
        sa.Column(
            "retrieved_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("source_url", sa.Text(), nullable=False, unique=True),
        sa.Column(
            "action_types",
            sa.ARRAY(sa.Text()),
            nullable=False,
            server_default="{}",
        ),
        sa.Column(
            "pro_argumente", sa.ARRAY(sa.Text()), nullable=False, server_default="{}"
        ),
        sa.Column(
            "contra_argumente", sa.ARRAY(sa.Text()), nullable=False, server_default="{}"
        ),
        sa.Column(
            "personal_impact_snippets",
            sa.dialects.postgresql.JSONB(),
            nullable=False,
            server_default="{}",
        ),
        sa.Column("embedding", Vector(1024), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint(
            "(support_count IS NULL) = (support_count_as_of IS NULL)",
            name="chk_support_count_as_of_pairing",
        ),
    )

    op.create_index(
        "idx_opportunities_active",
        "opportunities",
        ["active"],
    )
    op.create_index(
        "idx_opportunities_region",
        "opportunities",
        ["region"],
        postgresql_where=sa.text("active = true"),
    )
    op.create_index(
        "idx_opportunities_retrieved_at",
        "opportunities",
        [sa.text("retrieved_at DESC")],
        postgresql_where=sa.text("active = true"),
    )
    # HNSW + cosine distance, per the plan — used only for de-duplication
    # against decision_object, not clustering.
    op.execute(
        "CREATE INDEX idx_opportunities_embedding ON opportunities "
        "USING hnsw (embedding vector_cosine_ops)"
    )


def downgrade() -> None:
    # No reason to reconstruct the retired civic_actions/pipeline_runs
    # shape (see module docstring) — this migration is a one-way rebuild.
    raise NotImplementedError(
        "opportunities migration is a deliberate one-way rebuild, not reversible"
    )
