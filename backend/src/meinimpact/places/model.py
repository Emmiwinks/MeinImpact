"""What one covered place declares: identifiers and rules, never data.

A place is a level of decision (EU, Bund, a Land, a Landkreis, a
Kommune). Its `key` is the region value listings and opportunities carry
("dresden"), so it never changes once a place is live. Reference data
(districts, PLZ, places) comes from sync scripts; a place only names the
ids those scripts start from.
"""

from dataclasses import dataclass
from enum import StrEnum

from meinimpact.infrastructure.listings.sources.oparl import OParlBody
from meinimpact.infrastructure.listings.sources.sachsen_beteiligung import PortalSite


class Level(StrEnum):
    EU = "eu"
    BUND = "bund"
    LAND = "land"
    KREIS = "kreis"
    KOMMUNE = "kommune"

    @property
    def depth(self) -> int:
        """0 for the widest level, higher for more specific ones."""
        return list(Level).index(self)


class Status(StrEnum):
    """A draft place is ingested and shows in /admin, but the app never
    serves its opportunities or counts it as coverage."""

    DRAFT = "draft"
    LIVE = "live"


@dataclass(frozen=True, slots=True)
class Place:
    key: str
    # As people say it, and as compounds use it ("Dresden-Mockritz")
    name: str
    level: Level
    # Official area key (AGS): who a listing here concerns is everyone whose
    # Kreis key starts with it. Empty for Bund and EU.
    ags: str
    # The next wider place this one belongs to; None only for the EU
    parent: str | None
    # Flipped to LIVE by hand after reviewing the place's coverage report
    status: Status = Status.DRAFT
    # Districts: synced from Wikidata (`scripts/sync_districts.py <key>`)
    wikidata_id: str | None = None
    district_types: tuple[str, ...] = ()
    # Shared registries that cover this place
    openpetition_path: str | None = None
    oparl: OParlBody | None = None
    # A Land's participation portal, and substrings of the authority names
    # on it that are the Land itself (ministries, Landesamt ...)
    portal: PortalSite | None = None
    portal_land_markers: tuple[str, ...] = ()
    # How the Land portal names this place's own authority, if it differs
    # from `name`
    portal_names: tuple[str, ...] = ()

    @property
    def depth(self) -> int:
        return self.level.depth

    @property
    def authority_names(self) -> tuple[str, ...]:
        return self.portal_names or (self.name,)

    @property
    def is_live(self) -> bool:
        return self.status is Status.LIVE
