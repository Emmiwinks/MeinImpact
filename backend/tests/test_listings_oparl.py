"""OParl source: upcoming council decisions, against a fake OParl server.

Payloads are trimmed from the live Dresden endpoint (2026-11-08): ids, field
names and the http-vs-https mix are as served.
"""

from collections.abc import Mapping
from datetime import UTC, date, datetime
from typing import Any

import httpx

from meinimpact.infrastructure.listings.http import CrawlPolicy, PoliteHttpClient
from meinimpact.infrastructure.listings.model import ActionKind, Region
from meinimpact.infrastructure.listings.sources.oparl import (
    DRESDEN,
    AgendaItem,
    Candidate,
    Consultation,
    Meeting,
    OParlDetailReader,
    OParlSource,
    build_listings,
    choose_recipient_bodies,
    paper_document,
    parse_agenda_page,
    pdf_text,
)
from tests.listing_fakes import make_listing

NOW = datetime(2026, 11, 8, 12, 0, tzinfo=UTC)
_BODY = "http://oparl.dresden.de/bodies/0001"


def _item(
    number: int, *, meeting: int, consultation: int | None, name: str, **extra: Any
) -> dict[str, Any]:
    item: dict[str, Any] = {
        "id": f"{_BODY}/agendaitems/{number}",
        "type": "https://schema.oparl.org/1.1/AgendaItem",
        "meeting": f"{_BODY}/meetings/{meeting}",
        "name": name,
        "public": True,
        **extra,
    }
    if consultation is not None:
        item["consultation"] = f"{_BODY}/consultations/{consultation}"
    return item


def _meeting(
    number: int, start: str, organization: str, **extra: Any
) -> dict[str, Any]:
    return {
        "id": f"{_BODY}/meetings/{number}",
        "name": f"{number}. Sitzung",
        "start": start,
        "organization": [f"{_BODY}/organizations/gr/{organization}"],
        **extra,
    }


def _consultation(number: int, paper: str, role: str) -> dict[str, Any]:
    return {
        "id": f"{_BODY}/consultations/{number}",
        "paper": f"{_BODY}/papers/vo/{paper}",
        "role": role,
    }


_AGENDA_PAGE_1 = {
    "data": [
        # Same petition: committee advises first, council decides later
        _item(1, meeting=10, consultation=100, name="Keine Windräder in der Heide"),
        _item(2, meeting=11, consultation=101, name="Keine Windräder in der Heide"),
        # Headings and question rounds have no consultation
        _item(3, meeting=11, consultation=None, name="Fragestunde"),
        # Not public
        _item(4, meeting=11, consultation=102, name="Personalie", public=False),
    ],
    "links": {"next": f"{_BODY}/agendaitems?page=2&created_since=x"},
}
_AGENDA_PAGE_2 = {
    "data": [
        _item(5, meeting=12, consultation=103, name="Längst beschlossen"),
        _item(6, meeting=13, consultation=104, name="Beiratsthema"),
        _item(7, meeting=14, consultation=105, name="Abgesagt"),
        _item(8, meeting=15, consultation=106, name="Spielplatz Blasewitz"),
        # Public agenda item, but the paper is not public (contract award)
        _item(9, meeting=15, consultation=107, name="Vergabenummer: 2026-66-1"),
    ],
    "links": {},
}

_OBJECTS: Mapping[str, Mapping[str, Any]] = {
    "/bodies/0001/meetings/10": _meeting(10, "2026-11-17T16:00:00+01:00", "157"),
    "/bodies/0001/meetings/11": _meeting(11, "2026-11-26T16:00:00+01:00", "1"),
    "/bodies/0001/meetings/12": _meeting(12, "2026-10-29T16:00:00+01:00", "1"),
    "/bodies/0001/meetings/13": _meeting(13, "2026-11-20T16:00:00+01:00", "90"),
    "/bodies/0001/meetings/14": _meeting(
        14, "2026-11-19T16:00:00+01:00", "1", cancelled=True
    ),
    "/bodies/0001/meetings/15": _meeting(15, "2026-11-18T17:30:00+01:00", "167"),
    "/bodies/0001/organizations/gr/1": {"name": "Stadtrat"},
    "/bodies/0001/organizations/gr/157": {
        "name": "Ausschuss für Stadtentwicklung, Bau, Verkehr und Liegenschaften"
    },
    "/bodies/0001/organizations/gr/90": {"name": "Integrations- und Ausländerbeirat"},
    "/bodies/0001/organizations/gr/167": {"name": "Stadtbezirksbeirat Blasewitz"},
    "/bodies/0001/consultations/100": _consultation(100, "30796", "beratend"),
    "/bodies/0001/consultations/101": _consultation(101, "30796", "beschließend"),
    "/bodies/0001/consultations/103": _consultation(103, "1", "beschließend"),
    "/bodies/0001/consultations/104": _consultation(104, "2", "beschließend"),
    "/bodies/0001/consultations/106": _consultation(106, "31000", "beschließend"),
    "/bodies/0001/consultations/107": _consultation(107, "31199", "beschließend"),
    "/bodies/0001/papers/vo/30796": {
        "paperType": "Petition",
        # Embedded as served: the committee prepares, the council decides
        "consultation": [
            {"organization": [f"{_BODY}/organizations/gr/157"], "role": "beratend"},
            {"organization": [f"{_BODY}/organizations/gr/1"], "role": "beschließend"},
        ],
    },
    "/bodies/0001/papers/vo/31000": {"paperType": "Vorlage STB Blasewitz"},
}


async def _no_sleep(_: float) -> None:
    return None


def _server(
    extra: Mapping[str, httpx.Response] | None = None,
) -> tuple[PoliteHttpClient, list[str]]:
    requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path == "/robots.txt":
            return httpx.Response(404)
        requested.append(path)
        assert request.url.scheme == "https"
        if extra and path in extra:
            return extra[path]
        if path == "/bodies/0001/agendaitems":
            page = request.url.params.get("page")
            return httpx.Response(200, json=_AGENDA_PAGE_2 if page else _AGENDA_PAGE_1)
        found = _OBJECTS.get(path)
        return httpx.Response(200, json=found) if found else httpx.Response(404)

    http = PoliteHttpClient(
        policy=CrawlPolicy(default_delay_s=0),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        sleep=_no_sleep,
    )
    return http, requested


def test_agenda_page_keeps_public_items_with_a_paper() -> None:
    items, next_url = parse_agenda_page(_AGENDA_PAGE_1)

    assert [item.name for item in items] == ["Keine Windräder in der Heide"] * 2
    assert items[0].meeting_url == "https://oparl.dresden.de/bodies/0001/meetings/10"
    assert next_url == (
        "https://oparl.dresden.de/bodies/0001/agendaitems?page=2&created_since=x"
    )
    assert parse_agenda_page(_AGENDA_PAGE_2)[1] is None


async def test_one_listing_per_upcoming_paper_with_the_deciding_meeting() -> None:
    http, _ = _server()

    listings = await OParlSource(http, DRESDEN).fetch(observed_at=NOW)

    by_id = {listing.external_id: listing for listing in listings}
    # vo/31199 is on a public agenda but its paper is not public: dropped
    assert set(by_id) == {"vo/30796", "vo/31000"}
    windrad = by_id["vo/30796"]
    assert windrad.kind is ActionKind.DECISION
    assert windrad.region is Region.DRESDEN
    assert windrad.url == "https://ratsinfo.dresden.de/vo0050.asp?__kvonr=30796"
    assert windrad.organizer == "Stadtrat"
    assert windrad.closes_on == date(2026, 11, 26)
    assert windrad.summary == "Stadtrat entscheidet darüber."
    # The district body's name reaches the district matcher via the summary
    assert (
        by_id["vo/31000"].summary == "Stadtbezirksbeirat Blasewitz entscheidet darüber."
    )
    # A council item's letter goes to the committee that prepares it; a
    # district item's to the district council itself
    organizations = "https://oparl.dresden.de/bodies/0001/organizations/gr"
    assert windrad.recipient_bodies == (f"{organizations}/157",)
    assert by_id["vo/31000"].recipient_bodies == (f"{organizations}/167",)


def test_council_item_without_a_committee_goes_to_the_council() -> None:
    council = "https://x/organizations/gr/1"
    names = {
        council: "Stadtrat",
        "https://x/gr/90": "Integrations- und Ausländerbeirat",
    }

    bodies = choose_recipient_bodies(
        council, "Stadtrat", [council, "https://x/gr/90"], names, DRESDEN
    )

    assert bodies == (council,)


async def test_skips_past_cancelled_and_out_of_scope_meetings_cheaply() -> None:
    http, requested = _server()

    await OParlSource(http, DRESDEN).fetch(observed_at=NOW)

    # Consultations are only resolved for upcoming meetings of bodies in scope
    assert "/bodies/0001/consultations/103" not in requested  # past
    assert "/bodies/0001/consultations/104" not in requested  # advisory board
    assert "/bodies/0001/consultations/105" not in requested  # cancelled
    # Each meeting and body is read once
    assert requested.count("/bodies/0001/meetings/11") == 1
    assert requested.count("/bodies/0001/organizations/gr/1") == 1


def test_advisory_only_paper_gets_the_next_advisory_meeting() -> None:
    def candidate(start: date) -> Candidate:
        return Candidate(
            AgendaItem("Thema", "m", "c"),
            Meeting("m", start, "o"),
            "Ausschuss für Bildung",
            Consultation(f"{_BODY}/papers/vo/7", deciding=False),
        )

    [listing] = build_listings(
        [candidate(date(2026, 12, 1)), candidate(date(2026, 11, 20))],
        DRESDEN,
        observed_at=NOW,
    )

    assert listing.closes_on == date(2026, 11, 20)
    assert listing.summary == "Ausschuss für Bildung berät darüber."


def _pdf(text: str) -> bytes:
    """A minimal valid one-page PDF showing `text` (Latin-1)."""
    stream = f"BT /F1 12 Tf 72 720 Td ({text}) Tj ET".encode("latin-1")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    out += b"".join(b"%010d 00000 n \n" % offset for offset in offsets)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (
        len(objects) + 1,
        xref,
    )
    return bytes(out)


def test_paper_document_falls_back_to_the_attachment_named_like_the_paper() -> None:
    def pdf(name: str) -> dict[str, str]:
        return {"name": name, "mimeType": "application/pdf", "accessUrl": name}

    paper = {
        "reference": "V0958/26",
        "auxiliaryFile": [pdf("bereits gefasster Beschluss V2174_23"), pdf("V0958_26")],
    }
    assert paper_document(paper) == pdf("V0958_26")
    assert paper_document({**paper, "mainFile": pdf("Petition")}) == pdf("Petition")
    assert (
        paper_document({"reference": "V1/26", "auxiliaryFile": [pdf("Anlage")]}) is None
    )


def test_pdf_text_reads_text_and_tolerates_garbage() -> None:
    assert pdf_text(_pdf("Der Stadtrat beschliesst")) == "Der Stadtrat beschliesst"
    assert pdf_text(b"not a pdf") is None


async def test_detail_reader_returns_paper_type_and_pdf_text() -> None:
    paper = {
        "paperType": "Petition",
        "reference": "P0140/26",
        "mainFile": {
            "mimeType": "application/pdf",
            "accessUrl": f"{_BODY}/downloadfiles/a/00899539.pdf",
        },
    }
    http, _ = _server(
        {
            "/bodies/0001/papers/vo/30796": httpx.Response(200, json=paper),
            "/bodies/0001/downloadfiles/a/00899539.pdf": httpx.Response(
                200, content=_pdf("Keine Windraeder")
            ),
        }
    )

    text = await OParlDetailReader(http, DRESDEN).read(
        make_listing("vo/30796", source_id=DRESDEN.source_id)
    )

    assert text == "Petition P0140/26\n\nKeine Windraeder"
