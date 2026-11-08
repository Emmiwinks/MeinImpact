"""Council members in Postgres, replaced wholesale on every sync."""

from collections.abc import Collection, Sequence
from datetime import datetime

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.council.oparl_members import CouncilMember
from meinimpact.infrastructure.models import CouncilMemberRecord


class PostgresCouncilRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def replace(
        self, source_id: str, members: Sequence[CouncilMember], *, synced_at: datetime
    ) -> None:
        await self._session.execute(
            delete(CouncilMemberRecord).where(
                CouncilMemberRecord.source_id == source_id
            )
        )
        self._session.add_all(
            CouncilMemberRecord(
                source_id=source_id,
                organization_url=m.organization_url,
                organization_name=m.organization_name,
                person_url=m.person_url,
                person_name=m.person_name,
                fraktion_url=m.fraktion_url,
                fraktion_name=m.fraktion_name,
                synced_at=synced_at,
            )
            for m in members
        )
        await self._session.commit()

    async def last_synced(self, source_id: str) -> datetime | None:
        result = await self._session.execute(
            select(func.max(CouncilMemberRecord.synced_at)).where(
                CouncilMemberRecord.source_id == source_id
            )
        )
        return result.scalar_one_or_none()

    async def members_of(
        self, organization_urls: Collection[str]
    ) -> list[CouncilMember]:
        if not organization_urls:
            return []
        result = await self._session.execute(
            select(CouncilMemberRecord).where(
                CouncilMemberRecord.organization_url.in_(organization_urls)
            )
        )
        return [
            CouncilMember(
                organization_url=r.organization_url,
                organization_name=r.organization_name,
                person_url=r.person_url,
                person_name=r.person_name,
                fraktion_url=r.fraktion_url,
                fraktion_name=r.fraktion_name,
            )
            for r in result.scalars().all()
        ]
