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
  Relevance is determined by engagement state (see below), not by keyword
  matching against a fixed topic list. This allows the pipeline to surface
  any politically relevant action regardless of subject area.

- **Relevance is a state, not a score.** Every action is assigned an
  `engagement_state` (A/B/C/D) instead of a weighted numeric hotness score.
  States are explainable to users in one sentence and map directly to a
  concrete reason to act now. See "Engagement States" below.

- **Two parallel pipelines feed one shared pool.** Parliamentary-driven
  actions (top-down, from DIP) and petition-driven actions (bottom-up,
  from citizen petition platforms) are fetched, evaluated, and classified
  independently, then merged and deduplicated before persisting.

- **AI classification runs once per action, result is cached in DB.**
  Re-classification only occurs if the action is manually flagged or the
  classification schema changes.

- **Pipeline is fault-tolerant per source.** A single source failure
  does not abort the pipeline.

- **Hard cost ceiling per run.** If AI spend for one pipeline run exceeds
  the configured ceiling, classification stops and remaining items are
  marked `pending_classification` for the next run.

---

## Engagement States

Every action in the pool gets an `engagement_state` field (`A` | `B` | `C`).
State `D` means "no good hook for citizen engagement right now" — `D`
actions are discarded before classification and never enter the pool.
This is an honest signal, not a system failure.

The state determines:
1. Whether the action enters the pool at all (`D` = excluded)
2. Its priority in the feed (`A` > `B` > `C`)
3. The `state_reason` shown to the user for why they should act now

**State A — Decision window open.**
A formal parliamentary process is active and time-bound: a vote is
scheduled, a committee is actively deliberating, or a petition deadline
or quorum is close. Highest priority. The user is told exactly when the
window closes.

**State B — Positioning window open.**
No formal process is running, but positions on the topic are structurally
still forming — a Vorgang referred to committee with no vote result yet,
cross-party positioning still incomplete, or an early legislative reading
with no vote scheduled (see "State Determination: Parliamentary Actions"
below for the exact DIP-derived signals). Letters and questions sent now
can shape positions before they harden — often more effective than acting
immediately before a vote. This is an action-level property, not a
per-user one: the app additionally personalises the displayed reason
client-side using the user's own MdB (see "State B triggers" below).
Does not apply to citizen petitions (no single MdB to target).

**State C — Debate window open.**
The topic is publicly present in media and public discourse but has not
yet entered a formal parliamentary process. Engagement helps push the
topic onto the parliamentary agenda.

**State D — No window.**
Potentially relevant, but no good engagement hook exists right now.
Not classified, not added to the pool.

---

## Two Parallel Pipelines, One Shared Pool

### Pipeline 1: Parliamentary-driven (top-down)

Source: DIP API.

For each active Vorgang (Gesetzentwurf, Antrag, Anfrage, Petition)
returned by DIP in the last 30 days:

1. Determine engagement state (see "State Determination" below)
2. If state D: skip, do not classify
3. If state A, B, or C: run Mistral classification, hand off to merge stage

Primary action types produced: `brief`, `anfrage`, `bundestag_petition`.

### Pipeline 2: Petition-driven (bottom-up)

Sources: Bundestag petition portal (DIP), WeAct (Tavily search),
openpetition (Tavily search or Google Custom Search API fallback).

For each petition found:

1. Determine engagement state using petition-specific logic (see below)
2. If state D: skip
3. If state A or C: run Mistral classification, hand off to merge stage

State B does not apply to citizen petitions — there is no single MdB
whose positioning can be targeted. Petitions go directly from A to C.

Primary action types produced: `petition`.

### Merging and Deduplication

After both pipelines run, their `ClassifiedAction` outputs are combined
and deduplicated in two steps:

**Step 1 — Exact URL match** (existing logic, unchanged): drop any item
whose `source_url` already exists in `civic_actions`.

**Step 2 — Topic fingerprint match** (new): two actions are duplicates if
they share the same DIP descriptor OR their titles are >85% similar
(`thefuzz` ratio). When a duplicate pair is found:
- Keep the one with the higher `engagement_state` (A > B > C)
- If states are equal, keep by type priority:
  Bundestag petition > WeAct/openpetition petition > Brief > Anfrage

```python
STATE_RANK = {"A": 3, "B": 2, "C": 1}
TYPE_PRIORITY = ["bundestag_petition", "petition", "brief", "anfrage"]

def resolve_duplicate(a: ClassifiedAction, b: ClassifiedAction) -> ClassifiedAction:
    if STATE_RANK[a.engagement_state] != STATE_RANK[b.engagement_state]:
        return max(a, b, key=lambda x: STATE_RANK[x.engagement_state])
    return min(a, b, key=lambda x: TYPE_PRIORITY.index(x.action_type))
```

---

## State Determination: Parliamentary Actions (Pipeline 1)

Checked in order; stop at the first match.

### State A triggers

```
1. DIP Vorgang has a scheduled Abstimmungstermin within 30 days
   → state_reason: "Abstimmung am {date}"

2. DIP Vorgang status contains "Ausschussberatung" and the committee is
   actively meeting (recent Ausschuss-Sitzungen in DIP /aktivitaet)
   → state_reason: "Wird aktuell im Ausschuss beraten"

3. It is a Bundestag petition with signature count > 40,000
   (quorum is 50,000 — close enough for urgency)
   → state_reason: "Petition kurz vor dem Quorum: {count} von 50.000"
```

### State B triggers (only if not A)

State B is an **action-level** property — "are positions on this topic
structurally still forming" — not a per-user property. The pool is shared
across every device (see `features/feed.md` "no server-side
personalisation"), so there is no single MdB to check at ingestion time.
The earlier version of this spec checked "the user's MdB (resolved from
PLZ)" against 3 position sources — that doesn't work for a shared pool and
has been replaced with the following DIP-derived signals, checked directly
against the Vorgang:

```
State B triggers if ANY of the following. Each gets its own state_reason
stating the concrete fact that was actually observed — not a shared
interpretive sentence like "positions are still open", which asserts
something inferred, not something known:

1. Vorgangstyp is Gesetzentwurf or Antrag AND beratungsstand is
   "Überwiesen" (referred to committee) AND no Abstimmungsergebnis
   exists yet
   → state_reason: "An den Ausschuss überwiesen"

2. Fewer than 2 Fraktionen have documented Stellungnahmen on this
   Vorgang
   → state_reason: "Erst {count} von 2 Fraktionen haben sich
     öffentlich positioniert"

3. Vorgang is in "1. Beratung" or "2. Beratung" with no scheduled
   namentliche Abstimmung
   → state_reason: "Noch in der {1./2. Beratung}"

4. Filed but not yet referred to committee (earliest structural stage,
   added after `scripts/audit_dip_coverage.py` showed these Vorgänge
   were being fetched but falling through to state D unmatched)
   → state_reason: "Gerade erst eingereicht"
```

**Client-side MdB personalisation (device, not pipeline):** when the app
displays a state-B action, it checks the cached Abgeordnetenwatch answer
history for the user's own MdB (`profile.mdb` in Hive, refreshed every 30
days — see `data/sources-federal.md` Source 3). If that specific MdB has
already answered a question on this topic, the displayed `state_reason`
changes locally to *"[MdB Name] hat sich bereits geäußert — schreib
trotzdem"* (optionally displayed at lower visual priority, as if state C).
The action itself stays state B in the pool for every other user — this is
purely a display-layer personalisation, not a pool-level re-classification.
See `features/feed.md` for the display-side spec.

The 3-source MdB position check (Abgeordnetenwatch, DIP Reden, Bundestag
RSS — see "MdB Position Sources" below) is **not** used for state B
determination. It continues to serve the tracking feature's MdB-statement
refresh (`features/tracking.md` Stage 6), which is a per-tracked-action,
per-user-relevant-MdB check running after a user has already acted — a
fundamentally different question from "should this enter the pool at all".

### State C triggers (only if not A and not B)

Use Tavily to check for recent quality-media coverage of the Vorgang's
official title (see "State C via Tavily" below).

```
If at least 2 articles from at least 2 different quality-media domains
in the last 14 days:
  → state C
  → state_reason: "Das Thema wird aktuell öffentlich diskutiert"

Otherwise:
  → state D → discard, do not classify
```

---

## State Determination: Petition Actions (Pipeline 2)

### State A triggers

```
1. Signature count > 80% of stated goal AND deadline within 30 days
   → state_reason: "Kurz vor dem Ziel: {count} von {goal} — noch {days} Tage"

2. Signature count > 40,000 (Bundestag petition, 50k quorum)
   → state_reason: "Petition kurz vor dem Quorum"

3. Momentum: > 1,000 new signatures in the last 7 days
   (requires previous_signature_count from the last run)
   → state_reason: "Über 1.000 neue Unterschriften diese Woche"
```

### State C triggers (only if not A)

```
1. Petition is active (deadline in the future or no deadline)
2. At least 500 signatures
3. Tavily finds the petition's topic covered in quality media within
   the last 14 days (see "State C via Tavily" below)

If all conditions met:
  → state C
  → state_reason: "Läuft — und das Thema ist gerade in der Diskussion"

Otherwise:
  → state D → discard
```

---

## MdB Position Sources (Tracking + Client-Side Personalisation)

**Not used for state B determination** (see above — state B is an
action-level DIP signal, not a per-MdB check). These 3 sources serve two
other purposes: the tracking feature's MdB-statement refresh
(`features/tracking.md` Stage 6, server-side, per tracked action) and the
device-side state-B reason personalisation (`features/feed.md`, using the
already-cached Abgeordnetenwatch answer history from the MdB lookup —
Source 1 below — refreshed every 30 days).

Checked in parallel for tracking. Results are stored in `mdb_statements`
with a `source` field indicating which source found the match.

**Source 1: Abgeordnetenwatch API (public, no key required)**
```
Base URL: https://www.abgeordnetenwatch.de/api/v2

# Resolve MdB from PLZ (already implemented, cached in Hive on device)
GET /politicians?zip={plz}&parliament_period=132

# Get public answers by this MdB
GET /answers?politician={aw_politician_id}&updated_since={90_days_ago}

# Match: does any answer's topic or text contain the action's descriptors?
```

**Source 2: DIP Plenarprotokolle (public API, key required)**
```
GET /aktivitaet
  ?f.person.id={mdb_dip_id}
  &f.aktivitaetsart=Rede
  &f.datum.start={90_days_ago}
  &format=json

# Match: filter by DIP descriptor overlap with this action's descriptors
```

**Source 3: Bundestag.de MdB RSS (public, no key)**
```
URL pattern: https://www.bundestag.de/ajax/filterlist/de/abgeordnete/
             {nachname}-{vorname}/rss

# Parse title and pubDate only — no full text needed
# Match: keyword match against the action's topic keywords
# Only articles from the last 60 days
```

Persisted to `mdb_statements`:
- `found = true`, `source = 'abgeordnetenwatch' | 'dip_reden' | 'bundestag_rss'`
- `found = false`, `source = null` if all three return no match
- `searched_at = now()`

---

## State C via Tavily (No RSS, No Keyword Dictionary)

State C detection does not use a maintained keyword dictionary or RSS
feed parsing. Instead it uses text that already exists in the source
data — the DIP Vorgang title, or the petition title — directly as the
Tavily search query. This requires no mapping, is always current, and
handles new topics automatically as they emerge.

```python
QUALITY_MEDIA_DOMAINS = [
    "tagesschau.de",
    "zeit.de",
    "spiegel.de",
    "faz.net",
    "sueddeutsche.de",
    "mdr.de",
]

async def check_state_c(query_text: str) -> bool:
    """query_text is the DIP Vorgang title (Vorgang.titel) for
    parliamentary actions, or the petition title for petition actions —
    used verbatim, no keyword mapping."""
    results = await tavily_client.search(
        query=query_text,
        include_domains=QUALITY_MEDIA_DOMAINS,
        days=14,
        max_results=5,
    )
    articles = results.get("results", [])
    domains_found = {extract_domain(r["url"]) for r in articles}
    return len(articles) >= 2 and len(domains_found) >= 2
```

`QUALITY_MEDIA_DOMAINS` is the only constant to maintain and can be
extended at any time without touching pipeline logic. No RSS feed
parsing is needed anywhere in the pipeline — Tavily handles media
coverage detection entirely.

---

## Mistral Classification

Unchanged from the previous spec. Each item that survives state
determination (state A, B, or C) is classified using Mistral. The
classification prompt (topics, pro/contra, `is_controversial`,
`position_required`, `werte_relevanz`, `urgency`) is not affected by
the engagement state model — `urgency` remains a Mistral-derived field
used elsewhere (e.g. classification quality), but `engagement_state` is
the primary relevance and priority signal for the feed. See
`features/feed.md`.

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

## Persist

```python
async def persist_actions(actions: list[ClassifiedAction]) -> int:
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
                engagement_state, state_reason, pipeline_source,
                previous_signature_count, active, updated_at
            ) VALUES (...)
            ON CONFLICT (source_url) DO UPDATE SET
                urgency = EXCLUDED.urgency,
                engagement_state = EXCLUDED.engagement_state,
                state_reason = EXCLUDED.state_reason,
                previous_signature_count = civic_actions.previous_signature_count,
                tavily_context = EXCLUDED.tavily_context,
                updated_at = now()
        """, action.dict())
        inserted += 1
    return inserted
```

**Upsert on `source_url`** allows re-runs to update `engagement_state`
and `state_reason` without creating duplicates. On update, the previous
row's signature count is preserved into `previous_signature_count` before
the new count overwrites it, so the next run can compute momentum.

---

## Deactivate Expired

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

    # Stage 0a: Parliamentary pipeline (DIP)
    parliamentary_actions = await run_parliamentary_pipeline(errors)

    # Stage 0b: Petition pipeline (runs in parallel with 0a)
    petition_actions = await run_petition_pipeline(errors)

    # Stage 1: Merge + Deduplicate
    existing = await db.fetch_existing_urls_and_titles()
    merged = deduplicate_exact_url(
        parliamentary_actions + petition_actions, existing["urls"]
    )
    deduped = deduplicate_topic_fingerprint(merged, existing["titles"])

    # Stage 2: Tavily context enrichment (unchanged, still SKIPPED in MVP)
    enriched = deduped

    # Stage 3: Persist
    inserted = await persist_actions(enriched)

    # Stage 4: Deactivate expired
    await deactivate_expired()

    # Stage 5: RSS fetch and news_items refresh (unchanged)
    await refresh_news_items()

    # Stage 6: MdB statement refresh (unchanged, now records `source`)
    await refresh_mdb_statements()

    # Stage 7: Log run
    await log_run(
        run_id=run_id,
        parliamentary_actions_found=len(parliamentary_actions),
        petition_actions_found=len(petition_actions),
        state_a_count=sum(1 for a in enriched if a.engagement_state == "A"),
        state_b_count=sum(1 for a in enriched if a.engagement_state == "B"),
        state_c_count=sum(1 for a in enriched if a.engagement_state == "C"),
        state_d_discarded=count_discarded_state_d(),
        inserted=inserted,
        errors=errors,
        duration_seconds=time.time() - start,
        ai_cost_eur=await get_today_ai_spend(),
    )


async def run_parliamentary_pipeline(errors: list[str]) -> list[ClassifiedAction]:
    vorgaenge = await fetch_active_dip_vorgaenge(errors)  # last 30 days
    classified = []
    for vorgang in vorgaenge:
        state, reason = await determine_parliamentary_state(vorgang)
        if state == "D":
            continue
        classified.append(await classify_action(vorgang, state, reason,
                                                  pipeline_source="parliamentary"))
    return [c for c in classified if c is not None]


async def run_petition_pipeline(errors: list[str]) -> list[ClassifiedAction]:
    petitions = await fetch_bundestag_petitions(errors)
    petitions += await fetch_civil_society_petitions(errors)  # WeAct, openpetition
    classified = []
    for petition in petitions:
        state, reason = await determine_petition_state(petition)
        if state == "D":
            continue
        classified.append(await classify_action(petition, state, reason,
                                                  pipeline_source="petition"))
    return [c for c in classified if c is not None]
```

---

## MdB Statement Refresh

Runs daily as part of the pipeline (Stage 6). Searches for public
statements by tracked MdBs on topics related to active actions, using
the 3 MdB position sources described above ("MdB Position Sources —
Tracking + Client-Side Personalisation"). See `data/sources-federal.md`
for implementation details.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/data-flow.md`,
  `data/sources-federal.md`, `data/database-schema.md`
- Referenced by: `features/feed.md`, `features/tracking.md`,
  `technical/monitoring.md`

---

## Open Questions

- [ ] Confirm exact `beratungsstand` string values used by DIP for each
      deliberation stage. Current values are best-guess; verify against
      live API data before relying on them for state A determination.
- [ ] Confirm DIP `/aktivitaet` reliably surfaces committee (Ausschuss)
      sitting dates for the "actively meeting" state A trigger.
</content>
</invoke>
