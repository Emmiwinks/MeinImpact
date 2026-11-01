# Ingestion Pipeline

## Purpose
Defines the background process that reads open participation
opportunities from the registries that publish them, filters and enriches
them, and stores them for the feed. This is the core data engine of
MeinImpact.

---

## Status (2026-11-01): registry-based, implemented

Earlier designs sourced topics from the Bundestag DIP API, then from Tavily
search. Both are retired: topics are not actions, and search results were
stale, unranked and random. The pipeline now reads **action registries
directly**: places where a participation opportunity is listed with an
open window and a way to take part.

### Flow

```
catalog.default_sources   openPetition (Bund/Sachsen/Dresden), Beteiligungsportal
                          Sachsen, EU "Have your say", WeAct
collect()                 all sources concurrently, failures isolated per source
steps.default_steps       in_coverage -> actionable -> not_expired -> dedupe
store.sync()              mirror into `opportunities`, snapshot support counts,
                          deactivate entries a fully-read registry no longer lists
enrich pending            new or changed listings only: detail text (openPetition,
                          EU) + one Mistral call (relevance + neutral framing)
store.save_enrichment()   committed per result, so progress survives failures
```

Code: `backend/src/meinimpact/infrastructure/listings/` (sources, HTTP,
steps), `infrastructure/ai/listing_enricher.py`,
`infrastructure/pipeline/ingestion.py`, composition in
`services/ingestion.py`.

### Rules

- **Trigger-based only.** `POST /v1/admin/ingestion/run` (starts in the
  background, one run at a time) or `scripts/run_ingestion.py`. No
  in-process scheduler.
- **Polite, rule-abiding crawling.** Every request goes through
  `PoliteHttpClient`: robots.txt per RFC 9309, per-host Crawl-delay (min.
  1 s), one honest User-Agent. Registries that disallow crawling
  (ratsinfo.dresden.de, the Landtag Sachsen calendar) are only used via
  official APIs (e.g. OParl).
- **Registry facts are never invented.** Dates, status, support counts and
  URLs come from the registry. The LLM only decides relevance and writes
  title, summary, tags, werte axes, arguments and personal-impact
  snippets; its output is normalized in code against the taxonomy.
- **Registry status labels are not trusted alone.** Registries list
  expired items as running; `not_expired` drops anything past its end
  date.
- **Identity is the registry entry** (`source_id`, `external_id`). No
  embedding dedup.
- **Enrichment runs once per registry text version**
  (`enrichment_input_hash`); unchanged listings never cost another call.
  Failed enrichments stay pending and are retried next run.
- **Deactivation only for complete registries.** If any configured
  instance of a registry failed this run, none of its entries are
  deactivated.
- **Fault-tolerant per source and per listing.**

### Appeal scores, districts, free topics (since 2026-11-02)

- **Scores:** every relevant listing gets `everyday_relevance` and
  `accessibility` (1-5). The feed withholds only expert-only items (both
  very low, `EXPERT_ONLY_MAX_*` in the repository); the app ranks the rest:
  personal match, then appeal, then werte alignment.
- **Titles:** varied question forms (not mostly "Soll ..."), summaries in
  plain language.
- **Districts:** per city, from Wikidata (`scripts/sync_districts.py` ->
  committed `infrastructure/geo/data/<city>.json`; Dresden: 123 Ortsteile).
  Matched deterministically in the registry and detail text only; the LLM
  is not asked (it mapped streets to wrong districts in a live run). Empty =
  whole city. A new city is one `CityConfig` plus a sync run. Street-level
  inference would need geodata (geocoding), not model guesses.
- **Free topic:** the LLM's own topic label next to the fixed tags;
  `scripts/topic_report.py` shows where the taxonomy force-fits.
- **`ENRICHMENT_VERSION`** is part of the enrichment input hash: bumping it
  re-enriches everything on the next run.

### Relevance (LLM, per listing)

Kept: petitions, statements on displayed plans (Bauleitplanung),
consultations, citizen surveys and public dialogues on public decisions,
understandable for a private person. Dropped: property viewings, job and
speaker calls, internal administration trainings, award ceremonies,
professional-only info events, highly technical acts. Scope must be EU,
Bund, Sachsen or Dresden; other municipalities and other Länder are
dropped (nationally relevant topics count as Bund).

---

## Dependencies

- Reads: `architecture/overview.md`, `data/database-schema.md`
- Referenced by: `features/feed.md`, `technical/monitoring.md`

---

## Open Questions

- [ ] Decision calendars for standing actions (write to MdB/MdL/Stadtrat):
      Dresden OParl API, Bundestag agenda (PDF or DIP), Landtag Sachsen
      (robots-disallowed; EDAS or permission).
- [ ] Bundestag ePetitionen (list needs a JS session token).
- [ ] Momentum: support snapshots are recorded per run; how (and whether)
      to surface momentum is undecided.
- [ ] Hard cost ceiling per run for enrichment.
- [ ] Sources with the opposite political lean to openPetition/WeAct.
