"""Fetches and condenses the GeoNames postal code table for Germany.

Used by `scripts/sync_plz.py` only, never at request time: the condensed
table is reference data that is synced, reviewed and committed. GeoNames
data is CC BY 4.0 (https://www.geonames.org), so the app names it.
"""

import csv
import io
import math
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass

import httpx

DE_ZIP_URL = "https://download.geonames.org/export/zip/DE.zip"
ATTRIBUTION = "GeoNames (geonames.org), CC BY 4.0"


@dataclass(frozen=True, slots=True)
class PlzRow:
    """One place within a PLZ, as GeoNames lists it."""

    plz: str
    place: str
    kreis: str  # AGS of the Kreis or kreisfreie Stadt, e.g. "14612"
    lat: float
    lon: float


def parse_rows(text: str) -> list[PlzRow]:
    """GeoNames' tab-separated rows; places without a Kreis are skipped
    (only Jungholz, an Austrian enclave with a German PLZ)."""
    rows = []
    for fields in csv.reader(io.StringIO(text), delimiter="\t"):
        if len(fields) < 11 or not fields[8]:
            continue
        rows.append(
            PlzRow(
                plz=fields[1],
                place=fields[2],
                kreis=fields[8],
                lat=float(fields[9]),
                lon=float(fields[10]),
            )
        )
    return rows


def condense(rows: list[PlzRow]) -> dict[str, tuple[str, float, float]]:
    """One point and Kreis per PLZ.

    A PLZ often lists several places. Its point is the medoid (the place
    closest to all others), so a stray place hundreds of kilometres off,
    as some special PLZs have, cannot drag it away. Its Kreis is the one
    most of its places lie in, the medoid's on a tie.
    """
    by_plz: dict[str, list[PlzRow]] = defaultdict(list)
    for row in rows:
        by_plz[row.plz].append(row)
    condensed = {}
    for plz, places in sorted(by_plz.items()):
        medoid = min(
            places,
            key=lambda a: sum(
                math.dist((a.lat, a.lon), (b.lat, b.lon)) for b in places
            ),
        )
        counts = Counter(p.kreis for p in places)
        top = max(counts.values())
        kreis = (
            medoid.kreis
            if counts[medoid.kreis] == top
            else min(k for k, n in counts.items() if n == top)
        )
        condensed[plz] = (kreis, round(medoid.lat, 4), round(medoid.lon, 4))
    return condensed


class GeoNamesPlzSource:
    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(timeout=60.0)

    async def fetch(self) -> list[PlzRow]:
        response = await self._client.get(DE_ZIP_URL)
        response.raise_for_status()
        with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
            text = archive.read("DE.txt").decode("utf-8")
        return parse_rows(text)

    async def aclose(self) -> None:
        await self._client.aclose()
