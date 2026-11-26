"""The configured listing sources and detail readers: the one place they
are assembled.

Which registries cover which place is declared in the place files
(`meinimpact.places`); this module turns those declarations into sources.
Adding a registry means writing its module under `sources/`, a field for
it on `Place` if it is per place, and its assembly here.
"""

import re
from collections.abc import Callable, Mapping

from meinimpact import places as covered
from meinimpact.infrastructure.geo.districts import (
    CITIES,
    DistrictMatcher,
    load_districts,
)
from meinimpact.infrastructure.geo.locality import LocalityResolver, Neighbourhoods
from meinimpact.infrastructure.geo.places import PlaceIndex
from meinimpact.infrastructure.geo.plz import PlzIndex
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.source import DetailReader, ListingSource
from meinimpact.infrastructure.listings.sources import (
    eu_have_your_say,
    openpetition,
    weact,
)
from meinimpact.infrastructure.listings.sources.eu_have_your_say import (
    EuHaveYourSayDetailReader,
    EuHaveYourSaySource,
)
from meinimpact.infrastructure.listings.sources.oparl import (
    OParlBody,
    OParlDetailReader,
    OParlSource,
)
from meinimpact.infrastructure.listings.sources.openpetition import (
    OpenPetitionDetailReader,
    OpenPetitionScope,
    OpenPetitionSource,
)
from meinimpact.infrastructure.listings.sources.sachsen_beteiligung import (
    PortalCoverage,
    SachsenBeteiligungSource,
    municipality_name,
)
from meinimpact.infrastructure.listings.sources.weact import (
    WeActDetailReader,
    WeActSource,
)

OPARL_BODIES: tuple[OParlBody, ...] = tuple(
    place.oparl for place in covered.ALL if place.oparl
)

OPENPETITION_SCOPES = tuple(
    OpenPetitionScope(place.key, place.openpetition_path)
    for place in covered.ALL
    if place.openpetition_path
)

PORTAL_LANDS: tuple[covered.Place, ...] = tuple(
    place for place in covered.ALL if place.portal
)

# Display names shown with every opportunity in the app.
SOURCE_NAMES: Mapping[str, str] = {
    openpetition.SOURCE_ID: "openPetition",
    **{land.portal.source_id: land.portal.name for land in PORTAL_LANDS if land.portal},
    eu_have_your_say.SOURCE_ID: "EU-Kommission: Ihre Meinung zählt",
    weact.SOURCE_ID: "WeAct",
    **{
        body.source_id: f"Ratsinformationssystem {body.locality}"
        for body in OPARL_BODIES
    },
}


def portal_coverage(
    land: covered.Place, index: PlaceIndex | None = None
) -> PortalCoverage:
    """The Land's portal, with every covered place inside the Land matched
    by its authority names, most specific first. A town without a place of
    its own counts for its covered Landkreis (`index` locates it; loaded
    from the place table when the Land has a covered Kreis)."""
    inside = sorted(
        (p for p in covered.ALL if p.depth > land.depth and p.ags.startswith(land.ags)),
        key=lambda p: -p.depth,
    )
    kreise = {p.ags: p.key for p in inside if p.level is covered.Level.KREIS}
    nearby: Callable[[str], str | None] | None = None
    if kreise:
        places = index or PlaceIndex.load(PlzIndex.load())

        def in_covered_kreis(authority: str) -> str | None:
            town = municipality_name(authority)
            kreis = places.kreis_of(town, land.ags) if town else None
            return kreise.get(kreis) if kreis else None

        nearby = in_covered_kreis
    return PortalCoverage(
        land=land.key,
        land_markers=land.portal_land_markers,
        local=tuple((p.key, p.authority_names) for p in inside),
        nearby=nearby,
    )


def default_sources(http: PoliteHttpClient) -> list[ListingSource]:
    return [
        *(OpenPetitionSource(http, scope) for scope in OPENPETITION_SCOPES),
        *(
            SachsenBeteiligungSource(http, land.portal, portal_coverage(land))
            for land in PORTAL_LANDS
            if land.portal
        ),
        EuHaveYourSaySource(http),
        WeActSource(http),
        *(OParlSource(http, body) for body in OPARL_BODIES),
    ]


def place_sources(http: PoliteHttpClient, place: covered.Place) -> list[ListingSource]:
    """Only the sources that can list something for `place` or a place
    inside it: its and its inner places' registries, and the portal of its
    Land. For a dry run of one place, without reading everything."""
    inside = {
        p.key
        for p in covered.ALL
        if p.depth >= place.depth and p.ags.startswith(place.ags)
    }
    lands = {p.key for p in covered.chain(place.key)} | inside
    return [
        *(
            OpenPetitionSource(http, s)
            for s in OPENPETITION_SCOPES
            if s.region in inside
        ),
        *(
            SachsenBeteiligungSource(http, land.portal, portal_coverage(land))
            for land in PORTAL_LANDS
            if land.portal and land.key in lands
        ),
        *(OParlSource(http, body) for body in OPARL_BODIES if body.region in inside),
    ]


def default_district_matchers() -> dict[str, DistrictMatcher]:
    """Each place with synced districts, by its key."""
    return {key: DistrictMatcher.for_city(city) for key, city in CITIES.items()}


def default_locality_resolver(plz: PlzIndex) -> LocalityResolver:
    """Locates opportunities with the councils' neighbourhood bodies, each
    city's synced districts and the PLZ and place tables."""
    neighbourhoods = {}
    for body in OPARL_BODIES:
        city = CITIES.get(body.region)
        if city is None or not body.neighbourhoods:
            continue
        districts = load_districts(city)
        neighbourhoods[body.region] = Neighbourhoods(
            bodies=tuple(re.compile(pattern) for pattern in body.neighbourhoods),
            districts=tuple(districts),
            matcher=DistrictMatcher(city.name, districts),
        )
    return LocalityResolver(plz, PlaceIndex.load(plz), neighbourhoods)


def default_detail_readers(http: PoliteHttpClient) -> dict[str, DetailReader]:
    """Readers for registries whose list view is too thin to enrich from.

    The Land portals' teasers already carry the text; its detail pages
    add nothing usable. WeAct's page summary often only repeats the title.
    """
    return {
        openpetition.SOURCE_ID: OpenPetitionDetailReader(http),
        eu_have_your_say.SOURCE_ID: EuHaveYourSayDetailReader(http),
        weact.SOURCE_ID: WeActDetailReader(http),
        **{body.source_id: OParlDetailReader(http, body) for body in OPARL_BODIES},
    }
