"""Add last_seen_run_id to opportunities.

Supports the "one run, one feed" design agreed in conversation (see
project memory `project_dip_to_tavily_pivot.md`): the pool endpoint serves
only the opportunities touched by the most recent ingestion run, not an
ever-accumulating pool. Rejected an earlier `last_seen_at`-based staleness/
decay design — rediscovery-by-search-ranking isn't a real hotness signal,
so "was this touched by the latest run" (an exact identity, not a fuzzy
time window) is what actually matters. `updated_at` (already bumped on
every insert/refresh) doubles as the ordering tiebreak to find "the latest
run's id" — no separate timestamp column needed.

Every existing row backfills to its own random run id (harmless — this
project has no real ingestion history yet, just calibration test rows).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202609270011"
down_revision: str | None = "202609270010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities",
        sa.Column(
            "last_seen_run_id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )
    op.execute(
        "UPDATE opportunities SET last_seen_run_id = gen_random_uuid() "
        "WHERE last_seen_run_id IS NULL"
    )
    op.alter_column("opportunities", "last_seen_run_id", nullable=False)
    op.create_index(
        "idx_opportunities_last_seen_run_id",
        "opportunities",
        ["last_seen_run_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "idx_opportunities_last_seen_run_id",
        table_name="opportunities",
        if_exists=True,
    )
    op.drop_column("opportunities", "last_seen_run_id")
