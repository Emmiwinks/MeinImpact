"""Pure pipeline helper functions shared across steps.

These are module-level functions with no I/O, making them fully unit-testable.
`deduplicate()`, `prefilter()`, and `calculate_momentum()` (the pre-
engagement-state versions) were removed in the cutover to the state-based
pipeline — see `pipeline/merge.py` (dedup) and `pipeline/steps/prefilter.py`
(cheap pre-check) for their replacements.
"""

from collections.abc import Mapping
from typing import Any

from meinimpact.infrastructure.sources.protocol import RawSourceItem

_PREFILTER_MIN_TITLE_LEN = 10


def passes_basic_checks(item: RawSourceItem) -> bool:
    """Cheap pre-check used by `steps/prefilter.py`, run before the expensive
    per-item I/O in `BuildRuleContextStep` (3-source MdB check, Tavily media
    search): title length + German-language only.

    Deliberately does not include a flat petition-signature floor — that's
    handled with more nuance by the state A/C petition rules (goal-relative,
    not a flat floor).
    """
    if len(item["title"]) < _PREFILTER_MIN_TITLE_LEN:
        return False
    return _is_german(item["title"])


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
            return bool(detect(text) == "de")
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


def map_domain_action_type(classified: Mapping[str, Any]) -> str:
    """Maps classification output to a domain ActionType string.

    Takes `Mapping[str, Any]` rather than `ClassifiedAction` directly:
    mypy's TypedDict structural compatibility is stricter in practice than
    PEP 589 suggests for "TypedDict with extra required keys used where a
    total=False TypedDict is expected", so a loosely-typed Mapping is used
    instead — satisfied by `ClassifiedAction`, by plain dict literals in
    tests, and by anything else read-only dict-shaped.
    """
    # Prefer explicit action_types list from classification
    for at in classified.get("action_types", []):
        if at in _ACTION_TYPE_MAP:
            return _ACTION_TYPE_MAP[at]
    # Fall back to raw source type
    return _RAW_TYPE_TO_DOMAIN.get(classified.get("type", ""), "representative_letter")


def effort_minutes_for(domain_action_type: str) -> int:
    return _EFFORT_MINUTES.get(domain_action_type, 15)


def impact_hint_for(urgency: str) -> str:
    return _IMPACT_HINT.get(urgency, "Parlamentarische Aktion")
