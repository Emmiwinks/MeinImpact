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
                          Sachsen, EU "Have your say", WeAct, Dresden council
                          (OParl, upcoming decisions)
collect()                 all sources concurrently, failures isolated per source
steps.default_steps       in_coverage -> actionable -> not_expired -> dedupe
store.sync()              mirror into `opportunities`, snapshot support counts,
                          deactivate entries a fully-read registry no longer lists
enrich pending            new or changed listings only: detail text (openPetition,
                          EU, council paper PDFs) + one Mistral call (relevance
                          + neutral framing)
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

### Council decisions: Dresden OParl (since 2026-11-08)

Upcoming decisions are the occasion for "standing actions" (write to the
members before the vote). Source: `listings/sources/oparl.py`, kind
`decision`, `source_id` `dresden-ratsinfo`.

- **API:** `https://oparl.dresden.de/bodies/0001` (OParl 1.1, licence
  dl-de/zero-2.0, no robots.txt). `ratsinfo.dresden.de` disallows crawling
  and is only used as the human-facing link
  (`vo0050.asp?__kvonr=<paper id>`).
- **One listing per paper** (Vorlage, Antrag, Petition) with an upcoming
  meeting. `closes_on` = the next deciding ("beschließend") meeting, else
  the next advisory one; `organizer` = that body.
- **Discovery:** agenda items created in the last 28 days (agendas are
  published about two weeks ahead) -> their meetings (date, body) ->
  consultations only for upcoming meetings of bodies in scope. The paper
  list is too large to walk (1,200+ changes in 45 days, mostly district
  budget grants). A run takes about 15-25 min because the server is slow.
- **Bodies in scope:** Stadtrat, committees, Stadtbezirksbeiräte,
  Ortschaftsräte. Not: advisory boards (Beiräte), party groups.
- **Non-public papers are dropped.** Contract awards sit on public agendas,
  but OParl answers 404 for their paper and the web link shows an error.
- **Detail text:** paper type, reference and the paper PDF's first pages
  (`pypdf`), read only for new or changed listings. Often there is no
  `mainFile`; the paper is then the attachment named after its reference
  (`V1070/26` -> `V1070_26`).
- **Relevance for Ratsvorlagen:** the way to act (write to the members) is
  always there, so the model only judges public interest vs. routine. The
  first dry run (2026-11-08, 71 papers, no Stadtrat agenda published yet)
  showed the model rejecting nearly everything for "no participation
  option", including the school-building strategy and the 2027/28 budget;
  the prompt was fixed (ENRICHMENT_VERSION 12); no re-test planned.
- **Districts:** the body name is in the registry summary, so a
  Stadtbezirksbeirat's district is matched like any other. Known gap: the
  district list has Ortsteile, not Stadtbezirke, and lacks
  Schönfeld-Weißig.
- Council members' emails are available via OParl memberships/persons
  (not read yet; needed for letters).

### Relevance (LLM, per listing)

Kept: petitions, statements on displayed plans (Bauleitplanung),
consultations, citizen surveys and public dialogues on public decisions,
upcoming council decisions (Ratsvorlagen), understandable for a private
person. Dropped: property viewings, job and speaker calls, internal
administration trainings, award ceremonies, professional-only info events,
highly technical acts; for council papers also administrative routine
(committee appointments, budget transfers, annual accounts, grants to
single clubs, property deals, personnel matters, information-only papers).
Scope must be EU, Bund, Sachsen or Dresden; other municipalities and other
Länder are dropped (nationally relevant topics count as Bund).

---

## Dependencies

- Reads: `architecture/overview.md`, `data/database-schema.md`
- Referenced by: `features/feed.md`, `technical/monitoring.md`

---

## Open Questions

- [x] Dresden council decisions via OParl (2026-11-08).
- [ ] Roadmap: Landtag Sachsen decisions. Session calendar and EDAS are
      robots-disallowed; options are asking the Landtag for permission or
      entering key plenary items by hand.
- [ ] Not planned now: Bundestag agenda (low expected impact; PDF or DIP).
- [ ] Scheduled ingestion: decisions appear ~2 weeks ahead and expire on
      the meeting day, so runs must be at least daily once deployed.
- [ ] Bundestag ePetitionen (list needs a JS session token).
- [ ] Momentum: support snapshots are recorded per run; how (and whether)
      to surface momentum is undecided.
- [ ] Hard cost ceiling per run for enrichment.
- [ ] Sources with the opposite political lean to openPetition/WeAct.
