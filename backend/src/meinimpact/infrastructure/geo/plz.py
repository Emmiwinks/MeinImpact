"""Where a PLZ lies, and how far each Kreis reaches.

Both come from the committed GeoNames table (`scripts/sync_plz.py`), so a
new city or Kreis needs no data of its own: its centre and reach follow
from the points of its PLZs.
"""

import json
import math
import statistics
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

DATA_FILE = Path(__file__).parent / "data" / "plz.json"

_EARTH_RADIUS_KM = 6371.0
# A Kreis reaches its farthest PLZ point, except points beyond this many
# times its typical (90th percentile) distance: islands like Neuwerk
# (Hamburg, 105 km out) would otherwise make the whole city "near" to
# everything around it. The plain 90th percentile alone is too short:
# a city's many central special PLZs (post boxes, large customers) pull
# it in, and Dresden's outskirts would fall outside Dresden.
_TYPICAL_QUANTILE = 0.9
_OUTLIER_FACTOR = 2.0


@dataclass(frozen=True, slots=True)
class Point:
    lat: float
    lon: float


@dataclass(frozen=True, slots=True)
class Area:
    """A centre and the radius around it that something concerns."""

    centre: Point
    km: float


@dataclass(frozen=True, slots=True)
class PlzLocation:
    kreis: str  # AGS of the Kreis or kreisfreie Stadt, e.g. "14612"
    point: Point


def distance_km(a: Point, b: Point) -> float:
    """Great-circle distance (haversine)."""
    lat1, lat2 = math.radians(a.lat), math.radians(b.lat)
    dlat = lat2 - lat1
    dlon = math.radians(b.lon - a.lon)
    h = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    )
    return 2 * _EARTH_RADIUS_KM * math.asin(math.sqrt(h))


def centroid(points: list[Point]) -> Point:
    return Point(
        lat=sum(p.lat for p in points) / len(points),
        lon=sum(p.lon for p in points) / len(points),
    )


class PlzIndex:
    def __init__(self, locations: dict[str, PlzLocation]) -> None:
        self._locations = locations
        self._kreis_areas = _kreis_areas(locations.values())

    @classmethod
    def load(cls, path: Path = DATA_FILE) -> PlzIndex:
        raw = json.loads(path.read_text(encoding="utf-8"))
        return cls(
            {
                plz: PlzLocation(kreis, Point(lat, lon))
                for plz, (kreis, lat, lon) in raw["plz"].items()
            }
        )

    def locate(self, plz: str) -> PlzLocation | None:
        return self._locations.get(plz)

    def kreis_area(self, kreis: str) -> Area | None:
        return self._kreis_areas.get(kreis)


def _kreis_areas(locations: Iterable[PlzLocation]) -> dict[str, Area]:
    points: dict[str, list[Point]] = defaultdict(list)
    for location in locations:
        points[location.kreis].append(location.point)
    areas = {}
    for kreis, kreis_points in points.items():
        # The median, not the mean: an island must not move the centre.
        centre = Point(
            lat=statistics.median(p.lat for p in kreis_points),
            lon=statistics.median(p.lon for p in kreis_points),
        )
        distances = sorted(distance_km(centre, p) for p in kreis_points)
        typical = distances[int((len(distances) - 1) * _TYPICAL_QUANTILE)]
        reach = max(d for d in distances if d <= _OUTLIER_FACTOR * typical)
        areas[kreis] = Area(centre, round(reach, 1))
    return areas
