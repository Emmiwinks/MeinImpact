"""PostgreSQL-backed civic action repository."""

from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.domain.entities import ActionType, CivicAction
from meinimpact.infrastructure.models import CivicActionRecord


class PostgresActionRepository:
    """Reads civic actions from PostgreSQL."""

    def __init__(self, session: AsyncSession) -> None:
        """Initializes the repository with a database session."""
        self._session = session

    async def list_open_actions(self) -> Sequence[CivicAction]:
        """Returns all active actions currently in the pool."""
        result = await self._session.execute(
            select(CivicActionRecord).where(CivicActionRecord.active == True)  # noqa: E712
        )
        return [_to_domain(r) for r in result.scalars().all()]

    async def get_action(self, action_id: str) -> CivicAction | None:
        """Returns an action by ID, or None when not found."""
        result = await self._session.execute(
            select(CivicActionRecord).where(CivicActionRecord.id == action_id)
        )
        record = result.scalar_one_or_none()
        return _to_domain(record) if record else None


def _to_domain(record: CivicActionRecord) -> CivicAction:
    return CivicAction(
        id=record.id,
        title=record.title,
        action_type=ActionType(record.action_type),
        summary=record.summary,
        region=record.region,
        deadline=record.deadline,
        effort_minutes=record.effort_minutes,
        impact_hint=record.impact_hint,
        source_url=record.source_url,
        urgency=record.urgency,
        werte_relevanz=dict(record.werte_relevanz),
        pro_argumente=tuple(record.pro_argumente or []),
        contra_argumente=tuple(record.contra_argumente or []),
        action_types=tuple(record.action_types or []),
        is_controversial=record.is_controversial,
        position_required=record.position_required,
        active=record.active,
        tavily_context=record.tavily_context,
        engagement_state=record.engagement_state,
        state_reason=record.state_reason,
        pipeline_source=record.pipeline_source,
        previous_signature_count=record.previous_signature_count,
    )
