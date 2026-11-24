"""Drop the tables of the retired action stack before the first beta.

The `/v1/actions`, push, beta-token, tracking and MdB routes were removed
on 2026-11-21 and `civic_actions` itself went in 202609270010. These tables
were left behind without readers or writers: `user_profiles`,
`action_tracking`, `beta_tokens`, `push_subscriptions`, `action_stats`,
`tracking_events`, `mdb_statements`. Two of them hold installation ids
(`user_profiles`, `action_tracking`), which the privacy policy says the
server does not keep.

`news_items` stays on purpose (shelved media pipeline).
"""

from collections.abc import Sequence

from alembic import op

revision: str = "202611240026"
down_revision: str | None = "202611230025"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

LEGACY_TABLES = (
    "action_tracking",
    "action_stats",
    "tracking_events",
    "mdb_statements",
    "push_subscriptions",
    "beta_tokens",
    "user_profiles",
)


def upgrade() -> None:
    for table in LEGACY_TABLES:
        op.execute(f"DROP TABLE IF EXISTS {table} CASCADE")


def downgrade() -> None:
    raise NotImplementedError(
        "the retired action stack's tables are not rebuilt; this drop is one-way"
    )
