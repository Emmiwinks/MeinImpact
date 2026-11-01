"""Fetches a city's districts from the Wikidata query service.

Used by `scripts/sync_districts.py` only, never at request or ingestion
time: district lists are reference data that is synced, reviewed and
committed.
"""

from typing import Any

import httpx

from meinimpact.infrastructure.geo.districts import CityConfig, District

SPARQL_URL = "https://query.wikidata.org/sparql"
# Wikimedia's User-Agent policy requires a way to contact the operator.
USER_AGENT = (
    "MeinImpactBot/0.1 (+https://github.com/Emmiwinks/MeinImpact) district-sync"
)


def build_query(city: CityConfig) -> str:
    types = " ".join(f"wd:{t}" for t in city.district_types)
    return f"""
SELECT DISTINCT ?item ?name WHERE {{
  VALUES ?type {{ {types} }}
  ?item wdt:P131 wd:{city.wikidata_id} ; wdt:P31 ?type ; rdfs:label ?name .
  FILTER(LANG(?name) = "de")
}}"""


def parse_bindings(payload: dict[str, Any]) -> list[District]:
    districts = {
        binding["item"]["value"].rsplit("/", 1)[-1]: binding["name"]["value"]
        for binding in payload["results"]["bindings"]
    }
    return sorted(
        (District(name=name, wikidata_id=qid) for qid, name in districts.items()),
        key=lambda d: d.name,
    )


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
