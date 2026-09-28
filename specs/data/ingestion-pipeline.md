# Ingestion Pipeline

## Purpose
Defines the background process that fetches, filters, classifies, and
stores civic actions into the pool. This is the core data engine of
MeinImpact.

---

## Status (2026-09-27): being redesigned

The previous design — two parallel pipelines (parliamentary, sourced from
the Bundestag DIP API; petition, partly DIP/partly Tavily) with a DIP-
derived `engagement_state` (A/B/C/D) rule engine — has been retired. The
DIP API is no longer used to source the topic pool. Topic discovery will
instead be based on Tavily search. The full design is not written up yet;
this document tracks what's been agreed so far and what's still open.

**What's agreed:**
- No DIP dependency for topic-pool sourcing. The DIP adapter
  (`infrastructure/sources/dip_adapter.py`) is preserved, unused, for
  possible reuse later — nothing in the pipeline calls it.
- Petition sourcing (previously a mix of DIP and Tavily/Google CSE) is
  also being redesigned, not just patched to drop its DIP part.
- The pipeline runs on manual/admin trigger only, not on a daily schedule.
  No APScheduler cron job for ingestion for now.
- Built from small, reusable, independently-testable components — not a
  monolithic script.
- Whether an engagement-state-like relevance signal (the old A/B/C/D
  model) is reintroduced, and on what basis, is part of the pending
  design — nothing here should be assumed carried over.
- `tavily_media_adapter.py` (the old state-C "quality-media coverage"
  check) is held, unused, pending review of whether it fits the new
  design — not deleted, not assumed reusable either.

**What's unaffected by this change** (out of scope for the DIP removal):
- MdB position sources (Abgeordnetenwatch, DIP Plenarprotokolle, Bundestag
  RSS — `data/sources-federal.md` Source 6) and the tracking feature's
  MdB-statement refresh. These never fed the topic pool.
- AI classification via Mistral as a concept (the specific prompt/schema
  will likely need revisiting once the new source shape is known, but
  classify-after-discover is not being questioned here).

---

## Decisions carried over (still true, source-agnostic)

- **Pipeline is fully server-side.** No device interaction during
  ingestion. Devices download the resulting pool via the standard feed
  endpoint.
- **AI classification runs once per action, result is cached in DB.**
  Re-classification only occurs if the action is manually flagged or the
  classification schema changes.
- **Pipeline is fault-tolerant per source.** A single source failure does
  not abort the pipeline.
- **Hard cost ceiling per run.** If AI spend for one pipeline run exceeds
  the configured ceiling, classification stops and remaining items are
  marked `pending_classification` for the next run.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/data-flow.md`,
  `data/sources-federal.md`, `data/database-schema.md`
- Referenced by: `features/feed.md`, `features/tracking.md`,
  `technical/monitoring.md`

---

## Open Questions

- [ ] Full Tavily-search-based topic discovery design: what gets
      searched for, how results become candidate topics, how duplicates
      across searches are handled.
- [ ] Whether a relevance/priority signal (successor to engagement_state)
      is needed, and what it would be derived from without DIP.
- [ ] Whether petition sourcing survives in the new design and in what
      form.
- [ ] Whether `tavily_media_adapter.py` gets reused once the new source
      shape is known.
- [ ] Target DB schema for the new pipeline's output — see
      `data/database-schema.md`.
