"""Types shared across pipeline stages."""

from datetime import date
from typing import NotRequired, TypedDict


class ClassifiedAction(TypedDict):
    """A RawSourceItem enriched with Tavily context and Mistral classification."""

    # ── From RawSourceItem ────────────────────────────────────────────────────
    external_id: str
    title: str
    type: str
    status: str
    deadline: date | None
    source_url: str
    description: str
    initiated_by: str
    source: str
    tavily_context: NotRequired[str]
    signature_count: NotRequired[int]
    # ── Classification output ─────────────────────────────────────────────────
    topics: list[str]
    urgency: str  # "high" | "mid" | "low"
    werte_relevanz: dict[str, float]
    pro_argumente: list[str]
    contra_argumente: list[str]
    action_types: list[str]  # "brief" | "petition" | "anfrage"
    is_controversial: bool
    position_required: bool
    momentum_score: float
