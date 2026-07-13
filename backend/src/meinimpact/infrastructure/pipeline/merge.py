"""Merge + deduplicate the outputs of both pipelines.

Per specs/data/ingestion-pipeline.md "Merging and Deduplication":
  Step 1: exact source_url match (existing dedup logic, unchanged in intent)
  Step 2: topic fingerprint match — same DIP descriptor OR >85% title
          similarity — on a collision, keep the higher engagement_state
          (A > B > C), tie-broken by type priority.

Operates on `list[ItemState]` (not `ClassifiedAction`/`RawSourceItem`
directly) because engagement_state lives on `ItemState.state_trace`, not on
the classified action itself — see `pipeline/step.py`.
"""

from thefuzz import fuzz  # type: ignore[import-untyped]

from meinimpact.infrastructure.pipeline.step import ItemState

STATE_RANK: dict[str, int] = {"A": 3, "B": 2, "C": 1}
# Lower index = higher priority when engagement_state is tied.
TYPE_PRIORITY: list[str] = ["bundestag_petition", "petition", "brief", "anfrage"]
_FUZZY_TITLE_THRESHOLD = 85


def merge_and_deduplicate(
    parliamentary: list[ItemState],
    petition: list[ItemState],
    existing_urls: set[str],
    existing_titles: list[str],
) -> list[ItemState]:
    """Combines both pipelines' surviving items and deduplicates them."""
    for item in parliamentary:
        item.pipeline_source = "parliamentary"
    for item in petition:
        item.pipeline_source = "petition"

    combined = parliamentary + petition
    after_url_dedup = _deduplicate_exact_url(combined, existing_urls)
    return _deduplicate_fingerprint(after_url_dedup, existing_titles)


def _deduplicate_exact_url(items: list[ItemState], existing_urls: set[str]) -> list[ItemState]:
    seen = set(existing_urls)
    kept: list[ItemState] = []
    for item in items:
        url = item.raw["source_url"]
        if url in seen:
            continue
        kept.append(item)
        seen.add(url)
    return kept


def _deduplicate_fingerprint(
    items: list[ItemState], existing_titles: list[str]
) -> list[ItemState]:
    """Resolves fingerprint collisions within `items` (existing_titles are
    only used to detect a match, never to drop something new outright —
    pool actions already deduped by source_url are not re-inserted anyway)."""
    kept: list[ItemState] = []
    for candidate in items:
        duplicate_index = _find_duplicate_index(candidate, kept, existing_titles)
        if duplicate_index is None:
            kept.append(candidate)
        elif _should_replace(kept[duplicate_index], candidate):
            kept[duplicate_index] = candidate
    return kept


def _find_duplicate_index(
    candidate: ItemState, kept: list[ItemState], existing_titles: list[str]
) -> int | None:
    for i, existing in enumerate(kept):
        if _is_duplicate(candidate, existing):
            return i
    return None


def _is_duplicate(a: ItemState, b: ItemState) -> bool:
    descriptor_a = a.raw.get("descriptor")
    descriptor_b = b.raw.get("descriptor")
    if descriptor_a and descriptor_b and set(descriptor_a) & set(descriptor_b):
        return True
    return fuzz.ratio(a.raw["title"], b.raw["title"]) > _FUZZY_TITLE_THRESHOLD


def _should_replace(existing: ItemState, candidate: ItemState) -> bool:
    existing_rank = _state_rank(existing)
    candidate_rank = _state_rank(candidate)
    if candidate_rank != existing_rank:
        return candidate_rank > existing_rank
    return _type_priority(candidate) < _type_priority(existing)


def _state_rank(item: ItemState) -> int:
    if item.state_trace is None:
        return 0
    return STATE_RANK.get(item.state_trace.engagement_state, 0)


def _type_priority(item: ItemState) -> int:
    label = _type_label(item)
    try:
        return TYPE_PRIORITY.index(label)
    except ValueError:
        return len(TYPE_PRIORITY)


def _type_label(item: ItemState) -> str:
    if item.raw.get("type") == "petition":
        return "bundestag_petition" if item.raw.get("source") == "dip" else "petition"
    action_types = (item.classified or {}).get("action_types") or []
    if "anfrage" in action_types:
        return "anfrage"
    return "brief"
