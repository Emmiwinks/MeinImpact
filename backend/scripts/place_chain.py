#!/usr/bin/env python3
"""Step 1 of adding a place: its chain of levels, from Wikidata.

Finds municipalities Wikidata's search returns for the name, and for each
prints Kommune -> Landkreis -> Land with AGS, Wikidata id, Ortsteil count,
whether the PLZ/place table locates it, and whether a place file exists.
Read-only; one Wikidata query per level.

  docker compose exec api python scripts/place_chain.py "Wittenberg"
"""

import sys
from typing import Any

import httpx

from meinimpact import places
from meinimpact.infrastructure.geo.places import PlaceIndex
from meinimpact.infrastructure.geo.plz import PlzIndex
from meinimpact.infrastructure.geo.wikidata import USER_AGENT

_SPARQL = "https://query.wikidata.org/sparql"
_SEARCH = "https://www.wikidata.org/w/api.php"
ORTSTEIL = "Q253019"


def _query(client: httpx.Client, sparql: str) -> list[dict[str, str]]:
    response = client.get(_SPARQL, params={"query": sparql, "format": "json"})
    response.raise_for_status()
    rows: list[dict[str, Any]] = response.json()["results"]["bindings"]
    return [{k: v["value"] for k, v in row.items()} for row in rows]


def _qid(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def _one(client: httpx.Client, prop: str, key: str) -> tuple[str, str] | None:
    """(QID, label) of the item whose `prop` is `key`, if exactly one."""
    rows = _query(
        client,
        f"""SELECT ?item ?itemLabel WHERE {{ ?item wdt:{prop} "{key}" .
        SERVICE wikibase:label {{ bd:serviceParam wikibase:language "de". }} }}""",
    )
    return (_qid(rows[0]["item"]), rows[0]["itemLabel"]) if len(rows) == 1 else None


def _land(client: httpx.Client, qid: str) -> tuple[str, str] | None:
    """The Bundesland (Q1221156) the Kreis or kreisfreie Stadt lies in."""
    rows = _query(
        client,
        f"""SELECT ?land ?landLabel WHERE {{ wd:{qid} wdt:P131+ ?land .
        ?land wdt:P31 wd:Q1221156 .
        SERVICE wikibase:label {{ bd:serviceParam wikibase:language "de". }} }}""",
    )
    return (_qid(rows[0]["land"]), rows[0]["landLabel"]) if len(rows) == 1 else None


def _located_as(index: PlaceIndex, label: str, kreis: str) -> str | None:
    """The name under which the place table knows the town: its label, or
    one word of it ("Lutherstadt Wittenberg" may be just "Wittenberg")."""
    for name in (label, *sorted(label.split(), key=len, reverse=True)):
        if len(name) > 3 and index.locate(name, kreis) is not None:
            return name
    return None


def _file(ags: str) -> str:
    match = next((p for p in places.ALL if p.ags == ags), None)
    return f"file exists ({match.key}, {match.status})" if match else "new"


def _candidates(client: httpx.Client, name: str) -> list[str]:
    """QIDs Wikidata's own search finds for the name (a label query over
    every municipality times out)."""
    response = client.get(
        _SEARCH,
        params={
            "action": "wbsearchentities",
            "search": name,
            "language": "de",
            "type": "item",
            "limit": 30,
            "format": "json",
        },
    )
    response.raise_for_status()
    return [hit["id"] for hit in response.json().get("search", [])]


def main(name: str) -> None:
    index = PlaceIndex.load(PlzIndex.load())
    with httpx.Client(headers={"User-Agent": USER_AGENT}, timeout=60) as client:
        values = " ".join(f"wd:{qid}" for qid in _candidates(client, name))
        towns = (
            _query(
                client,
                f"""SELECT ?item ?label ?ags WHERE {{ VALUES ?item {{ {values} }}
                ?item wdt:P439 ?ags ; rdfs:label ?label .
                FILTER(LANG(?label) = "de" && STRLEN(?ags) = 8) }}""",
            )
            if values
            else []
        )
        if not towns:
            raise SystemExit(f"no municipality with {name!r} in its German label")
        for town in towns:
            ags, qid = town["ags"], _qid(town["item"])
            kreis = _one(client, "P440", ags[:5])
            land = _land(client, kreis[0] if kreis else qid)
            ortsteile = _query(
                client,
                f"""SELECT (COUNT(?d) AS ?n) WHERE {{
                ?d wdt:P31 wd:{ORTSTEIL} ; wdt:P131 wd:{qid} }}""",
            )[0]["n"]
            kreisfrei = kreis is not None and kreis[0] == qid
            located = _located_as(index, town["label"], ags[:5])
            table = f"located as {located!r}" if located else "NOT located"
            print(f"\n{town['label']}")
            print(
                f"  Kommune  {ags}  {qid}  {ortsteile} Ortsteile  {table} in "
                f"places.json  {_file(ags[:5] if kreisfrei else ags)}"
            )
            if kreisfrei:
                print("  Landkreis  none (kreisfreie Stadt: its AGS is the Kreis key)")
            elif kreis:
                print(
                    f"  Landkreis  {ags[:5]}  {kreis[0]}  {kreis[1]}  {_file(ags[:5])}"
                )
            else:
                print(f"  Landkreis  {ags[:5]}  not found in Wikidata")
            if land:
                print(f"  Land     {ags[:2]}  {land[0]}  {land[1]}  {_file(ags[:2])}")
            else:
                print(f"  Land     {ags[:2]}  not found in Wikidata")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit('usage: place_chain.py "<name>"')
    main(sys.argv[1])
