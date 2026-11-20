"""The configured listing sources and detail readers: the one place they
are assembled.

Adding a registry means writing its module under `sources/` and adding it
here; nothing else changes.
"""

import re
from collections.abc import Mapping

from meinimpact.infrastructure.geo.districts import (
    CITIES,
    DistrictMatcher,
    load_districts,
)
from meinimpact.infrastructure.geo.locality import LocalityResolver, Neighbourhoods
from meinimpact.infrastructure.geo.plz import PlzIndex
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import Region
from meinimpact.infrastructure.listings.source import DetailReader, ListingSource
from meinimpact.infrastructure.listings.sources import (
    eu_have_your_say,
    oparl,
    openpetition,
    sachsen_beteiligung,
    weact,
)
from meinimpact.infrastructure.listings.sources.eu_have_your_say import (
    EuHaveYourSayDetailReader,
    EuHaveYourSaySource,
)
from meinimpact.infrastructure.listings.sources.oparl import (
    OParlDetailReader,
    OParlSource,
)
from meinimpact.infrastructure.listings.sources.openpetition import (
    OpenPetitionDetailReader,
    OpenPetitionScope,
    OpenPetitionSource,
)
from meinimpact.infrastructure.listings.sources.sachsen_beteiligung import (
    SachsenBeteiligungSource,
)
from meinimpact.infrastructure.listings.sources.weact import (
    WeActDetailReader,
    WeActSource,
)

OPARL_BODIES = (oparl.DRESDEN,)

OPENPETITION_SCOPES = (
    OpenPetitionScope(Region.BUND, "/region/petition/Deutschland"),
    OpenPetitionScope(Region.SACHSEN, "/region/petition/Sachsen"),
    OpenPetitionScope(Region.DRESDEN, "/region/petition/Dresden"),
)

# Display names shown with every opportunity in the app.
SOURCE_NAMES: Mapping[str, str] = {
    openpetition.SOURCE_ID: "openPetition",
    sachsen_beteiligung.SOURCE_ID: "Beteiligungsportal Sachsen",
    eu_have_your_say.SOURCE_ID: "EU-Kommission: Ihre Meinung zählt",
    weact.SOURCE_ID: "WeAct",
    oparl.DRESDEN.source_id: "Ratsinformationssystem Dresden",
}


def default_sources(http: PoliteHttpClient) -> list[ListingSource]:
    return [
        *(OpenPetitionSource(http, scope) for scope in OPENPETITION_SCOPES),
        SachsenBeteiligungSource(http),
        EuHaveYourSaySource(http),
        WeActSource(http),
        *(OParlSource(http, body) for body in OPARL_BODIES),
    ]


def default_locality_resolver(plz: PlzIndex) -> LocalityResolver:
    """Locates opportunities with the councils' neighbourhood bodies, each
    city's synced districts and the PLZ table."""
    neighbourhoods = {}
    for body in OPARL_BODIES:
        city = CITIES.get(body.region.value)
        if city is None or not body.neighbourhoods:
            continue
        districts = load_districts(city)
        neighbourhoods[body.region.value] = Neighbourhoods(
            bodies=tuple(re.compile(pattern) for pattern in body.neighbourhoods),
            districts=tuple(districts),
            matcher=DistrictMatcher(city.name, districts),
        )
    return LocalityResolver(plz, neighbourhoods)


def default_detail_readers(http: PoliteHttpClient) -> dict[str, DetailReader]:
    """Readers for registries whose list view is too thin to enrich from.

    The Sachsen portal's teaser already carries the text; its detail pages
    add nothing usable. WeAct's page summary often only repeats the title.
    """
    return {
        openpetition.SOURCE_ID: OpenPetitionDetailReader(http),
        eu_have_your_say.SOURCE_ID: EuHaveYourSayDetailReader(http),
        weact.SOURCE_ID: WeActDetailReader(http),
        oparl.DRESDEN.source_id: OParlDetailReader(http, oparl.DRESDEN),
    }
