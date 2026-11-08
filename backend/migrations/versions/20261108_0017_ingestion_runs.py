"""Add the ingestion schedule and run history.

`ingestion_schedule` is a single row the admin page edits (on/off and the
interval). `ingestion_runs` records every run, scheduled or manual; a row in
status `running` doubles as the cross-machine lock, so two Fly machines never
ingest at the same time.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "202611080017"
down_revision: str | None = "202611030016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ingestion_schedule",
        sa.Column("id", sa.SmallInteger(), primary_key=True),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("interval_hours", sa.Integer(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("id = 1", name="ingestion_schedule_single_row"),
        sa.CheckConstraint("interval_hours > 0", name="ingestion_schedule_interval"),
    )
    op.execute(
        "INSERT INTO ingestion_schedule (id, enabled, interval_hours, updated_at) "
        "VALUES (1, true, 48, now())"
    )
    op.create_table(
        "ingestion_runs",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("trigger", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("summary", postgresql.JSONB(), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.CheckConstraint(
            "trigger IN ('scheduled', 'manual')", name="ingestion_runs_trigger"
        ),
        sa.CheckConstraint(
            "status IN ('running', 'succeeded', 'failed')",
            name="ingestion_runs_status",
        ),
    )
    op.create_index("ix_ingestion_runs_started_at", "ingestion_runs", ["started_at"])


def downgrade() -> None:
    op.drop_index("ix_ingestion_runs_started_at", table_name="ingestion_runs")
    op.drop_table("ingestion_runs")
    op.drop_table("ingestion_schedule")
