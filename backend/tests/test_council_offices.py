"""Fraktion office addresses: the data files, the source check, OParl."""

from datetime import date
from pathlib import Path
from typing import Any

import httpx
import pytest

from meinimpact.infrastructure.council import offices
from meinimpact.infrastructure.council.offices import (
    FRAKTION_OFFICES,
    OfficeAddress,
    check_sources,
    load_offices,
    save_offices,
    shows_address,
)
from meinimpact.infrastructure.council.oparl_members import (
    fetch_fraktionen,
    is_fraktion,
)
from meinimpact.infrastructure.listings.http import CrawlPolicy, PoliteHttpClient
from meinimpact.places.defs.dresden import COUNCIL as DRESDEN

_GR = "https://oparl.dresden.de/bodies/0001/organizations/gr/"


async def _no_sleep(_: float) -> None:
    return None


def _http(handler: Any) -> PoliteHttpClient:
    return PoliteHttpClient(
        policy=CrawlPolicy(default_delay_s=0, get_retries=0),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        sleep=_no_sleep,
    )


def test_dresden_addresses_load_from_the_data_file() -> None:
    assert len(FRAKTION_OFFICES) == 10
    assert FRAKTION_OFFICES[_GR + "5"] == "cdu-fraktion@dresden.de"
    # Renamed Fraktion: two OParl ids, one office
    assert FRAKTION_OFFICES[_GR + "205"] == FRAKTION_OFFICES[_GR + "217"]
    assert all(o.verified_on and (o.source or o.note) for o in load_offices("dresden"))


def test_a_place_without_a_file_has_no_addresses() -> None:
    assert load_offices("nowhere") == []


def test_save_and_load_round_trip(tmp_path: Path, monkeypatch: Any) -> None:
    monkeypatch.setattr(offices, "DATA_DIR", tmp_path)
    entry = OfficeAddress(
        organization="https://x/gr/1",
        fraktion="Grüne",
        email="gruene@stadt.de",
        source="https://stadt.de/gruene",
        verified_on="2026-11-25",
    )

    save_offices("stadt", [entry])

    assert load_offices("stadt") == [entry]


@pytest.mark.parametrize(
    "page",
    [
        "Mail: cdu-fraktion@dresden.de",
        "cdu-fraktion [at] dresden.de",
        "cdu-fraktion(at)dresden(dot)de",
        "CDU-Fraktion&#64;Dresden.de",
    ],
)
def test_address_is_found_also_in_obfuscated_forms(page: str) -> None:
    assert shows_address(page, "cdu-fraktion@dresden.de")


def test_other_address_is_not_found() -> None:
    assert not shows_address("spd-fraktion@dresden.de", "cdu-fraktion@dresden.de")


async def test_source_check_reports_gone_and_unreadable_pages() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        if request.url.path == "/ok":
            return httpx.Response(200, text="Kontakt: a@stadt.de")
        if request.url.path == "/moved":
            return httpx.Response(200, text="Kontakt: neu@stadt.de")
        return httpx.Response(500)

    def entry(name: str, path: str | None) -> OfficeAddress:
        source = f"https://stadt.de{path}" if path else None
        return OfficeAddress(f"u/{name}", name, "a@stadt.de", source, "2026-11-25")

    async with _http(handler) as http:
        problems = await check_sources(
            http,
            [
                entry("A", "/ok"),
                entry("B", "/moved"),
                entry("C", "/down"),
                entry("D", None),
            ],
        )

    assert problems == [
        "B: a@stadt.de steht nicht mehr auf https://stadt.de/moved",
        "C: Quelle nicht lesbar (HTTPStatusError)",
    ]


def test_fraktion_is_recognized_by_classification_or_name() -> None:
    assert is_fraktion({"classification": "Fraktion", "name": "CDU"})
    assert is_fraktion({"name": "Fraktion Die Linke"})
    assert not is_fraktion({"classification": "Ausschuss", "name": "Bauausschuss"})


async def test_fetch_fraktionen_keeps_current_ones_with_their_email() -> None:
    seats = ["https://x/memberships/1"]
    page = {
        "data": [
            {
                "id": _GR + "5",
                "name": "CDU-Fraktion",
                "classification": "Fraktion",
                "membership": seats,
            },
            # Dresden's second listing of the same Fraktion, without members
            {"id": _GR.replace("/gr/", "/at/") + "81", "name": "CDU-Fraktion"},
            {
                "id": "http://oparl.dresden.de/bodies/0001/organizations/gr/9",
                "name": "Fraktion Neu",
                "classification": "Fraktion",
                "email": " neu@stadt.de ",
                "membership": seats,
            },
            {
                "id": _GR + "1",
                "name": "Fraktion Alt",
                "classification": "Fraktion",
                "endDate": "2024-06-30",
                "membership": seats,
            },
            {
                "id": _GR + "2",
                "name": "Bauausschuss",
                "classification": "Ausschuss",
                "membership": seats,
            },
        ],
        "links": {},
    }

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        return httpx.Response(200, json=page)

    async with _http(handler) as http:
        fraktionen = await fetch_fraktionen(http, DRESDEN, today=date(2026, 11, 25))

    assert [(f.url, f.name, f.email) for f in fraktionen] == [
        (_GR + "5", "CDU-Fraktion", None),
        (_GR + "9", "Fraktion Neu", "neu@stadt.de"),
    ]
