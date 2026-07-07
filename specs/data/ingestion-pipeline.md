# Ingestion Pipeline

## Purpose
Defines the daily background process that fetches, filters, classifies,
and stores civic actions into the pool. This is the core data engine of
MeinImpact.

---

## Decisions

- **Pipeline runs once daily at 03:00 CET via APScheduler.** Sufficient
  for the content types used (legislative timelines, petition milestones).

- **Pipeline is fully server-side.** No device interaction during ingestion.
  Devices download the resulting pool via the standard feed endpoint.

- **No topic taxonomy.** Actions are not bucketed into predefined categories.
  Hotness is determined by parliamentary process stage and recency, not by
  keyword matching against a fixed topic list. This allows the pipeline to
  surface any politically relevant action regardless of subject area.

- **AI classification runs once per action, result is cached in DB.**
  Re-classification only occurs if the action is manually flagged or the
  classification schema changes.

- **Pipeline is fault-tolerant per source.** A single source failure
  does not abort the pipeline.

- **Hard cost ceiling per run.** If AI spend for one pipeline run exceeds
  the configured ceiling, classification stops and remaining items are
  marked `pending_classification` for the next run.

---

## Pipeline Stages

```
Stage 0: Hotness Evaluation
  DIP API → items in active beratungsstand + recent activity → imminence score

Stage 1: Civil Society Petitions
  Tavily → broad petition search on WeAct + openPetition

Stage 2: Deduplicate
Stage 3: Prefilter
Stage 4: Tavily Enrich            ← SKIPPED in MVP
Stage 5: Mistral Classify
Stage 6: Persist
Stage 7: Deactivate expired
Stage 8: MdB Statements
Stage 9: Log Run
```

---

## Stage 0: Hotness Evaluation

Fetches Bundestag Vorgänge that are in an active deliberation stage and
have had recent parliamentary activity. These are items where a decision
is approaching and citizen action is still timely.

**DIP query strategy:**

Two passes against the DIP `/vorgang` endpoint, combined:

**Pass A — Late-stage deliberation (vote imminent):**
```
f.beratungsstand = "2. Beratung"
f.beratungsstand = "2. Beratung und Schlussabstimmung"
f.beratungsstand = "3. Beratung"
f.aktualisiert.start = {7 days ago}
```

**Pass B — Active committee deliberation:**
```
f.beratungsstand = "Ausschussberatung"
f.aktualisiert.start = {3 days ago}
```

Each item receives an **imminence score** (0.0–1.0):

```python
BERATUNGSSTAND_SCORE: dict[str, float] = {
    "2. Beratung und Schlussabstimmung": 1.0,
    "3. Beratung":                        1.0,
    "2. Beratung":                        0.8,
    "Ausschussberatung":                  0.5,
}

def calculate_imminence(item: RawSourceItem, now: date) -> float:
    stage_score = BERATUNGSSTAND_SCORE.get(item["status"], 0.3)
    days_since_activity = (now - item["deadline"]).days if item["deadline"] else 7
    recency_score = max(0.0, 1.0 - days_since_activity / 7.0)
    return stage_score * 0.7 + recency_score * 0.3
```

Open Bundestag Petitionen (`f.vorgangstyp=Petition`,
`f.beratungsstand=Noch nicht beraten`) are always included regardless of
imminence score — they are inherently actionable while open.

**Output:** List of `RawSourceItem` dicts with `imminence_score` attached,
sorted descending. No minimum threshold — all fetched items proceed to
Stage 1 combination.

**Cost:** 2–3 DIP API calls per run (one per beratungsstand pass + petitions).
DIP is free with an API key.

---

## Stage 1: Civil Society Petitions

Independently of Stage 0, search for currently active civil society
petitions. These run in parallel with the DIP fetch and are merged before
deduplication.

```python
async def fetch_civil_petitions(tavily_api_key: str) -> list[RawSourceItem]:
    """Broad search for active petitions on WeAct and openPetition."""
    query = "Petition unterzeichnen aktuell 2026"
    results = await tavily_client.search(
        query,
        include_domains=["weact.campact.de", "openpetition.de"],
        max_results=10,
        days=30,
    )
    return [_parse_tavily_petition(r) for r in results if r.get("url")]
```

No topic filtering. All returned petitions proceed to deduplication.

**Fallback:** Google Custom Search API if Tavily returns no results
(`site:openpetition.de OR site:weact.campact.de Petition unterzeichnen`).
Free tier: 100 queries/day.

---

## Stage 2: Deduplicate

Remove items already present in the `civic_actions` table.

```python
def deduplicate(
    items: list[RawSourceItem],
    existing_urls: set[str],
    existing_titles: list[str],
) -> list[RawSourceItem]:
    new_items = []
    for item in items:
        if item['source_url'] in existing_urls:
            continue
        if any(
            fuzz.ratio(item['title'], t) > 85
            for t in existing_titles
        ):
            continue
        new_items.append(item)
    return new_items
```

Library: `thefuzz` (lightweight string matching).

---

## Stage 3: Prefilter

Rule-based filtering before any AI call.

```python
PREFILTER_RULES = [
    # Must have a minimum title length
    lambda item: len(item['title']) >= 10,

    # Deadline must be in the future or absent (ongoing actions)
    lambda item: (
        item.get('deadline') is None or
        item['deadline'] > date.today()
    ) if item['type'] == 'petition' else True,

    # Petitions must have minimum momentum
    lambda item: not (
        item['type'] == 'petition' and
        item.get('signature_count', None) is not None and
        item['signature_count'] < 500
    ),

    # Must be in German (lang detection)
    lambda item: detect_language(item['title']) == 'de',
]
```

**Expected reduction:** ~40–60% of raw items filtered here.
Target: ≤ 30 items proceed to AI classification per daily run.

---

## Stage 4: Tavily Context Enrichment

> **MVP STATUS: SKIPPED.**
> Tavily enrichment is not run in the MVP. `tavily_context` is left empty and
> Mistral classifies from title + DIP abstract alone. Re-enable when richer
> classification context is needed. Requires `MEINIMPACT_TAVILY_API_KEY`.

---

## Stage 5: Mistral Classification

Each item is classified using Mistral. The result determines whether
the item enters the pool and how it will be scored and presented.

```python
CLASSIFICATION_PROMPT = """
You are a German civic action classifier. Analyse the following political
action and return ONLY valid JSON with this exact structure:

{
  "urgency": "high" | "mid" | "low",
  "werte_relevanz": {
    "wirtschaft": <float -1.0 to 1.0>,
    "diplomatie": <float -1.0 to 1.0>,
    "freiheit": <float -1.0 to 1.0>,
    "wandel": <float -1.0 to 1.0>
  },
  "pro_argumente": ["...", "..."],
  "contra_argumente": ["...", "..."],
  "action_types": ["brief", "petition", "anfrage"],
  "is_controversial": <bool>,
  "position_required": <bool>
}

urgency rules:
- high: deadline within 14 days OR Bundestag vote imminent (2./3. Beratung)
- mid: deadline within 60 days OR active committee deliberation
- low: ongoing, no imminent deadline

werte_relevanz: 0.0 = axis not relevant, positive = positive pole,
negative = negative pole.

is_controversial: true if reasonable people with different values would
strongly disagree.
position_required: true if a letter can only be written from a clear
political position.

Action and context:
Title: {title}
Description: {description}
Parliamentary status: {status}
Web context: {tavily_context}
"""
```

**Cost estimate:** mistral-small, ~600 tokens input + ~150 output per item.
At 30 items/day: ~22,500 tokens/day ≈ €0.02/day.

---

## Stage 6: Persist

```python
async def persist_actions(actions: list[ClassifiedAction], news_counts: dict[str, int]) -> int:
    inserted = 0
    for action in actions:
        if action is None:
            continue
        if await budget_exceeded():
            logger.warning("Budget ceiling reached, stopping classification")
            break
        await db.execute("""
            INSERT INTO civic_actions (
                id, title, action_type, summary, urgency, deadline,
                source_url, external_id, pro_argumente,
                contra_argumente, werte_relevanz, tavily_context,
                action_types, is_controversial, position_required,
                momentum_score, active, updated_at
            ) VALUES (...)
            ON CONFLICT (source_url) DO UPDATE SET
                urgency = EXCLUDED.urgency,
                momentum_score = EXCLUDED.momentum_score,
                tavily_context = EXCLUDED.tavily_context,
                updated_at = now()
        """, action.dict())
        inserted += 1
    return inserted
```

**Momentum score** is calculated at persist time from the item's
`imminence_score` (from Stage 0) combined with petition velocity:

```python
def calculate_momentum(imminence_score: float, signature_velocity: float | None) -> float:
    base = 0.3 + imminence_score * 0.4   # 0.3–0.7 from parliamentary stage

    if signature_velocity is not None:
        if signature_velocity > 1000:
            base += 0.3
        elif signature_velocity > 100:
            base += 0.15

    return min(base, 1.0)
```

**Upsert on `source_url`** allows re-runs to update urgency and momentum
without creating duplicates.

---

## Stage 7: Deactivate Expired

```python
async def deactivate_expired():
    await db.execute("""
        UPDATE civic_actions
        SET active = false
        WHERE deadline IS NOT NULL
        AND deadline < now() - INTERVAL '7 days'
        AND active = true
    """)
```

7-day grace period allows tracking completion events after deadline.

---

## Stage 9: Log Run

```python
async def log_run(
    run_id: str,
    fetched: int,
    deduplicated: int,
    prefiltered: int,
    classified: int,
    inserted: int,
    errors: list[str],
    duration_seconds: float,
    ai_cost_eur: float,
    hot_items_count: int,      # items from Stage 0 DIP fetch
    petition_count: int,       # items from Stage 1 Tavily fetch
):
```

---

## Momentum Score Calculation

Each action gets a `momentum_score` (0.0–1.0):

```python
def calculate_momentum(
    imminence_score: float,         # From Stage 0 beratungsstand scoring
    signature_velocity: float | None,  # Signatures/day for petitions
) -> float:
    base = 0.3 + imminence_score * 0.4

    if signature_velocity is not None:
        if signature_velocity > 1000:
            base += 0.3
        elif signature_velocity > 100:
            base += 0.15

    return min(base, 1.0)
```

---

## Budget Ceiling

```python
DAILY_AI_BUDGET_EUR = 1.0

async def budget_exceeded() -> bool:
    today_spend = await db.fetchval("""
        SELECT COALESCE(SUM(cost_eur), 0)
        FROM api_spend
        WHERE date = CURRENT_DATE
        AND provider IN ('mistral', 'tavily')
    """)
    return today_spend >= DAILY_AI_BUDGET_EUR
```

---

## Full Pipeline Orchestration

```python
async def run_ingestion_pipeline():
    run_id = str(uuid4())
    start = time.time()
    errors = []

    # Stage 0: Hotness Evaluation (DIP)
    dip_items = await fetch_hot_dip_items(settings, errors)

    # Stage 1: Civil Society Petitions (Tavily)
    petition_items = await fetch_civil_petitions(settings, errors)

    raw_items = dip_items + petition_items

    existing = await db.fetch_existing_urls_and_titles()

    # Stage 2
    new_items = deduplicate(raw_items, **existing)

    # Stage 3
    filtered_items = prefilter(new_items)

    # Stage 4: SKIPPED in MVP
    enriched = filtered_items

    # Stage 5
    classified = await asyncio.gather(*[
        classify_action(item) for item in enriched
    ])

    # Stage 6
    inserted = await persist_actions(classified)

    # Stage 7
    await deactivate_expired()

    # Stage 8: MdB statement tracking
    await refresh_mdb_statements()

    # Stage 9
    await log_run(
        run_id=run_id,
        fetched=len(raw_items),
        deduplicated=len(new_items),
        prefiltered=len(filtered_items),
        classified=sum(1 for c in classified if c is not None),
        inserted=inserted,
        errors=errors,
        duration_seconds=time.time() - start,
        ai_cost_eur=await get_today_ai_spend(),
        hot_items_count=len(dip_items),
        petition_count=len(petition_items),
    )
```

---

## MdB Statement Refresh

Stage 8 — unchanged from previous spec. Runs daily as part of the pipeline.
Searches for public statements by tracked MdBs on topics related to active
actions. See `data/sources-federal.md` for implementation details.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/data-flow.md`,
  `data/sources-federal.md`, `data/database-schema.md`
- Referenced by: `features/feed.md`, `technical/monitoring.md`

---

## Open Questions

- [ ] Confirm exact `beratungsstand` string values used by DIP for each
      deliberation stage. Current values are best-guess; verify against
      live API data before relying on them for imminence scoring.
- [ ] Signature velocity for WeAct: requires storing previous signature
      counts. Add `previous_signature_count` field to civic_actions if needed.
