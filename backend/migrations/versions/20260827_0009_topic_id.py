"""Add topic_id to civic_actions.

Not a taxonomy — the `topics` JSONB category-tagging column was already
removed in 20260624_0007_drop_topics.py ("feed is now purely
value-alignment driven") and this doesn't reintroduce it. `topic_id` is an
internal grouping key: actions that are different engagement *options*
(petition, letter) for the same real-world topic share one `topic_id`,
assigned by fingerprint matching in `pipeline/merge.py` (same DIP
descriptor OR >85% fuzzy title match — unchanged rule, previously used to
pick a single winning action and discard the rest; now used to group
instead of discard). See specs/data/ingestion-pipeline.md.

Every existing row backfills to its own id (singleton topic) — safe, no
data loss, nothing currently relies on cross-row grouping.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202608270009"
down_revision: str | None = "202607100008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "civic_actions",
        sa.Column("topic_id", sa.String(length=120), nullable=True),
    )
    op.execute("UPDATE civic_actions SET topic_id = id WHERE topic_id IS NULL")
    op.alter_column("civic_actions", "topic_id", nullable=False)
    op.create_index(
        "idx_actions_topic_id",
        "civic_actions",
        ["topic_id"],
        postgresql_where=sa.text("active = true"),
    )


def downgrade() -> None:
    op.drop_index("idx_actions_topic_id", table_name="civic_actions", if_exists=True)
    op.drop_column("civic_actions", "topic_id")
