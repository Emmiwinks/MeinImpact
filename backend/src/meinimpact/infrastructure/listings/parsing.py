"""Small, pure helpers for reading German registry markup."""

import re
from datetime import date

from bs4 import BeautifulSoup, Tag

_GERMAN_MONTHS = {
    "januar": 1,
    "februar": 2,
    "märz": 3,
    "april": 4,
    "mai": 5,
    "juni": 6,
    "juli": 7,
    "august": 8,
    "september": 9,
    "oktober": 10,
    "november": 11,
    "dezember": 12,
}
_NUMERIC_DATE = re.compile(r"(\d{1,2})\.(\d{1,2})\.(\d{4})")
_LONG_DATE = re.compile(r"(\d{1,2})\.\s*([A-Za-zäÄ]+)\s+(\d{4})")
_INTEGER = re.compile(r"\d[\d.]*")
_WHITESPACE = re.compile(r"\s+")


def clean_text(value: str) -> str:
    """Collapses all whitespace (incl. non-breaking spaces) to single spaces."""
    return _WHITESPACE.sub(" ", value.replace("\xa0", " ")).strip()


def text_of(tag: Tag | None) -> str | None:
    """Cleaned text content of a tag, or None if missing or empty."""
    if tag is None:
        return None
    return clean_text(tag.get_text(" ")) or None


_NON_CONTENT = ("script", "style", "noscript", "nav", "form", "button", "svg")


def content_text(html: str, selector: str) -> str | None:
    """Readable text of the first element matching `selector`, without
    scripts, navigation, forms and buttons. None if absent or empty."""
    soup = BeautifulSoup(html, "html.parser")
    element = soup.select_one(selector)
    if element is None:
        return None
    for noise in element.find_all(_NON_CONTENT):
        noise.decompose()
    return text_of(element)


def attr_of(tag: Tag | None, name: str) -> str | None:
    """A single-valued attribute of a tag, or None."""
    if tag is None:
        return None
    value = tag.get(name)
    return value if isinstance(value, str) else None


def parse_german_int(value: str | None) -> int | None:
    """'548.769' -> 548769. Takes the first number in the string."""
    if not value:
        return None
    match = _INTEGER.search(value)
    return int(match.group().replace(".", "")) if match else None


def parse_german_dates(value: str | None) -> list[date]:
    """All dd.mm.yyyy dates in a string, in order. Invalid dates are skipped."""
    if not value:
        return []
    found: list[date] = []
    for day, month, year in _NUMERIC_DATE.findall(value):
        try:
            found.append(date(int(year), int(month), int(day)))
        except ValueError:
            continue
    return found


def parse_german_long_date(value: str | None) -> date | None:
    """'Montag, 30. November 2026' -> date(2026, 11, 30)."""
    if not value:
        return None
    match = _LONG_DATE.search(value)
    if match is None:
        return None
    day, month_name, year = match.groups()
    month = _GERMAN_MONTHS.get(month_name.lower())
    if month is None:
        return None
    try:
        return date(int(year), month, int(day))
    except ValueError:
        return None
