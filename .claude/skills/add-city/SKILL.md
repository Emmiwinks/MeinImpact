---
name: add-city
description: Add a place (Kommune, Landkreis or Land) to MeinImpact's coverage: find its participation sources and council contacts, write its draft place file, sync its data, dry-run it and report coverage for review. Use when asked to add, cover or onboard a city, town, Kreis or Land.
---

# Add a place

A place is one file under `backend/src/meinimpact/places/defs/`, holding identifiers and rules only. Everything downstream (sources, coverage, districts, prompts, council sync) reads from there. The fields and their meaning live in `places/model.py`; `defs/dresden.py` is the worked example. The run ends at the **review stop**: the user decides what goes live.

All commands run in the API container from `backend/` (`docker compose exec api python ...`), in PowerShell.

## 1. Levels

```
python scripts/place_chain.py "<name>"
```

It prints, for every municipality Wikidata finds for the name, the chain Kommune → Landkreis (or "kreisfreie Stadt") → Land with AGS, Wikidata QID, Ortsteil count, the name the place table locates it by, and "file exists" or "new" per level. Pick the municipality the user meant; ask if two fit. Its output is the input for every later step: use these AGS and QIDs, never ones from memory.

Done when the chosen municipality's chain is printed with no "not found" line.

## 2. Sources

For every new level, go through [reference/known-platforms.md](reference/known-platforms.md) top to bottom. Search the web only for what that list leaves open, and only for registries of the kinds named there.

For each candidate, fetch its `robots.txt` before anything else and record one verdict: **found** (allowed, machine-readable or parseable, has open items), **rejected** (why), or **blocked** (robots, login, JS token wall). A blocked source that matters gets a permission request drafted from [reference/permission-letter.md](reference/permission-letter.md); the user sends it.

A source counts only if a shared adapter under `infrastructure/listings/sources/` can read it, configured from the place file. When a shared adapter fits but cannot take the place as configuration yet, extend it to take it (configuration, never a copy of the module). A source that needs a module of its own for this one place: stop and ask the user first.

Done when every platform in the list has a verdict for every new level.

## 3. Place files

Write one file per new level, `status` left at its default (draft). The module docstring records the step-2 verdicts: sources found, rejected (with reason), blocked (with contact status, e.g. "asked 2026-11-25"). That docstring is the place's record; the next change to this place starts by reading it.

Then: `python -m pytest -q --no-cov tests/test_places.py`. The registry validates parents, AGS nesting and live/draft order on import.

Done when the tests pass.

## 4. Reference data and contacts

- Districts, if the place has `wikidata_id` and `district_types`: `python scripts/sync_districts.py <key>`; read the diff (names plausible, count close to the city's own list).
- Council with OParl: `python scripts/sync_council_offices.py <key>`. For every Fraktion it lists without an address, find the office address on the Fraktion's own site or the city's Fraktion page and add it to `infrastructure/council/data/<key>.json` with that page as `source` and today as `verified_on`. One address per Fraktion, never a member's personal address.

Place data comes only from these sync scripts and from pages recorded as `source`; never type coordinates, lists or addresses in from memory.

Done when every current Fraktion has an address with a source, or is named in the report as missing.

## 5. Dry run

```
python scripts/dryrun_place.py <key> --enrich 20
```

It prints kept listings per source, kind and region, authorities that name the place but match no file (fix with `portal_names`, rerun), and for the sample the relevant share and € per listing. The sample costs real Mistral money (about 1 cent per listing); 20 is enough.

Then the quality gates: `ruff format --check`, `ruff check`, `mypy --no-incremental src scripts tests`, `pytest`.

Done when the dry run finished without failed sources you did not expect and all gates are green.

## 6. Review stop

Report to the user in plain, short language:

- The chain, and which files are new.
- Per source: found / rejected / blocked, one line each.
- Dry-run numbers against the targets in `services/coverage.py`, and which targets look out of reach.
- Relevant share of the sample, € per listing, and the one-off cost of enriching everything kept.
- Contacts: addresses found, addresses missing, permission letters drafted.

Then wait. On the user's OK: commit the files in one commit (their convention: directly on main, gates green). Going live is a separate, later step the user takes after the first real ingestion run shows the place's coverage card on /admin: set `status=Status.LIVE` in its file (and in its parents', which must be live first).
