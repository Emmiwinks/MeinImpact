"""Add enrichment's reach and places to opportunities.

`reach` says where the consequences are felt (nachbarschaft, ort, stadt,
umland), `places` the municipalities, Kreise or city parts the text names;
`geo/locality.py` locates them. Both stay empty for opportunities enriched
before, until their next enrichment.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202611210023"
down_revision: str | None = "202611210022"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities", sa.Column("reach", sa.String(length=20), nullable=True)
    )
    op.add_column(
        "opportunities",
        sa.Column("places", sa.ARRAY(sa.Text()), nullable=False, server_default="{}"),
    )


def downgrade() -> None:
    op.drop_column("opportunities", "places")
    op.drop_column("opportunities", "reach")
