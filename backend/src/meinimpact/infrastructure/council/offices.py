"""Fraktion office addresses, as reviewed data per place.

Letters about council decisions go to the offices of the Fraktionen whose
members sit on the deciding or preparing body, never to personal addresses
(decided 2026-11-08: one address per Fraktion treats every party the same).
Keys are OParl organization URLs, so a renamed Fraktion keeps working while
OParl keeps its id. A Fraktion missing here shows in the app without an
address; the member sync reports it.

Each place with a council has `data/<place key>.json`. Entries come from
OParl where it carries an email (`scripts/sync_council_offices.py`), else
from the Fraktion's own or the city's page, which is kept as `source`. Every
week the member sync checks that each source page still shows its address.
"""

import json
import re
from collections.abc import Iterable, Sequence
from dataclasses import asdict, dataclass
from pathlib import Path

from meinimpact import places as covered
from meinimpact.infrastructure.listings.http import PoliteHttpClient

DATA_DIR = Path(__file__).parent / "data"


@dataclass(frozen=True, slots=True)
class OfficeAddress:
    organization: str
    fraktion: str
    email: str
    # Page that shows the address; None where it came by other means (`note`)
    source: str | None
    verified_on: str
    note: str = ""


def data_file(place_key: str) -> Path:
    return DATA_DIR / f"{place_key}.json"


def load_offices(place_key: str) -> list[OfficeAddress]:
    path = data_file(place_key)
    if not path.exists():
        return []
    raw = json.loads(path.read_text(encoding="utf-8"))
    return [OfficeAddress(**entry) for entry in raw["offices"]]


def save_offices(place_key: str, offices: Iterable[OfficeAddress]) -> Path:
    path = data_file(place_key)
    path.parent.mkdir(exist_ok=True)
    rows = sorted((asdict(o) for o in offices), key=lambda o: o["organization"])
    payload = {"place": place_key, "offices": rows}
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    path.write_text(text, encoding="utf-8")
    return path


def all_offices() -> list[OfficeAddress]:
    return [o for p in covered.ALL if p.oparl for o in load_offices(p.key)]


# OParl organization URL -> office address, over every covered council
FRAKTION_OFFICES: dict[str, str] = {o.organization: o.email for o in all_offices()}


def shows_address(page: str, email: str) -> bool:
    """Whether a page shows the address, also in the common "[at]" form."""
    local, _, domain = email.partition("@")
    pattern = (
        re.escape(local)
        + r"\s*(?:@|\[at\]|\(at\)|&#64;|&commat;)\s*"
        + re.escape(domain).replace(r"\.", r"\s*(?:\.|\[dot\]|\(dot\))\s*")
    )
    return re.search(pattern, page, re.IGNORECASE) is not None


async def check_sources(
    http: PoliteHttpClient, offices: Sequence[OfficeAddress]
) -> list[str]:
    """Addresses whose source page no longer shows them, or cannot be read."""
    problems = []
    for office in offices:
        if office.source is None:
            continue
        try:
            page = (await http.get(office.source)).text
        except Exception as exc:  # reported, never fatal
            problems.append(
                f"{office.fraktion}: Quelle nicht lesbar ({type(exc).__name__})"
            )
            continue
        if not shows_address(page, office.email):
            problems.append(
                f"{office.fraktion}: {office.email} steht nicht mehr auf "
                f"{office.source}"
            )
    return problems
