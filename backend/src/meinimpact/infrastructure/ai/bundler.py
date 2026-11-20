"""Bundles opportunities on one matter into one card with options.

Two calls keep it cheap and careful:
1. `propose_groups`: one call over every open opportunity's title and
   summary proposes groups about the same concrete matter (the same site,
   the same bath, the same law). Proposals only.
2. `describe`: per proposed group, with each option's full text, the model
   confirms it is one matter and writes the card: a header, a shared title
   and summary, and per option a label and the sentence that says how it
   differs from the others. That sentence is what lets people pick.

Rules the model cannot overrule: 2 to `MAX_OPTIONS` options of one kind,
and council decisions only from the same body (the same budget in two
bodies goes to two different sets of recipients).
"""

import hashlib
import uuid
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import date
from typing import Any

from meinimpact.infrastructure.ai.mistral_json import JsonCompleter
from meinimpact.infrastructure.listings.model import ActionKind

BUNDLE_VERSION = "1"
MAX_OPTIONS = 4
_MAX_DETAIL_CHARS = 2500


@dataclass(frozen=True, slots=True)
class BundleItem:
    """One open opportunity as the bundler sees it."""

    id: uuid.UUID
    # (source_id, external_id): finds the run's listing for its full text
    key: tuple[str, str]
    kind: str
    source_org: str
    organizer: str | None
    # The registry's own title: plan numbers and parts ("Nord", "Süd") that
    # tell options apart are often only here
    registry_title: str
    title: str
    summary: str
    closes_on: date | None
    # Changes whenever the opportunity's own text changes
    enrichment_input_hash: str
    # The bundle it is in now, and that bundle's input hash
    bundle_id: uuid.UUID | None = None
    bundle_input_hash: str | None = None


@dataclass(frozen=True, slots=True)
class BundleOption:
    label: str
    difference: str


@dataclass(frozen=True, slots=True)
class Bundle:
    header: str
    title: str
    summary: str
    options: Mapping[uuid.UUID, BundleOption]


def bundle_input_hash(items: Sequence[BundleItem]) -> str:
    """Fingerprint of a group: its members, their texts and the bundler
    version, so an unchanged group is never described twice."""
    text = "\n".join(
        [BUNDLE_VERSION, *sorted(f"{i.id}:{i.enrichment_input_hash}" for i in items)]
    )
    return hashlib.sha256(text.encode()).hexdigest()


def allowed(items: Sequence[BundleItem]) -> bool:
    if not 2 <= len(items) <= MAX_OPTIONS:
        return False
    if len({i.kind for i in items}) != 1:
        return False
    if items[0].kind == ActionKind.DECISION.value:
        return len({i.organizer for i in items}) == 1
    return True


def build_grouping_prompt(items: Sequence[BundleItem]) -> str:
    lines = "\n".join(
        f"{n}. [{i.kind}; {i.source_org}; {i.organizer or '-'}; "
        f"bis {i.closes_on or '-'}] {i.title} ({i.registry_title}): {i.summary}"
        for n, i in enumerate(items, start=1)
    )
    return f"""Unten stehen offene Beteiligungsmöglichkeiten einer
Bürger-App, jede mit Nummer. Finde Gruppen, die um GENAU DIESELBE konkrete
Sache gehen: dasselbe Gelände oder Gebäude, dasselbe Gesetz oder Vorhaben,
dieselbe Förderentscheidung. Etwa zwei Planverfahren für dasselbe Gelände
oder zwei Petitionen gegen dasselbe Gesetz.

Fast gleiche Titel sind meistens dieselbe Sache, schlage sie vor. Gleiche
Straße, gleiches Bad oder gleiches Gesetz in verschiedenen Einträgen auch.
KEINE Gruppe, wenn nur das Thema ähnlich ist (zwei verschiedene
Baugebiete, zwei verschiedene Pflegereformen, verschiedene Bäder, zwei
verschiedene EU-Initiativen). Die meisten Einträge gehören in keine Gruppe.
Die Vorschläge werden danach einzeln genau geprüft.

Antworte NUR mit JSON: {{"gruppen": [[<Nummer>, <Nummer>, ...], ...]}}
Leere Liste, wenn es keine gibt.

{lines}
"""


def parse_groups(raw: Mapping[str, Any], count: int) -> list[list[int]]:
    """0-based indexes per group; anything malformed is dropped."""
    groups = raw.get("gruppen")
    if not isinstance(groups, list):
        return []
    seen: set[int] = set()
    parsed = []
    for group in groups:
        if not isinstance(group, list):
            continue
        members = sorted(
            {n - 1 for n in group if isinstance(n, int) and 1 <= n <= count} - seen
        )
        if len(members) >= 2:
            seen.update(members)
            parsed.append(members)
    return parsed


def build_describe_prompt(
    items: Sequence[BundleItem], details: Sequence[str | None]
) -> str:
    blocks = "\n\n".join(
        f"OPTION {n}\nArt: {i.kind}\nQuelle: {i.source_org}\n"
        f"Veranstalter/Behörde: {i.organizer or '-'}\nFrist: {i.closes_on or '-'}\n"
        f"Originaltitel: {i.registry_title}\nTitel: {i.title}\nKurztext: {i.summary}\n"
        f"Volltext:\n{(detail or '(kein weiterer Text)')[:_MAX_DETAIL_CHARS]}"
        for n, (i, detail) in enumerate(zip(items, details, strict=True), start=1)
    )
    return f"""Du arbeitest für eine neutrale deutsche Civic-Tech-App. Unten
stehen {len(items)} Beteiligungsmöglichkeiten, die vielleicht um dieselbe
konkrete Sache gehen. Die App soll sie als EINE Karte mit mehreren
Optionen zeigen, damit sich Menschen die passende aussuchen können.

Prüfe streng, Schritt für Schritt:
1. Nenne für jede Option ihren Gegenstand: das konkrete Gelände, Gebäude,
   Gesetz, Vorhaben oder die konkrete Förderentscheidung, in höchstens 10
   Wörtern, nur aus dem Text.
2. "zusammen": die Nummern der Optionen, deren Gegenstand DERSELBE ist.
   Ein ähnliches Thema reicht nicht. Verschiedene EU-Initiativen, verschiedene
   Gesetze, verschiedene Grundstücke oder Einrichtungen sind verschieden,
   auch wenn sie ähnlich klingen. Gehören nur einige zusammen, nenne nur
   diese. Gehören weniger als zwei zusammen oder bist du unsicher: leere
   Liste und alles andere leer.

Für die Optionen in "zusammen" schreibe in einfacher, neutraler Sprache,
nur mit Angaben aus den Texten (keine Gremien, Orte oder Zahlen, die nicht
dort stehen):
- kopfzeile: was gebündelt ist, z.B. "2 Petitionen · ähnliches Anliegen"
  oder "2 Planauslegungen · ein Ort"
- titel: eine kurze neutrale Frage zur gemeinsamen Sache
- zusammenfassung: 2 kurze Sätze, worum es geht
- pro Option:
  - label: woran man sie erkennt, kurz (z.B. "Bei openPetition, an den
    Bundestag", "Bebauungsplan", "Weiterbetrieb ab 2027")
  - unterschied: EIN Satz, was genau diese Option will oder entscheidet,
    im Unterschied zu den anderen. Nur was im Text steht, nichts erfinden.
    Unterscheiden sich zwei Optionen kaum, sag das ehrlich.

Antworte NUR mit JSON:
{{"gegenstaende": [{{"nummer": <1-{len(items)}>, "gegenstand": ""}}],
  "zusammen": [<Nummer>, ...], "kopfzeile": "", "titel": "",
  "zusammenfassung": "",
  "optionen": [{{"nummer": <Nummer aus zusammen>, "label": "", "unterschied": ""}}]}}

{blocks}
"""


def parse_bundle(raw: Mapping[str, Any], items: Sequence[BundleItem]) -> Bundle | None:
    """The options the model found to share one matter, each described;
    None when fewer than two do or any of them lacks its texts."""
    together = {
        n
        for n in raw.get("zusammen") or []
        if isinstance(n, int) and 1 <= n <= len(items)
    }
    texts = [str(raw.get(k) or "").strip() for k in ("kopfzeile", "titel")]
    summary = str(raw.get("zusammenfassung") or "").strip()
    options: dict[uuid.UUID, BundleOption] = {}
    for entry in raw.get("optionen") or []:
        if not isinstance(entry, Mapping):
            continue
        number = entry.get("nummer")
        label = str(entry.get("label") or "").strip()
        difference = str(entry.get("unterschied") or "").strip()
        if number in together and label and difference:
            options[items[number - 1].id] = BundleOption(label, difference)
    members = [items[n - 1] for n in sorted(together)]
    if (
        not all(texts)
        or not summary
        or len(options) != len(together)
        or not allowed(members)
    ):
        return None
    return Bundle(header=texts[0], title=texts[1], summary=summary, options=options)


class Bundler:
    def __init__(self, completer: JsonCompleter) -> None:
        self._completer = completer

    async def propose_groups(
        self, items: Sequence[BundleItem]
    ) -> list[list[BundleItem]]:
        if len(items) < 2:
            return []
        raw = await self._completer.complete_json(build_grouping_prompt(items))
        indexes = parse_groups(raw, len(items))
        # Identical card titles are always worth a check; the model's list
        # pass misses some (two petitions against one law).
        grouped = {n for group in indexes for n in group}
        by_title: dict[str, list[int]] = {}
        for n, item in enumerate(items):
            if n not in grouped:
                by_title.setdefault(item.title.strip().casefold(), []).append(n)
        indexes += [group for group in by_title.values() if len(group) >= 2]
        groups = [[items[n] for n in group] for group in indexes]
        return [group for group in groups if allowed(group)]

    async def describe(
        self, items: Sequence[BundleItem], details: Sequence[str | None]
    ) -> Bundle | None:
        raw = await self._completer.complete_json(build_describe_prompt(items, details))
        return parse_bundle(raw, items)
