"""Add everyday-relevance and accessibility scores to opportunities.

Enrichment now rates every relevant listing 1-5 on how directly it touches
an average person's everyday life and how quickly a layperson grasps it.
The feed withholds only expert-only items (both scores very low, e.g. EU
acts on trailer CO2 accounting, see `postgres_opportunity_repository`);
the app ranks everything else by the scores.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202611020013"
down_revision: str | None = "202611010012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_COLUMNS = ("everyday_relevance", "accessibility")


def upgrade() -> None:
    for column in _COLUMNS:
        op.add_column(
            "opportunities", sa.Column(column, sa.SmallInteger(), nullable=True)
        )
        op.create_check_constraint(
            f"chk_{column}_range", "opportunities", f"{column} BETWEEN 1 AND 5"
        )


def downgrade() -> None:
    for column in _COLUMNS:
        op.drop_constraint(f"chk_{column}_range", "opportunities", type_="check")
        op.drop_column("opportunities", column)
