"""Pipeline 2: petition (bottom-up) — declarative step composition.

Per specs/data/ingestion-pipeline.md "Pipeline 2: Petition-driven".
"""

from meinimpact.core.config import Settings
from meinimpact.infrastructure.ai.classifier import MistralClassifier
from meinimpact.infrastructure.pipeline.executor import run_pipeline
from meinimpact.infrastructure.pipeline.state_rules.petition_rules import (
    RULES as PETITION_RULES,
)
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps, PipelineStep
from meinimpact.infrastructure.pipeline.steps.build_rule_context import (
    BuildRuleContextStep,
    PreviousSignatureLookup,
)
from meinimpact.infrastructure.pipeline.steps.classify import ClassifyStep
from meinimpact.infrastructure.pipeline.steps.evaluate_state import EvaluateStateStep
from meinimpact.infrastructure.pipeline.steps.fetch import FetchStep
from meinimpact.infrastructure.pipeline.steps.filter_state_d import FilterStateDStep
from meinimpact.infrastructure.pipeline.steps.prefilter import PrefilterStep
from meinimpact.infrastructure.pipeline.steps.trace_discards import (
    DiscardSink,
    TraceDiscardsStep,
)
from meinimpact.infrastructure.sources.civil_petition_adapter import CivilPetitionAdapter
from meinimpact.infrastructure.sources.dip_adapter import DipAdapter, DipPetitionAdapter
from meinimpact.infrastructure.sources.google_cse_adapter import GoogleCseAdapter
from meinimpact.infrastructure.sources.tavily_client import TavilyClient
from meinimpact.infrastructure.sources.tavily_media_adapter import TavilyMediaCoverageAdapter


def build_petition_steps(
    settings: Settings,
    discard_sink: DiscardSink | None = None,
    previous_signature_lookup: PreviousSignatureLookup | None = None,
) -> list[PipelineStep]:
    """Builds the Pipeline 2 step list from settings."""
    steps: list[PipelineStep] = []

    if settings.dip_api_key:
        steps.append(
            FetchStep(
                DipPetitionAdapter(DipAdapter(api_key=settings.dip_api_key)),
                name="fetch_dip_petitions",
            )
        )

    if settings.tavily_api_key:
        google_cse = (
            GoogleCseAdapter(settings.google_cse_key, settings.google_cse_id)
            if settings.google_cse_key and settings.google_cse_id
            else None
        )
        steps.append(
            FetchStep(
                CivilPetitionAdapter(TavilyClient(settings.tavily_api_key), google_cse=google_cse),
                name="fetch_civil_petitions",
            )
        )

    steps.append(PrefilterStep())
    steps.append(_build_rule_context_step(settings, previous_signature_lookup))
    steps.append(EvaluateStateStep(PETITION_RULES))
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


def _build_rule_context_step(
    settings: Settings, previous_signature_lookup: PreviousSignatureLookup | None
) -> BuildRuleContextStep:
    media_check = None
    if settings.tavily_api_key:
        media_adapter = TavilyMediaCoverageAdapter(TavilyClient(settings.tavily_api_key))

        async def media_check(item):  # type: ignore[misc]
            result = await media_adapter.check_coverage(item["title"])
            return result.matched

    # signature_goal_lookup is NOT wired: it needs the petition's own stated
    # goal, which no source currently scrapes/extracts (WeAct/openpetition
    # search results don't include it, and Tavily's snippet doesn't reliably
    # contain it either). State A trigger #1 (near-goal) never fires until
    # that extraction exists; triggers #2 (Bundestag quorum) and #3
    # (momentum, via previous_signature_lookup below) work fully, as does
    # state C.
    return BuildRuleContextStep(
        media_check=media_check,
        previous_signature_lookup=previous_signature_lookup,
    )


async def run_petition_pipeline(
    deps: PipelineDeps,
    discard_sink: DiscardSink | None = None,
    previous_signature_lookup: PreviousSignatureLookup | None = None,
) -> list[ItemState]:
    """Runs Pipeline 2 end-to-end: fetch, prefilter, state determination,
    discard state D, classify."""
    steps = build_petition_steps(deps.settings, discard_sink, previous_signature_lookup)
    return await run_pipeline(steps, deps)
