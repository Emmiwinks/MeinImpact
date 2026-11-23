"""Anonymous usage counters in Postgres.

One row per day and event with a running count; nothing that tells callers
apart. The app sends `active_day` and `active_week` at most once per day and
week, so those count phones.
"""

from collections import defaultdict
from datetime import date
from typing import Literal

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.models import UsageCountRecord

UsageEvent = Literal[
    "active_day",
    "active_week",
    "onboarding_done",
    "card_turned",
    # Every card thrown away, also when the tester skips the reason
    "card_dismissed",
    "action_opened",
    "action_done",
    "letter_to_mail_app",
    "impact_opened",
]


class PostgresUsageRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def commit(self) -> None:
        await self._session.commit()

    async def count(self, event: UsageEvent, day: date) -> None:
        statement = insert(UsageCountRecord).values(day=day, event=event, count=1)
        await self._session.execute(
            statement.on_conflict_do_update(
                index_elements=[UsageCountRecord.day, UsageCountRecord.event],
                set_={"count": UsageCountRecord.count + 1},
            )
        )

    async def since(self, first_day: date) -> dict[date, dict[str, int]]:
        """Counts per day from [first_day] on; days without any are left out."""
        rows = await self._session.execute(
            select(
                UsageCountRecord.day, UsageCountRecord.event, UsageCountRecord.count
            ).where(UsageCountRecord.day >= first_day)
        )
        days: defaultdict[date, dict[str, int]] = defaultdict(dict)
        for day, event, count in rows.all():
            days[day][event] = count
        return dict(days)
