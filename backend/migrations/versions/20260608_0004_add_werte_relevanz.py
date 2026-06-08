"""Add werte_relevanz column to civic_actions and seed values."""

import json
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "202606080004"
down_revision: str | None = "202606070003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Per-action werte_relevanz: axis → float in [-1, +1]
# Axes: wirtschaft (left=-redistribution, right=+free-market)
#       diplomatie (left=-national, right=+international)
#       freiheit   (left=-civil-liberties, right=+state-security)
#       wandel     (left=-tradition, right=+reform)
_WERTE = [
    ("bundesbau-wohnungsbau-brief", {"wirtschaft": -0.7, "wandel": 0.3}),
    (
        "bundestag-solar-petition",
        {"wirtschaft": -0.3, "wandel": 0.7, "diplomatie": 0.4},
    ),
    ("kohleausstieg-anfrage", {"wandel": 0.9, "diplomatie": 0.5, "wirtschaft": -0.3}),
    ("bafoeg-reform-brief", {"wirtschaft": -0.6, "wandel": 0.4}),
    ("krankenhausreform-brief", {"wirtschaft": -0.5}),
    ("deutsche-bahn-petition", {"wirtschaft": -0.4, "wandel": 0.3}),
    ("kita-ausbau-brief", {"wirtschaft": -0.7, "wandel": 0.3}),
    (
        "fahrradinfrastruktur-anfrage",
        {"wandel": 0.5, "diplomatie": 0.3, "wirtschaft": -0.3},
    ),
    (
        "gebaeudeenergiegesetz-brief",
        {"wandel": 0.6, "freiheit": 0.4, "wirtschaft": -0.4},
    ),
    ("wahlrecht-16-petition", {"wandel": 0.8}),
]


def upgrade() -> None:
    """Adds werte_relevanz column and populates seed values."""
    op.add_column(
        "civic_actions",
        sa.Column(
            "werte_relevanz",
            JSONB(),
            nullable=False,
            server_default="{}",
        ),
    )
    stmt = sa.text(
        "UPDATE civic_actions SET werte_relevanz = CAST(:wr AS jsonb) WHERE id = :id"
    )
    for action_id, wr in _WERTE:
        op.execute(stmt.bindparams(wr=json.dumps(wr), id=action_id))


def downgrade() -> None:
    """Removes werte_relevanz column."""
    op.drop_column("civic_actions", "werte_relevanz")
