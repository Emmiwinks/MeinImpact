"""Dummy civic actions for the initial product scaffold."""

from collections.abc import Sequence
from datetime import date

from meinimpact.domain.entities import ActionType, CivicAction

_DUMMY_ACTIONS: tuple[CivicAction, ...] = (
    CivicAction(
        id="solar-letter-bundestag",
        title="Ask your representative about community solar access",
        action_type=ActionType.REPRESENTATIVE_LETTER,
        summary=(
            "A Bundestag committee vote will discuss community solar access "
            "rules next week."
        ),
        region="Germany",
        deadline=date(2026, 6, 14),
        effort_minutes=3,
        impact_hint="The vote position can be checked after the committee week.",
        source_url="https://www.bundestag.de/",
        urgency="high",
    ),
    CivicAction(
        id="school-funding-petition",
        title="Support a petition for transparent school renovation funding",
        action_type=ActionType.PETITION_SIGNATURE,
        summary=(
            "A public petition is close to its quorum and asks for clearer "
            "renovation funding timelines."
        ),
        region="Germany",
        deadline=date(2026, 6, 28),
        effort_minutes=2,
        impact_hint="The quorum status can be checked after the deadline.",
        source_url="https://epetitionen.bundestag.de/",
        urgency="mid",
    ),
    CivicAction(
        id="local-bike-plan-comment",
        title="Comment on a local safe cycling planning document",
        action_type=ActionType.PLANNING_COMMENT,
        summary=(
            "A city planning consultation accepts resident comments on safer "
            "school cycling routes."
        ),
        region="Dresden",
        deadline=date(2026, 7, 21),
        effort_minutes=3,
        impact_hint="Submitted comments become part of the formal review file.",
        source_url="https://www.dresden.de/",
        urgency="low",
    ),
)


class DummyActionRepository:
    """In-memory civic action repository for the first iteration."""

    async def list_open_actions(self) -> Sequence[CivicAction]:
        """Lists currently available dummy actions."""
        return _DUMMY_ACTIONS

    async def get_action(self, action_id: str) -> CivicAction | None:
        """Returns a dummy action by ID when available."""
        for action in _DUMMY_ACTIONS:
            if action.id == action_id:
                return action
        return None
