"""Repository interfaces for domain services."""

from collections.abc import Sequence
from typing import Protocol

from meinimpact.domain.entities import CivicAction, NewsItem


class CivicActionRepository(Protocol):
    """Persistence boundary for civic actions."""

    async def list_open_actions(self) -> Sequence[CivicAction]:
        """Lists actions that may currently be recommended."""

    async def get_action(self, action_id: str) -> CivicAction | None:
        """Returns an action by ID when it exists."""


class NewsRepository(Protocol):
    """Persistence boundary for civic news context."""

    async def list_recent_news(self, limit: int) -> Sequence[NewsItem]:
        """Lists recent news items."""
