"""The configured listing sources and detail readers: the one place they
are assembled.

Which registries cover which place is declared in the place files
(`meinimpact.places`); this module turns those declarations into sources.
Adding a registry means writing its module under `sources/`, a field for
it on `Place` if it is per place, and its assembly here.
"""

import re
from collections.abc import Mapping

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
    sachsen_beteiligung,
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

# Display names shown with every opportunity in the app.
SOURCE_NAMES: Mapping[str, str] = {
    openpetition.SOURCE_ID: "openPetition",
    sachsen_beteiligung.SOURCE_ID: "Beteiligungsportal Sachsen",
    eu_have_your_say.SOURCE_ID: "EU-Kommission: Ihre Meinung zählt",
    weact.SOURCE_ID: "WeAct",
    **{
        body.source_id: f"Ratsinformationssystem {body.locality}"
        for body in OPARL_BODIES
    },
}


def portal_coverage(land: covered.Place) -> PortalCoverage:
    """The Land's portal, with every covered place inside the Land matched
    by its authority names, most specific first."""
    inside = sorted(
        (p for p in covered.ALL if p.depth > land.depth and p.ags.startswith(land.ags)),
        key=lambda p: -p.depth,
    )
    return PortalCoverage(
        land=land.key,
        land_markers=land.portal_land_markers,
        local=tuple((p.key, p.authority_names) for p in inside),
    )


def default_sources(http: PoliteHttpClient) -> list[ListingSource]:
    sachsen = covered.by_key("sachsen")
    return [
        *(OpenPetitionSource(http, scope) for scope in OPENPETITION_SCOPES),
        *(
            [SachsenBeteiligungSource(http, portal_coverage(sachsen))]
            if sachsen
            else []
        ),
        EuHaveYourSaySource(http),
        WeActSource(http),
        *(OParlSource(http, body) for body in OPARL_BODIES),
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

    The Sachsen portal's teaser already carries the text; its detail pages
    add nothing usable. WeAct's page summary often only repeats the title.
    """
    return {
        openpetition.SOURCE_ID: OpenPetitionDetailReader(http),
        eu_have_your_say.SOURCE_ID: EuHaveYourSayDetailReader(http),
        weact.SOURCE_ID: WeActDetailReader(http),
        **{body.source_id: OParlDetailReader(http, body) for body in OPARL_BODIES},
    }
