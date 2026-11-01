"""German number/date helpers used by the listing parsers."""

from datetime import date

import pytest

from meinimpact.infrastructure.listings.parsing import (
    clean_text,
    parse_german_dates,
    parse_german_int,
    parse_german_long_date,
)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("548.769", 548_769), ("(+40.942)", 40_942), ("6 Teilnehmer", 6), ("", None)],
)
def test_parse_german_int(raw: str, expected: int | None) -> None:
    assert parse_german_int(raw) == expected


def test_parse_german_dates_skips_impossible_dates() -> None:
    assert parse_german_dates("30.10.2026 bis 31.02.2027 bis 06.12.2026") == [
        date(2026, 10, 30),
        date(2026, 12, 6),
    ]
    assert parse_german_dates(None) == []


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("Montag, 30. November 2026", date(2026, 11, 30)),
        ("Sonntag, 1. März 2027", date(2027, 3, 1)),
        ("30. Brumaire 2026", None),
        ("31. Februar 2027", None),
        ("bald", None),
        (None, None),
    ],
)
def test_parse_german_long_date(raw: str | None, expected: date | None) -> None:
    assert parse_german_long_date(raw) == expected


def test_clean_text_collapses_whitespace_and_nbsp() -> None:
    assert clean_text("  Für\xa0den\n\t Erhalt  ") == "Für den Erhalt"
