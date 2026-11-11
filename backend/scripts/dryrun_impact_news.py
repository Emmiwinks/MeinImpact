#!/usr/bin/env python3
"""Dry run: the Mein Impact news ladder over a sample of actions.

Sample: every relevant opportunity in the DB that is closed or no longer
listed (we know these are over), a few open ones, and the relevant council
decisions from the latest `dryrun_decisions` output (the local DB has no
decisions). Runs every rung for every action (`exhaustive`), so each
rung's hit rate can be reviewed. Writes JSON and a Markdown report for
hand review. Nothing is written to the DB.

Costs per action: 1 Tavily credit per rung (max 3) and 1 + up to 3
Mistral calls.

  docker compose exec api python scripts/dryrun_impact_news.py [--open N]
"""

import argparse
import asyncio
import json
import random
import sys
from dataclasses import asdict
from datetime import UTC, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from sqlalchemy import select

from meinimpact.core.config import get_settings
from meinimpact.infrastructure.ai.mistral_json import MistralJsonCompleter
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.impact.news_ladder import (
    LEVELS,
    ImpactSubject,
    LadderResult,
    NewsLadder,
    TavilySearch,
    search_since,
)
from meinimpact.infrastructure.models import OpportunityRecord

_OUTPUT_DIR = Path(__file__).parent / "dryrun_output"
_CONCURRENCY = 3
_SUMMARY_CHARS = 800
# Council decisions from the dry-run file: their start is unknown
_UNKNOWN_START_DAYS = 180


async def _db_sample(open_count: int) -> list[tuple[str, ImpactSubject]]:
    today = datetime.now(UTC).date()
    database = Database(get_settings().database_url)
    async for session in database.session():
        result = await session.execute(
            select(OpportunityRecord).where(OpportunityRecord.is_relevant.is_(True))
        )
        records = list(result.scalars().all())
    over = [
        r
        for r in records
        if not r.active or (r.closes_on is not None and r.closes_on < today)
    ]
    still_open = [r for r in records if r not in over]
    random.Random(11).shuffle(still_open)
    picked = [("over", r) for r in over] + [
        ("open", r) for r in still_open[:open_count]
    ]
    return [
        (
            state,
            ImpactSubject(
                kind=r.kind,
                title=r.registry_title,
                summary=(r.registry_summary or r.summary or "")[:_SUMMARY_CHARS],
                organizer=r.organizer,
                locality=r.locality,
                source_url=r.source_url,
                since=search_since(r.opens_on, r.first_seen_at.date()),
            ),
        )
        for state, r in picked
    ]


def _decision_sample() -> list[tuple[str, ImpactSubject]]:
    files = sorted(_OUTPUT_DIR.glob("decisions_*.json"))
    if not files:
        return []
    rows = json.loads(files[-1].read_text(encoding="utf-8"))
    sample = []
    for row in rows:
        if not row["enrichment"].get("is_relevant"):
            continue
        listing = row["listing"]
        observed = datetime.fromisoformat(listing["observed_at"]).date()
        sample.append(
            (
                "decision",
                ImpactSubject(
                    kind=listing["kind"],
                    title=listing["title"],
                    summary=row["enrichment"].get("summary") or "",
                    organizer=listing["organizer"],
                    locality=listing["locality"],
                    source_url=listing["url"],
                    since=observed - timedelta(days=_UNKNOWN_START_DAYS),
                ),
            )
        )
    return sample


def _report(rows: list[dict[str, object]], started: datetime) -> str:
    lines = [f"# Mein Impact news ladder, dry run {started:%Y-%m-%d %H:%M}", ""]
    totals = {level: [0, 0, 0] for level in LEVELS}  # actions, hits, relevant
    found = {level: 0 for level in LEVELS}
    for row in rows:
        for rung in row["result"]["rungs"]:  # type: ignore[index]
            t = totals[rung["level"]]
            t[0] += 1
            t[1] += len(rung["hits"])
            relevant = sum(1 for h in rung["hits"] if h["relevant"])
            t[2] += relevant
            if relevant:
                found[rung["level"]] += 1
    lines += [
        f"{len(rows)} actions.",
        "",
        "| Rung | searched | hits | judged relevant | actions with ≥1 relevant |",
        "|---|---|---|---|---|",
    ]
    for level in LEVELS:
        searched, hits, relevant = totals[level]
        lines.append(f"| {level} | {searched} | {hits} | {relevant} | {found[level]} |")
    lines.append("")

    for row in rows:
        subject = row["subject"]
        lines += [
            f"## {subject['title']}",  # type: ignore[index]
            "",
            f"{row['state']} · {subject['kind']} · {subject['organizer'] or ''} · "  # type: ignore[index]
            f"since {subject['since']} · [Quelle]({subject['source_url']})",  # type: ignore[index]
            "",
        ]
        if "error" in row:
            lines += [f"**Error:** {row['error']}", ""]
            continue
        for rung in row["result"]["rungs"]:  # type: ignore[index]
            lines += [f"**{rung['level']}**: `{rung['query']}`", ""]
            if not rung["hits"]:
                lines += ["(no hits)", ""]
                continue
            for h in rung["hits"]:
                mark = "✅" if h["relevant"] else "❌"
                hit = h["hit"]
                lines.append(
                    f"- {mark} {h['kind']} · [{hit['title'] or hit['url']}]({hit['url']})"
                    f" · {hit['published_date'] or '?'} · {h['reason']}"
                )
            lines.append("")
    return "\n".join(lines)


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--open", type=int, default=6, help="open actions to add")
    args = parser.parse_args()

    settings = get_settings()
    started = datetime.now(UTC)
    sample = await _db_sample(args.open) + _decision_sample()
    print(f"{len(sample)} actions", flush=True)

    completer = MistralJsonCompleter(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=settings.mistral_extraction_model,
    )
    search = TavilySearch(settings.tavily_api_key or "")
    ladder = NewsLadder(completer, search)
    gate = asyncio.Semaphore(_CONCURRENCY)
    rows: list[dict[str, object]] = []

    async def one(state: str, subject: ImpactSubject) -> None:
        async with gate:
            row: dict[str, object] = {"state": state, "subject": asdict(subject)}
            try:
                result: LadderResult = await ladder.run(subject, exhaustive=True)
                row["result"] = asdict(result)
            except Exception as error:
                row["error"] = repr(error)
            rows.append(row)
            print(f"  {len(rows)}/{len(sample)} {subject.title[:60]}", flush=True)

    try:
        await asyncio.gather(*(one(state, s) for state, s in sample))
    finally:
        await completer.aclose()
        await search.aclose()

    order = {"over": 0, "decision": 1, "open": 2}
    rows.sort(key=lambda r: (order[str(r["state"])], str(r["subject"]["title"])))  # type: ignore[index]
    _OUTPUT_DIR.mkdir(exist_ok=True)
    stem = _OUTPUT_DIR / f"impact_news_{started:%Y%m%d_%H%M%S}"
    stem.with_suffix(".json").write_text(
        json.dumps(rows, default=str, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    stem.with_suffix(".md").write_text(_report(rows, started), encoding="utf-8")
    print(f"wrote {stem}.json and .md")


if __name__ == "__main__":
    asyncio.run(main())
