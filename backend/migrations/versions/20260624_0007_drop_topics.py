"""Drop topics column from civic_actions, news_items, and user_profiles.

Topic taxonomy removed — feed is now purely value-alignment driven.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "202606240007"
down_revision: str | None = "202606120006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_index("idx_actions_topics", table_name="civic_actions", if_exists=True)
    op.drop_column("civic_actions", "topics")

    with op.batch_alter_table("news_items") as batch_op:
        batch_op.drop_column("topics")

    with op.batch_alter_table("user_profiles") as batch_op:
        batch_op.drop_column("topics")


def downgrade() -> None:
    op.add_column(
        "user_profiles",
        sa.Column(
            "topics",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default="[]",
        ),
    )
    op.add_column(
        "news_items",
        sa.Column(
            "topics",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default="[]",
        ),
    )
    op.add_column(
        "civic_actions",
        sa.Column(
            "topics",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default="[]",
        ),
    )
