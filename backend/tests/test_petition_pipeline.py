"""Wiring tests for build_petition_steps — asserts step types/order,
not step logic (already covered by each step's own test file)."""

from types import SimpleNamespace

from meinimpact.infrastructure.pipeline.petition_pipeline import build_petition_steps
from meinimpact.infrastructure.pipeline.steps.build_rule_context import (
    BuildRuleContextStep,
)
from meinimpact.infrastructure.pipeline.steps.classify import ClassifyStep
from meinimpact.infrastructure.pipeline.steps.evaluate_state import EvaluateStateStep
from meinimpact.infrastructure.pipeline.steps.fetch import FetchStep
from meinimpact.infrastructure.pipeline.steps.filter_state_d import FilterStateDStep
from meinimpact.infrastructure.pipeline.steps.prefilter import PrefilterStep
from meinimpact.infrastructure.pipeline.steps.trace_discards import TraceDiscardsStep


def _settings(**overrides: object) -> SimpleNamespace:
    defaults: dict[str, object] = {
        "dip_api_key": "dip-key",
        "tavily_api_key": "tavily-key",
        "mistral_api_key": "mistral-key",
        "mistral_base_url": "https://api.mistral.ai/v1",
        "mistral_model": "mistral-small-latest",
        "google_cse_key": "cse-key",
        "google_cse_id": "cse-id",
    }
    defaults.update(overrides)
    return SimpleNamespace(**defaults)


def test_full_settings_produce_two_fetch_steps_and_expected_order() -> None:
    steps = build_petition_steps(_settings())  # type: ignore[arg-type]
    assert [type(s) for s in steps] == [
        FetchStep,
        FetchStep,
        PrefilterStep,
        BuildRuleContextStep,
        EvaluateStateStep,
        TraceDiscardsStep,
        FilterStateDStep,
        ClassifyStep,
    ]
    fetch_names = [s.name for s in steps if isinstance(s, FetchStep)]
    assert fetch_names == ["fetch_dip_petitions", "fetch_civil_petitions"]


def test_missing_dip_key_omits_dip_fetch_step_only() -> None:
    steps = build_petition_steps(_settings(dip_api_key=None))  # type: ignore[arg-type]
    fetch_names = [s.name for s in steps if isinstance(s, FetchStep)]
    assert fetch_names == ["fetch_civil_petitions"]


def test_missing_tavily_key_omits_civil_petition_fetch_step() -> None:
    steps = build_petition_steps(_settings(tavily_api_key=None))  # type: ignore[arg-type]
    fetch_names = [s.name for s in steps if isinstance(s, FetchStep)]
    assert fetch_names == ["fetch_dip_petitions"]


def test_missing_google_cse_config_still_builds_civil_petition_step() -> None:
    steps = build_petition_steps(_settings(google_cse_key=None, google_cse_id=None))  # type: ignore[arg-type]
    fetch_names = [s.name for s in steps if isinstance(s, FetchStep)]
    assert "fetch_civil_petitions" in fetch_names


def test_missing_mistral_key_omits_classify_step() -> None:
    steps = build_petition_steps(_settings(mistral_api_key=None))  # type: ignore[arg-type]
    assert ClassifyStep not in [type(s) for s in steps]


def test_evaluate_state_step_uses_petition_rules() -> None:
    from meinimpact.infrastructure.pipeline.state_rules.petition_rules import RULES

    steps = build_petition_steps(_settings())  # type: ignore[arg-type]
    evaluate_step = next(s for s in steps if isinstance(s, EvaluateStateStep))
    assert evaluate_step._rules is RULES
