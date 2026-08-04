"""Integration tests: pipeline persist stage against the real database.

These tests hit the live DB (inside Docker) and catch the class of bug where:
- A migration was written but not applied, OR
- The ORM model diverged from the actual schema.

If the `topics` column still exists with NOT NULL and no default, the first test
fails with NotNullViolationError — exactly the production error we want to catch
before it reaches production.
"""

from typing import cast

from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.pipeline.orchestrator import _persist
from meinimpact.infrastructure.pipeline.state_rules.protocol import StateTrace
from meinimpact.infrastructure.pipeline.step import ItemState
from meinimpact.infrastructure.pipeline.types import ClassifiedAction
from meinimpact.infrastructure.sources.protocol import RawSourceItem


def _classified(**overrides: object) -> ClassifiedAction:
    base: ClassifiedAction = {
        "external_id": "test-persist-schema-check",
        "title": "Test Gesetzentwurf für Schema-Integrationstests",
        "type": "gesetzentwurf",
        "status": "Ausschussberatung",
        "deadline": None,
        "source_url": "https://dip.bundestag.de/vorgang/test-persist-schema-check",
        "description": "Ein Antrag ausschließlich für automatisierte Tests.",
        "initiated_by": "Testfraktion",
        "source": "dip",
        "urgency": "mid",
        "werte_relevanz": {"wirtschaft": 0.3, "wandel": 0.5},
        "pro_argumente": ["Argument A"],
        "contra_argumente": ["Gegenargument A"],
        "action_types": ["representative_letter"],
        "is_controversial": False,
        "position_required": False,
    }
    base.update(overrides)  # type: ignore[typeddict-item]
    return base


def _item(
    *, state: str = "A", pipeline_source: str = "parliamentary", **overrides: object
) -> ItemState:
    classified = _classified(**overrides)
    trace = StateTrace(
        engagement_state=state,  # type: ignore[arg-type]
        state_reason="Abstimmung am 14. Juli",
        matched_rule="test",
        rules_checked=["test"],
        evidence={},
    )
    return ItemState(
        raw=classified,
        classified=classified,
        state_trace=trace,
        pipeline_source=pipeline_source,
    )


async def test_persist_inserts_row_without_schema_errors(
    db_session: AsyncSession,
) -> None:
    """Catches schema/migration drift.

    Fails if the DB schema doesn't match the ORM model — e.g. if a migration
    was written but not yet applied.
    """
    inserted = await _persist([_item()], db_session)
    assert inserted == 1


async def test_persist_skips_items_without_classification(db_session: AsyncSession) -> None:
    unclassified = ItemState(raw=cast(RawSourceItem, _classified()), classified=None)
    inserted = await _persist([unclassified], db_session)
    assert inserted == 0


async def test_persist_upserts_on_url_conflict(db_session: AsyncSession) -> None:
    url = "https://dip.bundestag.de/vorgang/upsert-conflict-test"
    await _persist([_item(source_url=url)], db_session)
    inserted = await _persist([_item(source_url=url, urgency="high")], db_session)
    assert inserted == 1


async def test_persist_stores_werte_relevanz(db_session: AsyncSession) -> None:
    werte = {"wirtschaft": 0.8, "diplomatie": 0.1, "freiheit": 0.5, "wandel": 0.9}
    await _persist([_item(werte_relevanz=werte)], db_session)
    # If werte_relevanz column is missing or wrong type, the insert raises here.


async def test_persist_stores_engagement_state_and_reason(db_session: AsyncSession) -> None:
    url = "https://dip.bundestag.de/vorgang/engagement-state-test"
    await _persist([_item(source_url=url, state="B")], db_session)
    # If engagement_state/state_reason columns are missing, the insert raises here.
