# Ingestion Pipeline

## Purpose
Defines the daily background process that fetches, filters, classifies,
and stores civic actions into the pool. This is the core data engine of
MeinImpact.

---

## Decisions

- **Pipeline runs once daily at 03:00 CET via APScheduler.** This is
  sufficient for the content types used (legislative timelines, petition
  milestones). Real-time ingestion is not required for MVP.

- **Pipeline is fully server-side.** No device interaction during ingestion.
  Devices download the resulting pool via the standard feed endpoint.

- **AI classification runs once per action, result is cached in DB.**
  Re-classification only occurs if the action is manually flagged or the
  classification schema changes.

- **Pipeline is fault-tolerant per source.** A single source failure
  does not abort the pipeline. See `data/sources-federal.md`.

- **Hard cost ceiling per run.** If AI spend for one pipeline run exceeds
  the configured ceiling, classification stops and remaining items are
  marked `pending_classification` for the next run.

---

## Pipeline Stages

```
Stage 0: Topic Radar              ← NEW
  DIP API + NewsData.io → ranked hot topics

Stage 1: Action Search            ← REPLACED (was: multi-source fetch)
  Per topic → find best action by priority

Stage 2: Deduplicate              ← same
Stage 3: Prefilter                ← same
Stage 4: Tavily Enrich            ← SKIPPED in MVP (see Stage 4 note)
Stage 5: Mistral Classify         ← same
Stage 6: Persist                  ← same
Stage 7: Deactivate expired       ← same
Stage 8: MdB Statements           ← same
Stage 9: Log Run                  ← same + topics_scanned, topics_above_threshold
```

---

## Stage 0: Topic Radar

Before fetching actions, the pipeline identifies which topics are currently
"burning" by combining two signals.

**Signal A — Parliamentary activity (DIP API):**
Count active Vorgang items per topic area in the last 14 days using the
`deskriptor` field to map items to our topic taxonomy.

**Signal B — News attention (NewsData.io):**
Count how many political news articles mention each topic in the last 7 days
using keyword matching per topic (e.g. `"Pflege" OR "Krankenhaus"` → `gesundheit`).

```python
TOPIC_KEYWORDS: dict[str, list[str]] = {
    "klimaschutz":   ["Klimaschutz", "CO2", "Erneuerbare", "Energiewende"],
    "soziales":      ["Sozialleistungen", "Bürgergeld", "Rente", "Pflege"],
    "demokratie":    ["Demokratie", "Verfassung", "Wahl", "Rechtsstaat"],
    "bildung":       ["Bildung", "Schule", "BAföG", "Studium"],
    "gesundheit":    ["Gesundheit", "Krankenhaus", "Pflege", "Medizin"],
    "wirtschaft":    ["Wirtschaft", "Inflation", "Haushalt", "Unternehmen"],
    "wohnen":        ["Wohnen", "Miete", "Wohnungsbau", "Mietpreise"],
    "digital":       ["Digital", "Datenschutz", "KI", "Technologie"],
    "verkehr":       ["Verkehr", "Bahn", "Straßen", "Mobilität"],
    "aussenpolitik": ["Außenpolitik", "Ukraine", "NATO", "Diplomatie"],
}

def calculate_topic_urgency(
    parliamentary_count: int,
    news_count: int,
    max_parliamentary: int,
    max_news: int,
) -> float:
    norm_parl = parliamentary_count / max(max_parliamentary, 1)
    norm_news = news_count / max(max_news, 1)
    return norm_parl * 0.6 + norm_news * 0.4
```

**Output:** Ranked list of `(topic, urgency_score)` tuples.
Only topics scoring above a minimum threshold (`TOPIC_URGENCY_THRESHOLD = 0.1`)
proceed to Stage 1.

---

## Stage 1: Action Search per Topic

For each hot topic from Stage 0, search for the single best available action
using this priority order. Only one action per topic enters the pool per run.
If a topic already has an active action in the pool, it is skipped.

```
Priority 1: Active Bundestag vote on this topic
  Source: DIP API /vorgang with topic keyword + beratungsstand="Abstimmung"
  Action type: representative_letter

Priority 2: Bundestag petition close to quorum (>30,000 signatures)
  Source: DIP API /vorgang?f.vorgangstyp=Petition
  Action type: petition_signature

Priority 3: Civil society petition with strong momentum
  Source: Tavily search restricted to weact.campact.de OR openpetition.de
  Fallback: Google Custom Search API (100 queries/day free tier)
  Action type: petition_signature

Priority 4: MdB has not publicly positioned on this topic
  Determined from mdb_statements table (found=false for this topic)
  Action type: public_question

Priority 5: Fallback — letter to MdB always possible
  No external source needed
  Action type: representative_letter
```

```python
async def find_best_action_for_topic(
    topic: str,
    keywords: list[str],
    existing_action_ids: set[str],
) -> RawSourceItem | None:
    # Try each priority in order, return first match
    for finder in [
        find_bundestag_vote,
        find_bundestag_petition,
        find_civil_society_petition,  # Tavily/Google search
        find_mdb_anfrage_opportunity,
    ]:
        result = await finder(topic, keywords)
        if result and result['source_url'] not in existing_action_ids:
            return result
    return None  # Fallback letter handled at persist time
```

**Output:** List of `RawSourceItem` dicts, one per hot topic at most.

See `data/sources-federal.md` for civil society petition search details.

---

## Stage 2: Deduplicate

Remove items already present in the `actions` table.

```python
def deduplicate(
    items: list[RawSourceItem],
    existing_urls: set[str],
    existing_titles: list[str],
) -> list[RawSourceItem]:
    new_items = []
    for item in items:
        # Exact URL match
        if item['source_url'] in existing_urls:
            continue
        # Fuzzy title match (catches same item from different sources)
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

Rule-based filtering before any AI call. Reduces AI cost by eliminating
items that would not make the feed regardless of classification.

```python
PREFILTER_RULES = [
    # Must have a minimum text length for meaningful classification
    lambda item: len(item.get('description', '') + item['title']) > 100,

    # Deadline must be in the future or absent (ongoing actions)
    lambda item: (
        item.get('deadline') is None or
        item['deadline'] > date.today()
    ),

    # WeAct petitions must have minimum momentum
    lambda item: not (
        item['type'] == 'petition' and
        item.get('signature_count', 0) < 500
    ),

    # Must be in German (lang detection)
    lambda item: detect_language(item['title']) == 'de',
]

def prefilter(items: list[RawSourceItem]) -> list[RawSourceItem]:
    return [
        item for item in items
        if all(rule(item) for rule in PREFILTER_RULES)
    ]
```

**Expected reduction:** ~60–70% of raw items are filtered out here.
Target: ≤ 30 items proceed to AI classification per daily run.

---

## Stage 4: Tavily Context Enrichment

> **MVP STATUS: SKIPPED.**
> Tavily enrichment is not run in the MVP. `tavily_context` is left empty and
> Mistral classifies from title + DIP abstract alone. This is sufficient for
> initial classification quality. Re-enable when there is a concrete use case
> that needs news coverage context (e.g. momentum scoring from media mentions,
> or richer pro/contra arguments). Requires `MEINIMPACT_TAVILY_API_KEY` to be
> set and the `TavilyClient` call to be re-enabled in the orchestrator.

For each item passing prefilter, fetch current web context.
This gives Mistral fresh background for classification and context generation.

```python
async def enrich_with_tavily(
    item: RawSourceItem,
) -> RawSourceItem:
    query = f"{item['title']} Bundestag Hintergründe Auswirkungen"
    try:
        result = await tavily_client.search(
            query=query,
            search_depth="basic",
            max_results=3,
        )
        item['tavily_context'] = "\n\n".join([
            r['content'] for r in result.get('results', [])
        ])[:2000]  # Cap at 2000 chars to control Mistral input size
    except TavilyError as e:
        sentry.capture_exception(e)
        item['tavily_context'] = ""  # Proceed without context
    return item
```

**Cost:** ~1 Tavily credit per item. At 30 items/day: ~30 credits/day,
well within rate limits.

---

## Stage 5: Mistral Classification

Each item is classified using Mistral. The result determines whether
the item enters the pool and how it will be scored and presented.

```python
CLASSIFICATION_PROMPT = """
You are a German civic action classifier. Analyse the following political
action and return ONLY valid JSON with this exact structure:

{
  "topics": ["klimaschutz", "soziales", ...],
  "urgency": "high" | "mid" | "low",
  "deadline_days": <int or null>,
  "werte_relevanz": {
    "wirtschaft": <float -1.0 to 1.0>,
    "diplomatie": <float -1.0 to 1.0>,
    "freiheit": <float -1.0 to 1.0>,
    "wandel": <float -1.0 to 1.0>
  },
  "pro_argumente": ["...", "..."],
  "contra_argumente": ["...", "..."],
  "action_types": ["brief", "petition", "anfrage"],
  -- Only these three types are valid for MVP
  "is_controversial": <bool>,
  "position_required": <bool>
}

Valid topics: klimaschutz, soziales, demokratie, bildung, gesundheit,
wirtschaft, wohnen, digital, verkehr, aussenpolitik

urgency rules:
- high: deadline within 14 days OR Bundestag vote scheduled
- mid: deadline within 60 days OR active public debate
- low: ongoing, no imminent deadline

werte_relevanz: 0.0 = axis not relevant, positive = positive pole,
negative = negative pole. See value profile spec for pole definitions.

is_controversial: true if reasonable people with different values would
strongly disagree. Used to suppress letter generation when unclear.

position_required: true if a letter can only be written from a clear
political position (cannot be neutral). If true AND user profile is
neutral on relevant axes, letter generation is suppressed.

Action and context:
Title: {title}
Description: {description}
Web context: {tavily_context}
"""

async def classify_action(item: RawSourceItem) -> ClassifiedAction | None:
    try:
        response = await mistral_client.chat.complete_async(
            model="mistral-small-latest",
            messages=[{
                "role": "user",
                "content": CLASSIFICATION_PROMPT.format(**item),
            }],
            response_format={"type": "json_object"},
            max_tokens=500,
        )
        data = json.loads(response.choices[0].message.content)
        # Validate required fields
        if not data.get('topics') or not data.get('urgency'):
            return None  # Skip malformed classifications
        return ClassifiedAction(**item, **data)
    except Exception as e:
        sentry.capture_exception(e)
        return None  # Skip on error, do not crash pipeline
```

**Cost estimate:** mistral-small, ~800 tokens input + ~200 output per item.
At 30 items/day: ~30,000 tokens/day ≈ €0.03/day.

---

## Stage 6: Persist

```python
async def persist_actions(actions: list[ClassifiedAction]) -> int:
    inserted = 0
    for action in actions:
        if action is None:
            continue
        # Check budget ceiling before each insert
        if await budget_exceeded():
            logger.warning("Budget ceiling reached, stopping classification")
            break
        await db.execute("""
            INSERT INTO actions (
                id, title, type, topics, urgency, deadline,
                source_url, external_id, pro_argumente,
                contra_argumente, werte_relevanz, tavily_context,
                action_types, is_controversial, position_required,
                momentum_score, active, created_at
            ) VALUES (
                gen_random_uuid(), :title, :type, :topics, :urgency,
                :deadline, :source_url, :external_id, :pro_argumente,
                :contra_argumente, :werte_relevanz, :tavily_context,
                :action_types, :is_controversial, :position_required,
                :momentum_score, true, now()
            )
            ON CONFLICT (source_url) DO UPDATE SET
                urgency = EXCLUDED.urgency,
                momentum_score = EXCLUDED.momentum_score,
                tavily_context = EXCLUDED.tavily_context
        """, action.dict())
        inserted += 1
    return inserted
```

**Upsert on `source_url`** allows re-runs to update urgency and context
without creating duplicates.

---

## Stage 7: Deactivate Expired

```python
async def deactivate_expired():
    await db.execute("""
        UPDATE actions
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
    topics_scanned: int,        # ← NEW: total topics evaluated in Stage 0
    topics_above_threshold: int, # ← NEW: topics that passed urgency threshold
):
    await db.execute("""
        INSERT INTO pipeline_runs (
            id, fetched_count, deduplicated_count, prefiltered_count,
            classified_count, inserted_count, errors, duration_seconds,
            ai_cost_eur, ran_at
        ) VALUES (...)
    """, ...)
```

Pipeline run logs are stored in `pipeline_runs` table for monitoring.
See `technical/monitoring.md`.

> **Schema note:** `topics_scanned` and `topics_above_threshold` are not yet
> columns in `pipeline_runs`. Add via migration when Stage 0 is implemented.

---

## Momentum Score Calculation

Each action gets a `momentum_score` (0.0–1.0) that reflects current
public attention, combined with urgency:

```python
def calculate_momentum(
    item: RawSourceItem,
    news_mention_count: int,  # How many NewsData.io articles reference it
    signature_velocity: float | None,  # Signatures/day for petitions
) -> float:
    base = 0.3

    # News mentions boost
    if news_mention_count >= 5:
        base += 0.3
    elif news_mention_count >= 2:
        base += 0.15

    # Petition velocity boost
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
DAILY_AI_BUDGET_EUR = 1.0  # Hard ceiling for ingestion pipeline

async def budget_exceeded() -> bool:
    today_spend = await db.fetchval("""
        SELECT COALESCE(SUM(cost_eur), 0)
        FROM api_spend
        WHERE date = CURRENT_DATE
        AND provider IN ('mistral', 'tavily')
    """)
    return today_spend >= DAILY_AI_BUDGET_EUR
```

If ceiling is reached: stop classification, send Sentry alert, mark
remaining items as `pending_classification` for next run.

---

## Full Pipeline Orchestration

```python
async def run_ingestion_pipeline():
    run_id = str(uuid4())
    start = time.time()
    errors = []

    # Stage 0: Topic Radar
    hot_topics = await run_topic_radar()  # list[(topic, urgency_score)]
    topics_above_threshold = [t for t, s in hot_topics if s >= TOPIC_URGENCY_THRESHOLD]

    # Stage 1: Action Search per Topic
    existing = await db.fetch_existing_urls_and_titles()
    raw_items = []
    for topic in topics_above_threshold:
        item = await find_best_action_for_topic(topic, TOPIC_KEYWORDS[topic], existing['urls'])
        if item:
            raw_items.append(item)

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
        topics_scanned=len(TOPIC_KEYWORDS),
        topics_above_threshold=len(topics_above_threshold),
    )
```

---

## MdB Statement Refresh

Runs daily as part of the pipeline (Stage 8). Searches for public statements
by tracked MdBs on topics related to active actions.

```python
async def refresh_mdb_statements():
    # Get all active actions that have push subscribers
    # (only track statements for actions users are following)
    active_actions = await db.fetch("""
        SELECT a.id, a.title, a.topics, ps.action_ids
        FROM actions a
        JOIN push_subscriptions ps ON a.id = ANY(ps.action_ids)
        WHERE a.active = true
        GROUP BY a.id
    """)

    for action in active_actions:
        # Get the MdB for each subscriber's PLZ
        # We don't store PLZ, so we track statements for the
        # most common MdBs in subscribed regions.
        # MVP simplification: track top 5 MdBs by subscription count.
        top_mdbs = await get_top_mdbs_for_action(action.id)

        for mdb in top_mdbs:
            await refresh_single_mdb_statement(action, mdb)

async def refresh_single_mdb_statement(action, mdb):
    query = (
        f"{mdb.name} {' '.join(action.topics[:2])} "
        f"Bundestag Stellungnahme Pressemitteilung"
    )
    try:
        results = await tavily_client.search(
            query=query,
            days=30,
            max_results=3,
        )

        if not results.get('results'):
            # Explicit not-found result
            await db.execute("""
                INSERT INTO mdb_statements
                    (action_id, mdb_name, mdb_aw_id, found)
                VALUES (:action_id, :mdb_name, :mdb_aw_id, false)
                ON CONFLICT (action_id, mdb_name)
                DO UPDATE SET found=false, searched_at=now()
            """, {...})
            return

        # Summarise found statements
        summary = await mistral_client.chat.complete_async(
            model="mistral-small-latest",
            messages=[{"role": "user", "content":
                f"Summarise in one sentence (German) what {mdb.name} "
                f"said about {action.title}: "
                + "
".join([r['content'] for r in results['results']])
            }],
            max_tokens=100,
        )

        await db.execute("""
            INSERT INTO mdb_statements
                (action_id, mdb_name, mdb_aw_id, found,
                 statement_summary, source_url)
            VALUES (...)
            ON CONFLICT (action_id, mdb_name)
            DO UPDATE SET
                found=true,
                statement_summary=EXCLUDED.statement_summary,
                source_url=EXCLUDED.source_url,
                searched_at=now()
        """, {...})

    except Exception as e:
        sentry.capture_exception(e)
        # Non-fatal: tracking failures don't affect main pipeline
```

**Cost estimate:** At 10 active tracked actions × 5 MdBs each:
- 50 Tavily calls/day × €0.001 = €0.05/day
- ~25 Mistral summarisations (found only) × ~150 tokens = €0.001/day
- Total: ~€0.05/day for MdB tracking

**MVP simplification:** Instead of tracking per-user MdBs (which would
require storing PLZ server-side), we track the top MdBs by number of
push subscribers per action. This gives tracking results for the most
relevant MdBs without any personal data.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/data-flow.md`,
  `data/sources-federal.md`, `data/database-schema.md`
- Referenced by: `features/feed.md`, `technical/monitoring.md`

---

## Open Questions

- [ ] Confirm Mistral JSON mode (`response_format: json_object`) is
      reliable enough without output validation schema. Add Pydantic
      validation if malformed JSON rate > 5% in testing.
- [ ] Signature velocity for WeAct: requires storing previous signature
      counts to calculate delta. Add `previous_signature_count` field
      to actions table if needed.
