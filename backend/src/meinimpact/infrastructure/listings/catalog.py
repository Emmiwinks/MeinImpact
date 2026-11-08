"""The configured listing sources and detail readers: the one place they
are assembled.

Adding a registry means writing its module under `sources/` and adding it
here; nothing else changes.
"""

from collections.abc import Mapping

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
from meinimpact.infrastructure.listings.sources.weact import WeActSource

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
        OParlSource(http, oparl.DRESDEN),
    ]


def default_detail_readers(http: PoliteHttpClient) -> dict[str, DetailReader]:
    """Readers for registries whose list view is too thin to enrich from.

    The Sachsen portal's teaser and WeAct's page summary already carry the
    text; their detail pages add nothing usable.
    """
    return {
        openpetition.SOURCE_ID: OpenPetitionDetailReader(http),
        eu_have_your_say.SOURCE_ID: EuHaveYourSayDetailReader(http),
        oparl.DRESDEN.source_id: OParlDetailReader(http, oparl.DRESDEN),
    }
