"""Whom an opportunity concerns, as a place.

The region says who decides (and whom a letter goes to); the locality says
whom to show it to. `gebiet` is the area key (AGS) prefix of everyone it
concerns. Where possible an opportunity also gets an `area` around a
centre, so the app can rank by distance:
- A city's matter covers the city's Kreis area, or only one part of the
  city: the part enrichment names, else the part its neighbourhood body
  (Ortschaftsrat, Stadtbezirksbeirat ...) stands for. A city-wide reach
  beats the body: an Ortschaftsrat advising on the city budget is no
  neighbourhood matter.
- A Land or Bund matter that enrichment places in one or a few
  municipalities or Kreise (a school in Weinböhla, a railway from Pirna to
  Sebnitz) covers those. Its `gebiet` stays the region's: a wrongly placed
  matter is ranked lower far away, never withheld.
All of it is derived from synced data (PLZ and place table, Wikidata
districts); a city adds no place data by hand.
"""

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from enum import StrEnum

from meinimpact import places as covered
from meinimpact.infrastructure.geo.districts import District, DistrictMatcher
from meinimpact.infrastructure.geo.places import PlaceIndex
from meinimpact.infrastructure.geo.plz import (
    Area,
    PlzIndex,
    Point,
    centroid,
    distance_km,
)

# Radius around a neighbourhood's centre(s) that still counts as it: about
# a Stadtbezirk or Ortschaft, whose district names locate only its core.
NEIGHBOURHOOD_KM = 2.5
# Margin around the places of a matter for a whole area (a forest, a
# mine): the villages next to them are concerned too.
SURROUNDINGS_KM = 5.0


class Reach(StrEnum):
    NEIGHBOURHOOD = "nachbarschaft"
    PLACE = "ort"  # one whole municipality or small town
    CITY = "stadt"
    SURROUNDINGS = "umland"  # several municipalities: a railway, a forest

    @classmethod
    def of(cls, value: str | None) -> Reach | None:
        """The reach named `value`; None for none or an unknown one."""
        try:
            return cls(value) if value else None
        except ValueError:
            return None


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
                return self.points(match.group("area"))
        return []

    def points(self, area: str) -> list[Point]:
        """The district points of the part of the city called `area`."""
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
    """From the covered places, so a new place file changes it with no
    data of its own."""
    gebiete = [place.ags for place in covered.ALL if place.ags]
    if any(len(g) >= 5 and kreis.startswith(g) for g in gebiete):
        return Coverage.LOCAL
    if kreis[:2] in gebiete:
        return Coverage.LAND
    return Coverage.NONE


class LocalityResolver:
    def __init__(
        self,
        plz: PlzIndex,
        places: PlaceIndex,
        neighbourhoods: Mapping[str, Neighbourhoods] | None = None,
    ) -> None:
        """`neighbourhoods` maps a region to its city's neighbourhood
        bodies (Dresden today)."""
        self._plz = plz
        self._places = places
        self._neighbourhoods = neighbourhoods or {}

    def of(
        self,
        region: str,
        organizer: str | None,
        reach: Reach | None = None,
        places: Sequence[str] = (),
    ) -> Locality:
        """`reach` and `places` are enrichment's reading of the text; both
        are missing for opportunities enriched before it read them."""
        gebiet = covered.ags_of(region)
        if gebiet is None:
            return Locality(gebiet="")
        if len(gebiet) >= 5:
            return self._in_city(region, gebiet, organizer, reach, places)
        area = self._around(places, gebiet, reach) if reach else None
        return Locality(gebiet, reach, area) if area else Locality(gebiet)

    def _in_city(
        self,
        region: str,
        gebiet: str,
        organizer: str | None,
        reach: Reach | None,
        places: Sequence[str],
    ) -> Locality:
        neighbourhoods = self._neighbourhoods.get(region)
        if neighbourhoods and reach in (None, Reach.NEIGHBOURHOOD):
            points = [p for name in places for p in neighbourhoods.points(name)]
            if not points and organizer:
                points = neighbourhoods.locate(organizer)
            if points:
                centre = centroid(points)
                km = max(NEIGHBOURHOOD_KM, *(distance_km(centre, p) for p in points))
                area = Area(centre, round(km, 1))
                return Locality(gebiet, Reach.NEIGHBOURHOOD, area)
        city = self._plz.kreis_area(gebiet)
        return Locality(gebiet, Reach.CITY if city else None, city)

    def _around(self, places: Sequence[str], gebiet: str, reach: Reach) -> Area | None:
        """The area covering every place named that lies in `gebiet`;
        places that cannot be located are left out."""
        areas = [area for name in places if (area := self._places.locate(name, gebiet))]
        if not areas:
            return None
        centre = centroid([area.centre for area in areas])
        km = max(distance_km(centre, area.centre) + area.km for area in areas)
        if reach is Reach.SURROUNDINGS:
            km += SURROUNDINGS_KM
        return Area(centre, round(km, 1))
