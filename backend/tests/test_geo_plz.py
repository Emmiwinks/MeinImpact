"""The PLZ table: GeoNames parsing, condensing, and the committed index."""

import io
import zipfile

import httpx
import pytest

from meinimpact.infrastructure.geo.geonames import (
    GeoNamesPlzSource,
    PlzRow,
    condense,
    parse_rows,
)
from meinimpact.infrastructure.geo.plz import (
    PlzIndex,
    PlzLocation,
    Point,
    distance_km,
)

_GEONAMES = (
    "DE\t01067\tDresden Innere Altstadt\tSaxony\tSN\t\t00\tKreisfreie Stadt Dresden"
    "\t14612\t51.0507\t13.7366\t4\n"
    "DE\t01067\tDresden\tSaxony\tSN\t\t00\tKreisfreie Stadt Dresden"
    "\t14612\t51.0547\t13.7269\t4\n"
    "DE\t87491\tJungholz\t\t\t\t\t\t\t47.5741\t10.4472\t\n"
)


def test_parse_rows_skips_places_without_a_kreis() -> None:
    assert parse_rows(_GEONAMES) == [
        PlzRow("01067", "Dresden Innere Altstadt", "14612", 51.0507, 13.7366),
        PlzRow("01067", "Dresden", "14612", 51.0547, 13.7269),
    ]


def test_condense_takes_the_medoid_so_a_stray_place_cannot_drag_the_point() -> None:
    rows = [
        PlzRow("01689", "Weinböhla", "14627", 51.1667, 13.5667),
        PlzRow("01689", "Niederau", "14627", 51.1440, 13.5707),
        PlzRow("01689", "Coswig", "14627", 51.1300, 13.5800),
        PlzRow("01689", "Irgendwo", "09162", 48.1, 11.5),
    ]

    assert condense(rows) == {"01689": ("14627", 51.144, 13.5707)}


def test_condense_takes_the_kreis_most_places_lie_in() -> None:
    rows = [
        PlzRow("12345", "A", "11111", 50.0, 10.0),
        PlzRow("12345", "B", "22222", 50.01, 10.0),
        PlzRow("12345", "C", "22222", 50.02, 10.0),
    ]

    assert condense(rows)["12345"][0] == "22222"


async def test_source_reads_the_zipped_table() -> None:
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as z:
        z.writestr("DE.txt", _GEONAMES)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=archive.getvalue())

    source = GeoNamesPlzSource(
        httpx.AsyncClient(transport=httpx.MockTransport(handler))
    )

    assert len(await source.fetch()) == 2
    await source.aclose()


def test_distance_km() -> None:
    dresden, leipzig = Point(51.0504, 13.7373), Point(51.3397, 12.3731)
    assert distance_km(dresden, leipzig) == pytest.approx(100, abs=2)


def _ring(kreis: str, n: int, km: float) -> dict[str, PlzLocation]:
    """`n` PLZs on the axes around 51/13, `km` from the centre."""
    step = km / 111.0
    offsets = [(step, 0), (-step, 0), (0, step * 1.6), (0, -step * 1.6)]
    return {
        f"{kreis[:2]}{i:03d}": PlzLocation(
            kreis, Point(51 + offsets[i % 4][0], 13 + offsets[i % 4][1])
        )
        for i in range(n)
    }


def test_kreis_area_reaches_its_farthest_plz_but_not_an_island() -> None:
    locations = _ring("14612", 20, 10)
    locations["99999"] = PlzLocation("14612", Point(52.0, 13.0))  # 111 km out

    area = PlzIndex(locations).kreis_area("14612")

    assert area is not None
    assert area.km == pytest.approx(10, abs=1)


def test_committed_table_locates_dresden_and_weinboehla() -> None:
    index = PlzIndex.load()

    dresden = index.locate("01067")
    weinboehla = index.locate("01689")
    city = index.kreis_area("14612")

    assert dresden is not None and dresden.kreis == "14612"
    assert weinboehla is not None and weinboehla.kreis == "14627"
    assert index.locate("99999") is None
    # Dresden's outskirts (Langebrück, Schönfeld-Weißig) count as Dresden.
    assert city is not None and 10 < city.km < 15
