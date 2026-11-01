"""Rebuild opportunities around registry listings.

Opportunities now come from the registries that publish them (openPetition,
Beteiligungsportal Sachsen, EU Have your say, WeAct; see
`infrastructure/listings`) instead of Tavily search. Identity is the
registry entry (`source_id`, `external_id`), so the embedding-based dedup
column and its HNSW index go away. Enrichment is stored next to the
registry facts and keyed by `enrichment_input_hash`.

`opportunity_support_snapshots` records support counts per run, the basis
for momentum on registries that don't expose it.

Like 0010, this is a deliberate one-way rebuild: the Tavily-era rows were
calibration data only.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "202611010012"
down_revision: str | None = "202609270011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("DROP TABLE IF EXISTS opportunities CASCADE")

    op.create_table(
        "opportunities",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("source_id", sa.String(length=60), nullable=False),
        sa.Column("external_id", sa.Text(), nullable=False),
        sa.Column("source_url", sa.Text(), nullable=False),
        sa.Column("kind", sa.String(length=40), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("registry_region", sa.String(length=20), nullable=True),
        sa.Column("locality", sa.Text(), nullable=True),
        sa.Column("organizer", sa.Text(), nullable=True),
        sa.Column("registry_title", sa.Text(), nullable=False),
        sa.Column("registry_summary", sa.Text(), nullable=True),
        sa.Column(
            "source_labels", sa.ARRAY(sa.Text()), nullable=False, server_default="{}"
        ),
        sa.Column("opens_on", sa.Date(), nullable=True),
        sa.Column("closes_on", sa.Date(), nullable=True),
        sa.Column("support_count", sa.Integer(), nullable=True),
        sa.Column("support_goal", sa.Integer(), nullable=True),
        sa.Column("support_count_as_of", sa.DateTime(timezone=True), nullable=True),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("enrichment_input_hash", sa.String(length=64), nullable=True),
        sa.Column("enriched_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_relevant", sa.Boolean(), nullable=True),
        sa.Column("relevance_reason", sa.Text(), nullable=True),
        sa.Column("region", sa.String(length=20), nullable=True),
        sa.Column("title", sa.Text(), nullable=True),
        sa.Column("summary", sa.Text(), nullable=True),
        sa.Column(
            "affected_tags", sa.ARRAY(sa.Text()), nullable=False, server_default="{}"
        ),
        sa.Column(
            "werte_relevanz",
            postgresql.JSONB(),
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
            postgresql.JSONB(),
            nullable=False,
            server_default="{}",
        ),
        sa.UniqueConstraint(
            "source_id", "external_id", name="uq_opportunities_registry_entry"
        ),
        sa.CheckConstraint(
            "(support_count IS NULL) = (support_count_as_of IS NULL)",
            name="chk_support_count_as_of_pairing",
        ),
    )
    # The feed query: active, relevant, not yet closed.
    op.create_index(
        "idx_opportunities_feed",
        "opportunities",
        ["closes_on"],
        postgresql_where=sa.text("active AND is_relevant"),
    )

    op.create_table(
        "opportunity_support_snapshots",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "opportunity_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("opportunities.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("support_count", sa.Integer(), nullable=False),
        sa.UniqueConstraint(
            "opportunity_id", "observed_at", name="uq_support_snapshot_observation"
        ),
    )


def downgrade() -> None:
    raise NotImplementedError(
        "registry opportunities migration is a deliberate one-way rebuild"
    )
