"""Add letter recipients for council decisions.

`opportunities.recipient_bodies` holds the OParl organizations whose members
a letter about a decision goes to. `council_members` lists the current voting
members of each body with their Fraktion, replaced on every member sync; the
app reaches them through their Fraktion's office (`council/offices.py`).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202611090018"
down_revision: str | None = "202611080017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities",
        sa.Column(
            "recipient_bodies",
            sa.ARRAY(sa.Text()),
            nullable=False,
            server_default="{}",
        ),
    )
    op.create_table(
        "council_members",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("source_id", sa.String(length=60), nullable=False),
        sa.Column("organization_url", sa.Text(), nullable=False),
        sa.Column("organization_name", sa.Text(), nullable=False),
        sa.Column("person_url", sa.Text(), nullable=False),
        sa.Column("person_name", sa.Text(), nullable=False),
        sa.Column("fraktion_url", sa.Text(), nullable=True),
        sa.Column("fraktion_name", sa.Text(), nullable=True),
        sa.Column("synced_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_council_members_organization_url",
        "council_members",
        ["organization_url"],
    )


def downgrade() -> None:
    op.drop_index("ix_council_members_organization_url", table_name="council_members")
    op.drop_table("council_members")
    op.drop_column("opportunities", "recipient_bodies")
