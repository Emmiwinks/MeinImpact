"""Who a letter about a council decision goes to.

The members of the bodies the decision names (`recipient_bodies`), reached
through their Fraktion's office: one address per Fraktion, all pre-selected,
in alphabetical order so no party comes first by design. District and
village councils (Stadtbezirksbeirat, Ortschaftsrat) get names only for now;
their members mostly belong to no Stadtrat Fraktion.
"""

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from meinimpact.infrastructure.council.oparl_members import CouncilMember

_LOCAL_BODY = re.compile(r"^(Stadtbezirksbeirat|Ortschaftsrat) ")


@dataclass(frozen=True)
class Member:
    name: str
    fraktion: str | None


@dataclass(frozen=True)
class Office:
    fraktion: str
    # None when the office address is not known yet
    email: str | None


@dataclass(frozen=True)
class Recipients:
    bodies: list[str]
    members: list[Member]
    offices: list[Office]


def is_local_body(name: str) -> bool:
    """District and village councils: letters list names only."""
    return bool(_LOCAL_BODY.match(name))


def resolve_recipients(
    members: Sequence[CouncilMember], offices: Mapping[str, str]
) -> Recipients:
    bodies = sorted({m.organization_name for m in members})
    people = {m.person_url: m for m in members}.values()
    local = bool(bodies) and all(is_local_body(b) for b in bodies)
    # Keyed by address, so a Fraktion listed under two OParl ids (renamed)
    # gets one entry; unknown addresses stay apart per Fraktion
    by_address: dict[str, Office] = {}
    for m in people:
        if local or not m.fraktion_url:
            continue
        email = offices.get(m.fraktion_url)
        by_address.setdefault(
            email or m.fraktion_url,
            Office(fraktion=m.fraktion_name or "Fraktion", email=email),
        )
    return Recipients(
        bodies=bodies,
        members=sorted(
            (Member(name=m.person_name, fraktion=m.fraktion_name) for m in people),
            key=lambda m: m.name,
        ),
        offices=sorted(by_address.values(), key=lambda o: o.fraktion),
    )
