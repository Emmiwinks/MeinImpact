#!/usr/bin/env python3
"""Manually exercise the engagement-state rule engine with example scenarios.

This has zero I/O and zero external dependencies (no DB, no API keys) — it's
just the pure `state_rules` package, so it's the fastest way to see the A/B/C/D
logic behave the way you expect before the rest of the pipeline exists.

Run from the backend directory:
  python scripts/demo_state_rules.py

Or inside Docker:
  docker compose exec api python scripts/demo_state_rules.py
"""

import sys
from dataclasses import replace
from datetime import date, datetime, timedelta
from pathlib import Path

# Force UTF-8 output regardless of the host terminal's codepage (matters on
# Windows, where the default console codepage mangles the German reason text).
sys.stdout.reconfigure(encoding="utf-8")

# Allow running from backend root without installing the package
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from meinimpact.infrastructure.pipeline.state_rules.engine import (  # noqa: E402
    evaluate_state,
)
from meinimpact.infrastructure.pipeline.state_rules.parliamentary_rules import (  # noqa: E402
    RULES as PARLIAMENTARY_RULES,
)
from meinimpact.infrastructure.pipeline.state_rules.petition_rules import (  # noqa: E402
    RULES as PETITION_RULES,
)
from meinimpact.infrastructure.pipeline.state_rules.protocol import (  # noqa: E402
    RuleContext,
)
from meinimpact.infrastructure.sources.protocol import RawSourceItem  # noqa: E402

NOW = datetime(2026, 7, 10)


def _vorgang(
    *,
    type: str = "antrag",
    status: str = "Noch nicht beraten",
    signature_count: int | None = None,
) -> RawSourceItem:
    item: RawSourceItem = {
        "external_id": "1",
        "title": "Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
        "type": type,
        "status": status,
        "deadline": None,
        "source_url": "https://dip.bundestag.de/vorgang/1",
        "description": "...",
        "initiated_by": "CDU/CSU",
        "source": "dip",
    }
    if signature_count is not None:
        item["signature_count"] = signature_count
    return item


def _petition(*, signature_count: int, deadline: date | None = None) -> RawSourceItem:
    item: RawSourceItem = {
        "external_id": "2",
        "title": "Petition für mehr Klimaschutz",
        "type": "petition",
        "status": "offen",
        "deadline": deadline,
        "source_url": "https://weact.campact.de/petitions/1",
        "description": "...",
        "initiated_by": "Zivilgesellschaft",
        "source": "weact",
        "signature_count": signature_count,
    }
    return item


BASE_CTX = RuleContext(item=_vorgang(), now=NOW)

PARLIAMENTARY_SCENARIOS: list[tuple[str, RuleContext]] = [
    (
        "Vote scheduled in 10 days",
        replace(BASE_CTX, vote_date=(NOW + timedelta(days=10)).date()),
    ),
    (
        "Vote scheduled in 45 days (too far out)",
        replace(BASE_CTX, vote_date=(NOW + timedelta(days=45)).date()),
    ),
    (
        "Committee actively deliberating",
        replace(
            BASE_CTX,
            item=_vorgang(status="Ausschussberatung"),
            committee_recently_active=True,
        ),
    ),
    (
        "In committee, but no recent activity",
        replace(
            BASE_CTX,
            item=_vorgang(status="Ausschussberatung"),
            committee_recently_active=False,
        ),
    ),
    (
        "Bundestag petition close to quorum (45,000 sigs)",
        replace(BASE_CTX, item=_vorgang(type="petition", signature_count=45_000)),
    ),
    (
        "Referred to committee (Ueberwiesen), no vote result yet",
        replace(BASE_CTX, item=_vorgang(status="Überwiesen"), has_vote_result=False),
    ),
    (
        "Referred to committee, but already has a vote result",
        replace(BASE_CTX, item=_vorgang(status="Überwiesen"), has_vote_result=True),
    ),
    (
        "Only 1 of 2+ Fraktionen has a documented Stellungnahme",
        replace(BASE_CTX, stellungnahme_fraktion_count=1),
    ),
    (
        "2 Fraktionen already have documented Stellungnahmen",
        replace(BASE_CTX, stellungnahme_fraktion_count=2),
    ),
    (
        "Still in 1. Beratung, no vote scheduled",
        replace(BASE_CTX, item=_vorgang(status="1. Beratung"), vote_date=None),
    ),
    (
        "Media coverage found, nothing else applies",
        replace(BASE_CTX, media_coverage_matched=True),
    ),
    ("Nothing applies at all", BASE_CTX),
]

PETITION_SCENARIOS: list[tuple[str, RuleContext]] = [
    (
        "Near goal, deadline in 5 days",
        RuleContext(
            item=_petition(
                signature_count=8_500, deadline=(NOW + timedelta(days=5)).date()
            ),
            now=NOW,
            signature_goal=10_000,
        ),
    ),
    (
        "Near goal, but deadline is 60 days out",
        RuleContext(
            item=_petition(
                signature_count=8_500, deadline=(NOW + timedelta(days=60)).date()
            ),
            now=NOW,
            signature_goal=10_000,
        ),
    ),
    (
        "Bundestag petition close to quorum (42,000 sigs)",
        RuleContext(item=_petition(signature_count=42_000), now=NOW),
    ),
    (
        "Momentum: +1,500 signatures since last run",
        RuleContext(
            item=_petition(signature_count=5_000),
            now=NOW,
            previous_signature_count=3_500,
        ),
    ),
    (
        "Active, 600 sigs, in the news",
        RuleContext(
            item=_petition(
                signature_count=600, deadline=(NOW + timedelta(days=20)).date()
            ),
            now=NOW,
            media_coverage_matched=True,
        ),
    ),
    (
        "Only 200 signatures, in the news (below floor)",
        RuleContext(
            item=_petition(signature_count=200), now=NOW, media_coverage_matched=True
        ),
    ),
    (
        "Nothing applies at all",
        RuleContext(item=_petition(signature_count=50), now=NOW),
    ),
]


def _run(label: str, scenarios: list[tuple[str, RuleContext]], rules: object) -> None:
    print(f"\n=== {label} ===")
    for description, ctx in scenarios:
        trace = evaluate_state(ctx, rules)  # type: ignore[arg-type]
        print(f"- {description}")
        print(f"    state={trace.engagement_state}  rule={trace.matched_rule}")
        print(f"    reason: {trace.state_reason}")


if __name__ == "__main__":
    _run("Pipeline 1: Parliamentary", PARLIAMENTARY_SCENARIOS, PARLIAMENTARY_RULES)
    _run("Pipeline 2: Petition", PETITION_SCENARIOS, PETITION_RULES)
