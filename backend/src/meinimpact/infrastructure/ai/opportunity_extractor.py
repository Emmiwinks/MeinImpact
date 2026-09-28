"""Mistral-based extraction: a raw Tavily result -> opportunities fields.

Promoted from `scripts/dryrun_extraction.py` after two calibration rounds
(see project memory `project_tavily_retrieval_calibration.md`): the
mistral-small model produced inconsistent `personal_impact_snippets`
formatting under this prompt's multiple simultaneous constraints, fixed by
switching to `mistral-medium-latest` (config: `mistral_extraction_model`)
plus a tightened prompt. `werte_relevanz` and `personal_impact_snippets`
are additionally normalized in code after the model call — never trust the
model's own restraint to only populate tag-relevant keys.

Deliberately excludes `is_controversial`/`position_required` (dropped —
letters aren't in focus right now) and never fabricates `deadline`,
`support_count`, or `content_published_at`.
"""

import json
from datetime import UTC, date, datetime
from typing import Any, TypedDict

import httpx

from meinimpact.infrastructure.sources.tavily_opportunity_adapter import (
    RawOpportunityItem,
)

_MAX_CONTENT_CHARS = 3000

# Fixed taxonomy (rebuild plan section 2, plus Demokratieverteidigung added
# 2026-09-27 — grounded in Sachsen-Monitor 2023's "Bekämpfung des
# Rechtsextremismus" problem category) — tag -> relevant werte_relevanz
# axis/axes. Tags absent here are not value-differentiated: werte_relevanz
# stays {}.
TAG_AXES: dict[str, list[str]] = {
    "Wohnen/Miete": ["equality_markets"],
    "Mobilität/Verkehr": ["tradition_progress"],
    "Arbeit/Einkommen": ["equality_markets"],
    "Energie/Heizkosten": ["tradition_progress", "equality_markets"],
    "Bildung/Ausbildung": ["tradition_progress"],
    "Rente/Alter": ["equality_markets"],
    "Digitales/Datenschutz": ["liberty_authority"],
    "Sicherheit": ["liberty_authority"],
    "Migration/Integration": ["nation_globe"],
    "Außenpolitik/Verteidigung": ["liberty_authority"],
    "Demokratieverteidigung": ["liberty_authority"],
    "Gesundheit/Pflege": [],
    "Familie/Kinder": [],
    "Umwelt/Natur": [],
    "Selbstständigkeit/Unternehmertum": [],
}

AXIS_LANGUAGE = {
    "tradition_progress": "-1 = Bewahrung/Tradition ... +1 = Reform/Wandel",
    "equality_markets": (
        "-1 = Umverteilung/Sozialstaat ... +1 = freier Markt/Privatisierung"
    ),
    "liberty_authority": (
        "-1 = staatliche Regulierung/Eingriff ... +1 = individuelle Freiheit"
    ),
    "nation_globe": "-1 = nationaler Fokus ... +1 = international/multilateral",
}

# tag -> betroffenheitsprofil "field:value" keys worth a personal-impact
# snippet. Tags absent here get {}.
TAG_BETROFFENHEIT_KEYS: dict[str, list[str]] = {
    "Wohnen/Miete": ["wohnsituation:mieter", "wohnsituation:eigentuemer"],
    "Mobilität/Verkehr": ["oepnv_nutzung:true", "auto_nutzung:true"],
    "Arbeit/Einkommen": [
        "erwerbsstatus:angestellt",
        "erwerbsstatus:arbeitslos",
        "erwerbsstatus:selbststaendig",
    ],
    "Energie/Heizkosten": ["wohnsituation:mieter", "wohnsituation:eigentuemer"],
    "Bildung/Ausbildung": ["hat_kinder:true", "erwerbsstatus:schueler_student"],
    "Rente/Alter": ["erwerbsstatus:rentner"],
    "Migration/Integration": ["migrationshintergrund:true"],
    "Gesundheit/Pflege": ["pflege_betroffen:true"],
    "Familie/Kinder": ["hat_kinder:true"],
    "Selbstständigkeit/Unternehmertum": ["erwerbsstatus:selbststaendig"],
}

_ALL_VALID_SNIPPET_KEYS = {
    key for keys in TAG_BETROFFENHEIT_KEYS.values() for key in keys
}


class ExtractedOpportunity(TypedDict):
    """Fields matching `OpportunityRecord`, minus what the pipeline fills
    in itself (id, source_org, source_url, region, retrieved_at, active,
    updated_at)."""

    decision_object: str
    plain_language_title: str
    plain_language_summary: str
    affected_tags: list[str]
    werte_relevanz: dict[str, float]
    deadline: date | None
    support_count: int | None
    support_count_as_of: datetime | None
    content_published_at: date | None
    pro_argumente: list[str]
    contra_argumente: list[str]
    personal_impact_snippets: dict[str, str]
    action_types: list[str]


def _build_prompt(item: RawOpportunityItem) -> str:
    tag_list = "\n".join(
        f"- {tag}" + (f" (Achse: {', '.join(axes)})" if axes else " (keine Achse)")
        for tag, axes in TAG_AXES.items()
    )
    axis_list = "\n".join(f"- {axis}: {lang}" for axis, lang in AXIS_LANGUAGE.items())
    betroffenheit_list = "\n".join(
        f"- {tag}: {', '.join(keys)}" for tag, keys in TAG_BETROFFENHEIT_KEYS.items()
    )
    content = item["content"][:_MAX_CONTENT_CHARS]

    return f"""Du bist ein Extraktions-Assistent für ein deutsches Civic-Tech-Projekt.
Analysiere das folgende Suchergebnis und antworte NUR mit gültigem JSON in
dieser exakten Struktur:

{{
  "is_actionable": <bool>,
  "decision_object": "<kurze, quellenneutrale Beschreibung dessen, was konkret entschieden/gefordert wird>",
  "plain_language_title": "<als neutrale Frage formuliert, keine Kampagnensprache>",
  "plain_language_summary": "<2-3 neutrale Sätze>",
  "affected_tags": ["<tag>", ...],
  "werte_relevanz": {{"<achse>": <float -1.0 bis 1.0>, ...}},
  "deadline": "<YYYY-MM-DD oder null>",
  "support_count": <int oder null>,
  "support_count_as_of": "<YYYY-MM-DD oder null>",
  "content_published_at": "<YYYY-MM-DD oder null>",
  "pro_argumente": ["<arg>", "<arg>"],
  "contra_argumente": ["<arg>", "<arg>"],
  "personal_impact_snippets": {{"<feld:wert>": "<1 Satz: konkrete Bedeutung für diese Gruppe>", ...}},
  "action_types": ["petition" | "consultation" | "anfrage" | "brief"]
}}

is_actionable: false wenn es sich um einen reinen Nachrichtenartikel, eine
Übersichts-/Kategorieseite, eine rein informative Ankündigung ohne
Beteiligungsmöglichkeit, oder eine bereits abgeschlossene/entschiedene
Aktion handelt (z.B. eine Petition, die ihr Ziel schon erreicht hat und nur
noch als Erfolgsmeldung existiert). Wenn false: alle anderen Felder dürfen
minimal/leer bleiben.

affected_tags: NUR aus dieser festen Liste (Achse in Klammern, falls
werte-differenzierend):
{tag_list}

werte_relevanz: NUR die Achse(n) befüllen, die zum erkannten Tag passen
(siehe Zuordnung oben) — nicht alle vier erzwingen. 0.0 = Achse nicht
relevant für dieses Item. Achsen-Bedeutung (bipolar, eigene Sprache je
Achse, NIEMALS ein generisches "progressiv vs. konservativ"-Label):
{axis_list}

deadline / content_published_at: NUR wenn explizit im Text genannt.
NIEMALS erfinden — null wenn nicht vorhanden.

support_count: NUR die AKTUELLE, bereits erreichte Anzahl (z.B.
"12.345 Unterschriften" oder "12.345 von 50.000"  → 12345). NIEMALS ein
genanntes Ziel/Quorum/Minimum (das "von 50.000" in "12.345 von 50.000")
als support_count eintragen — Ziele sind kein aktueller Stand. Im Zweifel
(unklar ob Stand oder Ziel): null.
support_count_as_of: Pflichtfeld wenn support_count gesetzt ist (heutiges
Datum, falls kein anderes Datum im Text steht).

personal_impact_snippets: NUR für Gruppen, die laut dieser Zuordnung
eindeutig vom erkannten Tag betroffen sind. Format ist IMMER
{{"feld:wert": "<ganzer Satz>"}} — der Key ist exakt eine der Zeichenketten
unten (inklusive des ":wert"-Teils), der Value ist IMMER ein vollständiger
Satz, NIEMALS ein Bool oder eine Zahl. Beispiel für ein Item, das laut
Zuordnung "oepnv_nutzung:true" und "auto_nutzung:true" betrifft:
{{"oepnv_nutzung:true": "Bessere Radwege verkürzen deinen Arbeitsweg, wenn du
Bus oder Bahn nutzt.", "auto_nutzung:true": "Weniger Parkplätze könnten
deine Parkplatzsuche erschweren."}}
Leeres Objekt {{}} wenn kein Tag aus der Liste passt:
{betroffenheit_list}

action_types: welche Art von Beteiligung diese konkrete Quelle SELBST
anbietet (meist genau ein Wert) — "petition" für eine unterschreibbare
Petition, "consultation" für eine Bürgerbeteiligung/Stellungnahme/
Konsultation eines Amtes ohne Unterschriftenmechanismus, "anfrage"/"brief"
nur falls die Quelle das explizit ist.

Quelle (gefunden über eine "{item["region"]}"-Suche, das bestimmt NICHT
automatisch die Relevanz für diese Region):
Titel: {item["title"]}
URL: {item["url"]}
Domain: {item["domain"]}
Inhalt: {content}
"""


def _normalize_extraction(extracted: dict[str, Any]) -> dict[str, Any]:
    """Enforces the two constraints the model doesn't reliably self-limit
    to: werte_relevanz should only contain axes relevant to the detected
    tags, and personal_impact_snippets should only contain known
    "field:value" keys with actual sentence values. Don't trust the
    model's own restraint — filter in code."""
    tags = [t for t in (extracted.get("affected_tags") or []) if t in TAG_AXES]
    extracted["affected_tags"] = tags
    expected_axes = {axis for tag in tags for axis in TAG_AXES.get(tag, [])}
    werte = extracted.get("werte_relevanz") or {}
    extracted["werte_relevanz"] = {k: v for k, v in werte.items() if k in expected_axes}

    snippets = extracted.get("personal_impact_snippets") or {}
    extracted["personal_impact_snippets"] = {
        k: v
        for k, v in snippets.items()
        if k in _ALL_VALID_SNIPPET_KEYS and isinstance(v, str) and v.strip()
    }
    return extracted


def _parse_date(value: object) -> date | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _parse_as_of(value: object) -> datetime | None:
    parsed = _parse_date(value)
    if parsed is None:
        return None
    return datetime(parsed.year, parsed.month, parsed.day, tzinfo=UTC)


def _to_extracted(raw: dict[str, Any]) -> ExtractedOpportunity:
    return ExtractedOpportunity(
        decision_object=str(raw.get("decision_object", "")),
        plain_language_title=str(raw.get("plain_language_title", "")),
        plain_language_summary=str(raw.get("plain_language_summary", "")),
        affected_tags=list(raw.get("affected_tags") or []),
        werte_relevanz=dict(raw.get("werte_relevanz") or {}),
        deadline=_parse_date(raw.get("deadline")),
        support_count=raw.get("support_count")
        if isinstance(raw.get("support_count"), int)
        else None,
        support_count_as_of=_parse_as_of(raw.get("support_count_as_of")),
        content_published_at=_parse_date(raw.get("content_published_at")),
        pro_argumente=[str(a) for a in (raw.get("pro_argumente") or [])],
        contra_argumente=[str(a) for a in (raw.get("contra_argumente") or [])],
        personal_impact_snippets=dict(raw.get("personal_impact_snippets") or {}),
        action_types=[str(a) for a in (raw.get("action_types") or [])],
    )


class OpportunityExtractor:
    """Wraps Mistral extraction for one raw Tavily result at a time."""

    def __init__(self, api_key: str, base_url: str, model: str) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._model = model

    async def extract(self, item: RawOpportunityItem) -> ExtractedOpportunity | None:
        """Returns None when Mistral judges the item not actionable, or on
        any extraction/parsing error — callers should skip the item, not
        retry or fail the whole run over one bad result."""
        raw = await self._call_mistral(_build_prompt(item))
        if raw is None or not raw.get("is_actionable"):
            return None
        return _to_extracted(_normalize_extraction(raw))

    async def _call_mistral(self, prompt: str) -> dict[str, Any] | None:
        request_body = {
            "model": self._model,
            "stream": False,
            "temperature": 0.1,
            "response_format": {"type": "json_object"},
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 900,
        }
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self._base_url}/chat/completions",
                    headers=headers,
                    json=request_body,
                )
                response.raise_for_status()
            data = response.json()
            return dict(json.loads(data["choices"][0]["message"]["content"]))
        except Exception:
            return None
