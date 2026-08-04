"""Pipeline 1: parliamentary (top-down) — declarative step composition.

Per specs/data/ingestion-pipeline.md "Pipeline 1: Parliamentary-driven".
Reordering, removing, or adding a step is a one-line change in
`build_parliamentary_steps` — no executor changes needed.
"""

from datetime import date, timedelta

from meinimpact.core.config import Settings
from meinimpact.infrastructure.ai.classifier import MistralClassifier
from meinimpact.infrastructure.pipeline.executor import run_pipeline
from meinimpact.infrastructure.pipeline.state_rules.parliamentary_rules import (
    RULES as PARLIAMENTARY_RULES,
)
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps, PipelineStep
from meinimpact.infrastructure.pipeline.steps.build_rule_context import BuildRuleContextStep
from meinimpact.infrastructure.pipeline.steps.classify import ClassifyStep
from meinimpact.infrastructure.pipeline.steps.evaluate_state import EvaluateStateStep
from meinimpact.infrastructure.pipeline.steps.fetch import FetchStep
from meinimpact.infrastructure.pipeline.steps.filter_state_d import FilterStateDStep
from meinimpact.infrastructure.pipeline.steps.prefilter import PrefilterStep
from meinimpact.infrastructure.pipeline.steps.trace_discards import (
    DiscardSink,
    TraceDiscardsStep,
)
from meinimpact.infrastructure.sources.dip_adapter import DipAdapter
from meinimpact.infrastructure.sources.dip_committee_activity import DipCommitteeActivityAdapter
from meinimpact.infrastructure.sources.protocol import RawSourceItem
from meinimpact.infrastructure.sources.tavily_client import TavilyClient
from meinimpact.infrastructure.sources.tavily_media_adapter import TavilyMediaCoverageAdapter

_COMMITTEE_LOOKBACK_DAYS = 3


def build_parliamentary_steps(
    settings: Settings, discard_sink: DiscardSink | None = None
) -> list[PipelineStep]:
    """Builds the Pipeline 1 step list from settings."""
    steps: list[PipelineStep] = []

    if settings.dip_api_key:
        steps.append(FetchStep(DipAdapter(api_key=settings.dip_api_key)))

    steps.append(PrefilterStep())
    steps.append(_build_rule_context_step(settings))
    steps.append(EvaluateStateStep(PARLIAMENTARY_RULES))
    steps.append(TraceDiscardsStep(sink=discard_sink))
    steps.append(FilterStateDStep())

    if settings.mistral_api_key:
        steps.append(
            ClassifyStep(
                MistralClassifier(
                    api_key=settings.mistral_api_key,
                    base_url=settings.mistral_base_url,
                    model=settings.mistral_model,
                )
            )
        )
    return steps


def _build_rule_context_step(settings: Settings) -> BuildRuleContextStep:
    committee_check = None
    if settings.dip_api_key:
        committee_adapter = DipCommitteeActivityAdapter(api_key=settings.dip_api_key)

        async def committee_check(item: RawSourceItem) -> bool:
            since: date = date.today() - timedelta(days=_COMMITTEE_LOOKBACK_DAYS)
            return await committee_adapter.has_recent_activity(item["external_id"], since)

    media_check = None
    if settings.tavily_api_key:
        media_adapter = TavilyMediaCoverageAdapter(TavilyClient(settings.tavily_api_key))

        async def media_check(item: RawSourceItem) -> bool:
            result = await media_adapter.check_coverage(item["title"])
            return result.matched

    # vote_result_lookup / fraktion_stellungnahme_lookup (state B) are NOT
    # wired yet: both need DIP fields (Abstimmungsergebnis presence,
    # per-Fraktion Stellungnahme count) that dip_adapter.py doesn't parse
    # from the Vorgang document today. State B trigger #3
    # (EarlyReadingNoVoteScheduledRule) still works via vote_date_lookup
    # once that's wired; triggers #1 and #2 will fire once DIP parsing is
    # extended. This is a data-extraction gap, not an architectural one —
    # state B is correctly action-level now (see
    # specs/data/ingestion-pipeline.md "State B triggers").
    return BuildRuleContextStep(committee_check=committee_check, media_check=media_check)


async def run_parliamentary_pipeline(
    deps: PipelineDeps, discard_sink: DiscardSink | None = None
) -> list[ItemState]:
    """Runs Pipeline 1 end-to-end: fetch, prefilter, state determination,
    discard state D, classify."""
    steps = build_parliamentary_steps(deps.settings, discard_sink)
    return await run_pipeline(steps, deps)
