# Data Sources – Federal Level

## Purpose
Defines all external data sources used for the federal-level action pool,
including endpoints, data quality, update frequency, and known limitations.
State (Länder) and municipal sources are out of scope for MVP.

---

## Decisions

- **Only official or established sources are used.** No scraping of news
  sites or unofficial aggregators for civic action data. News context
  (Tavily, NewsData.io) is supplementary, not the primary action source.

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

**Purpose:** Abstimmungen (votes), Drucksachen (parliamentary papers),
Petitionen (petitions), upcoming agenda items.

**Base URL:** `https://search.dip.bundestag.de/api/v1`
**Authentication:** API key (free registration at dip.bundestag.de)
**Rate limit:** ~10 requests/second; batch fetching is safe at 1 req/sec

**Key endpoints used:**

```
GET /vorgang
  ?f.vorgangstyp=Antrag,Gesetzentwurf
  &f.datum.start={yesterday}
  &format=json
  → Parliamentary processes (Gesetzentwürfe, Anträge)

GET /abstimmung
  ?f.datum.start={yesterday}
  &format=json
  → Recent and upcoming votes

GET /vorgang
  ?f.vorgangstyp=Petition
  &f.status=offen
  &format=json
  → Open Bundestag petitions

GET /aktivitaet
  ?f.datum.start={yesterday}
  &format=json
  → Recent parliamentary activities
```

**Fields extracted per item:**

```python
{
  "external_id": str,           # DIP Vorgangs-ID
  "title": str,                 # Betreff / Titel
  "type": str,                  # "abstimmung" | "petition" | "gesetzentwurf"
  "status": str,                # current parliamentary status
  "deadline": date | None,      # Abstimmungstermin if known
  "source_url": str,            # Link to DIP detail page
  "full_text": str,             # Beschreibung / Betreff for AI classification
  "initiated_by": str,          # Fraktion or Bundesregierung
}
```

**Known limitations:**
- Abstimmungstermine are often not available far in advance
- Full bill text requires separate fetch by Drucksachen-ID
- API occasionally returns incomplete data for new items; retry after 24h

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

## Source 4: WeAct RSS Feed

**Purpose:** Civil society petitions from WeAct (Campact's petition platform).

**Feed URL:** `https://weact.campact.de/petitions.rss`
**Authentication:** None
**Update frequency:** Multiple times daily

**Fields extracted:**

```python
{
  "external_id": str,      # Derived from URL slug
  "title": str,
  "description": str,      # First 500 chars of petition description
  "source_url": str,
  "signature_count": int,  # If available in RSS item
  "deadline": date | None,
}
```

**Prefilter applied:**
- Minimum 500 signatures (filters out very new petitions with no momentum)
- German-language titles only (lang detection via langdetect library)
- Deduplication against existing `actions` table by `source_url`

**Known limitations:**
- Signature counts not always in RSS; may require HTML scrape for count
- Some petitions are regional or very niche; topic classification handles this

---

## Source 5: NewsData.io

**Purpose:** Current German political news for Tavily context enrichment
and urgency scoring.

**Base URL:** `https://newsdata.io/api/1/latest`
**Authentication:** API key (free tier)
**Rate limit:** 200 credits/day; 10 articles/credit = 2,000 articles/day
**Latency:** ~12 hours delay on free tier (acceptable for daily batch)

**Query used:**

```
GET /latest?country=de&category=politics&language=de&apikey={key}
```

**Fields extracted:**

```python
{
  "title": str,
  "description": str,
  "source_name": str,
  "published_at": datetime,
  "link": str,
}
```

**Used for:**
- Input to Tavily search queries (article titles trigger Tavily deep search)
- Urgency boosting: if a DIP action appears in 3+ news articles this week,
  its `momentum_score` increases

**Not stored as actions.** News items are not inserted into the `actions`
table. They are used as signals to enrich and score existing actions.

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
