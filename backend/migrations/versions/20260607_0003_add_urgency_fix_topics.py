"""Add urgency column and align topic keys to spec taxonomy."""

import json
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "202606070003"
down_revision: str | None = "202606070002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_UPDATES = [
    ("bundesbau-wohnungsbau-brief", ["wohnen", "demokratie", "wirtschaft"], "high"),
    ("bundestag-solar-petition", ["klimaschutz", "wirtschaft"], "mid"),
    ("kohleausstieg-anfrage", ["klimaschutz"], "low"),
    ("bafoeg-reform-brief", ["bildung", "demokratie"], "mid"),
    ("krankenhausreform-brief", ["gesundheit", "wirtschaft"], "mid"),
    ("deutsche-bahn-petition", ["verkehr", "klimaschutz"], "low"),
    ("kita-ausbau-brief", ["bildung", "soziales"], "high"),
    ("fahrradinfrastruktur-anfrage", ["verkehr", "klimaschutz"], "low"),
    ("gebaeudeenergiegesetz-brief", ["klimaschutz", "wohnen"], "low"),
    ("wahlrecht-16-petition", ["demokratie", "bildung"], "low"),
]


def upgrade() -> None:
    """Adds urgency column and rewrites topic keys to German spec taxonomy."""
    op.add_column(
        "civic_actions",
        sa.Column(
            "urgency",
            sa.String(length=10),
            nullable=False,
            server_default="low",
        ),
    )
    stmt = sa.text(
        "UPDATE civic_actions SET topics = CAST(:topics AS jsonb), urgency = :urgency "
        "WHERE id = :id"
    )
    for action_id, topics, urgency in _UPDATES:
        op.execute(
            stmt.bindparams(
                topics=json.dumps(topics),
                urgency=urgency,
                id=action_id,
            )
        )


def downgrade() -> None:
    """Removes urgency column (topic keys are not restored)."""
    op.drop_column("civic_actions", "urgency")
