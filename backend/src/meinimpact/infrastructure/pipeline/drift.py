"""Sources that behave unlike their own recent runs.

A registry that changes its markup rarely fails loudly: it returns nothing,
or a fraction of what it used to. Each source is compared with its own
history, not with a fixed number, so a small town's council and a big
petition platform are judged by the same rule.

Works on stored run summaries (plain dicts, as `asdict` wrote them), so it
needs nothing but the run history.
"""

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from statistics import mean
from typing import Any


@dataclass(frozen=True, slots=True)
class DriftConfig:
    """Provisional thresholds; tune after a few weeks of runs."""

    # Recent successful runs a source needs before it is judged at all
    min_history: int = 2
    # How many of the latest runs make up "recent"
    window: int = 5
    # A source whose kept listings fall by more than this share is flagged
    max_kept_drop: float = 0.7
    # ... but only if it used to keep at least this many (noise below)
    min_kept_baseline: float = 5.0


def find_drift(
    current: Sequence[Mapping[str, Any]],
    history: Sequence[Sequence[Mapping[str, Any]]],
    config: DriftConfig = DriftConfig(),
) -> list[str]:
    """`current` is this run's source rows, `history` the source rows of
    earlier runs, newest first. Failed sources are reported by the run
    itself; here only sources that answered but look wrong."""
    findings: list[str] = []
    for row in current:
        if row.get("error"):
            continue
        source = str(row["source"])
        past = [
            match
            for rows in history[: config.window]
            if (match := _row(rows, source)) is not None and not match.get("error")
        ]
        if len(past) < config.min_history:
            continue
        fetched_before = mean(int(r.get("fetched", 0)) for r in past)
        kept_before = mean(int(r.get("kept", 0)) for r in past)
        fetched, kept = int(row.get("fetched", 0)), int(row.get("kept", 0))
        if fetched == 0 and fetched_before > 0:
            findings.append(
                f"{source}: 0 gelesen (sonst {fetched_before:.0f}), "
                "Seite oder Parser geändert?"
            )
        elif kept_before >= config.min_kept_baseline and kept < kept_before * (
            1 - config.max_kept_drop
        ):
            findings.append(
                f"{source}: {kept} behalten (sonst {kept_before:.0f}), "
                "deutlich weniger als üblich"
            )
    return findings


def _row(rows: Sequence[Mapping[str, Any]], source: str) -> Mapping[str, Any] | None:
    return next((r for r in rows if r.get("source") == source), None)
