"""Dummy news repository for the initial product scaffold."""

from collections.abc import Sequence
from datetime import UTC, datetime

from meinimpact.domain.entities import NewsItem

_DUMMY_NEWS: tuple[NewsItem, ...] = (
    NewsItem(
        id="committee-solar-access",
        title="Committee hearing scheduled for community solar access",
        summary=(
            "A public committee calendar lists a hearing on community energy "
            "access and tenant participation."
        ),
        source="Bundestag calendar dummy source",
        published_at=datetime(2026, 5, 29, 8, 0, tzinfo=UTC),
        topics=("climate", "housing", "energy"),
        url="https://www.bundestag.de/",
    ),
    NewsItem(
        id="school-renovation-quorum",
        title="Education funding petition approaches quorum",
        summary=(
            "A public petition about school renovation funding is close to a "
            "formal response threshold."
        ),
        source="Petition platform dummy source",
        published_at=datetime(2026, 5, 28, 12, 0, tzinfo=UTC),
        topics=("education", "public spending"),
        url="https://epetitionen.bundestag.de/",
    ),
)


class DummyNewsRepository:
    """In-memory news repository for the first iteration."""

    async def list_recent_news(self, limit: int) -> Sequence[NewsItem]:
        """Lists recent dummy news items."""
        return _DUMMY_NEWS[:limit]
