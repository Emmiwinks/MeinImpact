"""How well each place is covered, from what the feed would serve now.

Shown per place on /admin; for a draft place it is the report to read
before flipping it to live. Thresholds are provisional (set 2026-11-24
before any second city existed) and live in `CoverageConfig`.
"""

from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import StrEnum
from statistics import mean

from meinimpact import places as covered
from meinimpact.domain.entities import Opportunity


@dataclass(frozen=True, slots=True)
class CoverageConfig:
    min_new_per_week: int = 15
    min_kinds: int = 3
    min_tags: int = 4
    max_source_share: float = 0.5
    # Direction note: an axis whose cards lean this far to one pole, over at
    # least `lean_min_cards` cards, is pointed out (a warning, never a block)
    lean_threshold: float = 0.5
    lean_min_cards: int = 6


class Light(StrEnum):
    GREEN = "green"
    YELLOW = "yellow"
    RED = "red"


@dataclass(frozen=True, slots=True)
class PlaceCoverage:
    place: covered.Place
    cards: int
    new_this_week: int
    kinds: int
    tags: int
    top_source: str | None
    top_source_share: float
    # Unmet thresholds, as readable lines
    gaps: tuple[str, ...]
    # Axes whose cards mostly agree with one pole: (axis, mean, cards)
    leans: tuple[tuple[str, float, int], ...] = field(default=())

    @property
    def light(self) -> Light:
        if not self.cards or len(self.gaps) >= 2:
            return Light.RED
        return Light.YELLOW if self.gaps else Light.GREEN


def coverage(
    opportunities: Sequence[Opportunity],
    *,
    now: datetime,
    config: CoverageConfig = CoverageConfig(),
) -> list[PlaceCoverage]:
    """One entry per covered Land, Kreis and Kommune, most specific first.
    Bund and EU are left out: each has one registry kind by nature, and
    whether a place is ready to go live is a local question."""
    week_ago = now - timedelta(days=7)
    result = []
    local = [p for p in covered.ALL if p.depth > covered.Level.BUND.depth]
    for place in sorted(local, key=lambda p: (-p.depth, p.key)):
        mine = [o for o in opportunities if o.region == place.key]
        sources = Counter(o.source_org for o in mine)
        top, top_count = sources.most_common(1)[0] if sources else (None, 0)
        share = top_count / len(mine) if mine else 0.0
        new = sum(o.first_seen_at >= week_ago for o in mine)
        kinds = len({o.kind for o in mine})
        tags = len({tag for o in mine for tag in o.affected_tags})
        gaps = []
        if new < config.min_new_per_week:
            gaps.append(
                f"{new} neue Karten in 7 Tagen (Ziel {config.min_new_per_week})"
            )
        if kinds < config.min_kinds:
            gaps.append(f"{kinds} Arten (Ziel {config.min_kinds})")
        if tags < config.min_tags:
            gaps.append(f"{tags} Themen (Ziel {config.min_tags})")
        if share > config.max_source_share:
            gaps.append(
                f"{share:.0%} aus {top} (höchstens {config.max_source_share:.0%})"
            )
        result.append(
            PlaceCoverage(
                place=place,
                cards=len(mine),
                new_this_week=new,
                kinds=kinds,
                tags=tags,
                top_source=top,
                top_source_share=share,
                gaps=tuple(gaps),
                leans=_leans(mine, config),
            )
        )
    return result


def _leans(
    opportunities: Sequence[Opportunity], config: CoverageConfig
) -> tuple[tuple[str, float, int], ...]:
    by_axis: dict[str, list[float]] = {}
    for opportunity in opportunities:
        for axis, value in opportunity.werte_relevanz.items():
            by_axis.setdefault(axis, []).append(value)
    return tuple(
        (axis, round(mean(values), 2), len(values))
        for axis, values in sorted(by_axis.items())
        if len(values) >= config.lean_min_cards
        and abs(mean(values)) >= config.lean_threshold
    )
