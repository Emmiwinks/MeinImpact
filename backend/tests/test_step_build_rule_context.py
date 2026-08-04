"""Tests for BuildRuleContextStep — fake check callables, no real I/O."""

from datetime import date
from uuid import uuid4

from meinimpact.infrastructure.pipeline.state_rules.protocol import RuleContext
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.pipeline.steps.build_rule_context import BuildRuleContextStep
from meinimpact.infrastructure.sources.protocol import RawSourceItem


def _deps() -> PipelineDeps:
    return PipelineDeps(settings=None, run_id=uuid4(), errors=[])  # type: ignore[arg-type]


def _ctx(item: ItemState) -> RuleContext:
    assert item.rule_context is not None
    return item.rule_context


def _item(external_id: str = "1") -> ItemState:
    return ItemState(
        raw={
            "external_id": external_id,
            "title": "Entwurf eines Gesetzes",
            "type": "antrag",
            "status": "Ausschussberatung",
            "deadline": None,
            "source_url": f"https://example.com/{external_id}",
            "description": "...",
            "initiated_by": "CDU/CSU",
            "source": "dip",
        }
    )


async def test_attaches_rule_context_to_every_item() -> None:
    step = BuildRuleContextStep()
    items = [_item("1"), _item("2")]
    result = await step.process(items, _deps())
    assert all(i.rule_context is not None for i in result)


async def test_defaults_are_false_none_when_no_checks_configured() -> None:
    step = BuildRuleContextStep()
    result = await step.process([_item()], _deps())
    ctx = _ctx(result[0])
    assert ctx.vote_date is None
    assert ctx.committee_recently_active is False
    assert ctx.has_vote_result is False
    assert ctx.stellungnahme_fraktion_count is None
    assert ctx.media_coverage_matched is False
    assert ctx.previous_signature_count is None
    assert ctx.signature_goal is None


async def test_uses_configured_committee_check() -> None:
    async def committee_check(item: RawSourceItem) -> bool:
        return True

    step = BuildRuleContextStep(committee_check=committee_check)
    result = await step.process([_item()], _deps())
    assert _ctx(result[0]).committee_recently_active is True


async def test_uses_configured_vote_result_lookup() -> None:
    step = BuildRuleContextStep(vote_result_lookup=lambda item: True)
    result = await step.process([_item()], _deps())
    assert _ctx(result[0]).has_vote_result is True


async def test_uses_configured_fraktion_stellungnahme_lookup() -> None:
    step = BuildRuleContextStep(fraktion_stellungnahme_lookup=lambda item: 1)
    result = await step.process([_item()], _deps())
    assert _ctx(result[0]).stellungnahme_fraktion_count == 1


async def test_uses_configured_media_check() -> None:
    async def media_check(item: RawSourceItem) -> bool:
        return True

    step = BuildRuleContextStep(media_check=media_check)
    result = await step.process([_item()], _deps())
    assert _ctx(result[0]).media_coverage_matched is True


async def test_uses_configured_vote_date_lookup() -> None:
    step = BuildRuleContextStep(vote_date_lookup=lambda item: date(2026, 7, 1))
    result = await step.process([_item()], _deps())
    assert _ctx(result[0]).vote_date == date(2026, 7, 1)


async def test_uses_configured_signature_lookups() -> None:
    step = BuildRuleContextStep(
        signature_goal_lookup=lambda item: 10_000,
        previous_signature_lookup=lambda item: 3_500,
    )
    result = await step.process([_item()], _deps())
    ctx = _ctx(result[0])
    assert ctx.signature_goal == 10_000
    assert ctx.previous_signature_count == 3_500


async def test_checks_run_per_item_independently() -> None:
    calls: list[str] = []

    async def committee_check(item: RawSourceItem) -> bool:
        calls.append(item["external_id"])
        return item["external_id"] == "1"

    step = BuildRuleContextStep(committee_check=committee_check)
    result = await step.process([_item("1"), _item("2")], _deps())
    assert sorted(calls) == ["1", "2"]
    by_id = {i.raw["external_id"]: _ctx(i).committee_recently_active for i in result}
    assert by_id == {"1": True, "2": False}
