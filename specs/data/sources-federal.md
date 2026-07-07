# Data Sources – Federal Level

## Purpose
Defines all external data sources used for the federal-level action pool,
including endpoints, data quality, update frequency, and known limitations.
State (Länder) and municipal sources are out of scope for MVP.

---

## Decisions

- **Only official or established sources are used.** No scraping of news
  sites or unofficial aggregators for civic action data.

- **No topic taxonomy.** Sources are queried broadly for active and
  imminent parliamentary items, not filtered by predefined topic keywords.
  Hotness is determined by parliamentary stage (beratungsstand) and
  recency, not by subject-area matching.

- **All sources are public and free.** No paid API tiers are required for
  MVP. Rate limits are respected via scheduled batch fetching, not
  real-time polling.

- **Sources are accessed exclusively from the backend.** The Flutter app
  never calls external civic APIs directly. This allows caching, rate
  limit management, and source switching without app updates.

- **Each source is encapsulated in its own repository adapter.** Switching
  or adding a source requires only a new adapter class, not changes to
  domain services.

---

## Source 1: Bundestag DIP API

**Purpose:** Gesetzentwürfe, Anträge, and open Petitionen from the
Bundestag parliamentary record. Votes (Abstimmungen) are tracked via
the `beratungsstand` field on Vorgänge, not a separate endpoint.

**Base URL:** `https://search.dip.bundestag.de/api/v1`
**OpenAPI spec:** v1.5 (downloaded 2026-06-12)
**Authentication:** API key required for all requests (401 otherwise).
Pass as query param `apikey=` or header `Authorization: ApiKey <key>`.
Free registration at dip.bundestag.de. A public demo key is available.
**Rate limit:** ~10 requests/second; batch fetching is safe at 1 req/sec

**Key endpoints used:**

```
GET /vorgang
  ?f.beratungsstand=2.+Beratung+und+Schlussabstimmung
  &f.beratungsstand=3.+Beratung
  &f.beratungsstand=2.+Beratung
  &f.aktualisiert.start={7_days_ago}
  &format=json
  → Late-stage Vorgänge approaching a vote

GET /vorgang
  ?f.beratungsstand=Ausschussberatung
  &f.aktualisiert.start={3_days_ago}
  &format=json
  → Vorgänge in active committee deliberation

GET /vorgang
  ?f.vorgangstyp=Petition
  &f.beratungsstand=Noch+nicht+beraten
  &format=json
  → Open Bundestag petitions (always included)
```

Each fetched item receives an **imminence score** (0.0–1.0) based on its
`beratungsstand` stage and recency of the last activity (`datum` field).
See `data/ingestion-pipeline.md` Stage 0 for the scoring formula.

> **Note on beratungsstand values:** The controlled vocabulary is not
> published by the Bundestag. The values above are verified against live
> API data and should be re-checked if DIP API behaviour changes.

**Endpoints that do NOT exist (corrected from earlier assumptions):**
- `GET /abstimmung` — this endpoint is not in the API. Votes are
  represented as Vorgänge with `beratungsstand` indicating the outcome.
- `f.status` filter — does not exist. Use `f.beratungsstand` instead.

**Pagination:**
All list endpoints return a `cursor` field (always present, never null).
Send the cursor back in the next request. Stop when the returned cursor
equals the cursor you just sent (i.e., it stops changing).

```
GET /vorgang?...&cursor={prev_cursor}
  → Stop when response.cursor == prev_cursor
```

**Fields extracted per item:**

```python
{
  "external_id": str,           # DIP Vorgangs-ID (string matching ^\d+$)
  "title": str,                 # Vorgang.titel  (NOT betreff — that field does not exist)
  "type": str,                  # "antrag" | "petition" | "gesetzentwurf"
  "status": str,                # Vorgang.beratungsstand
  "deadline": date | None,      # Vorgang.datum (date of latest associated document)
  "source_url": str,            # https://dip.bundestag.de/vorgang/{id}
  "description": str,           # Vorgang.abstract if present, else titel
  "initiated_by": str,          # Vorgang.initiative[] joined as comma-separated string
}
```

**Known limitations:**
- No `/abstimmung` endpoint: vote outcomes must be inferred from
  `beratungsstand` (e.g. "Angenommen", "Abgelehnt") on the Vorgang.
- Full bill text requires a secondary fetch via `/drucksache-text/{id}`.
- API occasionally returns incomplete data for new items; retry after 24h.
- `f.beratungsstand` values for "open petitions" may need tuning as the
  controlled vocabulary is not published; "Noch nicht beraten" is the
  current best guess.

---

## Source 2: bundestag.io (GraphQL)

**Purpose:** Supplementary structured data on MdBs, Fraktionen, and
votes with Abgeordnetenwatch cross-references.

**Base URL:** `https://bundestag.io/graphql`
**Authentication:** None (public)
**Rate limit:** Respectful use; max 1 req/2 sec

**Used for:**
- Cross-referencing DIP vote IDs with MdB voting records
- Enriching actions with Fraktion positions
- Not used as primary action source (DIP is primary)

**Not used in MVP ingestion pipeline.** Reserved for the MdB profile
feature (V2). Documented here for completeness.

---

## Source 3: Abgeordnetenwatch API

**Purpose:** MdB lookup by PLZ, public Q&A records, vote records per MdB.

**Base URL:** `https://www.abgeordnetenwatch.de/api/v2`
**Authentication:** None (public)
**Rate limit:** Respectful use; max 1 req/sec

**Key endpoints used:**

```
GET /politicians?zip={plz}&parliament_period=132
  → MdB for a given PLZ (Wahlkreis lookup)
  → Returns: name, party, wahlkreis, profile_url, photo_url

GET /polls?parliament_period=132&updated_since={timestamp}
  → Recent votes with party positions
  → Used to enrich action context

GET /candidacies-mandates?politician={id}&parliament_period=132
  → MdB mandate details
```

**Fields extracted for MdB lookup (cached locally on device):**

```json
{
  "name": "Sarah Müller",
  "party": "CDU",
  "wahlkreis": "Dresden-Nord",
  "wahlkreis_number": 160,
  "profile_url": "https://www.abgeordnetenwatch.de/profile/sarah-mueller",
  "photo_url": "https://..."
}
```

**Caching:** MdB data is cached for 30 days in Hive `profile.mdb`.
Refreshed on app start if older than 30 days and PLZ is set.

**Not stored on backend.** The PLZ-to-MdB lookup is a pass-through:
device sends PLZ, backend queries AW API, returns MdB data, does not
store either the PLZ or the MdB result.

---

## Source 4: Civil Society Petitions (Tavily / Google Custom Search)

**Purpose:** Civil society petitions from WeAct (weact.campact.de) and
openPetition (openpetition.de) for active topics.

**Why not an RSS/API:** Neither platform provides a documented public API or
RSS feed. WeAct has no feed; openPetition has no public API. Data is accessed
via web search instead.

**Primary method — Tavily search:**
```python
async def find_civil_society_petition(topic: str, keywords: list[str]) -> RawSourceItem | None:
    query = f"{' OR '.join(keywords)} Petition unterzeichnen 2026"
    results = await tavily_client.search(
        query=query,
        include_domains=["weact.campact.de", "openpetition.de"],
        search_depth="basic",
        max_results=3,
        days=30,
    )
    if not results.get("results"):
        return None
    best = results["results"][0]
    return RawSourceItem(
        external_id=slugify(best["url"]),
        title=best["title"],
        description=best["content"][:500],
        source_url=best["url"],
        type="petition",
        status="offen",
        deadline=None,
        initiated_by="Zivilgesellschaft",
        source="tavily_petition_search",
    )
```

**Fallback method — Google Custom Search API:**
If Tavily returns no results, fall back to Google Custom Search
(`site:openpetition.de OR site:weact.campact.de`).
Free tier: 100 queries/day (sufficient for MVP at ≤10 topics/day).

**Requires:** `MEINIMPACT_TAVILY_API_KEY` or `MEINIMPACT_GOOGLE_CSE_KEY` +
`MEINIMPACT_GOOGLE_CSE_ID`.

**Fields extracted:**
```python
{
  "external_id": str,      # Slugified URL
  "title": str,            # From search result title
  "description": str,      # First 500 chars of search result content
  "source_url": str,       # Direct petition URL
  "type": "petition",
  "source": "tavily_petition_search",
}
```

**Known limitations:**
- No signature count available via search (prefilter signature rule skipped)
- Result quality depends on Tavily indexing freshness (~24h lag)
- May occasionally surface expired petitions; deadline check in prefilter catches these

---

## Source 5: NewsData.io

> **MVP STATUS: NOT USED IN PIPELINE.**
> NewsData.io was previously used as a topic-frequency signal for the
> now-removed topic radar (Stage 0). With the new beratungsstand-based
> hotness evaluation, parliamentary process stage is the primary signal
> and no external news counting is required.
>
> NewsData.io may be re-introduced in a future version if a news-context
> enrichment use case arises (e.g. boosting momentum score when an action
> appears in current coverage). The API key config (`MEINIMPACT_NEWSDATA_API_KEY`)
> is retained for this purpose.

---

## Source 6: MdB Social Media & Public Statements

**Purpose:** Track public positions of Bundestagsabgeordnete on topics
related to active actions. Used exclusively for tracking, not for
ingesting new actions into the pool.

**Sources:**
- Twitter/X public profiles of MdBs (via Nitter RSS or Twitter API v2)
- Official press releases on bundestag.de MdB profile pages
- Abgeordnetenwatch public statements

**Base approach:** For each active action with a tracked MdB, run a
daily search for recent statements by that MdB on the action topic.

```python
# Tavily search per MdB per active action
query = f"{mdb_name} {action_topic_keywords} Statement Bundestag"
results = await tavily_client.search(query, days=7, max_results=3)
```

**Fields extracted:**

```python
{
  "mdb_name": str,
  "statement_summary": str,   # AI-summarised from search results
  "source_url": str | None,
  "found": bool,              # False if no statement found
  "search_date": date,
}
```

**Explicit "nothing found" handling:**
If no statement is found for an MdB on a topic within the last 30 days,
the tracking event is recorded with . The app shows:
*"[MdB Name] hat sich öffentlich noch nicht zu diesem Thema geäußert."*
This is shown proactively, not only on user request.

**Cost:** ~1 Tavily credit per MdB per active action per day.
At 10 active actions × 1 tracked MdB each: ~10 credits/day.
This is within the free tier (200 credits/day total).

**Known limitations:**
- Not all MdBs are active on social media
- Tavily may miss statements on niche platforms
- Bundestag.de MdB pages are not always up to date
- No access to private or deleted posts

---

## Adapter Interface

All sources implement the same Python protocol:

```python
class SourceAdapter(Protocol):
    async def fetch_new_items(
        self,
        since: datetime,
    ) -> list[RawSourceItem]: ...

    async def fetch_item_detail(
        self,
        external_id: str,
    ) -> RawSourceItem: ...
```

`RawSourceItem` is an unclassified dict passed to the ingestion pipeline
for AI classification. See `data/ingestion-pipeline.md`.

---

## Source Priority and Conflict Resolution

If the same civic action appears in multiple sources (e.g. a Bundestag
petition also covered by WeAct):

1. DIP API is the canonical source for Bundestag items
2. WeAct is canonical for civil society petitions
3. EU portal is canonical for EU consultations
4. Deduplication by `source_url` and fuzzy title match (>85% similarity)
5. On conflict: keep the canonical source, add secondary `source_url`
   as an additional link

---

## Failure Handling

Each adapter is independent. If one source fails:
- Log error to Sentry
- Skip that source for this run
- Other sources proceed normally
- Alert if DIP API fails (primary source): log as critical

No action is deleted from the pool due to a source fetch failure.
Actions expire naturally via their `deadline` field.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/data-flow.md`
- Referenced by: `data/ingestion-pipeline.md`, `data/database-schema.md`,
  `features/feed.md`

---

## Open Questions

- [ ] WeAct signature count: confirm whether RSS includes counts or
      whether HTML scraping is required. If scraping: add to adapter.
- [ ] MdB Twitter/X access: evaluate whether Nitter RSS is reliable
      enough or whether Twitter API v2 bearer token is needed.
      Twitter API v2 free tier: 1,500,000 tweets/month read access.
- [ ] DIP petition beratungsstand: confirm the exact `beratungsstand`
      values used for open/active public petitions. Current assumption
      is "Noch nicht beraten" — verify against live API data.
