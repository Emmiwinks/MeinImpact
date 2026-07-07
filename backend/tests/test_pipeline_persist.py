"""Integration tests: pipeline persist stage against the real database.

These tests hit the live DB (inside Docker) and catch the class of bug where:
- A migration was written but not applied, OR
- The ORM model diverged from the actual schema.

If the `topics` column still exists with NOT NULL and no default, the first test
fails with NotNullViolationError — exactly the production error we want to catch
before it reaches production.
"""

from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.pipeline.orchestrator import _persist
from meinimpact.infrastructure.pipeline.types import ClassifiedAction


def _item(**overrides: object) -> ClassifiedAction:
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
        "imminence_score": 0.5,
        "urgency": "mid",
        "werte_relevanz": {"wirtschaft": 0.3, "wandel": 0.5},
        "pro_argumente": ["Argument A"],
        "contra_argumente": ["Gegenargument A"],
        "action_types": ["representative_letter"],
        "is_controversial": False,
        "position_required": False,
        "momentum_score": 0.5,
    }
    base.update(overrides)  # type: ignore[typeddict-item]
    return base


async def test_persist_inserts_row_without_schema_errors(
    db_session: AsyncSession,
) -> None:
    """Catches schema/migration drift.

    Fails if the DB schema doesn't match the ORM model — e.g. if a migration
    was written but not yet applied (topics NOT NULL without migration = failure).
    """
    inserted = await _persist([_item()], db_session)
    assert inserted == 1


async def test_persist_skips_none_items(db_session: AsyncSession) -> None:
    inserted = await _persist([None, None], db_session)
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
