"""Parser tests for each listing source, against trimmed real registry pages.

Fixtures in tests/fixtures/listings/ were cut from the live pages on
2026-11-01 (signer names anonymized). When a registry changes its markup,
refresh the fixture and these tests show exactly what broke.
"""

import json
from datetime import UTC, date, datetime
from pathlib import Path

from meinimpact.infrastructure.listings.catalog import portal_coverage
from meinimpact.infrastructure.listings.model import (
    ActionKind,
    ListingStatus,
)
from meinimpact.infrastructure.listings.sources import (
    eu_have_your_say,
    openpetition,
    sachsen_beteiligung,
    weact,
)
from meinimpact.infrastructure.listings.sources.sachsen_beteiligung import (
    PortalCoverage,
)
from meinimpact.places.defs import sachsen

FIXTURES = Path(__file__).parent / "fixtures" / "listings"
NOW = datetime(2026, 11, 1, 12, 0, tzinfo=UTC)
SACHSEN = portal_coverage(sachsen.PLACE).region_for
assert sachsen.PLACE.portal is not None
SITE = sachsen.PLACE.portal


def _fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


# --- openPetition -----------------------------------------------------------


def test_openpetition_parses_every_card() -> None:
    listings = openpetition.parse_listing_page(
        _fixture("openpetition_listing.html"), region="bund", observed_at=NOW
    )

    assert len(listings) == 3
    first = listings[0]
    assert first.title.startswith("Für den Erhalt einer sicheren")
    assert first.url.startswith("https://www.openpetition.de/petition/online/")
    assert first.external_id == (
        "fuer-den-erhalt-einer-sicheren-individuellen-geburtshilfe-"
        "stoppt-den-neuen-hebammenhilfevertrag-2"
    )
    assert first.kind is ActionKind.PETITION
    assert first.status is ListingStatus.OPEN
    assert first.region == "bund"
    assert first.locality == "Deutschland"
    assert first.closes_on == date(2026, 11, 30)
    assert first.support.count == 548_769
    assert first.source_labels == ("Gesundheit",)


def test_openpetition_reads_partner_signatures_separately() -> None:
    listings = openpetition.parse_listing_page(
        _fixture("openpetition_listing.html"), region="bund", observed_at=NOW
    )

    veto = listings[1]
    assert veto.support.count == 434_881
    assert veto.support.partner_count == 40_942
    assert listings[0].support.partner_count is None


def test_openpetition_card_without_days_left_is_not_assumed_open() -> None:
    html = _fixture("openpetition_listing.html").replace("petition-days-left", "x")

    listings = openpetition.parse_listing_page(html, region="bund", observed_at=NOW)

    assert all(item.status is ListingStatus.UNKNOWN for item in listings)
    assert all(item.closes_on is None for item in listings)


def test_openpetition_card_past_collection_is_closed() -> None:
    """Region pages list ended petitions too, counting days since the end."""
    html = (
        _fixture("openpetition_listing.html")
        .replace(' title="Montag, 30. November 2026"', "")
        .replace("29 Tage", "346 Tage")
    )

    first = openpetition.parse_listing_page(html, region="dresden", observed_at=NOW)[0]

    assert first.status is ListingStatus.CLOSED
    assert first.closes_on is None


# --- Beteiligungsportal Sachsen ---------------------------------------------


def test_sachsen_parses_teasers_with_authority_region_and_dates() -> None:
    listings = sachsen_beteiligung.parse_teasers(
        _fixture("sachsen_listing.html"),
        site=SITE,
        observed_at=NOW,
        resolve_region=SACHSEN,
    )

    assert len(listings) == 3
    assert {item.source_id for item in listings} == {"beteiligung-sachsen"}
    event, _, survey = listings
    assert event.organizer == "Landeshauptstadt Dresden"
    assert event.region == "dresden"
    assert event.kind is ActionKind.EVENT
    assert event.status is ListingStatus.ANNOUNCED
    assert event.opens_on == event.closes_on == date(2026, 12, 4)
    assert event.url.startswith("https://buergerbeteiligung.sachsen.de/portal/")

    assert survey.organizer == "Stadt Oelsnitz/Vogtl."
    assert survey.region is None  # another municipality: outside coverage
    assert survey.kind is ActionKind.SURVEY
    assert survey.status is ListingStatus.OPEN
    assert (survey.opens_on, survey.closes_on) == (
        date(2026, 10, 30),
        date(2026, 12, 6),
    )
    assert survey.support.count == 6
    assert "Stadtentwicklung und Ländlicher Raum" in survey.source_labels


def test_sachsen_event_free_seats_are_not_counted_as_participants() -> None:
    event = sachsen_beteiligung.parse_teasers(
        _fixture("sachsen_listing.html"),
        site=SITE,
        observed_at=NOW,
        resolve_region=SACHSEN,
    )[0]

    assert event.support.count is None


def test_sachsen_reads_total_and_view_state_for_pagination() -> None:
    html = _fixture("sachsen_listing.html")

    assert sachsen_beteiligung.parse_total(html) == 786
    assert sachsen_beteiligung.parse_view_state(html)


def test_sachsen_partial_response_yields_the_next_page() -> None:
    fragment = sachsen_beteiligung.parse_partial_response(_fixture("sachsen_page2.xml"))

    listings = sachsen_beteiligung.parse_teasers(
        fragment, site=SITE, observed_at=NOW, resolve_region=SACHSEN
    )

    assert len(listings) == 2
    assert listings[0].title.startswith("Besichtigungstermin")


def test_sachsen_partial_response_without_list_update_is_empty() -> None:
    assert sachsen_beteiligung.parse_partial_response("<partial-response/>") == ""


def test_sachsen_region_for_authority() -> None:
    assert SACHSEN("Landeshauptstadt Dresden") == "dresden"
    assert SACHSEN("Landesdirektion Sachsen") == "sachsen"
    assert SACHSEN("Sächsisches Staatsministerium für Kultus") == "sachsen"
    assert SACHSEN("Landratsamt Sächsische Schweiz-Osterzgebirge") is None
    assert SACHSEN("Stadt Leipzig") is None


def test_a_town_without_a_place_file_counts_for_its_covered_kreis() -> None:
    from meinimpact.infrastructure.geo.places import PlaceIndex
    from meinimpact.infrastructure.geo.plz import Area, PlzIndex, Point
    from meinimpact.places.defs import sachsen_anhalt

    plz = PlzIndex({})
    index = PlaceIndex(
        {
            "Gräfenhainichen": [("15091", Area(Point(51.73, 12.45), 2.5))],
            "Zerbst/Anhalt": [("15082", Area(Point(51.97, 12.08), 3.0))],
        },
        {},
        plz,
    )
    resolve = portal_coverage(sachsen_anhalt.PLACE, index).region_for

    assert resolve("Stadt Gräfenhainichen") == "lk-wittenberg"
    assert resolve("Einheitsgemeinde Stadt Gräfenhainichen") == "lk-wittenberg"
    assert resolve("Stadt Zerbst/Anhalt") is None  # Kreis not covered
    assert resolve("Verbandsgemeinde Saale-Wipper") is None
    assert resolve("Lutherstadt Wittenberg") == "wittenberg"
    assert resolve("Landkreis Wittenberg") == "lk-wittenberg"
    assert resolve("Ministerium für Infrastruktur und Digitales") == "sachsen-anhalt"


def test_municipality_names_lose_their_prefix() -> None:
    name = sachsen_beteiligung.municipality_name

    assert name("Stadt Halle (Saale)") == "Halle (Saale)"
    assert name("Welterbestadt Quedlinburg") == "Quedlinburg"
    assert name("Landkreis Stendal") is None
    assert name("Verbandsgemeinde Beetzendorf-Diesdorf") is None


def test_portal_coverage_prefers_the_most_specific_place() -> None:
    """A Kreis town is matched before its Landkreis, whose name it shares."""
    coverage = PortalCoverage(
        land="anhalt",
        land_markers=("Ministerium",),
        local=(("town", ("Lutherstadt Wittenberg",)), ("kreis", ("Wittenberg",))),
    )

    assert coverage.region_for("Lutherstadt Wittenberg") == "town"
    assert coverage.region_for("Landkreis Wittenberg") == "kreis"
    assert coverage.region_for("Stadt Gräfenhainichen") is None
    assert coverage.region_for("Ministerium für Infrastruktur") == "anhalt"


# --- EU Have your say -------------------------------------------------------


def test_eu_parses_open_initiatives_with_german_titles() -> None:
    payload = json.loads(_fixture("eu_have_your_say.json"))

    listings, is_last = eu_have_your_say.parse_search_page(payload, observed_at=NOW)

    assert len(listings) == 3
    assert is_last is False
    first = listings[0]
    assert first.external_id == "16240"
    assert first.title.startswith("EU-Emissionshandelssystem")
    assert first.url.endswith("/initiatives/16240_de")
    assert first.kind is ActionKind.CONSULTATION
    assert first.status is ListingStatus.OPEN
    assert first.region == "eu"
    assert (first.opens_on, first.closes_on) == (date(2026, 10, 30), date(2026, 11, 27))
    assert first.source_labels == ("Climate action",)


def test_eu_falls_back_to_short_title_without_german_translation() -> None:
    payload = json.loads(_fixture("eu_have_your_say.json"))
    for item in payload["initiativeResultDtoPage"]["content"]:
        item["initiativeTranslations"] = []

    listings, _ = eu_have_your_say.parse_search_page(payload, observed_at=NOW)

    assert listings[0].title.startswith("States considered to be applying CORSIA")


# --- WeAct ------------------------------------------------------------------


def test_weact_index_yields_unique_canonical_petition_urls() -> None:
    urls = weact.parse_index(_fixture("weact_index.html"))

    assert urls == [
        "https://weact.campact.de/petitions/keine-kurzungen-beim-wohngeld",
        "https://weact.campact.de/petitions/aktionsplan-gegen-gewalt-an-kindern-jetzt",
        "https://weact.campact.de/petitions/spd-stoppt-den-frontalangriff-auf-die-informationsfreiheit",
    ]


def test_weact_petition_reads_store_and_drops_signer_names() -> None:
    url = "https://weact.campact.de/petitions/keine-kurzungen-beim-wohngeld"

    listing = weact.parse_petition(
        _fixture("weact_petition.html"), url=url, observed_at=NOW
    )

    assert listing is not None
    assert listing.title == "Keine Kürzungen beim Wohngeld!"
    assert listing.external_id == "keine-kurzungen-beim-wohngeld"
    assert listing.status is ListingStatus.OPEN
    assert listing.support.count == 58_500
    assert listing.support.goal == 75_000
    assert len(listing.support.recent_activity) == 10
    assert listing.support.recent_activity == tuple(
        sorted(listing.support.recent_activity, reverse=True)
    )
    assert "Anon" not in repr(listing)
    assert listing.summary and listing.summary.startswith("Die Bundesregierung")


def test_weact_closed_petition() -> None:
    html = _fixture("weact_petition.html").replace(
        "&quot;signatureFormHidden&quot;:false", "&quot;signatureFormHidden&quot;:true"
    )

    listing = weact.parse_petition(html, url="https://x/petitions/y", observed_at=NOW)

    assert listing is not None
    assert listing.status is ListingStatus.CLOSED


def test_weact_petition_text_names_addressees_and_demands() -> None:
    # Trimmed from the live page: the summary there only repeats the title.
    html = """
    <div class="main-column"><div class="petition-content">
      <h2 class="who mt-3">An: An die Bundesregierung sowie die
        Ministerpräsident*innen aller deutschen Bundesländer</h2>
      <div class="campaign-text embedly">
        <h1>Jetzt Menschen aus Sachsen-Anhalt aufnehmen!</h1>
        <div class="intro-copy what"><div class="trix-content">
          Wir fordern die Aufnahme von Menschen, die Sachsen-Anhalt jetzt
          verlassen möchten!
        </div></div>
      </div>
      <form><button>Unterschreiben</button></form>
    </div></div>
    """

    text = weact.parse_petition_text(html)

    assert text is not None
    assert "Ministerpräsident*innen aller deutschen Bundesländer" in text
    assert "Sachsen-Anhalt jetzt verlassen" in text
    assert "Unterschreiben" not in text
    assert weact.parse_petition_text("<html></html>") is None


def test_weact_page_without_store_is_skipped() -> None:
    assert weact.parse_petition("<html></html>", url="u", observed_at=NOW) is None
