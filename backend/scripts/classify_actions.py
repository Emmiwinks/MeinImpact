#!/usr/bin/env python3
"""Classify all seeded civic actions using Mistral and update the database.

Reads civic_actions, runs Mistral classification on each, and writes back:
  pro_argumente, contra_argumente, action_types, is_controversial,
  position_required, werte_relevanz (refined), urgency (refined), topics.

Run from the backend directory:
  python scripts/classify_actions.py

Requires MEINIMPACT_MISTRAL_API_KEY and MEINIMPACT_DATABASE_URL in .env or env.
"""

import asyncio
import json
import os
import sys
from pathlib import Path

# Allow running from backend root without installing the package
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import asyncpg
import httpx

# Load .env manually (no python-dotenv needed)
_env_path = Path(__file__).parent.parent / ".env"
if _env_path.exists():
    for line in _env_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())

MISTRAL_API_KEY = os.environ["MEINIMPACT_MISTRAL_API_KEY"]
DATABASE_URL = os.environ["MEINIMPACT_DATABASE_URL"]
MISTRAL_MODEL = os.environ.get("MEINIMPACT_MISTRAL_MODEL", "mistral-small-latest")
MISTRAL_BASE_URL = os.environ.get(
    "MEINIMPACT_MISTRAL_BASE_URL", "https://api.mistral.ai/v1"
)

# asyncpg needs a plain postgresql:// URL
PG_DSN = DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")

CLASSIFICATION_PROMPT = """Du bist ein deutscher Civic-Tech-Klassifikator für politische Aktionen.

Analysiere folgende Bürgeraktion und antworte NUR mit gültigem JSON in dieser exakten Struktur:

{{
  "topics": ["<topic>", ...],
  "urgency": "high",
  "werte_relevanz": {{
    "wirtschaft": 0.0,
    "diplomatie": 0.0,
    "freiheit": 0.0,
    "wandel": 0.0
  }},
  "pro_argumente": ["<arg>", "<arg>", "<arg>"],
  "contra_argumente": ["<arg>", "<arg>", "<arg>"],
  "action_types": ["brief"],
  "is_controversial": false,
  "position_required": false
}}

Gültige Topics (nur diese verwenden): klimaschutz, soziales, demokratie, bildung,
gesundheit, wirtschaft, wohnen, digital, verkehr, aussenpolitik

urgency-Regeln:
- high: Abstimmung/Frist innerhalb 14 Tagen
- mid: Frist innerhalb 60 Tagen ODER aktive öffentliche Debatte
- low: laufend, keine unmittelbare Frist

werte_relevanz (Achsen, float -1.0 bis +1.0):
- wirtschaft: -1=Umverteilung/Sozialstaat … +1=freier Markt/Privatisierung
- diplomatie: -1=nationaler Fokus … +1=international/multilateral
- freiheit:   -1=staatl. Eingriff/Regulierung … +1=individuelle Freiheit
- wandel:     -1=Bewahrung/Tradition … +1=Reform/Veränderung
- 0.0 = Achse irrelevant

pro_argumente: genau 3 konkrete Argumente FÜR diese Aktion
contra_argumente: genau 3 Gegenargumente/Abwägungen
action_types: ["brief"] und/oder ["petition"] und/oder ["anfrage"] — je nach Aktion

is_controversial: true NUR bei starker gesellschaftlicher Spaltung (Migration, Abtreibung, Waffen)
position_required: true wenn Brief/Anfrage eine klare Positionierung erfordert

Aktion:
Titel: {title}
Typ: {action_type}
Zusammenfassung: {summary}
"""


async def call_mistral(prompt: str) -> dict | None:
    """Calls Mistral API with JSON mode and returns parsed result."""
    request_body = {
        "model": MISTRAL_MODEL,
        "stream": False,
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 700,
    }
    headers = {
        "Authorization": f"Bearer {MISTRAL_API_KEY}",
        "Content-Type": "application/json",
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            f"{MISTRAL_BASE_URL}/chat/completions",
            headers=headers,
            json=request_body,
        )
        response.raise_for_status()
        data = response.json()
        raw = data["choices"][0]["message"]["content"]
        return json.loads(raw)


async def classify_action(action: dict) -> dict | None:
    """Runs Mistral classification for a single action."""
    prompt = CLASSIFICATION_PROMPT.format(
        title=action["title"],
        action_type=action["action_type"],
        summary=action["summary"],
    )
    try:
        result = await call_mistral(prompt)
        if not result or not result.get("topics") or not result.get("urgency"):
            print(f"  ⚠ Malformed classification — missing required fields")
            return None
        return result
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None


async def main() -> None:
    print("Connecting to database …")
    conn = await asyncpg.connect(PG_DSN)

    print("Fetching civic actions …")
    actions = await conn.fetch(
        "SELECT id, title, action_type, summary FROM civic_actions ORDER BY id"
    )
    print(f"Found {len(actions)} actions.\n")

    results: list[dict] = []

    for action in actions:
        a = dict(action)
        print(f"▸ {a['title'][:65]}")
        classification = await classify_action(a)

        if classification is None:
            print("  ↳ Skipped\n")
            continue

        await conn.execute(
            """
            UPDATE civic_actions SET
                topics            = $1::jsonb,
                urgency           = $2::text,
                werte_relevanz    = $3::jsonb,
                pro_argumente     = $4::text[],
                contra_argumente  = $5::text[],
                action_types      = $6::text[],
                is_controversial  = $7::boolean,
                position_required = $8::boolean,
                updated_at        = now()
            WHERE id = $9::text
            """,
            json.dumps(classification["topics"]),
            classification["urgency"],
            json.dumps(classification["werte_relevanz"]),
            classification["pro_argumente"],
            classification["contra_argumente"],
            classification["action_types"],
            classification["is_controversial"],
            classification["position_required"],
            a["id"],
        )

        results.append({**a, **classification})
        print(f"  topics:  {', '.join(classification['topics'])}")
        print(f"  urgency: {classification['urgency']}")
        werte = {k: v for k, v in classification["werte_relevanz"].items() if v != 0.0}
        print(f"  werte:   {werte}")
        print(f"  types:   {classification['action_types']}")
        flags = []
        if classification["is_controversial"]:
            flags.append("controversial")
        if classification["position_required"]:
            flags.append("position_required")
        if flags:
            print(f"  flags:   {', '.join(flags)}")
        print()

    await conn.close()

    print("=" * 70)
    print(f"✓ Classified {len(results)}/{len(actions)} actions.\n")
    print("REVIEW TABLE")
    print("=" * 70)
    for r in results:
        print(f"\n{r['title']}")
        print(f"  Topics:   {', '.join(r['topics'])}")
        print(f"  Urgency:  {r['urgency']}")
        werte = {k: v for k, v in r["werte_relevanz"].items() if v != 0.0}
        print(f"  Werte:    {werte}")
        print(f"  Types:    {r['action_types']}")
        print(f"  Pro:")
        for arg in r["pro_argumente"]:
            print(f"    + {arg}")
        print(f"  Contra:")
        for arg in r["contra_argumente"]:
            print(f"    - {arg}")
        flags = []
        if r["is_controversial"]:
            flags.append("controversial")
        if r["position_required"]:
            flags.append("position_required")
        if flags:
            print(f"  Flags:    {', '.join(flags)}")


if __name__ == "__main__":
    asyncio.run(main())
