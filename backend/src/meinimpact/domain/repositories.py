"""Repository interfaces for domain services."""

from collections.abc import Sequence
from typing import Protocol

from meinimpact.domain.entities import (
    CivicAction,
    MdbStatement,
    NewsItem,
    TrackingEvent,
)


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


class ActionStatsRepository(Protocol):
    """Persistence boundary for anonymous action completion counters."""

    async def increment_completion(self, action_id: str) -> int:
        """Increments the completion count and returns the new total."""


class TrackingRepository(Protocol):
    """Persistence boundary for civic tracking events and MdB statements."""

    async def list_events(self, action_id: str) -> Sequence[TrackingEvent]:
        """Returns all tracking events for an action, newest first."""

    async def list_mdb_statements(self, action_id: str) -> Sequence[MdbStatement]:
        """Returns cached MdB statement results for an action."""


class FeedbackRepository(Protocol):
    """Persistence boundary for anonymous user feedback."""

    async def submit(
        self,
        action_id: str | None,
        rating: int | None,
        comment: str | None,
    ) -> None:
        """Stores a feedback entry."""


class PushSubscriptionRepository(Protocol):
    """Persistence boundary for anonymous push notification subscriptions."""

    async def register(self, push_token: str, platform: str) -> None:
        """Registers or refreshes a push token."""

    async def subscribe(self, push_token: str, action_id: str) -> None:
        """Adds an action to a push token's subscription list."""

    async def unsubscribe(self, push_token: str, action_id: str) -> None:
        """Removes an action from a push token's subscription list."""


class BetaTokenRepository(Protocol):
    """Persistence boundary for MVP beta access tokens."""

    async def activate(self, token: str) -> bool:
        """Returns True if the token exists (used or not). Marks it used."""
