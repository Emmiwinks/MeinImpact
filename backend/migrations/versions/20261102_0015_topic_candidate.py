"""Add the taxonomy candidate topic to opportunities.

`topic_candidate` is a topic from `CANDIDATE_TOPICS` (too thin for a tag
yet) that the model named for the opportunity; `scripts/topic_report.py`
counts them to decide when one becomes a tag.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202611020015"
down_revision: str | None = "202611020014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities", sa.Column("topic_candidate", sa.Text(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("opportunities", "topic_candidate")
