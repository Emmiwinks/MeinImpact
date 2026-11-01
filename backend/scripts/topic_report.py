#!/usr/bin/env python3
"""Taxonomy review: free topic labels next to the fixed tags they got.

Enrichment must pick from the fixed tag list, so a missing topic is
force-fit rather than visible. Its own free label (`free_topic`) is not:
this report lists the labels of all served opportunities with the tags
they were filed under. Recurring labels that fit their tags poorly are
candidates for a new tag. Run on each new survey wave or data review:
  docker compose exec api python scripts/topic_report.py
"""

import asyncio
from collections import Counter, defaultdict

from sqlalchemy import select

from meinimpact.core.config import get_settings
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.models import OpportunityRecord


async def main() -> None:
    database = Database(get_settings().database_url)
    try:
        async with database.session_factory() as session:
            rows = (
                await session.execute(
                    select(
                        OpportunityRecord.free_topic, OpportunityRecord.affected_tags
                    ).where(
                        OpportunityRecord.active.is_(True),
                        OpportunityRecord.is_relevant.is_(True),
                    )
                )
            ).all()
    finally:
        await database.close()

    counts: Counter[str] = Counter()
    tags_by_topic: dict[str, Counter[str]] = defaultdict(Counter)
    for free_topic, tags in rows:
        topic = free_topic or "(ohne Label)"
        counts[topic] += 1
        tags_by_topic[topic].update(tags or ["(kein Tag)"])

    print(f"{len(rows)} opportunities, {len(counts)} distinct free topics\n")
    for topic, count in counts.most_common():
        tags = ", ".join(tag for tag, _ in tags_by_topic[topic].most_common())
        print(f"{count:3}  {topic:40}  -> {tags}")


if __name__ == "__main__":
    asyncio.run(main())
