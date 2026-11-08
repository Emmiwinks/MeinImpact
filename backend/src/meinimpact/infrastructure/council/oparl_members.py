"""Current members of council bodies, read from OParl.

OParl has no "members of body X today" query, and a body's membership list
holds its whole history as separate URLs (Dresden's Stadtrat: 248). Persons,
though, embed all their memberships, so one walk over the people list (about
180 pages at 10 per page) yields every body's current voting members and
each person's Fraktion. A person's `modified` date does not change when a
membership is added, so the walk is always complete, never incremental.
"""

import re
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import date
from typing import Any

from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.parsing import clean_text
from meinimpact.infrastructure.listings.sources.oparl import OParlBody, https

_FRAKTION = re.compile(r"Fraktion")


@dataclass(frozen=True, slots=True)
class CouncilMember:
    organization_url: str
    organization_name: str
    person_url: str
    person_name: str
    fraktion_url: str | None
    fraktion_name: str | None


def is_current(membership: Mapping[str, Any], today: date) -> bool:
    start = membership.get("startDate")
    end = membership.get("endDate")
    return (not start or date.fromisoformat(str(start)) <= today) and (
        not end or date.fromisoformat(str(end)) >= today
    )


def members_of_person(
    person: Mapping[str, Any],
    names: Mapping[str, str],
    body: OParlBody,
    today: date,
) -> list[CouncilMember]:
    """The person's current voting seats in bodies in scope. Deputies
    ("Stellvertretendes Mitglied") carry no voting right and are left out."""
    current = [
        m
        for m in person.get("membership") or []
        if isinstance(m, dict) and m.get("organization") and is_current(m, today)
    ]
    # OParl keeps some ended Fraktion memberships open (seen live: Fraktionen
    # dissolved in 2024), so the most recently started one wins
    fraktionen = sorted(
        (
            m
            for m in current
            if _FRAKTION.search(names.get(https(str(m["organization"])), ""))
        ),
        key=lambda m: str(m.get("startDate") or ""),
    )
    fraktion_url = https(str(fraktionen[-1]["organization"])) if fraktionen else None
    patterns = [re.compile(p) for p in body.bodies]
    person_name = clean_text(str(person.get("name") or ""))
    members: list[CouncilMember] = []
    for membership in current:
        url = https(str(membership["organization"]))
        name = names.get(url, "")
        if not membership.get("votingRight") or not any(
            p.search(name) for p in patterns
        ):
            continue
        members.append(
            CouncilMember(
                organization_url=url,
                organization_name=name,
                person_url=https(str(person["id"])),
                person_name=person_name,
                fraktion_url=fraktion_url,
                fraktion_name=names.get(fraktion_url) if fraktion_url else None,
            )
        )
    return members


async def fetch_council_members(
    http: PoliteHttpClient,
    body: OParlBody,
    *,
    today: date,
    max_pages: int = 500,
) -> list[CouncilMember]:
    names = {
        https(str(org["id"])): clean_text(str(org.get("name") or ""))
        for org in await _all(http, f"{body.body_url}/organizations", max_pages)
    }
    members: list[CouncilMember] = []
    for person in await _all(http, f"{body.body_url}/people", max_pages):
        members.extend(members_of_person(person, names, body, today))
    return members


async def _all(
    http: PoliteHttpClient, url: str, max_pages: int
) -> list[Mapping[str, Any]]:
    items: list[Mapping[str, Any]] = []
    next_url: str | None = url
    for _ in range(max_pages):
        if next_url is None:
            return items
        payload = (await http.get(next_url)).json()
        items.extend(item for item in payload.get("data", []) if isinstance(item, dict))
        link = (payload.get("links") or {}).get("next")
        next_url = https(str(link)) if link else None
    raise RuntimeError(f"OParl list {url} has more than {max_pages} pages")
