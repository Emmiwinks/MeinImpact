"""District reference data, matching and the Wikidata sync source."""

import httpx
import pytest

from meinimpact.infrastructure.geo.districts import (
    CITIES,
    District,
    DistrictMatcher,
    load_districts,
)
from meinimpact.infrastructure.geo.wikidata import (
    WikidataDistrictSource,
    build_query,
    parse_bindings,
)

_DISTRICTS = [
    District("Mockritz", "Q1"),
    District("Plauen", "Q2"),
    District("Südvorstadt", "Q3"),
    District("Südvorstadt-Ost", "Q4"),
    District("Äußere Neustadt", "Q5"),
    District("Leubnitz", "Q6"),
    District("Leubnitz-Neuostra", "Q7"),
]


@pytest.fixture
def matcher() -> DistrictMatcher:
    return DistrictMatcher("Dresden", _DISTRICTS)


def test_finds_compound_and_bare_names_in_order(matcher: DistrictMatcher) -> None:
    text = (
        "Bebauungsplan Nr. 6065, Dresden-Mockritz, Wohnbebauung. "
        "Auch Plauen ist betroffen, ebenso Dresden-Mockritz erneut."
    )

    assert matcher.find(text) == ("Mockritz", "Plauen")


def test_prefers_the_longest_district_name(matcher: DistrictMatcher) -> None:
    assert matcher.find("Dresden-Südvorstadt-Ost") == ("Südvorstadt-Ost",)
    assert matcher.find("in Leubnitz-Neuostra") == ("Leubnitz-Neuostra",)
    assert matcher.find("in der Äußeren Neustadt") == ()  # inflected: no guess


def test_ignores_names_inside_other_words(matcher: DistrictMatcher) -> None:
    assert matcher.find("Plauener Straße, Mockritzer Bach, plauen") == ()


def test_committed_dresden_data_loads_and_covers_known_districts() -> None:
    districts = load_districts(CITIES["dresden"])
    names = {d.name for d in districts}

    assert len(districts) > 100
    assert {"Mockritz", "Hellerau", "Äußere Neustadt", "Gorbitz"} <= names


def test_wikidata_query_and_parsing() -> None:
    query = build_query(CITIES["dresden"])
    payload = {
        "results": {
            "bindings": [
                {
                    "item": {"value": "http://www.wikidata.org/entity/Q2"},
                    "name": {"value": "Plauen"},
                },
                {
                    "item": {"value": "http://www.wikidata.org/entity/Q1"},
                    "name": {"value": "Mockritz"},
                },
                {
                    "item": {"value": "http://www.wikidata.org/entity/Q1"},
                    "name": {"value": "Mockritz"},
                },
            ]
        }
    }

    assert "wd:Q1731" in query and "wd:Q253019" in query
    assert parse_bindings(payload) == [
        District("Mockritz", "Q1"),
        District("Plauen", "Q2"),
    ]


async def test_wikidata_source_identifies_itself_with_contact() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"results": {"bindings": []}})

    source = WikidataDistrictSource(
        httpx.AsyncClient(transport=httpx.MockTransport(handler))
    )

    assert await source.fetch(CITIES["dresden"]) == []
    assert "github.com" in seen[0].headers["User-Agent"]
    await source.aclose()
