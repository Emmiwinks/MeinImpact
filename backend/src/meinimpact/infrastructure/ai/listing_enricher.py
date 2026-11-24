"""Turns a registry listing into what the app shows, and decides relevance.

One LLM call per listing covers the first four points (for relevant
listings, the questionnaire statements and the reason line of point 3 get
two short calls of their own, see `build_werte_prompt` and
`build_anlass_prompt`):
1. Is this a real way for citizens to influence a public decision, at a
   level the app covers? Registries also list property viewings, staff
   trainings, award ceremonies and highly technical EU acts (all seen
   live); those are filtered here.
2. How much would an average person care, and how quickly could they grasp
   it? Two 1-5 scores. They are stored, not applied here: the feed query
   withholds only expert-only items and the app ranks by the scores, so
   tuning either needs no new LLM calls.
3. Engaging, neutral plain-language framing, topic tags, pro/contra and
   personal-impact snippets. Which questionnaire statements directly
   predict support (werte_relevanz), which budget areas get more or less
   money (geld), and why it is on the table now (anlass). The main and the
   werte call first say in one sentence what supporters want; the
   statements and the money are judged against that sentence, which keeps
   "stop X" cards from flipping sides.
4. A free-text topic label next to the fixed tags, so gaps in the taxonomy
   become visible (`scripts/topic_report.py`) instead of being force-fit.
5. The city districts concerned, for cities with district data: only names
   found deterministically in the registry and detail text. The model is
   not asked: in a live run it mapped streets to the wrong districts
   (Postplatz -> Innere Neustadt), and a wrong district is worse than none.
   Street-level inference needs real geodata, not model guesses.
6. Where the consequences are felt: a reach (one neighbourhood, place,
   city or surrounding area) and the municipalities, Kreise or city parts
   the text names. The model only names them; `geo/locality.py` locates
   them in synced data and skips what it cannot place unambiguously.

Registry facts (dates, counts, URL) never come from the model; they stay
with the listing. The model's structured output is normalized in code:
tags outside the taxonomy, unknown statements or budget areas and snippet
keys outside the Betroffenheitsprofil are dropped, never trusted.

`ENRICHMENT_VERSION` is part of the enrichment input hash: bump it whenever
the prompt or parsing changes, and the next run re-enriches every listing.
"""

import asyncio
import hashlib
from collections.abc import Mapping
from dataclasses import dataclass, field, replace
from typing import Any

from meinimpact import places as covered
from meinimpact.infrastructure.ai.lebenslagen import LEBENSLAGEN, LEBENSLAGEN_BY_ID
from meinimpact.infrastructure.ai.mistral_json import JsonCompleter
from meinimpact.infrastructure.ai.taxonomy import (
    CANDIDATE_TOPICS,
    GELD_BEREICHE,
    TAG_BETROFFENHEIT_KEYS,
    TAG_HINTS,
    TAGS,
    WERTE_AUSSAGEN,
)
from meinimpact.infrastructure.geo.districts import DistrictMatcher
from meinimpact.infrastructure.geo.locality import Reach
from meinimpact.infrastructure.listings.model import Listing

# Not bumped when anlass moved to its own call (2026-11-23): the user chose
# not to re-enrich the whole pool for it, so only new or changed listings
# get the new reason line.
ENRICHMENT_VERSION = "14"


_MAX_DETAIL_CHARS = 4000
# Registry text in the werte call, as in the probe that calibrated it
_MAX_WERTE_TEXT_CHARS = 1500
_MAX_ARGUMENTS = 3
_MAX_PLACES = 3
_MAX_AUSSAGEN = 2
_MAX_GELD = 2
_MAX_ANLASS_CHARS = 140
_SCORE_RANGE = range(1, 6)
_AUSSAGE_KEYS = tuple(WERTE_AUSSAGEN)
_SIDES = {"links": -1.0, "rechts": 1.0}
_DIRECTIONS = {"mehr": 1, "weniger": -1}

# The model answers with a covered place's key, or says it lies elsewhere
_SCOPES: Mapping[str, str | None] = {
    **{place.key: place.key for place in covered.ALL},
    "andere_kommune": None,
    "andere_region": None,
}


class EnrichmentError(ValueError):
    """The model's answer is unusable (missing fields, wrong types)."""


@dataclass(frozen=True, slots=True)
class Enrichment:
    is_relevant: bool
    reason: str
    region: str | None = None
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
    # The model's reason per Lebenslage (why it matters more for them); for
    # review in scripts/compare_models.py, not stored
    lebenslagen_gruende: Mapping[str, str] = field(default_factory=dict)
    # Questionnaire key -> -1 (supporters agree with its left statement) or
    # +1 (with its right one); only statements that directly predict support
    werte_relevanz: Mapping[str, float] = field(default_factory=dict)
    # (budget area, +1 more / -1 less money) if what supporters want happens
    geld: tuple[tuple[str, int], ...] = ()
    # Why it is on the table now, from the source text; "" if it doesn't say
    anlass: str = ""
    pro_argumente: tuple[str, ...] = ()
    contra_argumente: tuple[str, ...] = ()
    personal_impact_snippets: Mapping[str, str] = field(default_factory=dict)
    # Free label next to the fixed tags, for taxonomy maintenance only
    free_topic: str = ""
    # One of `CANDIDATE_TOPICS` when it fits, counted by the same report
    topic_candidate: str = ""
    # Where the consequences are felt, as the model reads the text: places
    # are names only, located by `geo/locality.py` from synced data
    reach: Reach | None = None
    places: tuple[str, ...] = ()
    # Set by `ListingEnricher` from the registry text, never by the model
    districts: tuple[str, ...] = ()


def enrichment_input_hash(listing: Listing) -> str:
    """Fingerprint of everything an enrichment depends on: the registry
    text and the enrichment version (prompt + parsing)."""
    text = "\n".join(
        (ENRICHMENT_VERSION, listing.kind, listing.title, listing.summary or "")
    )
    return hashlib.sha256(text.encode()).hexdigest()


def _scope_places(listing: Listing) -> tuple[covered.Place, ...]:
    """The places a listing may be scoped to, most specific first: its own
    place and the wider ones it belongs to. A nationwide registry's entry
    may concern any covered place, so it gets all of them."""
    own = covered.chain(listing.region)
    if own and own[0].depth > covered.Level.BUND.depth:
        return own
    return tuple(sorted(covered.ALL, key=lambda p: (-p.depth, p.key)))


def _scope_label(place: covered.Place) -> str:
    match place.level:
        case covered.Level.KOMMUNE:
            return f'"{place.key}" (Stadt {place.name})'
        case covered.Level.KREIS:
            return f'"{place.key}" (Landkreis {place.name} oder kreisweit)'
        case covered.Level.LAND:
            return f'"{place.key}" (Land {place.name} oder ganz {place.name})'
        case covered.Level.BUND:
            return (
                f'"{place.key}" (bundesweit relevant, auch wenn es anderswo '
                "angestoßen wurde)"
            )
        case _:
            return f'"{place.key}"'


def _scope_text(listing: Listing) -> tuple[str, str, str, str]:
    """The scope options, their explanation, and the place names the
    prompt's intro and everyday line address, all from the place files."""
    scopes = _scope_places(listing)
    options = " | ".join(
        f'"{key}"'
        for key in (*(p.key for p in scopes), "andere_kommune", "andere_region")
    )
    lands = [p for p in scopes if p.level is covered.Level.LAND]
    land = lands[0].name if len(lands) == 1 else None
    other_local = (
        f"nur eine andere Stadt/Gemeinde/einen Landkreis in {land}"
        if land
        else "nur eine Stadt/Gemeinde/einen Landkreis, die hier nicht genannt ist"
    )
    other_region = (
        f"nur ein anderes Bundesland oder eine Stadt außerhalb von {land}"
        if land
        else "nur ein Bundesland oder eine Stadt, die hier nicht genannt ist"
    )
    explained = ", ".join(_scope_label(p) for p in scopes)
    explanation = (
        f'{explained}, "andere_kommune" ({other_local}), '
        f'"andere_region" ({other_region}).'
    )
    names = [p.name for p in covered.chain(listing.region) if p.depth > 0]
    audience = (
        ", ".join(names[:-1]) + " und " + names[-1] if len(names) > 1 else "Deutschland"
    )
    local = [p.name for p in covered.chain(listing.region) if p.depth > 1]
    everyday = "/".join(local) if local else "Deutschland"
    return options, explanation, audience, everyday


def build_prompt(listing: Listing, detail: str | None) -> str:
    scope_options, scope_explanation, audience, everyday_place = _scope_text(listing)
    tag_list = "\n".join(
        f"- {tag}" + (f" ({TAG_HINTS[tag]})" if tag in TAG_HINTS else "")
        for tag in TAGS
    )
    geld_list = "\n".join(f"- {area}: {label}" for area, label in GELD_BEREICHE.items())
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
Menschen in {audience} konkrete Möglichkeiten, auf
öffentliche Entscheidungen Einfluss zu nehmen. Die App soll sich leicht und
motivierend anfühlen, nicht wie Behördenpost: jede Karte muss in wenigen
Sekunden verständlich sein und Lust machen, mitzumachen. Bewerte den
Eintrag unten und antworte NUR mit JSON in genau dieser Struktur:

{{
  "is_participation": <bool>,
  "reason": "<ein kurzer Satz, warum (nicht)>",
  "scope": {scope_options},
  "reichweite": "nachbarschaft" | "ort" | "stadt" | "umland" | "",
  "orte": ["<Gemeinde, Stadt, Landkreis oder Stadtteil>", ...],
  "alltagsbezug": <1-5>,
  "zugaenglichkeit": <1-5>,
  "title": "<kurze, neutrale Frage>",
  "summary": "<2 kurze Sätze in einfacher Sprache>",
  "thema": "<1-4 Wörter: das konkrete Thema in eigenen Worten>",
  "kandidat": "<Name aus der Kandidatenliste oder leer>",
  "affected_tags": ["<tag>", ...],
  "lebenslagen": [{{"id": "<id>", "grund": "<was sich für sie ändert>"}}, ...],
  "lebenslage_frei": "<Gruppe oder leer>",
  "dafuer": "<ein Satz>",
  "geld": [{{"bereich": "<id>", "richtung": "mehr" | "weniger"}}],
  "pro_argumente": ["<arg>", "<arg>"],
  "contra_argumente": ["<arg>", "<arg>"],
  "personal_impact_snippets": {{"<feld:wert>": "<ein ganzer Satz>"}}
}}

is_participation = true NUR wenn eine Privatperson hier selbst aktiv auf
eine öffentliche oder politische Entscheidung einwirken kann, z.B.:
Petition unterschreiben, Stellungnahme/Einwendung zu einem Plan abgeben
(z.B. Bebauungsplan-Auslegung), an einer Konsultation oder Bürgerumfrage zu
öffentlicher Planung/Politik teilnehmen, an einem öffentlichen Bürgerdialog
zu einem Vorhaben teilnehmen, oder vor einer anstehenden Entscheidung im
Stadtrat, einem Ausschuss, Stadtbezirks- oder Ortschaftsrat den Mitgliedern
schreiben (Ratsvorlage). Und das Thema muss für eine Privatperson
verständlich und nachvollziehbar relevant sein.
is_participation = false z.B. bei: Immobilien-Besichtigungen oder
-Verkäufen, Stellen- und Referentenausschreibungen, internen Schulungen oder
Auswertungen der Verwaltung, Preisverleihungen und Wettbewerben,
Informationsveranstaltungen nur für Fachgruppen, Förderprogramm-Infos,
Bekanntmachungen ohne Beteiligungsmöglichkeit, Fachumfragen für bestimmte
Branchen, hochtechnischen Rechtsakten ohne erkennbaren Bezug zum Alltag
(z.B. Zulassungen einzelner Stoffe, Zollkontingente).

Ratsvorlagen ("Art laut Quelle" beginnt mit "Ratsvorlage"): Hier ist die
Beteiligungsmöglichkeit IMMER gegeben, denn man kann den Mitgliedern des
Gremiums vor der Sitzung schreiben. Begründe false bei Ratsvorlagen NIE
mit fehlender Beteiligungsmöglichkeit. Entscheide nur: Würden Menschen in
der Stadt oder im Stadtteil die Folgen spüren oder darüber mitreden
wollen? Dann true, auch bei Strategien, Haushalten und Satzungen, z.B.
Haushaltssatzung, Schulbau-Strategie, Veränderungssperre für einen
Bebauungsplan, Zukunft des städtischen Klinikums, Regeln für
Stadtteilfeste, Umbau von Bahnübergängen, Schatten auf Spielplätzen.
false nur bei Verwaltungsroutine: Vergaben und Ausschreibungen,
Rahmenverträge für Beschaffung, Besetzung von Gremien,
Mittelübertragungen ohne erkennbares Vorhaben, Jahresabschlüsse,
Entschädigung von Ratsmitgliedern, Grundstücksgeschäfte, Personalien,
reine Informationsvorlagen, Zuschüsse an einzelne Vereine für deren
interne Zwecke.
Wenn false: alle Felder außer is_participation, reason und scope leer lassen.

scope = wo das Thema für Menschen zählt: {scope_explanation} Bei
Ratsvorlagen ist scope immer die Stadt, deren Rat entscheidet, auch wenn
die Folgen ins Umland reichen.

reichweite und orte = wo die Folgen spürbar sind. Das ist nicht dasselbe
wie scope: scope sagt, wer entscheidet, reichweite, wen es als Ort betrifft.
"nachbarschaft" = ein Stadtteil oder Viertel, eine Straße, ein Platz oder
eine einzelne Einrichtung (z.B. eine Schule, ein Park); "ort" = eine ganze
Gemeinde oder Kleinstadt; "stadt" = eine ganze Großstadt; "umland" = eine
Gegend über mehrere Gemeinden (z.B. eine Bahnstrecke, eine Stromleitung,
ein Tagebau, ein Wald, ein Landkreis); "" = kein bestimmter Ort, die
Folgen treffen Menschen im ganzen Land, in ganz Deutschland oder der EU,
auch wenn ein einzelner Ort den Anlass gab. Ein Gesetz, eine Verordnung
oder eine Regel für ein ganzes Land ist immer "", auch wenn der Text Orte
als Beispiele nennt.
orte: höchstens 3 amtliche Namen der betroffenen Gemeinden, Städte oder
Landkreise (z.B. "Weinböhla", "Pirna", "Erzgebirgskreis"). Liegt etwas in
einem Wald, Tal oder Ortsteil, nenne die Gemeinde, in der es liegt. Bei
"nachbarschaft" in einer Großstadt nenne den Stadtteil (z.B. "Pieschen").
Bei einer Strecke oder Leitung nenne Anfang und Ende. Nur Orte, die im
Text stehen oder in denen das Genannte sicher liegt; im Zweifel []. Bei
reichweite "" immer [].
Ratsvorlagen eines Ortschaftsrats oder Stadtbezirksbeirats: "nachbarschaft"
nur, wenn die Vorlage diesen Stadtteil selbst betrifft (z.B. sein eigenes
Budget, eine Straße dort). Berät das Gremium eine Vorlage für die ganze
Stadt (z.B. die Haushaltssatzung der Stadt oder Einwendungen dagegen, das
städtische Klinikum), dann "stadt": Wer berät, macht eine Vorlage nicht
zur Sache des Stadtteils.

alltagsbezug = wie direkt das den Alltag eines durchschnittlichen Menschen
in {everyday_place} berührt:
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
"Wie geht es weiter mit ...?", "Braucht die Stadt ...?", "Was passiert mit
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

lebenslagen: Gruppen aus dieser Liste, für die dieses Thema DEUTLICH
wichtiger ist als für den Durchschnitt aller Menschen, die am stärksten
betroffene zuerst. Gib zu jeder Gruppe einen kurzen "grund", was sich für
genau diese Gruppe konkret ändert. Findest du keinen solchen Grund, lass die
Gruppe weg; betrifft ein Thema alle gleichermaßen, ist [] richtig.
Beispiele:
- Kinderkrankengeld: eltern ("bekommen weniger bezahlte Tage, wenn das Kind
  krank ist"), alleinerziehend ("haben niemanden, der sich die Tage teilt")
- Fluglärm: [] (betrifft alle in der Region gleich)
{lebenslagen_list}
lebenslage_frei: nur wenn eine Gruppe klar betroffen ist, die in der Liste
fehlt: ihr kurzer Name, sonst leer.

dafuer: Wofür ist, wer hier mitmacht und dafür ist? Ein Satz. Bei Petitionen
das Anliegen, bei Ratsvorlagen und Konsultationen der Vorschlag selbst. Bei
"Stoppt X" ist man dafür, dass X nicht passiert.

geld: Wenn passiert, wofür man laut "dafuer" ist: Bekommt ein Bereich
öffentlicher Ausgaben dadurch klar mehr oder weniger Geld? Höchstens 2,
[] wenn es nicht ums Geld geht oder es unklar ist.
{geld_list}
Beispiele: "Bleibt die Kita X?" -> kinder_bildung mehr. "Dürfen elf Kitas
geschlossen werden?" (dafür = schließen) -> kinder_bildung weniger.
"Steigen die Kita-Gebühren?" (dafür = Eltern zahlen mehr, die Stadt
weniger) -> kinder_bildung weniger.

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


def build_werte_prompt(listing: Listing, enrichment: Enrichment) -> str:
    """The questionnaire statements get a call of their own: as one of ~20
    tasks in the main prompt the model put "the state must regulate markets"
    on almost every card (Bund 36/38, Dresden 26/60 in the first full run),
    alone it stays selective (Bund 20/37, Dresden 4/59 on the same cards)."""
    aussagen_list = "\n".join(
        f"{number}. LINKS: {left}\n   RECHTS: {right}"
        for number, (left, right) in enumerate(WERTE_AUSSAGEN.values(), start=1)
    )
    return f"""Du arbeitest für eine neutrale deutsche Civic-Tech-App. Bewerte die
Beteiligungsmöglichkeit unten und antworte nur mit JSON in genau dieser Struktur:

{{"dafuer": "<ein Satz>", "streit": "streit" | "einig",
  "aussagen": [
    {{"nr": <1-8>, "warum": "<halber Satz>", "dafuer_ist": "links" | "rechts"}}
  ]}}

dafuer: Wofür ist, wer hier mitmacht und dafür ist? Ein Satz. Bei Petitionen
das Anliegen, bei Ratsvorlagen und Konsultationen der Vorschlag selbst. Bei
"Stoppt X" ist man dafür, dass X nicht passiert.

streit: "streit", wenn Menschen mit unterschiedlichen politischen
Grundüberzeugungen hier typischerweise verschieden entscheiden würden.
"einig", wenn sich fast alle Betroffenen unabhängig von ihrer Weltanschauung
einig wären (z.B. die eigene Kita, Bahnlinie oder das Bad erhalten) oder es
vor allem um eigene Interessen geht.

aussagen: Welche Aussagenpaare unten sagen direkt voraus, ob jemand für den
Satz aus "dafuer" ist? Nur wenn die Aussage den Kern trifft, nicht wenn sie
nur thematisch verwandt ist. Meistens passt keins, höchstens 2. Für jedes
Paar: erst "warum" (wer würde den Satz aus "dafuer" unterstützen, und
warum), dann "dafuer_ist": "links", wenn eher Menschen, die der linken
Aussage zustimmen, den Satz aus "dafuer" unterstützen, sonst "rechts".
Bei "einig" fast immer [].
{aussagen_list}

Eintrag:
Art: {listing.kind}
Titel: {enrichment.title}
Kurz: {enrichment.summary}
Original: {listing.title}

Weiterer Text von der Quelle:
{(listing.summary or "")[:_MAX_WERTE_TEXT_CHARS] or "(kein Text)"}
"""


def parse_werte(raw: Mapping[str, Any]) -> dict[str, float]:
    """The werte call's answer as questionnaire key -> -1 / +1."""
    return _werte(raw.get("aussagen"))


def build_anlass_prompt(
    listing: Listing, detail: str | None, enrichment: Enrichment
) -> str:
    """The reason line gets a call of its own too: inside the main prompt it
    often took the initiators' framing ("drohende Kürzungen gefährden …")
    and turned steps of the process into reasons ("Der Entwurf liegt vor"),
    even with that exact counter-example in the prompt. Unlike the werte
    call it needs the full detail text: for council papers the reason is
    only in the PDF."""
    detail_text = (detail or listing.summary or "")[:_MAX_DETAIL_CHARS]
    return f"""Du arbeitest für eine neutrale deutsche Civic-Tech-App. Lies den
Eintrag unten und antworte nur mit JSON: {{"anlass": "<ein Satz oder leer>"}}

anlass: Warum steht das gerade an? Ein kurzer Satz, höchstens 140 Zeichen,
lieber kürzer. Nur wenn der Text einen Grund nennt, z.B. Sparzwang, weniger
Kinder, ein Gerichtsurteil, eine auslaufende Förderung, ein Gesetzentwurf.

Neutral: Nenne die Tatsache, nicht die Bewertung der Initiatoren. Keine
wertenden Wörter wie "drohen", "gefährden", "drastisch", "Elend".
- nicht "Drohende Kürzungen gefährden die Pflege", sondern "Ein
  Gesetzentwurf sieht Kürzungen bei der Pflege vor."
- nicht "Partei X plant Maßnahmen, die Geflüchteten schaden", sondern
  "Die Initiatoren befürchten Verschärfungen nach der Landtagswahl."

Ein Schritt im Verfahren ist kein Grund, dann leer:
- "Der Entwurf der Haushaltssatzung liegt vor." -> ""
- "Der Stadtrat entscheidet darüber." -> ""
- "Der Plan wird regelmäßig fortgeschrieben." -> ""

Keine Zahlen, die nicht im Text stehen. Nicht die Zusammenfassung
wiederholen.

Eintrag:
Titel: {enrichment.title}
Kurz: {enrichment.summary}
Original: {listing.title}

Text von der Quelle:
{detail_text or "(kein Text)"}
"""


def parse_anlass(raw: Mapping[str, Any]) -> str:
    """The anlass call's answer as one short line. A line the model makes
    too long ends at the last full word before the limit, never mid-word."""
    anlass = _text(raw.get("anlass"))
    if len(anlass) <= _MAX_ANLASS_CHARS:
        return anlass
    cut = anlass[: _MAX_ANLASS_CHARS - 1].rsplit(" ", 1)[0]
    return cut.rstrip(" ,;:-") + "…"


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

    tags = tuple(t for t in _strings(raw.get("affected_tags")) if t in TAGS)
    snippet_keys = {key for tag in tags for key in TAG_BETROFFENHEIT_KEYS.get(tag, [])}
    candidate = _text(raw.get("kandidat"))
    lebenslagen = _lebenslagen(raw.get("lebenslagen"))
    reach = Reach.of(_text(raw.get("reichweite")))
    return Enrichment(
        is_relevant=True,
        reason=reason,
        region=region,
        everyday_relevance=everyday_relevance,
        accessibility=accessibility,
        title=title,
        summary=summary,
        affected_tags=tags,
        lebenslagen=tuple(lebenslagen),
        lebenslagen_gruende=lebenslagen,
        lebenslage_frei=_text(raw.get("lebenslage_frei")),
        geld=_geld(raw.get("geld")),
        pro_argumente=_strings(raw.get("pro_argumente"))[:_MAX_ARGUMENTS],
        contra_argumente=_strings(raw.get("contra_argumente"))[:_MAX_ARGUMENTS],
        personal_impact_snippets={
            key: value.strip()
            for key, value in _mapping(raw.get("personal_impact_snippets")).items()
            if key in snippet_keys and isinstance(value, str) and value.strip()
        },
        free_topic=_text(raw.get("thema")),
        topic_candidate=candidate if candidate in CANDIDATE_TOPICS else "",
        reach=reach,
        places=_strings(raw.get("orte"))[:_MAX_PLACES] if reach else (),
    )


def _lebenslagen(value: object) -> dict[str, str]:
    """Catalog id -> the model's reason, in the model's order. An entry
    without a reason is dropped: the reason is what keeps the model from
    padding the list with groups that are merely also affected."""
    if not isinstance(value, list):
        return {}
    reasons: dict[str, str] = {}
    for item in value:
        if not isinstance(item, dict):
            continue
        lebenslage_id, reason = _text(item.get("id")), _text(item.get("grund"))
        if lebenslage_id in LEBENSLAGEN_BY_ID and reason:
            reasons.setdefault(lebenslage_id, reason)
    return reasons


def _werte(value: object) -> dict[str, float]:
    """Statement number (1-8) and side -> questionnaire key and its sign, at
    most `_MAX_AUSSAGEN`, the first answer per statement winning."""
    werte: dict[str, float] = {}
    for item in value if isinstance(value, list) else ():
        if not isinstance(item, dict) or len(werte) == _MAX_AUSSAGEN:
            continue
        number, side = item.get("nr"), _SIDES.get(_text(item.get("dafuer_ist")))
        if isinstance(number, bool) or not isinstance(number, int) or side is None:
            continue
        if 1 <= number <= len(_AUSSAGE_KEYS):
            werte.setdefault(_AUSSAGE_KEYS[number - 1], side)
    return werte


def _geld(value: object) -> tuple[tuple[str, int], ...]:
    """Known budget areas with a direction, at most `_MAX_GELD`, one entry
    per area."""
    geld: dict[str, int] = {}
    for item in value if isinstance(value, list) else ():
        if not isinstance(item, dict) or len(geld) == _MAX_GELD:
            continue
        area = _text(item.get("bereich"))
        direction = _DIRECTIONS.get(_text(item.get("richtung")))
        if area in GELD_BEREICHE and direction is not None:
            geld.setdefault(area, direction)
    return tuple(geld.items())


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
    """`district_matchers` maps a place key to its city's districts; places
    without one never get districts."""

    def __init__(
        self,
        completer: JsonCompleter,
        district_matchers: Mapping[str, DistrictMatcher] | None = None,
    ) -> None:
        self._completer = completer
        self._district_matchers = district_matchers or {}

    async def enrich(self, listing: Listing, detail: str | None) -> Enrichment:
        """Raises on transport or format errors; the caller decides whether
        to retry (the listing stays pending until enriched)."""
        raw = await self._completer.complete_json(build_prompt(listing, detail))
        enrichment = parse_enrichment(raw)
        if not enrichment.is_relevant:
            return enrichment

        werte, anlass = await asyncio.gather(
            self._completer.complete_json(build_werte_prompt(listing, enrichment)),
            self._completer.complete_json(
                build_anlass_prompt(listing, detail, enrichment)
            ),
        )
        enrichment = replace(
            enrichment, werte_relevanz=parse_werte(werte), anlass=parse_anlass(anlass)
        )

        matcher = (
            self._district_matchers.get(enrichment.region)
            if enrichment.region
            else None
        )
        if matcher is None:
            return enrichment
        text = "\n".join(
            part for part in (listing.title, listing.summary, detail) if part
        )
        return replace(enrichment, districts=matcher.find(text))
