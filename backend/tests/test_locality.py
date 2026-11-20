"""Whom an opportunity concerns as a place (`geo/locality.py`)."""

import re

import pytest

from meinimpact.infrastructure.geo.districts import District, DistrictMatcher
from meinimpact.infrastructure.geo.locality import (
    NEIGHBOURHOOD_KM,
    Coverage,
    Locality,
    LocalityResolver,
    Neighbourhoods,
    Reach,
    coverage_of,
)
from meinimpact.infrastructure.geo.plz import Area, PlzIndex, PlzLocation, Point
from meinimpact.infrastructure.listings.catalog import default_locality_resolver

_DISTRICTS = (
    District("Schönfeld", "Q1", Point(51.03, 13.89)),
    District("Pieschen", "Q2", Point(51.08, 13.72)),
    District("Innere Altstadt", "Q3", Point(51.05, 13.74)),
    District("Ohne Punkt", "Q4"),
)


@pytest.fixture
def resolver() -> LocalityResolver:
    plz = PlzIndex(
        {
            "01067": PlzLocation("14612", Point(51.05, 13.73)),
            "01099": PlzLocation("14612", Point(51.08, 13.80)),
        }
    )
    hoods = Neighbourhoods(
        bodies=(
            re.compile(r"^Stadtbezirksbeirat (?P<area>.+)$"),
            re.compile(r"^Ortschaftsrat (?P<area>.+)$"),
        ),
        districts=_DISTRICTS,
        matcher=DistrictMatcher("Dresden", _DISTRICTS),
    )
    return LocalityResolver(plz, {"dresden": hoods})


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
