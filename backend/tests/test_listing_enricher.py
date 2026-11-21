"""Listing enrichment: prompt content and normalization of the model's JSON."""

from dataclasses import replace
from typing import Any

import pytest

from meinimpact.infrastructure.ai import listing_enricher
from meinimpact.infrastructure.ai.lebenslagen import LEBENSLAGEN
from meinimpact.infrastructure.ai.listing_enricher import (
    EnrichmentError,
    ListingEnricher,
    build_prompt,
    build_werte_prompt,
    enrichment_input_hash,
    parse_enrichment,
    parse_werte,
)
from meinimpact.infrastructure.ai.taxonomy import (
    CANDIDATE_TOPICS,
    GELD_BEREICHE,
    TAG_BETROFFENHEIT_KEYS,
    TAG_HINTS,
    TAGS,
    WERTE_AUSSAGEN,
)
from meinimpact.infrastructure.geo.districts import District, DistrictMatcher
from meinimpact.infrastructure.geo.locality import Reach
from meinimpact.infrastructure.listings.model import Region
from tests.listing_fakes import make_listing


def _relevant(**overrides: Any) -> dict[str, Any]:
    raw: dict[str, Any] = {
        "is_participation": True,
        "reason": "Bebauungsplan liegt öffentlich aus.",
        "scope": "dresden",
        "alltagsbezug": 4,
        "zugaenglichkeit": 5,
        "title": "Soll am Alten Leipziger Bahnhof ein neues Quartier entstehen?",
        "summary": "Die Stadt legt den Plan aus. Bürger können Stellung nehmen.",
        "affected_tags": ["Wohnen/Miete"],
        "dafuer": "Am Alten Leipziger Bahnhof entsteht ein neues Quartier.",
        "streit": "streit",
        "aussagen": [
            {"nr": 7, "warum": "wer Wandel will", "dafuer_ist": "rechts"},
        ],
        "geld": [{"bereich": "strassen", "richtung": "mehr"}],
        "anlass": "Der alte Bahnhof liegt seit Jahren brach.",
        "pro_argumente": ["Mehr Wohnraum"],
        "contra_argumente": ["Weniger Grünfläche"],
        "personal_impact_snippets": {
            "wohnsituation:mieter": "Neue Wohnungen können den Markt entlasten."
        },
    }
    raw.update(overrides)
    return raw


def test_prompt_contains_registry_facts_and_truncated_detail() -> None:
    listing = replace(
        make_listing("x", title="Bebauungsplan Nr. 3093"),
        organizer="Landeshauptstadt Dresden",
        source_labels=("Bebauungsplan", "Öffentliche Auslegung"),
    )

    prompt = build_prompt(listing, "A" * 10_000)

    assert "Titel: Bebauungsplan Nr. 3093" in prompt
    assert "Veranstalter/Behörde: Landeshauptstadt Dresden" in prompt
    assert "Art laut Quelle: Bebauungsplan, Öffentliche Auslegung" in prompt
    assert "A" * 4000 in prompt
    assert "A" * 4001 not in prompt


def test_prompt_lists_every_tag_and_candidate_topic() -> None:
    prompt = build_prompt(make_listing(), None)

    for tag in TAGS:
        assert f"- {tag}" in prompt
    for topic in CANDIDATE_TOPICS:
        assert f"- {topic}" in prompt


def test_main_prompt_lists_every_budget_area_but_no_statements() -> None:
    prompt = build_prompt(make_listing(), None)

    for area, label in GELD_BEREICHE.items():
        assert f"- {area}: {label}" in prompt
    assert "LINKS:" not in prompt


def test_werte_prompt_lists_every_statement_pair_and_the_card() -> None:
    enrichment = parse_enrichment(_relevant())

    prompt = build_werte_prompt(make_listing("x", title="BP 3093"), enrichment)

    for number, (left, right) in enumerate(WERTE_AUSSAGEN.values(), start=1):
        assert f"{number}. LINKS: {left}\n   RECHTS: {right}" in prompt
    assert f"Titel: {enrichment.title}" in prompt
    assert "Original: BP 3093" in prompt


def test_taxonomy_tables_agree_with_each_other() -> None:
    assert set(TAG_BETROFFENHEIT_KEYS) <= set(TAGS)
    assert not set(CANDIDATE_TOPICS) & set(TAGS)
    assert set(TAG_HINTS) <= set(TAGS)
    # The app's questionnaire has exactly these eight questions
    assert len(WERTE_AUSSAGEN) == 8


def test_prompt_without_detail_says_so() -> None:
    assert "(kein weiterer Text)" in build_prompt(make_listing(), None)


def test_relevant_listing_is_parsed() -> None:
    enrichment = parse_enrichment(_relevant())

    assert enrichment.is_relevant
    assert enrichment.region is Region.DRESDEN
    assert (enrichment.everyday_relevance, enrichment.accessibility) == (4, 5)
    assert enrichment.title.startswith("Soll am Alten")
    assert enrichment.affected_tags == ("Wohnen/Miete",)
    assert enrichment.werte_relevanz == {}  # from the werte call only
    assert enrichment.geld == (("strassen", 1),)
    assert enrichment.anlass == "Der alte Bahnhof liegt seit Jahren brach."
    assert enrichment.personal_impact_snippets == {
        "wohnsituation:mieter": "Neue Wohnungen können den Markt entlasten."
    }


def test_non_participation_keeps_only_the_reason() -> None:
    enrichment = parse_enrichment(
        {
            "is_participation": False,
            "reason": "Immobilien-Besichtigung",
            "scope": "dresden",
            "title": "ignored",
        }
    )

    assert not enrichment.is_relevant
    assert enrichment.reason == "Immobilien-Besichtigung"
    assert enrichment.title == ""


@pytest.mark.parametrize("scope", ["andere_kommune", "andere_region", "mars", None])
def test_participation_outside_coverage_is_not_relevant(scope: str | None) -> None:
    enrichment = parse_enrichment(_relevant(scope=scope))

    assert not enrichment.is_relevant
    assert enrichment.reason.startswith("Außerhalb der Abdeckung")


def test_normalization_drops_what_the_taxonomy_does_not_allow() -> None:
    enrichment = parse_enrichment(
        _relevant(
            affected_tags=["Wohnen/Miete", "Erfundenes Thema", 42],
            personal_impact_snippets={
                "wohnsituation:mieter": "  Ganzer Satz.  ",
                "hat_kinder:true": "Passt nicht zum Tag.",
                "wohnsituation:eigentuemer": True,
                "erfunden:ja": "Unbekannter Schlüssel.",
            },
            pro_argumente=["a", "b", "c", "d", "", 7],
        )
    )

    assert enrichment.affected_tags == ("Wohnen/Miete",)
    assert enrichment.personal_impact_snippets == {
        "wohnsituation:mieter": "Ganzer Satz."
    }
    assert enrichment.pro_argumente == ("a", "b", "c")


def test_tag_without_snippet_keys_gets_no_snippets() -> None:
    enrichment = parse_enrichment(_relevant(affected_tags=["Umwelt/Natur"]))

    assert enrichment.personal_impact_snippets == {}


def test_statements_become_questionnaire_keys_with_the_supporters_side() -> None:
    werte = parse_werte(
        {
            "aussagen": [
                {"nr": 1, "warum": "Umverteilung", "dafuer_ist": "links"},
                {"nr": 1, "warum": "doppelt", "dafuer_ist": "rechts"},
                {"nr": 9, "dafuer_ist": "links"},
                {"nr": True, "dafuer_ist": "links"},
                {"nr": "2", "dafuer_ist": "links"},
                {"nr": 3, "dafuer_ist": "dafuer"},
                "6",
                {"nr": 6, "warum": "Bürgerrechte", "dafuer_ist": "rechts"},
                {"nr": 8, "warum": "zu viele", "dafuer_ist": "links"},
            ]
        }
    )

    assert werte == {"wirtschaft_gleichheit": -1.0, "freiheit_sicherheit": 1.0}


@pytest.mark.parametrize("aussagen", [[], None, "1 links", {"nr": 1}])
def test_no_usable_statement_means_no_werte(aussagen: object) -> None:
    assert parse_werte({"aussagen": aussagen}) == {}


def test_money_keeps_known_areas_with_a_direction() -> None:
    enrichment = parse_enrichment(
        _relevant(
            geld=[
                {"bereich": "kinder_bildung", "richtung": "weniger"},
                {"bereich": "kinder_bildung", "richtung": "mehr"},
                {"bereich": "wohnen", "richtung": "mehr"},
                {"bereich": "kultur", "richtung": "viel"},
                {"bereich": "kultur", "richtung": "mehr"},
                {"bereich": "soziales", "richtung": "mehr"},
            ]
        )
    )

    assert enrichment.geld == (("kinder_bildung", -1), ("kultur", 1))
    assert parse_enrichment(_relevant(geld=None)).geld == ()


def test_reason_is_cut_to_one_short_line() -> None:
    assert len(parse_enrichment(_relevant(anlass="x" * 400)).anlass) == 140
    assert parse_enrichment(_relevant(anlass=None)).anlass == ""


@pytest.mark.parametrize(
    "raw",
    [
        {"reason": "kein Flag"},
        {"is_participation": "ja"},
        _relevant(title=""),
        _relevant(summary=None),
        _relevant(alltagsbezug=None),
        _relevant(alltagsbezug=0),
        _relevant(zugaenglichkeit=6),
        _relevant(zugaenglichkeit="4"),
        _relevant(zugaenglichkeit=4.5),
        _relevant(alltagsbezug=True),
    ],
)
def test_unusable_answers_raise(raw: dict[str, Any]) -> None:
    with pytest.raises(EnrichmentError):
        parse_enrichment(raw)


def test_scores_are_not_required_for_non_participation() -> None:
    enrichment = parse_enrichment({"is_participation": False, "reason": "x"})

    assert enrichment.everyday_relevance is None


def test_input_hash_tracks_registry_text_and_enrichment_version(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    listing = make_listing("a", title="Kita erhalten")
    original = enrichment_input_hash(listing)

    assert enrichment_input_hash(listing) == original
    assert enrichment_input_hash(replace(listing, title="Kita retten")) != original
    monkeypatch.setattr(listing_enricher, "ENRICHMENT_VERSION", "next")
    assert enrichment_input_hash(listing) != original


def test_prompt_asks_for_varied_question_titles() -> None:
    prompt = build_prompt(make_listing(), None)

    assert 'Beginne NICHT standardmäßig mit "Soll"' in prompt
    assert '"alltagsbezug": <1-5>' in prompt


class FakeCompleter:
    def __init__(self, answer: dict[str, Any]) -> None:
        self.answer = answer
        self.prompts: list[str] = []

    async def complete_json(self, prompt: str) -> dict[str, Any]:
        self.prompts.append(prompt)
        return self.answer


def test_free_topic_is_kept_next_to_the_fixed_tags() -> None:
    enrichment = parse_enrichment(_relevant(thema="Menstruationsprodukte"))

    assert enrichment.free_topic == "Menstruationsprodukte"


def test_lebenslagen_need_a_catalog_id_and_a_reason() -> None:
    enrichment = parse_enrichment(
        _relevant(
            lebenslagen=[
                {"id": "wohngeld", "grund": "verlieren den Anspruch"},
                {"id": "wohngeld", "grund": "doppelt"},
                {"id": "Erfunden", "grund": "nicht im Katalog"},
                {"id": "eltern", "grund": ""},
                {"id": "rentner"},
                "mieter",
                42,
                {"id": "alleinerziehend", "grund": "kein zweites Einkommen"},
            ],
            lebenslage_frei="Kita-Personal",
        )
    )

    assert enrichment.lebenslagen == ("wohngeld", "alleinerziehend")
    assert enrichment.lebenslagen_gruende == {
        "wohngeld": "verlieren den Anspruch",
        "alleinerziehend": "kein zweites Einkommen",
    }
    assert enrichment.lebenslage_frei == "Kita-Personal"
    assert parse_enrichment(_relevant()).lebenslagen == ()


def test_prompt_lists_every_lebenslage_id() -> None:
    prompt = build_prompt(make_listing(), None)

    for item in LEBENSLAGEN:
        assert f"- {item.id}: {item.label}" in prompt


def test_candidate_topic_is_kept_only_from_the_candidate_list() -> None:
    assert (
        parse_enrichment(_relevant(kandidat="Verbraucher/Preise")).topic_candidate
        == "Verbraucher/Preise"
    )
    assert parse_enrichment(_relevant(kandidat="Erfunden")).topic_candidate == ""
    assert parse_enrichment(_relevant()).topic_candidate == ""


def test_reach_and_places_are_kept_up_to_three_places() -> None:
    enrichment = parse_enrichment(
        _relevant(
            scope="sachsen",
            reichweite="umland",
            orte=["Pirna", "Neustadt in Sachsen", "Sebnitz", "Bad Schandau", 7],
        )
    )

    assert enrichment.reach is Reach.SURROUNDINGS
    assert enrichment.places == ("Pirna", "Neustadt in Sachsen", "Sebnitz")


@pytest.mark.parametrize("reichweite", ["", "landesweit", None])
def test_no_or_unknown_reach_drops_the_places(reichweite: str | None) -> None:
    enrichment = parse_enrichment(_relevant(reichweite=reichweite, orte=["Dresden"]))

    assert enrichment.reach is None
    assert enrichment.places == ()


def test_prompt_separates_who_decides_from_where_it_matters() -> None:
    prompt = build_prompt(make_listing(), None)

    assert '"reichweite": "nachbarschaft" | "ort" | "stadt" | "umland" | ""' in prompt
    assert "Wer berät, macht eine Vorlage nicht" in prompt


_DRESDEN = DistrictMatcher(
    "Dresden", [District("Mockritz", "Q1"), District("Plauen", "Q2")]
)


async def test_districts_come_only_from_the_registry_text() -> None:
    # A model answer naming districts is ignored: only text matches count.
    completer = FakeCompleter(_relevant(stadtteile=["Mockritz"]))
    enricher = ListingEnricher(completer, {Region.DRESDEN: _DRESDEN})
    listing = make_listing(
        "bp", region=Region.DRESDEN, title="Bebauungsplan Dresden-Plauen"
    )

    enrichment = await enricher.enrich(listing, "Zweiter Abschnitt in Plauen")

    assert enrichment.districts == ("Plauen",)
    assert "stadtteile" not in completer.prompts[0]


async def test_no_districts_outside_cities_with_district_data() -> None:
    completer = FakeCompleter(_relevant(scope="sachsen"))
    enricher = ListingEnricher(completer, {Region.DRESDEN: _DRESDEN})

    enrichment = await enricher.enrich(make_listing("x"), "Dresden-Plauen")

    assert enrichment.districts == ()


async def test_relevant_listing_gets_its_werte_from_a_second_call() -> None:
    completer = FakeCompleter(_relevant())

    enrichment = await ListingEnricher(completer).enrich(make_listing("x"), None)

    assert len(completer.prompts) == 2
    assert "LINKS:" in completer.prompts[1]
    assert enrichment.werte_relevanz == {"wandel_tradition": 1.0}
    assert enrichment.geld == (("strassen", 1),)


async def test_irrelevant_listing_costs_one_call() -> None:
    completer = FakeCompleter({"is_participation": False, "reason": "Besichtigung"})

    enrichment = await ListingEnricher(completer).enrich(make_listing("x"), None)

    assert not enrichment.is_relevant
    assert len(completer.prompts) == 1


async def test_enricher_sends_the_prompt_and_parses_the_answer() -> None:
    completer = FakeCompleter(_relevant())
    listing = make_listing("x", title="Kita erhalten")

    enrichment = await ListingEnricher(completer).enrich(listing, "Detailtext")

    assert enrichment.is_relevant
    assert "Titel: Kita erhalten" in completer.prompts[0]
    assert "Detailtext" in completer.prompts[0]
