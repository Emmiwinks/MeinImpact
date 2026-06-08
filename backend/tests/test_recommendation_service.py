"""Recommendation service tests."""

from datetime import UTC, date, datetime, timedelta

import pytest

from meinimpact.domain.entities import ActionType, CivicAction, UserProfile
from meinimpact.infrastructure.actions.dummy_action_repository import (
    DummyActionRepository,
)
from meinimpact.services.recommendation_service import RecommendationService


@pytest.mark.asyncio
async def test_recommendation_prioritizes_matching_topics_and_region() -> None:
    service = RecommendationService(DummyActionRepository())
    recommendations = await service.recommend(
        UserProfile(
            topics=("klimaschutz", "wohnen"),
            value_axes={},
            region="Germany",
        ),
        limit=3,
    )
    assert recommendations[0].action.id == "solar-letter-bundestag"
    assert recommendations[0].score > recommendations[-1].score
    assert any("klimaschutz" in reason for reason in recommendations[0].reasons)


@pytest.mark.asyncio
async def test_recommendation_respects_limit() -> None:
    service = RecommendationService(DummyActionRepository())
    recommendations = await service.recommend(
        UserProfile(topics=("education",), value_axes={}, region=None),
        limit=1,
    )
    assert len(recommendations) == 1


def test_urgency_score_covers_deadline_boundaries() -> None:
    service = RecommendationService(DummyActionRepository())
    today = datetime.now(UTC).date()

    assert service._urgency_score(None) == 0
    assert service._urgency_score(today - timedelta(days=1)) == 0
    assert service._urgency_score(today + timedelta(days=7)) == 20
    assert service._urgency_score(today + timedelta(days=21)) == 10
    assert service._urgency_score(today + timedelta(days=22)) == 0


@pytest.mark.asyncio
async def test_recommendation_handles_actions_without_optional_boosts() -> None:
    service = RecommendationService(_SingleActionRepository())
    recommendations = await service.recommend(
        UserProfile(topics=("health",), value_axes={}, region="Berlin"),
        limit=1,
    )

    assert recommendations[0].score == 10
    assert recommendations[0].reasons == (
        "Base score for currently available civic actions.",
    )


class _SingleActionRepository:
    async def list_open_actions(self) -> list[CivicAction]:
        return [
            CivicAction(
                id="no-boost-action",
                title="No boost action",
                action_type=ActionType.PUBLIC_QUESTION,
                summary="Action with no matching profile attributes.",
                topics=("education",),
                region="Hamburg",
                deadline=date(2100, 1, 1),
                effort_minutes=4,
                impact_hint="Track later.",
                source_url="https://example.org",
            )
        ]

    async def get_action(self, action_id: str) -> None:
        del action_id
        return None
