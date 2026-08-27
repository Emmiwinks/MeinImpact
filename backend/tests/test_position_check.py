"""Tests for the MdB-position-check composition (mdb/position_check.py)."""

from dataclasses import dataclass
from datetime import datetime

from meinimpact.infrastructure.mdb.position_check import check_mdb_position
from meinimpact.infrastructure.sources.protocol import MdbTarget, PositionCheckResult

_MDB = MdbTarget(
    name="Sarah Müller",
    aw_politician_id=1,
    dip_person_id="2",
    nachname="mueller",
    vorname="sarah",
)
_SINCE = datetime(2026, 4, 1)


_Call = tuple[MdbTarget, list[str], datetime]


@dataclass(frozen=True)
class _FakeAdapter:
    result: PositionCheckResult
    calls: list[_Call]

    async def check_position(
        self, mdb: MdbTarget, descriptors: list[str], since: datetime
    ) -> PositionCheckResult:
        self.calls.append((mdb, descriptors, since))
        return self.result


async def test_found_true_when_any_adapter_finds_a_match() -> None:
    calls_a: list[_Call] = []
    calls_b: list[_Call] = []
    adapters = [
        _FakeAdapter(
            PositionCheckResult(found=False, source="abgeordnetenwatch"), calls_a
        ),
        _FakeAdapter(
            PositionCheckResult(found=True, source="dip_reden", statement_summary="x"),
            calls_b,
        ),
    ]
    result = await check_mdb_position(_MDB, ["klimaschutz"], _SINCE, adapters)
    assert result.found is True
    assert result.matched_source is not None
    assert result.matched_source.source == "dip_reden"


async def test_found_false_when_all_adapters_find_nothing() -> None:
    adapters = [
        _FakeAdapter(PositionCheckResult(found=False, source="abgeordnetenwatch"), []),
        _FakeAdapter(PositionCheckResult(found=False, source="dip_reden"), []),
        _FakeAdapter(PositionCheckResult(found=False, source="bundestag_rss"), []),
    ]
    result = await check_mdb_position(_MDB, ["klimaschutz"], _SINCE, adapters)
    assert result.found is False
    assert result.matched_source is None


async def test_all_adapters_are_invoked() -> None:
    calls_a: list[_Call] = []
    calls_b: list[_Call] = []
    calls_c: list[_Call] = []
    adapters = [
        _FakeAdapter(PositionCheckResult(found=False, source="a"), calls_a),
        _FakeAdapter(PositionCheckResult(found=False, source="b"), calls_b),
        _FakeAdapter(PositionCheckResult(found=False, source="c"), calls_c),
    ]
    await check_mdb_position(_MDB, ["klimaschutz"], _SINCE, adapters)
    assert len(calls_a) == 1
    assert len(calls_b) == 1
    assert len(calls_c) == 1


async def test_matches_tuple_preserves_all_results_in_order() -> None:
    adapters = [
        _FakeAdapter(PositionCheckResult(found=False, source="a"), []),
        _FakeAdapter(PositionCheckResult(found=True, source="b"), []),
    ]
    result = await check_mdb_position(_MDB, ["klimaschutz"], _SINCE, adapters)
    assert [m.source for m in result.matches] == ["a", "b"]


async def test_empty_adapter_list_returns_not_found() -> None:
    result = await check_mdb_position(_MDB, ["klimaschutz"], _SINCE, [])
    assert result.found is False
    assert result.matches == ()
