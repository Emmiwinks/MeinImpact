"""Diagnostic test: shows prefilter decisions for real DIP data.

Run with:
    docker compose exec api python -m pytest tests/test_prefilter_diagnostics.py -v -s

Prints a table of every fetched item and why it passed or was dropped.
Not a pass/fail assertion test — designed for human inspection.
"""

from datetime import UTC, datetime, timedelta

import pytest

from meinimpact.core.config import get_settings
from meinimpact.infrastructure.pipeline.stages import (
    _is_german,
    passes_basic_checks,
)
from meinimpact.infrastructure.sources.dip_adapter import DipAdapter

_MIN_TITLE_LEN = 10


def _diagnose_drop_reason(item: object) -> str:
    """Reconstructs a human-readable reason for a passes_basic_checks() drop.

    passes_basic_checks() only returns bool — this exists purely so the
    diagnostic table below stays readable. Keep in sync with
    `pipeline/stages.py`'s title-length constant and German-detection order.
    """
    title = item["title"]  # type: ignore[index]
    if len(title) < _MIN_TITLE_LEN:
        return f"title too short ({len(title)} chars < {_MIN_TITLE_LEN})"
    return "title not detected as German"


@pytest.mark.asyncio
@pytest.mark.live
async def test_prefilter_breakdown_live() -> None:
    """Fetches live DIP data and prints a per-item filter decision table."""
    settings = get_settings()
    if not settings.dip_api_key:
        pytest.skip("MEINIMPACT_DIP_API_KEY not set")

    adapter = DipAdapter(settings.dip_api_key)
    since = datetime.now(UTC) - timedelta(hours=25)
    items = await adapter.fetch_new_items(since)

    passed, dropped = [], []
    for item in items:
        if passes_basic_checks(item):
            passed.append((item, None))
        else:
            dropped.append((item, _diagnose_drop_reason(item)))

    print(f"\n{'=' * 80}")
    n_pass, n_drop = len(passed), len(dropped)
    print(
        f"PREFILTER BREAKDOWN  -  {len(items)} fetched, {n_pass} pass, {n_drop} dropped"
    )
    print(f"{'=' * 80}")

    if passed:
        print(f"\n✓ PASSED ({len(passed)})")
        print(f"  {'TYPE':<16} {'DEADLINE':<12} {'TITLE'}")
        print(f"  {'-' * 14}  {'-' * 10}  {'-' * 50}")
        for item, _ in passed:
            deadline = str(item.get("deadline") or "")
            print(f"  {item['type']:<16} {deadline:<12}  {item['title'][:70]}")

    if dropped:
        print(f"\n✗ DROPPED ({len(dropped)})")
        print(f"  {'TYPE':<16} {'REASON':<45} {'TITLE'}")
        print(f"  {'-' * 14}  {'-' * 43}  {'-' * 40}")
        for item, reason in dropped:
            print(f"  {item['type']:<16} {reason:<45}  {item['title'][:50]}")

    print()

    # Soft assertions — fail loudly if everything is dropped so we notice
    assert len(items) > 0, "DIP adapter returned no items at all"
    if len(passed) == 0:
        drop_reasons: dict[str, int] = {}
        for _, reason in dropped:
            drop_reasons[reason] = drop_reasons.get(reason, 0) + 1
        summary = ", ".join(f"{r!r}: {n}x" for r, n in drop_reasons.items())
        pytest.fail(f"All {len(dropped)} items were dropped. Reasons: {summary}")


@pytest.mark.asyncio
@pytest.mark.live
async def test_german_detection_on_dip_titles() -> None:
    """Checks langdetect accuracy on a sample of real DIP titles."""
    settings = get_settings()
    if not settings.dip_api_key:
        pytest.skip("MEINIMPACT_DIP_API_KEY not set")

    adapter = DipAdapter(settings.dip_api_key)
    since = datetime.now(UTC) - timedelta(hours=25)
    items = await adapter.fetch_new_items(since)

    misdetected = [item for item in items if not _is_german(item["title"])]

    if misdetected:
        print(f"\n⚠ Titles misdetected as non-German ({len(misdetected)}):")
        for item in misdetected:
            print(f"  {item['title']}")

    # Allow up to 10% misdetection — flag but don't fail the suite
    rate = len(misdetected) / max(len(items), 1)
    assert rate < 0.10, (
        f"{len(misdetected)}/{len(items)} titles ({rate:.0%}) misdetected as non-German"
    )
