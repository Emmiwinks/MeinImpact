#!/usr/bin/env python3
"""Taxonomy review: free topic labels and candidate topics next to the tags.

Enrichment must pick from the fixed tag list, so a missing topic is
force-fit rather than visible. Two signals show it:
- `free_topic`, the model's own label per opportunity (almost always unique,
  so read it as a list to cluster by eye);
- `topic_candidate`, a topic from `CANDIDATE_TOPICS` (too thin for a tag
  yet). A candidate whose count keeps growing across runs becomes a tag.
Opportunities filed under three or more tags are listed separately: that is
the usual sign of a force-fit. Run on each new survey wave or data review:
  docker compose exec api python scripts/topic_report.py
"""

import asyncio
from collections import Counter

from sqlalchemy import select

from meinimpact.core.config import get_settings
from meinimpact.infrastructure.ai.taxonomy import CANDIDATE_TOPICS
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.models import OpportunityRecord

_FORCE_FIT_TAGS = 3


async def main() -> None:
    database = Database(get_settings().database_url)
    try:
        async with database.session_factory() as session:
            rows = (
                await session.execute(
                    select(
                        OpportunityRecord.free_topic,
                        OpportunityRecord.topic_candidate,
                        OpportunityRecord.affected_tags,
                    ).where(
                        OpportunityRecord.active.is_(True),
                        OpportunityRecord.is_relevant.is_(True),
                    )
                )
            ).all()
    finally:
        await database.close()

    print(f"{len(rows)} opportunities\n")

    candidates = Counter(candidate for _, candidate, _ in rows if candidate)
    print("Candidate topics:")
    for topic in CANDIDATE_TOPICS:
        print(f"{candidates[topic]:3}  {topic}")

    print(f"\nFiled under {_FORCE_FIT_TAGS}+ tags or none (possible force-fits):")
    for free_topic, _, tags in sorted(rows, key=lambda row: len(row[2] or [])):
        if len(tags or []) >= _FORCE_FIT_TAGS or not tags:
            print(
                f"     {free_topic or '(ohne Label)':40}  -> {', '.join(tags or ['(kein Tag)'])}"
            )

    tag_counts = Counter(tag for _, _, tags in rows for tag in tags or [])
    print("\nOpportunities per tag:")
    for tag, count in tag_counts.most_common():
        print(f"{count:3}  {tag}")

    print("\nFree topics with their tags:")
    for free_topic, _, tags in sorted(rows, key=lambda row: row[0] or ""):
        print(
            f"     {free_topic or '(ohne Label)':40}  -> {', '.join(tags or ['(kein Tag)'])}"
        )


if __name__ == "__main__":
    asyncio.run(main())
