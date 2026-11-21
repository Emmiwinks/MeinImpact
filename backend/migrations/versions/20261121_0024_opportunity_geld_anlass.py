"""Add enrichment's money areas and reason to opportunities.

`geld` lists the budget areas that get more or less money if what
supporters want happens (`taxonomy.GELD_BEREICHE`), `anlass` why the matter
is on the table now. Both stay empty for opportunities enriched before,
until their next enrichment. `werte_relevanz` keeps its column; enrichment
13 fills it with questionnaire keys instead of axes.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "202611210024"
down_revision: str | None = "202611210023"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities",
        sa.Column(
            "geld",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )
    op.add_column("opportunities", sa.Column("anlass", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("opportunities", "anlass")
    op.drop_column("opportunities", "geld")
