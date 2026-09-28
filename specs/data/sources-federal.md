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

**Status (2026-09-27): being redesigned.** The DIP-based parliamentary
source and the DIP part of the petition source (below, formerly "Source
1") have been retired — the topic pool no longer sources from the
Bundestag DIP API. The new source model (Tavily search-based topic
discovery) is not yet written up here; see `data/ingestion-pipeline.md`
"Status" for what's agreed so far.

The DIP API adapter code is preserved unused (`infrastructure/sources/
dip_adapter.py`) in case a later stage of the project needs it again, but
nothing in the pipeline calls it.

MdB position sources (3a: Abgeordnetenwatch, 3b: DIP Plenarprotokolle, 3c:
Bundestag.de MdB RSS — see Source 6 below) are **unaffected** by this —
they never fed the ingestion pipeline, and continue to serve tracking's
MdB-statement refresh and the app's client-side personalisation exactly
as before.

Civil-society petition sourcing (Tavily/Google CSE, formerly "Source 4")
is also being redesigned as part of this pivot, not carried over as-is —
see `data/ingestion-pipeline.md`.

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

## Source 4: Civil Society Petitions — retired pending redesign

**Status (2026-09-27):** This source (Tavily/Google CSE search for WeAct
and openPetition results) and the `CivilPetitionAdapter` /
`GoogleCseAdapter` code that implemented it have been removed. Petition
sourcing is being redesigned as part of the move to Tavily-search-based
topic discovery, not carried over as-is — see `data/ingestion-pipeline.md`
"Status". If the new design still wants civil-society petitions, the
Tavily-search approach documented in git history for this section is a
reasonable starting point.

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

**Status (2026-09-27):** The two-pipeline model (parliamentary + petition)
and its DIP-descriptor/fuzzy-title dedup logic have been retired along
with the rest of the old ingestion pipeline — see
`data/ingestion-pipeline.md` "Status". How deduplication works against a
Tavily-search-based source is part of the pending redesign.

---

## Failure Handling

Each adapter is independent. If one source fails:
- Log error to Sentry
- Skip that source for this run
- Other sources proceed normally
- Alert if the primary topic-discovery source fails: log as critical

No action is deleted from the pool due to a source fetch failure.
Actions expire naturally via their `deadline` field.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/data-flow.md`
- Referenced by: `data/ingestion-pipeline.md`, `data/database-schema.md`,
  `features/feed.md`

---

## Open Questions

- [ ] Bundestag.de MdB RSS naming: confirm the `{nachname}-{vorname}`
      URL pattern holds for all current MdBs, or build a lookup table.
- [ ] Tavily-search-based topic discovery: full source/query design
      pending — see `data/ingestion-pipeline.md` "Status".
