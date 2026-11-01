"""Parser tests for each listing source, against trimmed real registry pages.

Fixtures in tests/fixtures/listings/ were cut from the live pages on
2026-11-01 (signer names anonymized). When a registry changes its markup,
refresh the fixture and these tests show exactly what broke.
"""

import json
from datetime import UTC, date, datetime
from pathlib import Path

from meinimpact.infrastructure.listings.model import (
    ActionKind,
    ListingStatus,
    Region,
)
from meinimpact.infrastructure.listings.sources import (
    eu_have_your_say,
    openpetition,
    sachsen_beteiligung,
    weact,
)

FIXTURES = Path(__file__).parent / "fixtures" / "listings"
NOW = datetime(2026, 11, 1, 12, 0, tzinfo=UTC)


def _fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


# --- openPetition -----------------------------------------------------------


def test_openpetition_parses_every_card() -> None:
    listings = openpetition.parse_listing_page(
        _fixture("openpetition_listing.html"), region=Region.BUND, observed_at=NOW
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
    assert first.region is Region.BUND
    assert first.locality == "Deutschland"
    assert first.closes_on == date(2026, 11, 30)
    assert first.support.count == 548_769
    assert first.source_labels == ("Gesundheit",)


def test_openpetition_reads_partner_signatures_separately() -> None:
    listings = openpetition.parse_listing_page(
        _fixture("openpetition_listing.html"), region=Region.BUND, observed_at=NOW
    )

    veto = listings[1]
    assert veto.support.count == 434_881
    assert veto.support.partner_count == 40_942
    assert listings[0].support.partner_count is None


def test_openpetition_card_without_days_left_is_not_assumed_open() -> None:
    html = _fixture("openpetition_listing.html").replace("petition-days-left", "x")

    listings = openpetition.parse_listing_page(
        html, region=Region.BUND, observed_at=NOW
    )

    assert all(item.status is ListingStatus.UNKNOWN for item in listings)
    assert all(item.closes_on is None for item in listings)


def test_openpetition_card_past_collection_is_closed() -> None:
    """Region pages list ended petitions too, counting days since the end."""
    html = (
        _fixture("openpetition_listing.html")
        .replace(' title="Montag, 30. November 2026"', "")
        .replace("29 Tage", "346 Tage")
    )

    first = openpetition.parse_listing_page(
        html, region=Region.DRESDEN, observed_at=NOW
    )[0]

    assert first.status is ListingStatus.CLOSED
    assert first.closes_on is None


# --- Beteiligungsportal Sachsen ---------------------------------------------


def test_sachsen_parses_teasers_with_authority_region_and_dates() -> None:
    listings = sachsen_beteiligung.parse_teasers(
        _fixture("sachsen_listing.html"), observed_at=NOW
    )

    assert len(listings) == 3
    event, _, survey = listings
    assert event.organizer == "Landeshauptstadt Dresden"
    assert event.region is Region.DRESDEN
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
        _fixture("sachsen_listing.html"), observed_at=NOW
    )[0]

    assert event.support.count is None


def test_sachsen_reads_total_and_view_state_for_pagination() -> None:
    html = _fixture("sachsen_listing.html")

    assert sachsen_beteiligung.parse_total(html) == 786
    assert sachsen_beteiligung.parse_view_state(html)


def test_sachsen_partial_response_yields_the_next_page() -> None:
    fragment = sachsen_beteiligung.parse_partial_response(_fixture("sachsen_page2.xml"))

    listings = sachsen_beteiligung.parse_teasers(fragment, observed_at=NOW)

    assert len(listings) == 2
    assert listings[0].title.startswith("Besichtigungstermin")


def test_sachsen_partial_response_without_list_update_is_empty() -> None:
    assert sachsen_beteiligung.parse_partial_response("<partial-response/>") == ""


def test_sachsen_region_for_authority() -> None:
    resolve = sachsen_beteiligung.region_for_authority

    assert resolve("Landeshauptstadt Dresden") is Region.DRESDEN
    assert resolve("Landesdirektion Sachsen") is Region.SACHSEN
    assert resolve("Sächsisches Staatsministerium für Kultus") is Region.SACHSEN
    assert resolve("Landratsamt Sächsische Schweiz-Osterzgebirge") is None
    assert resolve("Stadt Leipzig") is None


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
    assert first.region is Region.EU
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


def test_weact_page_without_store_is_skipped() -> None:
    assert weact.parse_petition("<html></html>", url="u", observed_at=NOW) is None
