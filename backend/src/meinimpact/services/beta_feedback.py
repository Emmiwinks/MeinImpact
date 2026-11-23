"""Beta feedback: the tester pseudonym and the retention cleanup.

A tester is named by a keyed hash of their installation id. The key comes
from the server's JWT secret, so the same phone always gets the same name,
but the name cannot be turned back into the id, and nobody without the
secret can compute it from an id. A reinstall makes a new tester.
"""

import asyncio
import hashlib
import hmac
import logging
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from meinimpact.core.config import Settings
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.feedback.postgres_feedback_repository import (
    PostgresFeedbackRepository,
)

logger = logging.getLogger(__name__)

_BERLIN = ZoneInfo("Europe/Berlin")


def pseudonym(installation_id: str, secret: str) -> str:
    key = f"beta-feedback\0{secret}".encode()
    digest = hmac.new(key, installation_id.encode(), hashlib.sha256).hexdigest()
    return digest[:12]


def today() -> date:
    """The Berlin day, the only time feedback keeps."""
    return datetime.now(_BERLIN).date()


async def prune_feedback(database: Database, settings: Settings) -> int:
    """Deletes feedback older than the retention; returns how many rows."""
    first_kept = today() - timedelta(days=settings.feedback_retention_days)
    async with database.session_factory() as session:
        repository = PostgresFeedbackRepository(session)
        removed = await repository.prune(first_kept)
        await repository.commit()
    return removed


async def run_feedback_cleanup(
    database: Database, settings: Settings, check_every: timedelta
) -> None:
    """Prunes old feedback forever; cancel to stop."""
    while True:
        try:
            removed = await prune_feedback(database, settings)
            if removed:
                logger.info("Deleted %s old feedback rows", removed)
        except Exception:  # a DB hiccup must not end the loop
            logger.exception("Feedback cleanup failed")
        await asyncio.sleep(check_every.total_seconds())
