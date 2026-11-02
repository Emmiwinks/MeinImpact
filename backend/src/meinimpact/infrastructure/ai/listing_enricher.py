"""Turns a registry listing into what the app shows, and decides relevance.

One LLM call per listing covers the first four points:
1. Is this a real way for citizens to influence a public decision, at a
   level the app covers? Registries also list property viewings, staff
   trainings, award ceremonies and highly technical EU acts (all seen
   live); those are filtered here.
2. How much would an average person care, and how quickly could they grasp
   it? Two 1-5 scores. They are stored, not applied here: the feed query
   withholds only expert-only items and the app ranks by the scores, so
   tuning either needs no new LLM calls.
3. Engaging, neutral plain-language framing, topic tags, werte axes,
   pro/contra and personal-impact snippets.
4. A free-text topic label next to the fixed tags, so gaps in the taxonomy
   become visible (`scripts/topic_report.py`) instead of being force-fit.
5. The city districts concerned, for cities with district data: only names
   found deterministically in the registry and detail text. The model is
   not asked: in a live run it mapped streets to the wrong districts
   (Postplatz -> Innere Neustadt), and a wrong district is worse than none.
   Street-level inference needs real geodata, not model guesses.

Registry facts (dates, counts, URL) never come from the model; they stay
with the listing. The model's structured output is normalized in code:
tags outside the taxonomy, axes not belonging to the tags and snippet keys
outside the Betroffenheitsprofil are dropped, never trusted.

`ENRICHMENT_VERSION` is part of the enrichment input hash: bump it whenever
the prompt or parsing changes, and the next run re-enriches every listing.
"""

import hashlib
from collections.abc import Mapping
from dataclasses import dataclass, field, replace
from typing import Any

from meinimpact.infrastructure.ai.lebenslagen import LEBENSLAGEN, LEBENSLAGEN_BY_ID
from meinimpact.infrastructure.ai.mistral_json import JsonCompleter
from meinimpact.infrastructure.ai.taxonomy import (
    AXIS_LANGUAGE,
    CANDIDATE_TOPICS,
    TAG_AXES,
    TAG_BETROFFENHEIT_KEYS,
    TAG_HINTS,
)
from meinimpact.infrastructure.geo.districts import DistrictMatcher
from meinimpact.infrastructure.listings.model import Listing, Region

ENRICHMENT_VERSION = "8"

MAX_LEBENSLAGEN = 3

_MAX_DETAIL_CHARS = 4000
_MAX_ARGUMENTS = 3
_SCORE_RANGE = range(1, 6)

_SCOPES: Mapping[str, Region | None] = {
    "eu": Region.EU,
    "bund": Region.BUND,
    "sachsen": Region.SACHSEN,
    "dresden": Region.DRESDEN,
    "andere_kommune": None,
    "andere_region": None,
}


class EnrichmentError(ValueError):
    """The model's answer is unusable (missing fields, wrong types)."""


@dataclass(frozen=True, slots=True)
class Enrichment:
    is_relevant: bool
    reason: str
    region: Region | None = None
    # 1-5: how directly it touches an average person's everyday life
    everyday_relevance: int | None = None
    # 1-5: how quickly a layperson grasps what it is about
    accessibility: int | None = None
    title: str = ""
    summary: str = ""
    affected_tags: tuple[str, ...] = ()
    # Lebenslagen catalog ids the opportunity concerns, and the model's own
    # label for a clearly concerned group the catalog lacks
    lebenslagen: tuple[str, ...] = ()
    lebenslage_frei: str = ""
    werte_relevanz: Mapping[str, float] = field(default_factory=dict)
    pro_argumente: tuple[str, ...] = ()
    contra_argumente: tuple[str, ...] = ()
    personal_impact_snippets: Mapping[str, str] = field(default_factory=dict)
    # Free label next to the fixed tags, for taxonomy maintenance only
    free_topic: str = ""
    # One of `CANDIDATE_TOPICS` when it fits, counted by the same report
    topic_candidate: str = ""
    # Set by `ListingEnricher` from the registry text, never by the model
    districts: tuple[str, ...] = ()


def enrichment_input_hash(listing: Listing) -> str:
    """Fingerprint of everything an enrichment depends on: the registry
    text and the enrichment version (prompt + parsing)."""
    text = "\n".join(
        (ENRICHMENT_VERSION, listing.kind, listing.title, listing.summary or "")
    )
    return hashlib.sha256(text.encode()).hexdigest()


def build_prompt(listing: Listing, detail: str | None) -> str:
    tag_list = "\n".join(
        f"- {tag}"
        + (f" ({TAG_HINTS[tag]})" if tag in TAG_HINTS else "")
        + (f" (Achse: {', '.join(axes)})" if axes else "")
        for tag, axes in TAG_AXES.items()
    )
    axis_list = "\n".join(f"- {axis}: {text}" for axis, text in AXIS_LANGUAGE.items())
    lebenslagen_list = "\n".join(
        f"- {item.id}: {item.label} ({item.area})" for item in LEBENSLAGEN
    )
    candidate_list = "\n".join(
        f"- {topic}: {hint}" for topic, hint in CANDIDATE_TOPICS.items()
    )
    snippet_list = "\n".join(
        f"- {tag}: {', '.join(keys)}" for tag, keys in TAG_BETROFFENHEIT_KEYS.items()
    )
    facts = "\n".join(
        f"{label}: {value}"
        for label, value in (
            ("Quelle", listing.source_id),
            ("Art laut Quelle", ", ".join(listing.source_labels) or listing.kind),
            ("Veranstalter/Behörde", listing.organizer),
            ("Ort laut Quelle", listing.locality),
            ("Titel", listing.title),
            ("Kurztext", listing.summary),
        )
        if value
    )
    detail_text = (detail or "")[:_MAX_DETAIL_CHARS] or "(kein weiterer Text)"

    return f"""Du arbeitest für eine neutrale deutsche Civic-Tech-App. Sie zeigt
Menschen in Dresden, Sachsen und Deutschland konkrete Möglichkeiten, auf
öffentliche Entscheidungen Einfluss zu nehmen. Die App soll sich leicht und
motivierend anfühlen, nicht wie Behördenpost: jede Karte muss in wenigen
Sekunden verständlich sein und Lust machen, mitzumachen. Bewerte den
Eintrag unten und antworte NUR mit JSON in genau dieser Struktur:

{{
  "is_participation": <bool>,
  "reason": "<ein kurzer Satz, warum (nicht)>",
  "scope": "eu" | "bund" | "sachsen" | "dresden" | "andere_kommune" | "andere_region",
  "alltagsbezug": <1-5>,
  "zugaenglichkeit": <1-5>,
  "title": "<kurze, neutrale Frage>",
  "summary": "<2 kurze Sätze in einfacher Sprache>",
  "thema": "<1-4 Wörter: das konkrete Thema in eigenen Worten>",
  "kandidat": "<Name aus der Kandidatenliste oder leer>",
  "affected_tags": ["<tag>", ...],
  "lebenslagen": ["<id>", ...],
  "lebenslage_frei": "<Gruppe oder leer>",
  "werte_relevanz": {{"<achse>": <-1.0 bis 1.0>}},
  "pro_argumente": ["<arg>", "<arg>"],
  "contra_argumente": ["<arg>", "<arg>"],
  "personal_impact_snippets": {{"<feld:wert>": "<ein ganzer Satz>"}}
}}

is_participation = true NUR wenn eine Privatperson hier selbst aktiv auf
eine öffentliche oder politische Entscheidung einwirken kann, z.B.:
Petition unterschreiben, Stellungnahme/Einwendung zu einem Plan abgeben
(z.B. Bebauungsplan-Auslegung), an einer Konsultation oder Bürgerumfrage zu
öffentlicher Planung/Politik teilnehmen, an einem öffentlichen Bürgerdialog
zu einem Vorhaben teilnehmen. Und das Thema muss für eine Privatperson
verständlich und nachvollziehbar relevant sein.
is_participation = false z.B. bei: Immobilien-Besichtigungen oder
-Verkäufen, Stellen- und Referentenausschreibungen, internen Schulungen oder
Auswertungen der Verwaltung, Preisverleihungen und Wettbewerben,
Informationsveranstaltungen nur für Fachgruppen, Förderprogramm-Infos,
Bekanntmachungen ohne Beteiligungsmöglichkeit, Fachumfragen für bestimmte
Branchen, hochtechnischen Rechtsakten ohne erkennbaren Bezug zum Alltag
(z.B. Zulassungen einzelner Stoffe, Zollkontingente).
Wenn false: alle Felder außer is_participation, reason und scope leer lassen.

scope = wo das Thema für Menschen zählt: "dresden" (Stadt Dresden),
"sachsen" (Freistaat Sachsen oder sachsenweit), "bund" (bundesweit
relevant, auch wenn es anderswo angestoßen wurde), "eu", "andere_kommune"
(nur eine andere sächsische Stadt/Gemeinde/einen Landkreis), "andere_region"
(nur ein anderes Bundesland oder eine Stadt außerhalb Sachsens).

alltagsbezug = wie direkt das den Alltag eines durchschnittlichen Menschen
in Dresden/Sachsen berührt:
5 = trifft viele Menschen spürbar (Miete, Kita/Schule, Bus und Bahn,
    Rente, Gesundheit, Löhne, die eigene Straße oder das eigene Viertel)
3 = spürbar für eine klar erkennbare Gruppe (z.B. Eltern, Studierende,
    Pflegende, ein Stadtteil)
1 = betrifft fast nur Fachleute, Behörden oder einzelne Branchen (z.B.
    Abgasberechnung für Anhängertypen, Chemikalien-Einstufungen,
    Verwaltungszusammenarbeit von Steuerbehörden)
zugaenglichkeit = wie schnell ein Laie versteht, worum es geht:
5 = in einem Satz ohne Vorwissen klar
3 = mit kurzer Erklärung verständlich
1 = nur mit Fachwissen verständlich
Bewerte ehrlich und streng; die meisten EU-Durchführungsrechtsakte liegen
bei 1-2.

title: eine kurze Frage (höchstens 90 Zeichen), neutral und ohne die
Position der Initiatoren, aber neugierig machend und alltagsnah. Wähle die
Frageform, die am natürlichsten klingt, und variiere sie, z.B.:
"Wie geht es weiter mit ...?", "Braucht Dresden ...?", "Was passiert mit
...?", "Mehr ... oder ...?", "Darf ...?", "Wer zahlt für ...?", "Bleibt
...?", "Soll ...?". Beginne NICHT standardmäßig mit "Soll". Keine
Fachbegriffe, Aktenzeichen oder Plannummern im Titel.
summary: 2 kurze Sätze in einfacher Sprache (etwa Niveau B1): worum geht
es, und wen betrifft es konkret. Fachbegriffe nur mit Erklärung. Neutral,
ohne die Position der Initiatoren zu übernehmen.

thema: das konkrete Thema frei benannt, unabhängig von der Tag-Liste unten
(z.B. "Tierschutz", "Menstruationsprodukte", "Kita-Schließung"). Erfinde
nichts dazu; wenn ein Tag gut passt, darf thema trotzdem genauer sein.

kandidat: nur wenn das Thema zu einer dieser Kandidaten-Gruppen gehört,
sonst leer:
{candidate_list}

affected_tags: NUR aus dieser Liste. Wähle nur Tags, die wirklich zum Thema
passen, lieber einen passenden als drei entfernte:
{tag_list}

lebenslagen: NUR ids aus dieser Liste. Nenne eine Gruppe nur, wenn dieses
Thema für sie deutlich wichtiger ist als für den Durchschnitt aller
Menschen, z.B. Kinderkrankengeld -> eltern, Wohngeld -> wohngeld. Betrifft
ein Thema alle gleichermaßen (Fluglärm, Grundwasser, Strompreise, Steuern),
nenne KEINE Gruppe: []. Fülle die Liste nie auf; Verkehrsgruppen (oepnv,
autofahrer, radfahrer, zu_fuss, pendler) nur bei echten Verkehrsthemen,
Berufsgruppen nur, wenn der Beruf selbst betroffen ist, und "angestellt"
nur bei Arbeitnehmerrechten. Höchstens {MAX_LEBENSLAGEN}:
{lebenslagen_list}
lebenslage_frei: nur wenn eine Gruppe klar betroffen ist, die in der Liste
fehlt: ihr kurzer Name, sonst leer.

werte_relevanz: NUR die Achsen der erkannten Tags, jede in ihrer eigenen
bipolaren Sprache (NIEMALS ein generisches "progressiv vs. konservativ"):
{axis_list}

pro_argumente / contra_argumente: je 1-{_MAX_ARGUMENTS} sachliche Argumente,
jedes ein kurzer Satz.

personal_impact_snippets: NUR Schlüssel aus dieser Zuordnung, und nur für
Gruppen, die vom erkannten Tag wirklich betroffen sind. Wert IMMER ein
ganzer Satz. {{}} wenn nichts passt:
{snippet_list}

Eintrag:
{facts}

Weiterer Text von der Quelle:
{detail_text}
"""


def parse_enrichment(raw: Mapping[str, Any]) -> Enrichment:
    """Validates and normalizes the model's JSON into an `Enrichment`."""
    if not isinstance(raw.get("is_participation"), bool):
        raise EnrichmentError("is_participation missing or not a bool")
    reason = _text(raw.get("reason"))
    scope = _text(raw.get("scope"))
    region = _SCOPES.get(scope)

    if not raw["is_participation"]:
        return Enrichment(is_relevant=False, reason=reason, region=region)
    if region is None:
        return Enrichment(
            is_relevant=False, reason=f"Außerhalb der Abdeckung ({scope or '?'})"
        )

    title = _text(raw.get("title"))
    summary = _text(raw.get("summary"))
    if not title or not summary:
        raise EnrichmentError("relevant listing without title or summary")
    everyday_relevance = _score(raw.get("alltagsbezug"))
    accessibility = _score(raw.get("zugaenglichkeit"))
    if everyday_relevance is None or accessibility is None:
        raise EnrichmentError("relevant listing without valid 1-5 scores")

    tags = tuple(t for t in _strings(raw.get("affected_tags")) if t in TAG_AXES)
    axes = {axis for tag in tags for axis in TAG_AXES[tag]}
    snippet_keys = {key for tag in tags for key in TAG_BETROFFENHEIT_KEYS.get(tag, [])}
    candidate = _text(raw.get("kandidat"))
    lebenslagen = tuple(
        dict.fromkeys(
            i for i in _strings(raw.get("lebenslagen")) if i in LEBENSLAGEN_BY_ID
        )
    )[:MAX_LEBENSLAGEN]
    return Enrichment(
        is_relevant=True,
        reason=reason,
        region=region,
        everyday_relevance=everyday_relevance,
        accessibility=accessibility,
        title=title,
        summary=summary,
        affected_tags=tags,
        lebenslagen=lebenslagen,
        lebenslage_frei=_text(raw.get("lebenslage_frei")),
        werte_relevanz={
            axis: max(-1.0, min(1.0, float(value)))
            for axis, value in _mapping(raw.get("werte_relevanz")).items()
            if axis in axes and isinstance(value, int | float)
        },
        pro_argumente=_strings(raw.get("pro_argumente"))[:_MAX_ARGUMENTS],
        contra_argumente=_strings(raw.get("contra_argumente"))[:_MAX_ARGUMENTS],
        personal_impact_snippets={
            key: value.strip()
            for key, value in _mapping(raw.get("personal_impact_snippets")).items()
            if key in snippet_keys and isinstance(value, str) and value.strip()
        },
        free_topic=_text(raw.get("thema")),
        topic_candidate=candidate if candidate in CANDIDATE_TOPICS else "",
    )


def _score(value: object) -> int | None:
    """A 1-5 integer score; anything else (incl. bools and floats) is None."""
    if isinstance(value, int) and not isinstance(value, bool):
        return value if value in _SCORE_RANGE else None
    return None


def _text(value: object) -> str:
    return value.strip() if isinstance(value, str) else ""


def _strings(value: object) -> tuple[str, ...]:
    if not isinstance(value, list):
        return ()
    return tuple(
        item.strip() for item in value if isinstance(item, str) and item.strip()
    )


def _mapping(value: object) -> Mapping[str, object]:
    return value if isinstance(value, dict) else {}


class ListingEnricher:
    """`district_matchers` maps a region to its city's districts (Dresden
    today); regions without one never get districts."""

    def __init__(
        self,
        completer: JsonCompleter,
        district_matchers: Mapping[Region, DistrictMatcher] | None = None,
    ) -> None:
        self._completer = completer
        self._district_matchers = district_matchers or {}

    async def enrich(self, listing: Listing, detail: str | None) -> Enrichment:
        """Raises on transport or format errors; the caller decides whether
        to retry (the listing stays pending until enriched)."""
        raw = await self._completer.complete_json(build_prompt(listing, detail))
        enrichment = parse_enrichment(raw)

        matcher = (
            self._district_matchers.get(enrichment.region)
            if enrichment.region
            else None
        )
        if matcher is None or not enrichment.is_relevant:
            return enrichment
        text = "\n".join(
            part for part in (listing.title, listing.summary, detail) if part
        )
        return replace(enrichment, districts=matcher.find(text))
