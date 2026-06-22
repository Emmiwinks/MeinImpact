"""Pure pipeline stage functions (Stages 2, 3, and momentum calculation).

These are module-level functions with no I/O, making them fully unit-testable.
"""

import logging
from datetime import date

from thefuzz import fuzz  # type: ignore[import-untyped]

from meinimpact.infrastructure.sources.protocol import RawSourceItem

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Stage 2: Deduplicate
# ---------------------------------------------------------------------------


def deduplicate(
    items: list[RawSourceItem],
    existing_urls: set[str],
    existing_titles: list[str],
) -> list[RawSourceItem]:
    """Removes items already present in the action pool.

    Exact URL match takes priority; fuzzy title match (>85% similarity)
    catches the same item appearing from two different sources.
    """
    new_items: list[RawSourceItem] = []
    seen_urls: set[str] = set(existing_urls)
    seen_titles: list[str] = list(existing_titles)

    for item in items:
        url = item["source_url"]
        title = item["title"]

        if url in seen_urls:
            continue
        if any(fuzz.ratio(title, t) > 85 for t in seen_titles):
            continue

        new_items.append(item)
        seen_urls.add(url)
        seen_titles.append(title)

    return new_items


# ---------------------------------------------------------------------------
# Stage 3: Prefilter
# ---------------------------------------------------------------------------

_PREFILTER_MIN_TITLE_LEN = 10
_PREFILTER_MIN_PETITION_SIGNATURES = 500


def prefilter(items: list[RawSourceItem]) -> list[RawSourceItem]:
    """Rule-based filter applied before any AI call.

    Expected to drop ~60-70% of raw items, keeping only those worth
    the cost of Mistral classification.
    """
    passed = []
    for item in items:
        reason = _drop_reason(item)
        if reason is None:
            passed.append(item)
        else:
            logger.debug("Prefilter dropped %r: %s", item["title"][:60], reason)
    return passed


def _drop_reason(item: RawSourceItem) -> str | None:
    """Returns the drop reason string, or None if the item passes."""
    if len(item["title"]) < _PREFILTER_MIN_TITLE_LEN:
        return (
            f"title too short ({len(item['title'])} chars < {_PREFILTER_MIN_TITLE_LEN})"
        )

    # For petitions: enforce future deadline and minimum signatures.
    # Bundestag items (antrag, gesetzentwurf) use deadline as activity date, not expiry.
    if item["type"] == "petition":
        deadline = item.get("deadline")  # type: ignore[misc]
        if (
            deadline is not None
            and isinstance(deadline, date)
            and deadline < date.today()
        ):
            return f"petition deadline in past ({deadline})"
        sigs = item.get("signature_count")  # type: ignore[misc]
        if sigs is not None and sigs < _PREFILTER_MIN_PETITION_SIGNATURES:
            min_sigs = _PREFILTER_MIN_PETITION_SIGNATURES
            return f"petition signatures too low ({sigs} < {min_sigs})"

    if not _is_german(item["title"]):
        return "title not detected as German"

    return None


def _is_german(text: str) -> bool:
    """Returns True if the text appears to be German.

    Uses langdetect with a fallback heuristic in case of short/ambiguous text.
    """
    if not text.strip():
        return False
    try:
        from langdetect import (  # type: ignore[import-untyped]
            LangDetectException,
            detect,
        )

        try:
            return detect(text) == "de"
        except LangDetectException:
            return True  # benefit of the doubt for short texts
    except ImportError:
        return _german_heuristic(text)


def _german_heuristic(text: str) -> bool:
    """Simple fallback: checks for common German function words."""
    indicators = {"der", "die", "das", "und", "für", "ist", "des", "den", "auf", "von"}
    words = set(text.lower().split())
    return len(words & indicators) >= 2


# ---------------------------------------------------------------------------
# Momentum score
# ---------------------------------------------------------------------------


def calculate_momentum(
    news_mention_count: int,
    signature_velocity: float | None = None,
) -> float:
    """Calculates a 0.0-1.0 momentum score from news coverage and petition velocity."""
    score = 0.3

    if news_mention_count >= 5:
        score += 0.3
    elif news_mention_count >= 2:
        score += 0.15

    if signature_velocity is not None:
        if signature_velocity > 1000:
            score += 0.3
        elif signature_velocity > 100:
            score += 0.15

    return min(score, 1.0)


# ---------------------------------------------------------------------------
# Action type mapping helpers (used by persist stage)
# ---------------------------------------------------------------------------

_ACTION_TYPE_MAP: dict[str, str] = {
    "brief": "representative_letter",
    "petition": "petition_signature",
    "anfrage": "public_question",
}

_RAW_TYPE_TO_DOMAIN: dict[str, str] = {
    "petition": "petition_signature",
    "gesetzentwurf": "representative_letter",
    "antrag": "representative_letter",
    "abstimmung": "representative_letter",
}

_EFFORT_MINUTES: dict[str, int] = {
    "petition_signature": 5,
    "public_question": 10,
    "representative_letter": 15,
}

_IMPACT_HINT: dict[str, str] = {
    "high": "Abstimmung oder Frist steht kurz bevor",
    "mid": "Aktive parlamentarische Beratung",
    "low": "Laufender Gesetzgebungsprozess",
}


def map_domain_action_type(classified: ClassifiedActionLike) -> str:
    """Maps classification output to a domain ActionType string."""
    # Prefer explicit action_types list from classification
    for at in classified.get("action_types", []):  # type: ignore[misc]
        if at in _ACTION_TYPE_MAP:
            return _ACTION_TYPE_MAP[at]
    # Fall back to raw source type
    return _RAW_TYPE_TO_DOMAIN.get(classified.get("type", ""), "representative_letter")  # type: ignore[misc]


def effort_minutes_for(domain_action_type: str) -> int:
    return _EFFORT_MINUTES.get(domain_action_type, 15)


def impact_hint_for(urgency: str) -> str:
    return _IMPACT_HINT.get(urgency, "Parlamentarische Aktion")


# Type alias used above to avoid circular import
from typing import Any  # noqa: E402

ClassifiedActionLike = dict[str, Any]
