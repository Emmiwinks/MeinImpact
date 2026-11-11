"""Mark opportunities that someone has done.

`opportunities.tracked_since` is the day the app first reported an
opportunity as done. It is a single anonymous mark per opportunity (no
count, no device, no person) and decides which opportunities Mein Impact
follows for outcomes and news.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202611110019"
down_revision: str | None = "202611090018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities",
        sa.Column("tracked_since", sa.Date(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("opportunities", "tracked_since")
