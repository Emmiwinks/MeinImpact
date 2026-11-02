"""Listing enrichment: prompt content and normalization of the model's JSON."""

from dataclasses import replace
from typing import Any

import pytest
from listing_fakes import make_listing

from meinimpact.infrastructure.ai import listing_enricher
from meinimpact.infrastructure.ai.lebenslagen import LEBENSLAGEN
from meinimpact.infrastructure.ai.listing_enricher import (
    EnrichmentError,
    ListingEnricher,
    build_prompt,
    enrichment_input_hash,
    parse_enrichment,
)
from meinimpact.infrastructure.ai.taxonomy import (
    AXIS_LANGUAGE,
    CANDIDATE_TOPICS,
    TAG_AXES,
    TAG_BETROFFENHEIT_KEYS,
    TAG_HINTS,
)
from meinimpact.infrastructure.geo.districts import District, DistrictMatcher
from meinimpact.infrastructure.listings.model import Region


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
        "werte_relevanz": {"equality_markets": -0.4},
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

    for tag in TAG_AXES:
        assert f"- {tag}" in prompt
    for topic in CANDIDATE_TOPICS:
        assert f"- {topic}" in prompt


def test_taxonomy_tables_agree_with_each_other() -> None:
    assert set(TAG_BETROFFENHEIT_KEYS) <= set(TAG_AXES)
    assert {axis for axes in TAG_AXES.values() for axis in axes} <= set(AXIS_LANGUAGE)
    assert not set(CANDIDATE_TOPICS) & set(TAG_AXES)
    assert set(TAG_HINTS) <= set(TAG_AXES)


def test_prompt_without_detail_says_so() -> None:
    assert "(kein weiterer Text)" in build_prompt(make_listing(), None)


def test_relevant_listing_is_parsed() -> None:
    enrichment = parse_enrichment(_relevant())

    assert enrichment.is_relevant
    assert enrichment.region is Region.DRESDEN
    assert (enrichment.everyday_relevance, enrichment.accessibility) == (4, 5)
    assert enrichment.title.startswith("Soll am Alten")
    assert enrichment.affected_tags == ("Wohnen/Miete",)
    assert enrichment.werte_relevanz == {"equality_markets": -0.4}
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
            werte_relevanz={
                "equality_markets": -3,
                "nation_globe": 0.5,  # not an axis of Wohnen/Miete
                "liberty_authority": "viel",
            },
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
    assert enrichment.werte_relevanz == {"equality_markets": -1.0}
    assert enrichment.personal_impact_snippets == {
        "wohnsituation:mieter": "Ganzer Satz."
    }
    assert enrichment.pro_argumente == ("a", "b", "c")


def test_untagged_listing_has_no_axes_or_snippets() -> None:
    enrichment = parse_enrichment(_relevant(affected_tags=["Umwelt/Natur"]))

    assert enrichment.werte_relevanz == {}
    assert enrichment.personal_impact_snippets == {}


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


def test_lebenslagen_keep_only_catalog_ids_deduplicated_and_capped() -> None:
    enrichment = parse_enrichment(
        _relevant(
            lebenslagen=[
                "mieter",
                "mieter",
                "Erfunden",
                42,
                "eltern",
                "pendler",
                "oepnv",
                "wohngeld",
                "rentner",
            ],
            lebenslage_frei="Kita-Personal",
        )
    )

    assert enrichment.lebenslagen == (
        "mieter",
        "eltern",
        "pendler",
        "oepnv",
        "wohngeld",
    )
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


async def test_enricher_sends_the_prompt_and_parses_the_answer() -> None:
    completer = FakeCompleter(_relevant())
    listing = make_listing("x", title="Kita erhalten")

    enrichment = await ListingEnricher(completer).enrich(listing, "Detailtext")

    assert enrichment.is_relevant
    assert "Titel: Kita erhalten" in completer.prompts[0]
    assert "Detailtext" in completer.prompts[0]
