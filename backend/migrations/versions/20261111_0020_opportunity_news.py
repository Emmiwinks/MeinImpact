"""Store the news Mein Impact found about tracked opportunities.

`opportunity_news` keeps every hit the news ladder judged relevant, with the
rung that found it. Hits accumulate across runs: a later run only adds URLs
not stored yet. `opportunities.news_checked_at` is when the ladder last ran
for an opportunity, so the schedule can search the stalest first and the app
can say when it last looked, also when nothing was found.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "202611110020"
down_revision: str | None = "202611110019"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "opportunities",
        sa.Column("news_checked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_table(
        "opportunity_news",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column(
            "opportunity_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("opportunities.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("level", sa.Text(), nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("url", sa.Text(), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("snippet", sa.Text(), nullable=False),
        sa.Column("published_on", sa.Date(), nullable=True),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("found_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("opportunity_id", "url", name="uq_opportunity_news_url"),
        sa.CheckConstraint(
            "level IN ('exact', 'issue', 'background')",
            name="opportunity_news_level",
        ),
    )


def downgrade() -> None:
    op.drop_table("opportunity_news")
    op.drop_column("opportunities", "news_checked_at")
