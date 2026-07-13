"""PostgreSQL-backed tracking events and MdB statements repository."""

from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.domain.entities import MdbStatement, TrackingEvent
from meinimpact.infrastructure.models import MdbStatementRecord, TrackingEventRecord


class PostgresTrackingRepository:
    """Reads civic tracking events and MdB statements from PostgreSQL."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def list_events(self, action_id: str) -> Sequence[TrackingEvent]:
        """Returns all tracking events for an action, newest first."""
        result = await self._session.execute(
            select(TrackingEventRecord)
            .where(TrackingEventRecord.action_id == action_id)
            .order_by(TrackingEventRecord.occurred_at.desc())
        )
        return [_event_to_domain(r) for r in result.scalars().all()]

    async def list_mdb_statements(self, action_id: str) -> Sequence[MdbStatement]:
        """Returns cached MdB statement results for an action."""
        result = await self._session.execute(
            select(MdbStatementRecord)
            .where(MdbStatementRecord.action_id == action_id)
            .order_by(MdbStatementRecord.searched_at.desc())
        )
        return [_statement_to_domain(r) for r in result.scalars().all()]


def _event_to_domain(record: TrackingEventRecord) -> TrackingEvent:
    return TrackingEvent(
        id=record.id,
        action_id=record.action_id,
        event_type=record.event_type,
        title=record.title,
        description=record.description,
        outcome=record.outcome,
        source_url=record.source_url,
        occurred_at=record.occurred_at,
    )


def _statement_to_domain(record: MdbStatementRecord) -> MdbStatement:
    return MdbStatement(
        mdb_name=record.mdb_name,
        found=record.found,
        statement_summary=record.statement_summary,
        source_url=record.source_url,
        searched_at=record.searched_at,
        source=record.source,
    )
