"""Merge the outputs of both pipelines and assign topic groupings.

Per specs/data/ingestion-pipeline.md "Merging and Deduplication":
  Step 1: exact source_url match (existing dedup logic, unchanged) — an
          item whose source_url is already persisted is dropped, it would
          just re-insert the identical thing.
  Step 2: topic assignment — same DIP descriptor OR >85% title similarity
          (`thefuzz`) means two items are different engagement *options*
          for the same real-world topic, not duplicates of each other.
          Both survive, tagged with the same `topic_id`. Nothing is
          discarded and nothing is ranked here — there used to be a
          `TYPE_PRIORITY` (bundestag_petition > petition > brief > anfrage)
          and a `STATE_RANK` (A > B > C) tie-break that picked one winner
          per topic fingerprint match. Both are gone: comparing "is a
          petition near quorum more urgent than a Vorgang in committee"
          was forcing an ordinal comparison across things that aren't
          actually comparable (different real-world mechanisms, not
          different values on one scale) — the same category error
          `TYPE_PRIORITY` made about action type, just applied to urgency.
          Every option a pipeline found for a topic is kept and shown.

Operates on `list[ItemState]` (not `ClassifiedAction`/`RawSourceItem`
directly) because engagement_state lives on `ItemState.state_trace`, not on
the classified action itself — see `pipeline/step.py`.
"""

from dataclasses import dataclass
from uuid import uuid4

from thefuzz import fuzz  # type: ignore[import-untyped]

from meinimpact.infrastructure.pipeline.step import ItemState

_FUZZY_TITLE_THRESHOLD = 85


@dataclass(frozen=True)
class ExistingFingerprint:
    """Identity of one already-persisted active action, fetched once per
    pipeline run so new items can join an existing topic across runs (not
    just within the same run) — see `orchestrator.py`'s `_load_existing`.

    No `descriptor` field: it isn't persisted (see
    specs/data/sources-federal.md Source 1 "Fields extracted per item" —
    only used transiently during a run), so cross-run matching relies on
    the fuzzy title match alone. That's sufficient; adding a `descriptor`
    column is future work if title matching proves too weak in practice.
    """

    id: str
    topic_id: str
    title: str


def merge_and_deduplicate(
    parliamentary: list[ItemState],
    petition: list[ItemState],
    existing_urls: set[str],
    existing: list[ExistingFingerprint],
) -> list[ItemState]:
    """Combines both pipelines' surviving items, drops exact re-fetches, and
    assigns a `topic_id` to everything that's left."""
    for item in parliamentary:
        item.pipeline_source = "parliamentary"
    for item in petition:
        item.pipeline_source = "petition"

    combined = parliamentary + petition
    after_url_dedup = _deduplicate_exact_url(combined, existing_urls)
    return _assign_topic_ids(after_url_dedup, existing)


def _deduplicate_exact_url(
    items: list[ItemState], existing_urls: set[str]
) -> list[ItemState]:
    seen = set(existing_urls)
    kept: list[ItemState] = []
    for item in items:
        url = item.raw["source_url"]
        if url in seen:
            continue
        kept.append(item)
        seen.add(url)
    return kept


def _assign_topic_ids(
    items: list[ItemState], existing: list[ExistingFingerprint]
) -> list[ItemState]:
    """Tags every item with a `topic_id`. An item joins an existing topic
    when it fingerprint-matches an already-persisted action (cross-run) or
    another item already assigned earlier in this same run (same-run);
    otherwise it starts a new topic. Nothing is dropped here."""
    seen: list[tuple[str, list[str] | None, str]] = [
        (e.title, None, e.topic_id) for e in existing
    ]
    for item in items:
        title = item.raw["title"]
        descriptor = item.raw.get("descriptor")
        match = _find_topic_match(title, descriptor, seen)
        item.topic_id = match if match is not None else str(uuid4())
        seen.append((title, descriptor, item.topic_id))
    return items


def _find_topic_match(
    title: str,
    descriptor: list[str] | None,
    seen: list[tuple[str, list[str] | None, str]],
) -> str | None:
    for other_title, other_descriptor, topic_id in seen:
        if _is_same_topic(title, descriptor, other_title, other_descriptor):
            return topic_id
    return None


def _is_same_topic(
    title_a: str,
    descriptor_a: list[str] | None,
    title_b: str,
    descriptor_b: list[str] | None,
) -> bool:
    if descriptor_a and descriptor_b and set(descriptor_a) & set(descriptor_b):
        return True
    return bool(fuzz.ratio(title_a, title_b) > _FUZZY_TITLE_THRESHOLD)
