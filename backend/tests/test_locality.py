"""Whom an opportunity concerns as a place (`geo/locality.py`)."""

import re

import pytest

from meinimpact.infrastructure.geo.districts import District, DistrictMatcher
from meinimpact.infrastructure.geo.locality import (
    NEIGHBOURHOOD_KM,
    SURROUNDINGS_KM,
    Coverage,
    Locality,
    LocalityResolver,
    Neighbourhoods,
    Reach,
    coverage_of,
)
from meinimpact.infrastructure.geo.places import MIN_PLACE_KM, PlaceIndex
from meinimpact.infrastructure.geo.plz import (
    Area,
    PlzIndex,
    PlzLocation,
    Point,
    distance_km,
)
from meinimpact.infrastructure.listings.catalog import default_locality_resolver

_DISTRICTS = (
    District("Schönfeld", "Q1", Point(51.03, 13.89)),
    District("Pieschen", "Q2", Point(51.08, 13.72)),
    District("Innere Altstadt", "Q3", Point(51.05, 13.74)),
    District("Ohne Punkt", "Q4"),
)


_WEINBOEHLA = Point(51.1667, 13.5667)
_PIRNA, _SEBNITZ = Point(50.9584, 13.937), Point(50.9754, 14.2758)


@pytest.fixture
def resolver() -> LocalityResolver:
    plz = PlzIndex(
        {
            "01067": PlzLocation("14612", Point(51.05, 13.73)),
            "01099": PlzLocation("14612", Point(51.08, 13.80)),
        }
    )
    places = PlaceIndex(
        {
            "Weinböhla": [("14627", Area(_WEINBOEHLA, 0.0))],
            "Pirna": [("14628", Area(_PIRNA, 1.0))],
            "Sebnitz": [("14628", Area(_SEBNITZ, 0.0))],
        },
        {},
        plz,
    )
    hoods = Neighbourhoods(
        bodies=(
            re.compile(r"^Stadtbezirksbeirat (?P<area>.+)$"),
            re.compile(r"^Ortschaftsrat (?P<area>.+)$"),
        ),
        districts=_DISTRICTS,
        matcher=DistrictMatcher("Dresden", _DISTRICTS),
    )
    return LocalityResolver(plz, places, {"dresden": hoods})


def test_bund_and_eu_concern_everyone(resolver: LocalityResolver) -> None:
    assert resolver.of("bund", "WeAct") == Locality(gebiet="")
    assert resolver.of("eu", None) == Locality(gebiet="")


def test_a_land_matter_has_no_area(resolver: LocalityResolver) -> None:
    assert resolver.of("sachsen", None) == Locality(gebiet="14")


def test_a_city_matter_covers_the_city(resolver: LocalityResolver) -> None:
    locality = resolver.of("dresden", "Stadtrat")

    assert (locality.gebiet, locality.reach) == ("14612", Reach.CITY)
    assert locality.area is not None
    assert locality.area.centre == Point(51.065, 13.765)  # median of the PLZs


def test_a_neighbourhood_body_locates_its_part_of_the_city(
    resolver: LocalityResolver,
) -> None:
    locality = resolver.of("dresden", "Ortschaftsrat Schönfeld-Weißig")

    assert locality == Locality(
        "14612", Reach.NEIGHBOURHOOD, Area(Point(51.03, 13.89), NEIGHBOURHOOD_KM)
    )


def test_a_stadtbezirk_named_like_no_district_takes_districts_ending_in_it(
    resolver: LocalityResolver,
) -> None:
    locality = resolver.of("dresden", "Stadtbezirksbeirat Altstadt")

    assert locality.reach is Reach.NEIGHBOURHOOD
    assert locality.area is not None and locality.area.centre == Point(51.05, 13.74)


def test_an_unlocatable_neighbourhood_falls_back_to_the_city(
    resolver: LocalityResolver,
) -> None:
    for organizer in ("Ortschaftsrat Nirgendwo", "Ortschaftsrat Ohne Punkt"):
        assert resolver.of("dresden", organizer).reach is Reach.CITY


def test_a_city_wide_reach_beats_the_neighbourhood_body(
    resolver: LocalityResolver,
) -> None:
    # An Ortschaftsrat advising on the city budget
    locality = resolver.of(
        "dresden", "Ortschaftsrat Schönfeld-Weißig", Reach.CITY, ("Dresden",)
    )

    assert locality.reach is Reach.CITY
    assert locality == resolver.of("dresden", "Stadtrat")


def test_a_named_part_of_the_city_locates_a_matter_without_a_body(
    resolver: LocalityResolver,
) -> None:
    locality = resolver.of("dresden", "Stadtrat", Reach.NEIGHBOURHOOD, ("Pieschen",))

    assert locality == Locality(
        "14612", Reach.NEIGHBOURHOOD, Area(Point(51.08, 13.72), NEIGHBOURHOOD_KM)
    )


def test_an_unknown_part_of_the_city_falls_back_to_the_body(
    resolver: LocalityResolver,
) -> None:
    by_body = resolver.of("dresden", "Ortschaftsrat Schönfeld-Weißig")

    assert (
        resolver.of(
            "dresden", "Ortschaftsrat Schönfeld-Weißig", Reach.NEIGHBOURHOOD, ("Hm",)
        )
        == by_body
    )


def test_a_land_matter_in_one_place_covers_that_place(
    resolver: LocalityResolver,
) -> None:
    locality = resolver.of("sachsen", None, Reach.PLACE, ("Weinböhla",))

    assert locality == Locality("14", Reach.PLACE, Area(_WEINBOEHLA, MIN_PLACE_KM))


def test_a_surrounding_area_covers_all_its_places_and_a_margin(
    resolver: LocalityResolver,
) -> None:
    locality = resolver.of(
        "sachsen", None, Reach.SURROUNDINGS, ("Pirna", "Nirgendwo", "Sebnitz")
    )

    assert locality.gebiet == "14" and locality.reach is Reach.SURROUNDINGS
    assert locality.area is not None
    half = distance_km(_PIRNA, _SEBNITZ) / 2
    assert locality.area.km == pytest.approx(half + 2.0 + SURROUNDINGS_KM, abs=0.2)


def test_a_place_outside_the_region_or_without_reach_is_ignored(
    resolver: LocalityResolver,
) -> None:
    assert resolver.of("bund", None, Reach.PLACE, ("Nirgendwo",)) == Locality("")
    assert resolver.of("sachsen", None, None, ("Weinböhla",)) == Locality("14")


def test_a_bund_matter_in_one_place_keeps_its_gebiet(
    resolver: LocalityResolver,
) -> None:
    locality = resolver.of("bund", "WeAct", Reach.PLACE, ("Weinböhla",))

    assert locality.gebiet == ""
    assert locality.area == Area(_WEINBOEHLA, MIN_PLACE_KM)


def test_reach_of_a_stored_value() -> None:
    assert Reach.of("umland") is Reach.SURROUNDINGS
    assert Reach.of(None) is None
    assert Reach.of("galaxie") is None


def test_an_unknown_region_concerns_everyone(resolver: LocalityResolver) -> None:
    assert resolver.of("mars", None) == Locality(gebiet="")


def test_coverage_follows_the_covered_regions() -> None:
    assert coverage_of("14612") is Coverage.LOCAL  # Dresden
    assert coverage_of("14627") is Coverage.LAND  # Landkreis Meißen
    assert coverage_of("09162") is Coverage.NONE  # München


def test_the_configured_resolver_locates_dresdens_ortschaften() -> None:
    resolver = default_locality_resolver(PlzIndex.load())

    village = resolver.of("dresden", "Ortschaftsrat Schönfeld-Weißig")
    city = resolver.of("dresden", "Stadtrat")

    assert village.reach is Reach.NEIGHBOURHOOD
    assert city.reach is Reach.CITY
    assert village.area is not None and city.area is not None
    assert village.area.km < city.area.km


def test_the_configured_resolver_locates_saxon_places_from_the_prod_pool() -> None:
    resolver = default_locality_resolver(PlzIndex.load())

    school = resolver.of("sachsen", None, Reach.PLACE, ("Weinböhla",))
    railway = resolver.of(
        "sachsen", None, Reach.SURROUNDINGS, ("Pirna", "Neustadt (Sachsen)", "Sebnitz")
    )
    region = resolver.of("sachsen", None, Reach.SURROUNDINGS, ("Erzgebirgskreis",))

    assert school.area is not None and school.area.km < 5
    assert railway.area is not None and 15 < railway.area.km < 30
    assert region.area is not None and region.area.km > 20


_WITTENBERG = Point(51.866, 12.646)


def test_a_town_inside_a_kreis_is_its_own_place_and_the_kreis_its_surroundings() -> (
    None
):
    plz = PlzIndex(
        {
            "06886": PlzLocation("15091", _WITTENBERG),
            "06925": PlzLocation("15091", Point(51.76, 13.05)),
        }
    )
    places = PlaceIndex({"Wittenberg": [("15091", Area(_WITTENBERG, 3.0))]}, {}, plz)
    resolver = LocalityResolver(plz, places)

    town = resolver.of("wittenberg", "Lutherstadt Wittenberg")
    kreis = resolver.of("lk-wittenberg", "Landkreis Wittenberg")

    assert town == Locality("15091375", Reach.PLACE, Area(_WITTENBERG, 3.0))
    assert kreis.gebiet == "15091"
    assert kreis.reach is Reach.SURROUNDINGS
    assert kreis.area == plz.kreis_area("15091")


def test_a_kreis_matter_in_one_of_its_towns_lies_at_that_town() -> None:
    graefenhainichen = Point(51.73, 12.45)
    plz = PlzIndex({"06886": PlzLocation("15091", _WITTENBERG)})
    places = PlaceIndex(
        {"Gräfenhainichen": [("15091", Area(graefenhainichen, 2.5))]}, {}, plz
    )
    resolver = LocalityResolver(plz, places)

    plan = resolver.of(
        "lk-wittenberg", "Stadt Gräfenhainichen", Reach.PLACE, ("Gräfenhainichen",)
    )

    assert plan == Locality("15091", Reach.PLACE, Area(graefenhainichen, 2.5))
    assert places.kreis_of("Gräfenhainichen", "15") == "15091"
    assert places.kreis_of("Gräfenhainichen", "14") is None


def test_a_merged_municipality_is_found_by_its_parts() -> None:
    plz = PlzIndex({})
    point = Area(Point(51.8, 12.4), 2.0)
    places = PlaceIndex(
        {
            "Oranienbaum": [("15091", point)],
            "Wörlitz": [("15091", point)],
            "Bitterfeld": [("15082", point)],
            "Wolfen": [("15082", point)],
            "Grenzdorf": [("15082", point)],
        },
        {},
        plz,
    )

    assert places.kreis_of("Oranienbaum-Wörlitz", "15") == "15091"
    assert places.kreis_of("Bitterfeld-Wolfen", "15") == "15082"
    assert places.kreis_of("Oranienbaum-Unbekannt", "15") is None
    assert places.kreis_of("Wörlitz-Grenzdorf", "15") is None  # two Kreise
