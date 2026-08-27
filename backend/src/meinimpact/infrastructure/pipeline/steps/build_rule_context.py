"""BuildRuleContextStep — fans out the I/O each item needs before rule
evaluation, and attaches the resulting RuleContext.

This is the only step that talks to the media-coverage/committee-activity/
vote-result checks; every downstream step (EvaluateStateStep) is pure. Each
check is an injected async callable rather than a hardcoded adapter — a
pipeline that doesn't need a given check simply doesn't pass it (defaults
to "no signal found").

State B is resolved entirely from DIP-derived fields (`has_vote_result`,
`stellungnahme_fraktion_count`) — there is deliberately no per-MdB position
check here. The pool is shared across every device (see features/feed.md
"no server-side personalisation"), so there is no single MdB to check at
ingestion time; per-user personalisation of the state-B reason happens
client-side instead. See specs/data/ingestion-pipeline.md "State B
triggers".

`vote_date` resolution is deliberately left to an injected lookup too:
per specs/data/ingestion-pipeline.md Open Questions, DIP does not expose a
clean "scheduled vote date" field — the exact mechanism is unresolved, so
this step does not guess at one.
"""

import asyncio
from collections.abc import Awaitable, Callable
from datetime import date, datetime

from meinimpact.infrastructure.pipeline.state_rules.protocol import RuleContext
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.sources.protocol import RawSourceItem

VoteDateLookup = Callable[[RawSourceItem], date | None]
CommitteeCheck = Callable[[RawSourceItem], Awaitable[bool]]
VoteResultLookup = Callable[[RawSourceItem], bool]
FraktionStellungnahmeLookup = Callable[[RawSourceItem], int | None]
MediaCheck = Callable[[RawSourceItem], Awaitable[bool]]
SignatureGoalLookup = Callable[[RawSourceItem], int | None]
PreviousSignatureLookup = Callable[[RawSourceItem], int | None]


class BuildRuleContextStep:
    """Builds one `RuleContext` per item, fanning out the configured checks
    across all items concurrently."""

    name = "build_rule_context"

    def __init__(
        self,
        *,
        vote_date_lookup: VoteDateLookup | None = None,
        committee_check: CommitteeCheck | None = None,
        vote_result_lookup: VoteResultLookup | None = None,
        fraktion_stellungnahme_lookup: FraktionStellungnahmeLookup | None = None,
        media_check: MediaCheck | None = None,
        signature_goal_lookup: SignatureGoalLookup | None = None,
        previous_signature_lookup: PreviousSignatureLookup | None = None,
    ) -> None:
        self._vote_date_lookup = vote_date_lookup
        self._committee_check = committee_check
        self._vote_result_lookup = vote_result_lookup
        self._fraktion_stellungnahme_lookup = fraktion_stellungnahme_lookup
        self._media_check = media_check
        self._signature_goal_lookup = signature_goal_lookup
        self._previous_signature_lookup = previous_signature_lookup

    async def process(
        self, items: list[ItemState], deps: PipelineDeps
    ) -> list[ItemState]:
        contexts = await asyncio.gather(*[self._build_one(item) for item in items])
        for item, context in zip(items, contexts, strict=True):
            item.rule_context = context
        return items

    async def _build_one(self, item: ItemState) -> RuleContext:
        committee_active = False
        if self._committee_check is not None:
            committee_active = await self._committee_check(item.raw)

        media_matched = False
        if self._media_check is not None:
            media_matched = await self._media_check(item.raw)

        return RuleContext(
            item=item.raw,
            now=datetime.now(),
            vote_date=self._vote_date_lookup(item.raw)
            if self._vote_date_lookup
            else None,
            committee_recently_active=committee_active,
            has_vote_result=(
                self._vote_result_lookup(item.raw)
                if self._vote_result_lookup
                else False
            ),
            stellungnahme_fraktion_count=(
                self._fraktion_stellungnahme_lookup(item.raw)
                if self._fraktion_stellungnahme_lookup
                else None
            ),
            media_coverage_matched=media_matched,
            previous_signature_count=(
                self._previous_signature_lookup(item.raw)
                if self._previous_signature_lookup
                else None
            ),
            signature_goal=(
                self._signature_goal_lookup(item.raw)
                if self._signature_goal_lookup
                else None
            ),
        )
