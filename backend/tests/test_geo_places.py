"""Locating named municipalities and Kreise (`geo/places.py`)."""

import pytest

from meinimpact.infrastructure.geo.places import MIN_PLACE_KM, PlaceIndex
from meinimpact.infrastructure.geo.plz import Area, PlzIndex, PlzLocation, Point

_SCHOENBORN_BB = Point(51.6, 13.49)
_SCHOENBORN_RP = Point(49.95, 7.47)
_NEUSTADT_SN = Point(51.03, 14.22)
_NEUSTADT_VOGTLAND = Point(50.47, 12.33)
_WEISSWASSER = Point(51.5, 14.64)


@pytest.fixture
def index() -> PlaceIndex:
    plz = PlzIndex(
        {
            "08280": PlzLocation("14521", Point(50.6, 12.7)),
            "09456": PlzLocation("14521", Point(50.5, 13.0)),
            "08056": PlzLocation("14524", Point(50.72, 12.49)),
        }
    )
    return PlaceIndex(
        {
            "Schönborn": [
                ("12062", Area(_SCHOENBORN_BB, 0.0)),
                ("07140", Area(_SCHOENBORN_RP, 0.0)),
            ],
            "Neustadt in Sachsen": [("14628", Area(_NEUSTADT_SN, 0.0))],
            "Neustadt/Vogtland": [("14523", Area(_NEUSTADT_VOGTLAND, 0.0))],
            "Weißwasser": [("14626", Area(_WEISSWASSER, 3.5))],
        },
        {"Erzgebirgskreis": "14521", "Landkreis Zwickau": "14524"},
        plz,
    )


def test_a_one_point_village_still_reaches_its_houses(index: PlaceIndex) -> None:
    area = index.locate("Neustadt in Sachsen")

    assert area == Area(_NEUSTADT_SN, MIN_PLACE_KM)


def test_a_larger_place_keeps_its_own_reach(index: PlaceIndex) -> None:
    assert index.locate("Weißwasser") == Area(_WEISSWASSER, 3.5)


def test_a_name_in_several_kreise_is_located_only_within_the_gebiet(
    index: PlaceIndex,
) -> None:
    assert index.locate("Schönborn") is None
    assert index.locate("Schönborn", "12") == Area(_SCHOENBORN_BB, MIN_PLACE_KM)
    assert index.locate("Schönborn", "14") is None


def test_differently_written_names_are_matched_loosely(index: PlaceIndex) -> None:
    assert index.locate("Neustadt (Sachsen)", "14") == Area(_NEUSTADT_SN, MIN_PLACE_KM)
    assert index.locate("Weißwasser/Oberlausitz", "14") == Area(_WEISSWASSER, 3.5)
    # Two Saxon Neustadts: the bare name says too little
    assert index.locate("Neustadt", "14") is None


def test_a_kreis_is_located_by_its_plz_area(index: PlaceIndex) -> None:
    area = index.locate("Erzgebirgskreis", "14")

    assert area is not None and area.km > 5
    assert index.locate("Erzgebirgskreis", "09") is None


def test_a_kreis_may_be_named_without_its_kind(index: PlaceIndex) -> None:
    area = index.locate("Landkreis Zwickau")

    assert area is not None
    assert index.locate("Zwickau", "14") == area


def test_committed_table_locates_places_from_the_prod_pool() -> None:
    index = PlaceIndex.load(PlzIndex.load())

    for name in ("Weinböhla", "Moritzburg", "Pausa", "Boxberg/Oberlausitz"):
        assert index.locate(name, "14") is not None, name
    assert index.locate("Erzgebirgskreis", "14") is not None
    assert index.locate("Pöllwitz", "14") is None  # a village in Thüringen
