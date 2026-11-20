"""Fetches a city's districts from the Wikidata query service.

Used by `scripts/sync_districts.py` only, never at request or ingestion
time: district lists are reference data that is synced, reviewed and
committed.
"""

import re
from typing import Any

import httpx

from meinimpact.infrastructure.geo.districts import CityConfig, District
from meinimpact.infrastructure.geo.plz import Point

SPARQL_URL = "https://query.wikidata.org/sparql"
# Wikimedia's User-Agent policy requires a way to contact the operator.
USER_AGENT = (
    "MeinImpactBot/0.1 (+https://github.com/Emmiwinks/MeinImpact) district-sync"
)


def build_query(city: CityConfig) -> str:
    types = " ".join(f"wd:{t}" for t in city.district_types)
    return f"""
SELECT DISTINCT ?item ?name ?coord WHERE {{
  VALUES ?type {{ {types} }}
  ?item wdt:P131 wd:{city.wikidata_id} ; wdt:P31 ?type ; rdfs:label ?name .
  FILTER(LANG(?name) = "de")
  OPTIONAL {{ ?item wdt:P625 ?coord . }}
}}"""


# Wikidata writes coordinates as WKT, longitude first: "Point(13.75 51.06)".
_WKT_POINT = re.compile(r"^Point\(([-\d.]+) ([-\d.]+)\)$")


def parse_bindings(payload: dict[str, Any]) -> list[District]:
    """One district per item; an item with several coordinates keeps the
    first."""
    districts: dict[str, District] = {}
    for binding in payload["results"]["bindings"]:
        qid = binding["item"]["value"].rsplit("/", 1)[-1]
        if qid in districts:
            continue
        match = _WKT_POINT.match(binding.get("coord", {}).get("value", ""))
        districts[qid] = District(
            name=binding["name"]["value"],
            wikidata_id=qid,
            point=(
                Point(lat=float(match.group(2)), lon=float(match.group(1)))
                if match
                else None
            ),
        )
    return sorted(districts.values(), key=lambda d: d.name)


class WikidataDistrictSource:
    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(timeout=60.0)

    async def fetch(self, city: CityConfig) -> list[District]:
        response = await self._client.get(
            SPARQL_URL,
            params={"query": build_query(city), "format": "json"},
            headers={"User-Agent": USER_AGENT},
        )
        response.raise_for_status()
        return parse_bindings(response.json())

    async def aclose(self) -> None:
        await self._client.aclose()
