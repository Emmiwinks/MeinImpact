"""Bundle opportunities on one matter into one card with options.

All members of a bundle share `bundle_id` and the bundle's header, title
and summary; each keeps its own label and the sentence saying how it
differs from the others. `bundle_input_hash` spares the model a second
description of an unchanged bundle (`ai/bundler.py`).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "202611210022"
down_revision: str | None = "202611150021"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_TEXT_COLUMNS = (
    "bundle_header",
    "bundle_title",
    "bundle_summary",
    "bundle_label",
    "bundle_difference",
    "bundle_input_hash",
)


def upgrade() -> None:
    op.add_column(
        "opportunities", sa.Column("bundle_id", UUID(as_uuid=True), nullable=True)
    )
    for name in _TEXT_COLUMNS:
        op.add_column("opportunities", sa.Column(name, sa.Text(), nullable=True))


def downgrade() -> None:
    for name in reversed(_TEXT_COLUMNS):
        op.drop_column("opportunities", name)
    op.drop_column("opportunities", "bundle_id")
