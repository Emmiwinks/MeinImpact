"""Core types for engagement-state determination.

Per specs/data/ingestion-pipeline.md, every candidate action is assigned an
`engagement_state` ('A' | 'B' | 'C' | 'D') by running an ordered list of
`StateRule` objects against a `RuleContext` — first rule to match wins. 'D'
means no engagement hook exists right now; the item is discarded before
classification.

`RuleContext` carries everything a rule needs, already resolved by the
pipeline driver (see `infrastructure/pipeline/steps/build_rule_context.py`)
*before* rule evaluation happens. This keeps every rule a pure function of
its inputs: no I/O, no adapter imports, fully unit-testable with hand-built
contexts.
"""

from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Literal, Protocol

from meinimpact.infrastructure.sources.protocol import RawSourceItem

EngagementState = Literal["A", "B", "C", "D"]


@dataclass(frozen=True)
class RuleContext:
    """Everything a rule needs to decide, pre-fetched — no I/O inside rules.

    Fields are optional/default-valued because a single `RuleContext` shape
    is shared by both the parliamentary and petition rule lists, and not
    every field applies to both pipelines.

    State B is deliberately an action-level signal (`has_vote_result`,
    `stellungnahme_fraktion_count`), not a per-MdB check — the pool is
    shared across every device (see features/feed.md "no server-side
    personalisation"), so there is no single MdB to check at ingestion
    time. Per-user MdB personalisation of the state-B reason happens
    client-side; see features/feed.md.
    """

    item: RawSourceItem
    now: datetime

    # Parliamentary-specific (state A #1/#2, state B)
    vote_date: date | None = None
    committee_recently_active: bool = False
    has_vote_result: bool = False
    stellungnahme_fraktion_count: int | None = None

    # Shared (state C, both pipelines)
    media_coverage_matched: bool = False

    # Petition-specific (state A #1-#3, state C)
    previous_signature_count: int | None = None
    signature_goal: int | None = None


@dataclass(frozen=True)
class RuleResult:
    """Returned by a rule when it fires. `None` means 'try the next rule'."""

    state: EngagementState
    reason: str  # German, user-facing state_reason
    rule_name: str
    evidence: dict[str, object] = field(default_factory=dict)


@dataclass(frozen=True)
class StateTrace:
    """Full evaluation outcome for one item — the traceability artifact."""

    engagement_state: EngagementState
    state_reason: str
    matched_rule: str
    rules_checked: list[str]
    evidence: dict[str, object]


class StateRule(Protocol):
    """One rule in an ordered chain. First rule to return non-None wins."""

    name: str

    def evaluate(self, context: RuleContext) -> RuleResult | None: ...
