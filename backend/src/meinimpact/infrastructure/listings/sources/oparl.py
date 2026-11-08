"""Upcoming council decisions from an OParl 1.1 endpoint (Dresden today).

A council decides on papers (Vorlagen, Anträge, Petitionen). Each paper
reaches a meeting through a consultation, which says which body discusses
it and whether that body decides ("beschließend") or only advises. One
listing per paper with an upcoming meeting; its deadline is that meeting,
the last day a message to the members can still matter.

OParl has no date filter on meetings, and the paper list is too large to
walk daily (Dresden: 1,200+ papers changed in 45 days, mostly district
budget grants). So discovery starts from agenda items created recently
(an agenda is published about two weeks before a meeting), reads each of
their meetings once for its date and body, and only then resolves the
consultations of upcoming meetings in scope.

The paper's text lives in PDFs; `OParlDetailReader` extracts it for
enrichment only for new or changed listings.
"""

import io
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any

import httpx
from pypdf import PdfReader

from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import (
    ActionKind,
    Listing,
    ListingStatus,
    Region,
)
from meinimpact.infrastructure.listings.parsing import clean_text

DECIDING_ROLE = "beschließend"
_MAX_PDF_PAGES = 6


@dataclass(frozen=True, slots=True)
class OParlBody:
    """One council's OParl body and how to link its papers for people.

    `paper_web_url` takes `{number}`, the paper's numeric id; OParl itself
    carries no human-facing link. `bodies` are regexes over organization
    names: only meetings of matching bodies are read (the city council and
    its committees, district and village councils; not advisory boards or
    party groups).
    """

    source_id: str
    body_url: str
    region: Region
    locality: str
    paper_web_url: str
    bodies: tuple[str, ...]


DRESDEN = OParlBody(
    source_id="dresden-ratsinfo",
    body_url="https://oparl.dresden.de/bodies/0001",
    region=Region.DRESDEN,
    locality="Dresden",
    paper_web_url="https://ratsinfo.dresden.de/vo0050.asp?__kvonr={number}",
    bodies=(
        r"^Stadtrat$",
        r"^Ausschuss ",
        r"ausschuss$",
        r"^Stadtbezirksbeirat ",
        r"^Ortschaftsrat ",
    ),
)


@dataclass(frozen=True, slots=True)
class AgendaItem:
    name: str
    meeting_url: str
    consultation_url: str


@dataclass(frozen=True, slots=True)
class Meeting:
    url: str
    start: date
    organization_url: str | None


@dataclass(frozen=True, slots=True)
class Consultation:
    paper_url: str
    deciding: bool


def parse_agenda_page(
    payload: Mapping[str, Any],
) -> tuple[list[AgendaItem], str | None]:
    """Public agenda items that point to a paper, and the next page URL.

    Items without a consultation are headings, question rounds or reports:
    nothing is decided on them.
    """
    items = [
        AgendaItem(
            name=clean_text(str(item.get("name") or "")),
            meeting_url=https(str(item["meeting"])),
            consultation_url=https(str(item["consultation"])),
        )
        for item in payload.get("data", [])
        if item.get("consultation")
        and item.get("meeting")
        and item.get("public") is not False
        and item.get("name")
    ]
    return items, _next_url(payload)


def parse_meeting(payload: Mapping[str, Any]) -> Meeting | None:
    """None for meetings without a start or that were cancelled."""
    start = payload.get("start")
    if not start or payload.get("cancelled"):
        return None
    organizations = payload.get("organization") or []
    return Meeting(
        url=https(str(payload["id"])),
        start=datetime.fromisoformat(str(start)).date(),
        organization_url=https(str(organizations[0])) if organizations else None,
    )


def parse_consultation(payload: Mapping[str, Any]) -> Consultation | None:
    paper = payload.get("paper")
    if not paper:
        return None
    return Consultation(
        paper_url=https(str(paper)), deciding=payload.get("role") == DECIDING_ROLE
    )


def paper_external_id(paper_url: str) -> str:
    """`.../papers/vo/30796` -> `vo/30796`, stable across runs."""
    return paper_url.split("/papers/", 1)[1]


@dataclass(frozen=True, slots=True)
class Candidate:
    item: AgendaItem
    meeting: Meeting
    body_name: str
    consultation: Consultation


def build_listings(
    candidates: Sequence[Candidate], body: OParlBody, *, observed_at: datetime
) -> list[Listing]:
    """One listing per paper. A paper on several upcoming agendas (committee,
    then council) gets the next deciding meeting as its deadline, else the
    next advisory one."""
    best: dict[str, Candidate] = {}
    for candidate in candidates:
        current = best.get(candidate.consultation.paper_url)
        if current is None or _rank(candidate) < _rank(current):
            best[candidate.consultation.paper_url] = candidate
    return [_listing(c, body, observed_at=observed_at) for c in best.values()]


def _rank(candidate: Candidate) -> tuple[bool, date]:
    return (not candidate.consultation.deciding, candidate.meeting.start)


def _listing(
    candidate: Candidate, body: OParlBody, *, observed_at: datetime
) -> Listing:
    external_id = paper_external_id(candidate.consultation.paper_url)
    deciding = candidate.consultation.deciding
    verb = "entscheidet" if deciding else "berät"
    role = DECIDING_ROLE if deciding else "beratend"
    return Listing(
        source_id=body.source_id,
        external_id=external_id,
        url=body.paper_web_url.format(number=external_id.rsplit("/", 1)[-1]),
        title=candidate.item.name,
        kind=ActionKind.DECISION,
        status=ListingStatus.OPEN,
        region=body.region,
        observed_at=observed_at,
        locality=body.locality,
        organizer=candidate.body_name,
        summary=f"{candidate.body_name} {verb} darüber.",
        closes_on=candidate.meeting.start,
        source_labels=(f"Ratsvorlage, {role}",),
    )


class OParlSource:
    """Upcoming decisions of one OParl body (see the module docstring)."""

    def __init__(
        self,
        http: PoliteHttpClient,
        body: OParlBody,
        *,
        lookback_days: int = 28,
        max_pages: int = 120,
    ) -> None:
        self._http = http
        self._body = body
        self._lookback_days = lookback_days
        self._max_pages = max_pages
        self._body_patterns = tuple(re.compile(p) for p in body.bodies)

    @property
    def source_id(self) -> str:
        return self._body.source_id

    @property
    def name(self) -> str:
        return self._body.source_id

    async def fetch(self, *, observed_at: datetime) -> list[Listing]:
        today = observed_at.date()
        items = await self._recent_agenda_items(observed_at)

        meetings: dict[str, Meeting | None] = {}
        body_names: dict[str, str] = {}
        candidates: list[Candidate] = []
        for item in items:
            if item.meeting_url not in meetings:
                meetings[item.meeting_url] = await self._meeting(item.meeting_url)
            meeting = meetings[item.meeting_url]
            if meeting is None or meeting.start < today or not meeting.organization_url:
                continue
            if meeting.organization_url not in body_names:
                body_names[meeting.organization_url] = await self._body_name(
                    meeting.organization_url
                )
            body_name = body_names[meeting.organization_url]
            if not self._in_scope(body_name):
                continue
            consultation = parse_consultation(
                (await self._http.get(item.consultation_url)).json()
            )
            if consultation is not None:
                candidates.append(Candidate(item, meeting, body_name, consultation))

        listings = build_listings(candidates, self._body, observed_at=observed_at)
        return [listing for listing in listings if await self._is_public(listing)]

    async def _is_public(self, listing: Listing) -> bool:
        """Non-public papers (seen live: contract awards) sit on public
        agendas, but OParl answers 404 for them and the web link shows only
        an error page."""
        try:
            await self._http.get(f"{self._body.body_url}/papers/{listing.external_id}")
        except httpx.HTTPStatusError as error:
            if error.response.status_code == 404:
                return False
            raise
        return True

    async def _recent_agenda_items(self, observed_at: datetime) -> list[AgendaItem]:
        since = (observed_at - timedelta(days=self._lookback_days)).isoformat()
        url: str | None = f"{self._body.body_url}/agendaitems"
        params: dict[str, str | int] | None = {"created_since": since}
        items: list[AgendaItem] = []
        for _ in range(self._max_pages):
            if url is None:
                break
            response = await self._http.get(url, params=params)
            batch, url = parse_agenda_page(response.json())
            items.extend(batch)
            params = None  # the next link already carries the filter
        return items

    async def _meeting(self, url: str) -> Meeting | None:
        return parse_meeting((await self._http.get(url)).json())

    async def _body_name(self, url: str) -> str:
        payload = (await self._http.get(url)).json()
        return clean_text(str(payload.get("name") or ""))

    def _in_scope(self, body_name: str) -> bool:
        return any(p.search(body_name) for p in self._body_patterns)


def pdf_text(data: bytes, *, max_pages: int = _MAX_PDF_PAGES) -> str | None:
    """Plain text of a paper's first pages; None for scans or broken PDFs."""
    try:
        reader = PdfReader(io.BytesIO(data))
        pages = [page.extract_text() or "" for page in reader.pages[:max_pages]]
    except Exception:  # pypdf raises a wide range on malformed files
        return None
    return clean_text(" ".join(pages)) or None


class OParlDetailReader:
    """Paper type, reference and the main PDF's text."""

    def __init__(self, http: PoliteHttpClient, body: OParlBody) -> None:
        self._http = http
        self._body = body

    async def read(self, listing: Listing) -> str | None:
        paper = (
            await self._http.get(f"{self._body.body_url}/papers/{listing.external_id}")
        ).json()
        header = " ".join(
            part
            for part in (
                str(paper.get("paperType") or ""),
                str(paper.get("reference") or ""),
            )
            if part
        )
        main_file = paper_document(paper)
        text = None
        if main_file is not None:
            pdf = await self._http.get(https(str(main_file["accessUrl"])))
            text = pdf_text(pdf.content)
        return "\n\n".join(part for part in (header, text) if part) or None


def paper_document(paper: Mapping[str, Any]) -> Mapping[str, Any] | None:
    """The PDF holding the paper itself. Often there is no `mainFile` and the
    paper is an attachment named after its reference (`V1070/26` ->
    `V1070_26`), next to annexes and earlier resolutions."""
    pdfs = [
        file
        for file in (paper.get("mainFile"), *(paper.get("auxiliaryFile") or []))
        if isinstance(file, dict)
        and file.get("mimeType") == "application/pdf"
        and file.get("accessUrl")
    ]
    if paper.get("mainFile") in pdfs:
        return paper["mainFile"]  # type: ignore[no-any-return]
    reference = str(paper.get("reference") or "").replace("/", "_")
    return next(
        (f for f in pdfs if reference and str(f.get("name")) == reference), None
    )


def https(url: str) -> str:
    """OParl ids are http URLs; the same server answers on https."""
    return (
        "https://" + url.removeprefix("http://") if url.startswith("http://") else url
    )


def _next_url(payload: Mapping[str, Any]) -> str | None:
    links = payload.get("links") or {}
    next_url = links.get("next")
    return https(str(next_url)) if next_url else None
