"""Contract checks for the place files: cheap, offline, one run for all.

Each place must be consistent with the others and with the synced data it
names; parsers are tested per shared adapter, not per place.
"""

import json
import re

import pytest

from meinimpact import places
from meinimpact.infrastructure.geo.districts import CITIES, DATA_DIR, data_file
from meinimpact.places import Level, Place, PlaceConfigError, validate

_PLACES_JSON = DATA_DIR / "places.json"


def test_registry_loads_every_level_once_for_eu_and_bund() -> None:
    levels = [place.level for place in places.ALL]

    assert levels.count(Level.EU) == 1
    assert levels.count(Level.BUND) == 1
    assert places.by_key("dresden") is not None


@pytest.mark.parametrize("place", places.ALL, ids=lambda p: p.key)
def test_place_regexes_compile(place: Place) -> None:
    if place.oparl:
        for pattern in (
            *place.oparl.bodies,
            *place.oparl.committees,
            *place.oparl.neighbourhoods,
        ):
            re.compile(pattern)


@pytest.mark.parametrize("place", places.ALL, ids=lambda p: p.key)
def test_place_districts_are_synced(place: Place) -> None:
    if place.key in CITIES:
        assert data_file(CITIES[place.key]).exists(), (
            f"run scripts/sync_districts.py {place.key}"
        )


@pytest.mark.parametrize(
    "place", [p for p in places.ALL if p.level is Level.KREIS], ids=lambda p: p.key
)
def test_kreis_ags_is_known(place: Place) -> None:
    raw = json.loads(_PLACES_JSON.read_text(encoding="utf-8"))
    assert place.ags in json.dumps(raw)


def test_validate_rejects_a_parent_that_is_missing() -> None:
    eu = places.by_key("eu")
    assert eu is not None
    orphan = Place(key="x", name="X", level=Level.LAND, ags="99", parent="nowhere")

    with pytest.raises(PlaceConfigError, match="missing"):
        validate([eu, orphan])


def test_chain_runs_from_the_place_up_to_the_eu() -> None:
    assert [p.key for p in places.chain("dresden")] == [
        "dresden",
        "sachsen",
        "bund",
        "eu",
    ]
    assert places.chain("nowhere") == ()
    assert places.chain(None) == ()


def test_a_new_place_is_a_draft_until_flipped() -> None:
    place = Place(key="x", name="X", level=Level.LAND, ags="99", parent="bund")

    assert place.status is places.Status.DRAFT
    assert not place.is_live


def test_validate_rejects_a_live_place_under_a_draft() -> None:
    eu = places.by_key("eu")
    bund = places.by_key("bund")
    assert eu and bund
    land = Place(key="land", name="L", level=Level.LAND, ags="15", parent="bund")
    town = Place(
        key="town",
        name="T",
        level=Level.KOMMUNE,
        ags="15091375",
        parent="land",
        status=places.Status.LIVE,
    )

    with pytest.raises(PlaceConfigError, match="draft"):
        validate([eu, bund, land, town])


def test_validate_rejects_an_ags_outside_the_parent() -> None:
    sachsen = places.by_key("sachsen")
    bund = places.by_key("bund")
    eu = places.by_key("eu")
    assert sachsen and bund and eu
    stray = Place(
        key="x", name="X", level=Level.KOMMUNE, ags="15091375", parent="sachsen"
    )

    with pytest.raises(PlaceConfigError, match="AGS"):
        validate([eu, bund, sachsen, stray])
