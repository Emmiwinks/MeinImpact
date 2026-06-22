"""Add unique constraint on civic_actions.source_url.

Required for the pipeline's ON CONFLICT (source_url) DO UPDATE upsert.
"""

from collections.abc import Sequence

from alembic import op

revision: str = "202606120006"
down_revision: str | None = "202606080005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Remove duplicate rows keeping the most recently updated one per source_url
    op.execute("""
        DELETE FROM civic_actions
        WHERE id IN (
            SELECT id FROM (
                SELECT id,
                       ROW_NUMBER() OVER (
                           PARTITION BY source_url
                           ORDER BY updated_at DESC NULLS LAST, id DESC
                       ) AS rn
                FROM civic_actions
            ) ranked
            WHERE rn > 1
        )
    """)
    op.create_unique_constraint(
        "uq_civic_actions_source_url",
        "civic_actions",
        ["source_url"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_civic_actions_source_url",
        "civic_actions",
        type_="unique",
    )
