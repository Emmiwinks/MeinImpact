"""Whom an opportunity concerns, as a place.

The region says who decides (and whom a letter goes to); the locality says
whom to show it to. `gebiet` is the area key (AGS) prefix of everyone it
concerns. A city's matters also get an `area` around a centre, so the app
can rank by distance: a city-wide one covers the city's Kreis area, one
from a neighbourhood body (Ortschaftsrat, Stadtbezirksbeirat ...) only
that part of the city. All of it is derived from synced data (PLZ table,
Wikidata districts); a city adds no place data by hand.
"""

import re
from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum

from meinimpact.infrastructure.geo.districts import District, DistrictMatcher
from meinimpact.infrastructure.geo.plz import (
    Area,
    PlzIndex,
    Point,
    centroid,
    distance_km,
)
from meinimpact.infrastructure.listings.model import REGION_AGS, Region

# Radius around a neighbourhood's centre(s) that still counts as it: about
# a Stadtbezirk or Ortschaft, whose district names locate only its core.
NEIGHBOURHOOD_KM = 2.5


class Reach(StrEnum):
    CITY = "stadt"
    NEIGHBOURHOOD = "nachbarschaft"


@dataclass(frozen=True, slots=True)
class Locality:
    gebiet: str
    reach: Reach | None = None
    area: Area | None = None


@dataclass(frozen=True, slots=True)
class Neighbourhoods:
    """One city's neighbourhood bodies, and its districts to locate them."""

    bodies: tuple[re.Pattern[str], ...]
    districts: tuple[District, ...]
    matcher: DistrictMatcher

    def locate(self, organizer: str) -> list[Point]:
        """The district points of the part of the city `organizer` is the
        body of; empty when it is no neighbourhood body or the part's name
        names no district."""
        for body in self.bodies:
            match = body.match(organizer)
            if match:
                return self._points(match.group("area"))
        return []

    def _points(self, area: str) -> list[Point]:
        names = set(self.matcher.find(area))
        if not names:
            # A Stadtbezirk "Altstadt" is no district itself but names
            # "Innere Altstadt" and the like.
            names = {d.name for d in self.districts if d.name.endswith(f" {area}")}
        return [d.point for d in self.districts if d.name in names and d.point]


class Coverage(StrEnum):
    """What the app has topics from for someone living in a Kreis."""

    LOCAL = "local"  # their city or Kreis, and up
    LAND = "land"  # their Land, Bund and EU
    NONE = "none"  # Bund and EU only


def coverage_of(kreis: str) -> Coverage:
    """From the regions the sources cover, so a new city's source changes
    it with no data of its own."""
    gebiete = [ags for ags in REGION_AGS.values() if ags]
    if any(len(g) >= 5 and kreis.startswith(g) for g in gebiete):
        return Coverage.LOCAL
    if kreis[:2] in gebiete:
        return Coverage.LAND
    return Coverage.NONE


class LocalityResolver:
    def __init__(
        self,
        plz: PlzIndex,
        neighbourhoods: Mapping[str, Neighbourhoods] | None = None,
    ) -> None:
        """`neighbourhoods` maps a region to its city's neighbourhood
        bodies (Dresden today)."""
        self._plz = plz
        self._neighbourhoods = neighbourhoods or {}

    def of(self, region: str, organizer: str | None) -> Locality:
        try:
            gebiet = REGION_AGS[Region(region)]
        except ValueError:
            return Locality(gebiet="")
        if len(gebiet) < 5:
            return Locality(gebiet=gebiet)
        neighbourhoods = self._neighbourhoods.get(region)
        points = (
            neighbourhoods.locate(organizer) if neighbourhoods and organizer else []
        )
        if points:
            centre = centroid(points)
            km = max(NEIGHBOURHOOD_KM, *(distance_km(centre, p) for p in points))
            return Locality(gebiet, Reach.NEIGHBOURHOOD, Area(centre, round(km, 1)))
        city = self._plz.kreis_area(gebiet)
        return Locality(gebiet, Reach.CITY if city else None, city)
