"""${message}."""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
${imports if imports else ""}

revision: str = ${repr(up_revision)}
down_revision: str | None = ${repr(down_revision)}
branch_labels: str | Sequence[str] | None = ${repr(branch_labels)}
depends_on: str | Sequence[str] | None = ${repr(depends_on)}


def upgrade() -> None:
    """Applies the migration."""
    ${upgrades if upgrades else "pass"}


def downgrade() -> None:
    """Reverts the migration."""
    ${downgrades if downgrades else "pass"}
