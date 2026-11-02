"""Add Lebenslagen to opportunities.

`lebenslagen` holds the catalog ids (`ai/lebenslagen.py`) an opportunity
concerns; the app matches them against the groups a user picked on their
device. `lebenslage_frei` is the model's own label for a clearly concerned
group the catalog lacks, for catalog maintenance (`scripts/topic_report.py`).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202611030016"
down_revision: str | None = "202611020015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities",
        sa.Column(
            "lebenslagen", sa.ARRAY(sa.Text()), nullable=False, server_default="{}"
        ),
    )
    op.add_column(
        "opportunities", sa.Column("lebenslage_frei", sa.Text(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("opportunities", "lebenslage_frei")
    op.drop_column("opportunities", "lebenslagen")
