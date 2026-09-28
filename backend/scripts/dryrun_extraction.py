#!/usr/bin/env python3
"""Step 1 dry-run, extraction stage: turn raw Tavily results (already
retrieved and saved by dryrun_retrieval.py) into the opportunities schema
fields via Mistral. Pure read-only — reads a saved retrieval JSON file,
writes an extraction JSON file, no DB writes, no new Tavily credits spent.

Schema fields produced, per the conversation that finalized them:
  decision_object, plain_language_title, plain_language_summary,
  affected_tags, werte_relevanz, deadline, support_count,
  support_count_as_of, content_published_at, pro_argumente,
  contra_argumente, personal_impact_snippets, action_types.
Also produces `is_actionable` (not persisted, dry-run-only) — operationalizes
"best result" as a pass/fail genuineness filter (real + actionable + not
already decided/expired) rather than a ranking, per the "what are the best
results" discussion. Deliberately excludes is_controversial/position_required
(dropped — letters aren't in focus right now).

Run from the backend directory:
  python scripts/dryrun_extraction.py [path/to/retrieval_*.json]
  (defaults to the most recently modified file in dryrun_output/)

Requires MEINIMPACT_MISTRAL_API_KEY in .env or env.
"""

import asyncio
import json
import os
import sys
from datetime import UTC, datetime
from pathlib import Path

import httpx

# Allow running from backend root without installing the package
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

# Load .env manually (no python-dotenv needed)
_env_path = Path(__file__).parent.parent / ".env"
if _env_path.exists():
    for line in _env_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())

MISTRAL_API_KEY = os.environ["MEINIMPACT_MISTRAL_API_KEY"]
# Round 1 (mistral-small-latest) showed inconsistent personal_impact_snippets
# formatting — testing whether a stronger model follows the multi-constraint
# prompt more reliably before concluding it needs prompt-only fixes.
MISTRAL_MODEL = os.environ.get("MEINIMPACT_DRYRUN_MISTRAL_MODEL", "mistral-medium-latest")
MISTRAL_BASE_URL = os.environ.get(
    "MEINIMPACT_MISTRAL_BASE_URL", "https://api.mistral.ai/v1"
)

_MAX_CONTENT_CHARS = 3000
_MAX_CONCURRENCY = 5

# ---------------------------------------------------------------------------
# Fixed taxonomy (spec section 2) — tag -> relevant werte_relevanz axis/axes.
# Tags absent here are not value-differentiated: werte_relevanz stays {}.
# ---------------------------------------------------------------------------

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
    # Added 2026-09-27: grounded in Sachsen-Monitor 2023 ("Bekämpfung des
    # Rechtsextremismus" — 10% cite it as Sachsen's biggest problem) and
    # broad Politbarometer-adjacent concern about extremism as a threat to
    # democracy. liberty_authority axis: a party-ban proceeding is exactly
    # the state-authority-vs-political-freedom tension that axis captures.
    "Demokratieverteidigung": ["liberty_authority"],
    "Gesundheit/Pflege": [],
    "Familie/Kinder": [],
    "Umwelt/Natur": [],
    "Selbstständigkeit/Unternehmertum": [],
}

AXIS_LANGUAGE = {
    "tradition_progress": "-1 = Bewahrung/Tradition ... +1 = Reform/Wandel",
    "equality_markets": "-1 = Umverteilung/Sozialstaat ... +1 = freier Markt/Privatisierung",
    "liberty_authority": "-1 = staatliche Regulierung/Eingriff ... +1 = individuelle Freiheit",
    "nation_globe": "-1 = nationaler Fokus ... +1 = international/multilateral",
}

# tag -> betroffenheitsprofil "field:value" keys worth a personal-impact
# snippet, drafted earlier in the conversation. Tags absent here get {}.
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


def _build_prompt(item: dict, region: str) -> str:
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

Quelle (gefunden über eine "{region}"-Suche, das bestimmt NICHT automatisch
die Relevanz für diese Region):
Titel: {item["title"]}
URL: {item["url"]}
Domain: {item["domain"]}
Inhalt: {content}
"""


_ALL_VALID_SNIPPET_KEYS = {
    key for keys in TAG_BETROFFENHEIT_KEYS.values() for key in keys
}


def _normalize_extraction(extracted: dict) -> dict:
    """Enforces the two constraints round 1 showed the model doesn't
    reliably self-limit to: werte_relevanz should only contain axes
    relevant to the detected tags, and personal_impact_snippets should
    only contain known "field:value" keys with actual sentence values.
    Don't trust the model's own restraint — filter in code."""
    tags = extracted.get("affected_tags") or []
    expected_axes = {axis for tag in tags for axis in TAG_AXES.get(tag, [])}
    werte = extracted.get("werte_relevanz") or {}
    extracted["werte_relevanz"] = {
        k: v for k, v in werte.items() if k in expected_axes
    }

    snippets = extracted.get("personal_impact_snippets") or {}
    extracted["personal_impact_snippets"] = {
        k: v
        for k, v in snippets.items()
        if k in _ALL_VALID_SNIPPET_KEYS and isinstance(v, str) and v.strip()
    }
    return extracted


async def call_mistral(client: httpx.AsyncClient, prompt: str) -> dict | None:
    request_body = {
        "model": MISTRAL_MODEL,
        "stream": False,
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 900,
    }
    headers = {
        "Authorization": f"Bearer {MISTRAL_API_KEY}",
        "Content-Type": "application/json",
    }
    try:
        response = await client.post(
            f"{MISTRAL_BASE_URL}/chat/completions",
            headers=headers,
            json=request_body,
            timeout=30.0,
        )
        response.raise_for_status()
        data = response.json()
        raw = data["choices"][0]["message"]["content"]
        return json.loads(raw)
    except Exception as exc:
        print(f"  ✗ Extraction error: {exc}")
        return None


async def extract_one(
    client: httpx.AsyncClient, sem: asyncio.Semaphore, item: dict, region: str
) -> dict:
    async with sem:
        prompt = _build_prompt(item, region)
        extracted = await call_mistral(client, prompt)
    if extracted is not None:
        extracted = _normalize_extraction(extracted)
    return {"source": item, "region": region, "extracted": extracted}


def _latest_retrieval_file() -> Path:
    out_dir = Path(__file__).parent / "dryrun_output"
    files = sorted(out_dir.glob("retrieval_*.json"), key=lambda p: p.stat().st_mtime)
    if not files:
        raise SystemExit(f"No retrieval_*.json files found in {out_dir}")
    return files[-1]


async def main() -> None:
    in_path = Path(sys.argv[1]) if len(sys.argv) > 1 else _latest_retrieval_file()
    print(f"Reading retrieval results from {in_path}")
    retrieval = json.loads(in_path.read_text())

    tasks = []
    sem = asyncio.Semaphore(_MAX_CONCURRENCY)
    async with httpx.AsyncClient() as client:
        for query in retrieval["queries"]:
            region = query["label"]
            for item in query["results"]:
                tasks.append(extract_one(client, sem, item, region))
        results = await asyncio.gather(*tasks)

    print(f"\n{'=' * 70}")
    print(f"Extracted {len(results)} items")
    print(f"{'=' * 70}")

    tag_counts: dict[str, int] = {}
    action_type_counts: dict[str, int] = {}
    actionable_count = 0
    failed_count = 0

    for r in results:
        e = r["extracted"]
        print(f"\n[{r['region']}] {r['source']['title']}")
        print(f"  url: {r['source']['url']}")
        if e is None:
            print("  ✗ EXTRACTION FAILED")
            failed_count += 1
            continue
        print(f"  is_actionable: {e.get('is_actionable')}")
        if not e.get("is_actionable"):
            continue
        actionable_count += 1
        print(f"  decision_object:   {e.get('decision_object')}")
        print(f"  plain_language_title: {e.get('plain_language_title')}")
        print(f"  affected_tags:     {e.get('affected_tags')}")
        print(f"  werte_relevanz:    {e.get('werte_relevanz')}")
        print(f"  deadline:          {e.get('deadline')}")
        print(f"  support_count:     {e.get('support_count')} (as of {e.get('support_count_as_of')})")
        print(f"  content_published_at: {e.get('content_published_at')}")
        print(f"  pro_argumente:     {e.get('pro_argumente')}")
        print(f"  contra_argumente:  {e.get('contra_argumente')}")
        print(f"  personal_impact_snippets: {e.get('personal_impact_snippets')}")
        print(f"  action_types:      {e.get('action_types')}")
        for tag in e.get("affected_tags") or []:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1
        for at in e.get("action_types") or []:
            action_type_counts[at] = action_type_counts.get(at, 0) + 1

    print(f"\n{'=' * 70}")
    print(
        f"Summary: {actionable_count}/{len(results)} marked actionable, "
        f"{failed_count} extraction failures"
    )
    print("\nTag distribution (actionable items only):")
    for tag, count in sorted(tag_counts.items(), key=lambda kv: -kv[1]):
        print(f"  {count:3d}  {tag}")
    print("\naction_types distribution:")
    for at, count in sorted(action_type_counts.items(), key=lambda kv: -kv[1]):
        print(f"  {count:3d}  {at}")
    print(f"{'=' * 70}")

    out_dir = Path(__file__).parent / "dryrun_output"
    out_path = out_dir / f"extraction_{datetime.now(UTC):%Y%m%d_%H%M%S}.json"
    out_path.write_text(json.dumps(results, indent=2, ensure_ascii=False))
    print(f"\nSaved full output to {out_path}")


if __name__ == "__main__":
    asyncio.run(main())
