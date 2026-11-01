"""Add city districts and a free topic label to opportunities.

`districts` holds the city districts an opportunity concerns (Dresden
today; names from `infrastructure/geo/data`), empty meaning the whole city
or region. `free_topic` is the model's own topic label next to the fixed
tags, used to spot taxonomy gaps (`scripts/topic_report.py`).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202611020014"
down_revision: str | None = "202611020013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities",
        sa.Column(
            "districts", sa.ARRAY(sa.Text()), nullable=False, server_default="{}"
        ),
    )
    op.add_column("opportunities", sa.Column("free_topic", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("opportunities", "free_topic")
    op.drop_column("opportunities", "districts")
