"""Transparent civic action recommendation scoring."""

from datetime import UTC, date, datetime

from meinimpact.domain import repositories
from meinimpact.domain.entities import CivicAction, Recommendation, UserProfile


class RecommendationService:
    """Scores civic actions against a user profile."""

    def __init__(self, action_repository: repositories.CivicActionRepository) -> None:
        """Initializes the service with an action repository."""
        self._action_repository = action_repository

    async def recommend(
        self,
        profile: UserProfile,
        limit: int,
    ) -> list[Recommendation]:
        """Returns the highest scoring recommendations."""
        actions = await self._action_repository.list_open_actions()
        recommendations = [self._score_action(action, profile) for action in actions]
        recommendations.sort(key=lambda item: item.score, reverse=True)
        return recommendations[:limit]

    def _score_action(
        self,
        action: CivicAction,
        profile: UserProfile,
    ) -> Recommendation:
        """Scores one action and records human-readable reasons."""
        score = 10
        reasons = ["Base score for currently available civic actions."]
        topic_overlap = profile.normalized_topics.intersection(
            topic.lower() for topic in action.topics
        )
        if topic_overlap:
            score += 40 + (5 * len(topic_overlap))
            reasons.append(
                "Matches selected topics: " + ", ".join(sorted(topic_overlap)) + "."
            )
        if profile.region and action.region == profile.region:
            score += 20
            reasons.append(f"Matches the user's region: {profile.region}.")
        urgency_score = self._urgency_score(action.deadline)
        if urgency_score:
            score += urgency_score
            reasons.append("Deadline is soon enough to make action timely.")
        if action.effort_minutes <= 3:
            score += 10
            reasons.append("Can be completed in about three minutes.")
        return Recommendation(action=action, score=score, reasons=tuple(reasons))

    def _urgency_score(self, deadline: date | None) -> int:
        """Returns a score component based on deadline urgency."""
        if deadline is None:
            return 0
        today = datetime.now(UTC).date()
        days_left = (deadline - today).days
        if days_left < 0:
            return 0
        if days_left <= 7:
            return 20
        if days_left <= 21:
            return 10
        return 0
