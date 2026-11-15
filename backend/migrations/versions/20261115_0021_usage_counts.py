"""Count what the app is used for, one number per day and event.

`usage_counts` is all the server keeps about use: no device, no session, no
opportunity, only "on this day, this happened N times". The app sends the
"active" events at most once per day and week itself, so their counts are
phones, not opens. Shown on /admin.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202611150021"
down_revision: str | None = "202611110020"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "usage_counts",
        sa.Column("day", sa.Date(), primary_key=True),
        sa.Column("event", sa.Text(), primary_key=True),
        sa.Column("count", sa.Integer(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("usage_counts")
