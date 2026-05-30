"""Domain entity tests."""

from datetime import UTC

from meinimpact.domain.entities import utc_now


def test_utc_now_returns_timezone_aware_value() -> None:
    assert utc_now().tzinfo == UTC
