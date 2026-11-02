#!/usr/bin/env python3
"""Taxonomy review: free topic labels, candidate topics and Lebenslagen.

Enrichment must pick from fixed lists (topic tags, Lebenslagen catalog), so a
missing entry is force-fit rather than visible. Signals shown here:
- `free_topic`, the model's own label per opportunity (almost always unique,
  so read it as a list to cluster by eye);
- `topic_candidate`, a topic from `CANDIDATE_TOPICS` (too thin for a tag
  yet). A candidate whose count keeps growing across runs becomes a tag;
- opportunities filed under three or more tags, the usual sign of a
  force-fit;
- Lebenslagen usage per catalog id (0 = never tagged, a candidate for
  removal or a prompt problem) and `lebenslage_frei`, the model's own label
  for a clearly concerned group the catalog lacks.
Run on each new survey wave or data review:
  docker compose exec api python scripts/topic_report.py
"""

import asyncio
from collections import Counter

from sqlalchemy import select

from meinimpact.core.config import get_settings
from meinimpact.infrastructure.ai.lebenslagen import LEBENSLAGEN
from meinimpact.infrastructure.ai.taxonomy import CANDIDATE_TOPICS
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.models import OpportunityRecord

_FORCE_FIT_TAGS = 3


def _tags(affected_tags: list[str] | None) -> str:
    return ", ".join(affected_tags or ["(kein Tag)"])


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
                        OpportunityRecord.lebenslagen,
                        OpportunityRecord.lebenslage_frei,
                    ).where(
                        OpportunityRecord.active.is_(True),
                        OpportunityRecord.is_relevant.is_(True),
                    )
                )
            ).all()
    finally:
        await database.close()

    print(f"{len(rows)} opportunities\n")

    candidates = Counter(row.topic_candidate for row in rows if row.topic_candidate)
    print("Candidate topics:")
    for topic in CANDIDATE_TOPICS:
        print(f"{candidates[topic]:3}  {topic}")

    print(f"\nFiled under {_FORCE_FIT_TAGS}+ tags or none (possible force-fits):")
    for row in sorted(rows, key=lambda row: len(row.affected_tags or [])):
        tags = row.affected_tags or []
        if len(tags) >= _FORCE_FIT_TAGS or not tags:
            print(f"     {row.free_topic or '(ohne Label)':40}  -> {_tags(tags)}")

    tag_counts = Counter(tag for row in rows for tag in row.affected_tags or [])
    print("\nOpportunities per tag:")
    for tag, count in tag_counts.most_common():
        print(f"{count:3}  {tag}")

    lebenslagen = Counter(i for row in rows for i in row.lebenslagen or [])
    print("\nOpportunities per Lebenslage (0 = never tagged):")
    for item in sorted(LEBENSLAGEN, key=lambda item: -lebenslagen[item.id]):
        print(f"{lebenslagen[item.id]:3}  {item.id}")
    untagged = sum(1 for row in rows if not row.lebenslagen)
    print(f"\n{untagged} opportunities without any Lebenslage")

    missing = Counter(row.lebenslage_frei for row in rows if row.lebenslage_frei)
    print("\nGroups the catalog lacks (model's own labels):")
    for label, count in missing.most_common():
        print(f"{count:3}  {label}")

    print("\nFree topics with their tags:")
    for row in sorted(rows, key=lambda row: row.free_topic or ""):
        print(
            f"     {row.free_topic or '(ohne Label)':40}  -> {_tags(row.affected_tags)}"
        )


if __name__ == "__main__":
    asyncio.run(main())
