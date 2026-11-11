"""Scheduled Mein Impact news search for tracked opportunities.

A round searches the opportunity that waited longest, then the next, until
nothing is due or the day's budget could not cover one more search. The
spend is measured, not estimated: Tavily credits used and the tokens
Mistral reports, priced with the rates in the settings. Before each search
the round keeps back what one search could cost at most, so the day stays
under budget.

An opportunity is searched again at most every `impact_news_recheck_days`.
A failed search is given back (due again next round) and ends the round,
since the cause is usually the provider and would fail every search.
"""

import asyncio
import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Protocol
from zoneinfo import ZoneInfo

from meinimpact.core.config import Settings
from meinimpact.infrastructure.ai.mistral_json import (
    JsonCompleter,
    MistralJsonCompleter,
)
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.impact.news_ladder import (
    LEVELS,
    NewsLadder,
    TavilySearch,
    WebSearch,
)
from meinimpact.infrastructure.impact.postgres_news_repository import (
    PostgresImpactNewsRepository,
)

logger = logging.getLogger(__name__)

_BERLIN = ZoneInfo("Europe/Berlin")
# Upper bound of one search: every rung, a query call plus one judge call
# per rung, each with a long prompt and a full answer
_MAX_CALLS = 1 + len(LEVELS)
_MAX_PROMPT_TOKENS = 4000
_MAX_ANSWER_TOKENS = 1200
_PER_MILLION = Decimal(1_000_000)


@dataclass(frozen=True, slots=True)
class Prices:
    tavily_credit: Decimal
    mistral_input_per_m: Decimal
    mistral_output_per_m: Decimal

    @classmethod
    def from_settings(cls, settings: Settings) -> Prices:
        return cls(
            tavily_credit=Decimal(str(settings.tavily_eur_per_credit)),
            mistral_input_per_m=Decimal(
                str(settings.mistral_extraction_eur_per_m_input)
            ),
            mistral_output_per_m=Decimal(
                str(settings.mistral_extraction_eur_per_m_output)
            ),
        )

    def tavily(self, credits: int) -> Decimal:
        return credits * self.tavily_credit

    def mistral(self, prompt_tokens: int, completion_tokens: int) -> Decimal:
        return (
            prompt_tokens * self.mistral_input_per_m
            + completion_tokens * self.mistral_output_per_m
        ) / _PER_MILLION

    @property
    def worst_case_search(self) -> Decimal:
        return self.tavily(len(LEVELS)) + _MAX_CALLS * self.mistral(
            _MAX_PROMPT_TOKENS, _MAX_ANSWER_TOKENS
        )


class MeteredCompleter(JsonCompleter, Protocol):
    prompt_tokens: int
    completion_tokens: int


class MeteredSearch(WebSearch, Protocol):
    credits: int


@dataclass
class NewsRoundSummary:
    searched: int = 0
    new_items: int = 0
    spent_eur: Decimal = Decimal(0)
    # "budget", "nothing_due" or "error"
    stopped: str = ""


async def run_news_round(
    repository: PostgresImpactNewsRepository,
    completer: MeteredCompleter,
    search: MeteredSearch,
    *,
    prices: Prices,
    daily_budget: Decimal,
    recheck_after: timedelta,
    now: Callable[[], datetime] = lambda: datetime.now(UTC),
) -> NewsRoundSummary:
    ladder = NewsLadder(completer, search)
    summary = NewsRoundSummary()
    while True:
        moment = now()
        day = moment.astimezone(_BERLIN).date()
        if daily_budget - await repository.spent_on(day) < prices.worst_case_search:
            summary.stopped = "budget"
            break
        claim = await repository.claim_due(
            now=moment, checked_before=moment - recheck_after
        )
        if claim is None:
            summary.stopped = "nothing_due"
            break

        credits = search.credits
        prompt, completion = completer.prompt_tokens, completer.completion_tokens
        failed = False
        try:
            result = await ladder.run(claim.subject)
        except Exception:
            logger.exception("News search failed for %s", claim.opportunity_id)
            await repository.release(claim)
            failed = True
        else:
            summary.new_items += await repository.save(
                claim.opportunity_id, result, checked_at=moment
            )
            summary.searched += 1

        # Paid even when the search failed halfway
        tavily_cost = prices.tavily(search.credits - credits)
        used_prompt = completer.prompt_tokens - prompt
        used_completion = completer.completion_tokens - completion
        mistral_cost = prices.mistral(used_prompt, used_completion)
        if tavily_cost:
            repository.record_spend(day, "tavily", tavily_cost, tokens=None)
        if mistral_cost:
            repository.record_spend(
                day, "mistral", mistral_cost, tokens=used_prompt + used_completion
            )
        await repository.commit()
        summary.spent_eur += tavily_cost + mistral_cost
        if failed:
            summary.stopped = "error"
            break
    return summary


async def run_configured_news_round(
    settings: Settings, database: Database
) -> NewsRoundSummary | None:
    """One round with the production providers; None without their keys."""
    if not settings.mistral_api_key or not settings.tavily_api_key:
        logger.warning("Mein Impact news needs the Mistral and Tavily keys")
        return None
    completer = MistralJsonCompleter(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=settings.mistral_extraction_model,
        max_tokens=_MAX_ANSWER_TOKENS,
    )
    search = TavilySearch(settings.tavily_api_key)
    try:
        async with database.session_factory() as session:
            return await run_news_round(
                PostgresImpactNewsRepository(session),
                completer,
                search,
                prices=Prices.from_settings(settings),
                daily_budget=Decimal(str(settings.impact_news_daily_budget_eur)),
                recheck_after=timedelta(days=settings.impact_news_recheck_days),
            )
    finally:
        await completer.aclose()
        await search.aclose()


async def run_news_scheduler(
    settings: Settings, database: Database, check_every: timedelta
) -> None:
    """Runs a news round every `check_every` forever; cancel to stop."""
    while True:
        try:
            summary = await run_configured_news_round(settings, database)
            if summary is not None and summary.searched:
                logger.info("Mein Impact news round: %s", summary)
        except Exception:  # a DB hiccup must not end the loop
            logger.exception("Mein Impact news round failed")
        await asyncio.sleep(check_every.total_seconds())
