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
  Relevance is determined by engagement state (A/B/C/D — see
  `data/ingestion-pipeline.md`), not by subject-area matching.

- **Sources are organised into two parallel categories, not one priority
  tree.** Parliamentary sources feed Pipeline 1 (top-down); petition
  sources feed Pipeline 2 (bottom-up). Both categories feed the same
  pool. See "Source Categories" below.

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

## Source Categories

Sources are grouped by which pipeline they feed. See
`data/ingestion-pipeline.md` for the full pipeline structure.

**Parliamentary sources (Pipeline 1, top-down):**
- Source 1: Bundestag DIP API — Vorgänge (primary action source; state B is
  also determined directly from DIP fields — beratungsstand, Stellungnahme
  count — not from an MdB check, see `data/ingestion-pipeline.md`)
- Tavily quality-media search — state C determination

MdB position sources (3a: Abgeordnetenwatch, 3b: DIP Plenarprotokolle, 3c:
Bundestag.de MdB RSS — see Source 6 below) do **not** feed the ingestion
pipeline. They serve tracking's MdB-statement refresh and the app's
client-side state-B personalisation only.

**Petition sources (Pipeline 2, bottom-up):**
- Source 1: Bundestag DIP API — open Bundestag petitions
- Source 4: Tavily / Google Custom Search — WeAct, openpetition
- Tavily quality-media search — state C determination

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

Each fetched Vorgang is run through engagement state determination
(state A/B/C/D) based entirely on DIP-derived signals: `beratungsstand`
stage, scheduled vote dates, committee activity, and — for state B —
committee-referral status and Stellungnahme count (no per-user MdB check
involved; see `data/ingestion-pipeline.md` "State B triggers" for why).
See `data/ingestion-pipeline.md` "State Determination: Parliamentary
Actions" for the full logic. Items resolving to state D are discarded
before classification.

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

> **MVP STATUS: NOT USED. REPLACED BY TAVILY.**
> NewsData.io was previously used as a topic-frequency signal for the
> now-removed weighted hotness score. State C determination (public debate
> presence) is now done entirely via Tavily, searching quality-media
> domains using the DIP Vorgang title or petition title verbatim as the
> query — no keyword dictionary, no RSS parsing. See
> `data/ingestion-pipeline.md` "State C via Tavily".
>
> The API key config (`MEINIMPACT_NEWSDATA_API_KEY`) is retained in case
> a future news-context enrichment use case arises, but is not read by
> the pipeline.

---

## Source 6: MdB Public Statements

**Purpose:** Determine whether a specific MdB has already taken a public
position on a topic. **Not used for state B determination** — state B is
an action-level DIP signal, not a per-MdB check (see
`data/ingestion-pipeline.md` "State B triggers"). Used for two things
instead: tracking's MdB-statement refresh (post-completion, surfaced in
the tracking detail screen — `features/tracking.md` Stage 6) and the
app's client-side state-B reason personalisation (`features/feed.md`,
using the cached Abgeordnetenwatch answer history from the MdB lookup,
refreshed every 30 days — Source 6a alone is sufficient for this, the
other two sources are tracking-only). Three sources are checked in
parallel for tracking; this replaces the earlier Twitter/X and
Nitter-based approach, which required an unreliable third-party RSS
bridge.

**Source 6a: Abgeordnetenwatch API** — see Source 3 above
(`GET /answers?politician={aw_id}&updated_since={90_days_ago}`).

**Source 6b: DIP Plenarprotokolle**
```
GET /aktivitaet
  ?f.person.id={mdb_dip_id}
  &f.aktivitaetsart=Rede
  &f.datum.start={90_days_ago}
  &format=json
```
Requires the MdB's DIP person ID, resolved once and cached alongside the
Abgeordnetenwatch ID.

**Source 6c: Bundestag.de MdB RSS**
```
https://www.bundestag.de/ajax/filterlist/de/abgeordnete/{nachname}-{vorname}/rss
```
Parses `title` and `pubDate` only; matched against the action's topic
keywords, articles from the last 60 days only.

**Fields extracted (persisted to `mdb_statements`):**

```python
{
  "mdb_name": str,
  "found": bool,               # False if no statement found in any source
  "source": str | None,        # 'abgeordnetenwatch' | 'dip_reden' | 'bundestag_rss' | None
  "statement_summary": str | None,  # AI-summarised, NULL if found=false
  "source_url": str | None,
  "searched_at": datetime,
}
```

**Explicit "nothing found" handling:**
If all three sources return no match, the tracking detail screen shows:
*"[MdB Name] hat sich öffentlich noch nicht zu diesem Thema geäußert."*
Shown proactively, not only on user request. This has no bearing on the
action's pool-level `engagement_state` — that was already decided at
ingestion time, independent of any specific MdB.

**Cost:** Abgeordnetenwatch and DIP calls are free. Bundestag.de RSS is
free. No Tavily credits are spent on MdB position checks.

**Known limitations:**
- Abgeordnetenwatch answer coverage varies by MdB activity level
- DIP Reden matching depends on descriptor overlap, which may miss
  topically-relevant speeches that DIP tagged differently
- Bundestag.de MdB RSS naming convention (`nachname-vorname`) is not
  guaranteed for all MdBs; needs a fallback lookup for edge cases

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

## Merge Conflict Resolution

Both pipelines can independently surface the same real-world action
(e.g. a Bundestag petition also picked up by the petition pipeline's
DIP query, or a petition also covered by WeAct). Resolution happens at
the merge stage in `data/ingestion-pipeline.md`, not per-source:

1. Deduplicate by exact `source_url` match first
2. Then deduplicate by topic fingerprint: same DIP descriptor OR fuzzy
   title match >85% similarity
3. On conflict: keep the action with the higher `engagement_state`
   (A > B > C)
4. If states are equal: keep by type priority — Bundestag petition >
   WeAct/openpetition petition > Brief > Anfrage

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
- [ ] Bundestag.de MdB RSS naming: confirm the `{nachname}-{vorname}`
      URL pattern holds for all current MdBs, or build a lookup table.
- [ ] DIP petition beratungsstand: confirm the exact `beratungsstand`
      values used for open/active public petitions. Current assumption
      is "Noch nicht beraten" — verify against live API data.
