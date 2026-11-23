"""Beta feedback: POST /v1/feedback(/card), the store behind it, /admin/feedback."""

import uuid
from datetime import date
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.api.dependencies import get_feedback_repository
from meinimpact.api.routes import admin_portal
from meinimpact.core.config import Settings
from meinimpact.infrastructure.feedback.postgres_feedback_repository import (
    CardFeedback,
    CardNote,
    DismissedCard,
    Message,
    PostgresFeedbackRepository,
    ReasonCounts,
    StoredMessage,
)
from meinimpact.infrastructure.models import (
    BetaFeedbackRecord,
    CardFeedbackRecord,
    OpportunityRecord,
)
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
)
from meinimpact.main import create_app
from meinimpact.services.beta_feedback import pseudonym
from tests.listing_fakes import NOW, make_listing

_INSTALLATION = "00000000-0000-4000-8000-000000000001"
_CARD = uuid.UUID("11111111-1111-4111-8111-111111111111")
_RANKING = {
    "position": 2,
    "score": 1.4,
    "appeal": 0.6,
    "situation": 0.5,
    "interest": 0.1,
    "locality": 0.2,
    "werte": 0.5,
}


class FakeFeedback:
    def __init__(self) -> None:
        self.cards: list[CardFeedback] = []
        self.messages_added: list[Message] = []
        self.handled: list[tuple[uuid.UUID, bool]] = []
        self.commits = 0
        self.stored: list[StoredMessage] = []
        self.counts = ReasonCounts(by_reach={}, testers={})
        self.dismissed: list[DismissedCard] = []
        self.notes: list[CardNote] = []
        self.export: list[dict[str, Any]] = []

    async def add_card(self, feedback: CardFeedback) -> None:
        self.cards.append(feedback)

    async def add_message(self, message: Message) -> None:
        self.messages_added.append(message)

    async def commit(self) -> None:
        self.commits += 1

    async def reason_counts(self, since: date) -> ReasonCounts:
        return self.counts

    async def most_dismissed(self, since: date, limit: int) -> list[DismissedCard]:
        return self.dismissed

    async def card_notes(self, limit: int) -> list[CardNote]:
        return self.notes

    async def messages(self, limit: int) -> list[StoredMessage]:
        return self.stored

    async def set_handled(self, message_id: uuid.UUID, handled: bool) -> None:
        self.handled.append((message_id, handled))

    async def export_cards(self) -> list[dict[str, Any]]:
        return self.export


@pytest.fixture(autouse=True)
def _reset_throttle() -> None:
    admin_portal._failures.clear()


def _client(feedback: FakeFeedback) -> TestClient:
    app = create_app(Settings(jwt_secret="test-secret", admin_password="pw"))
    app.dependency_overrides[get_feedback_repository] = lambda: feedback
    return TestClient(app, follow_redirects=False)


def _auth(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/v1/auth/anonymous-session",
        json={"installation_id": _INSTALLATION, "app_version": "0.1.0"},
    )
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _card_body(**overrides: Any) -> dict[str, Any]:
    return {
        "opportunity_id": str(_CARD),
        "reason": "too_far",
        "ranking": _RANKING,
        "app_version": "0.3.0+12",
        **overrides,
    }


# --- tester name --------------------------------------------------------------


def test_pseudonym_is_stable_and_keyed() -> None:
    name = pseudonym(_INSTALLATION, "secret")
    assert name == pseudonym(_INSTALLATION, "secret")
    assert len(name) == 12
    assert _INSTALLATION not in name
    assert name != pseudonym(_INSTALLATION, "other-secret")
    assert name != pseudonym("00000000-0000-4000-8000-000000000002", "secret")


# --- POST /v1/feedback/card ---------------------------------------------------


def test_card_feedback_requires_a_session() -> None:
    response = _client(FakeFeedback()).post("/v1/feedback/card", json=_card_body())
    assert response.status_code == 401


def test_card_feedback_keeps_reason_ranking_and_pseudonym() -> None:
    feedback = FakeFeedback()
    client = _client(feedback)

    response = client.post(
        "/v1/feedback/card",
        json=_card_body(reason="dont_support", note="  Finde ich falsch.  "),
        headers=_auth(client),
    )

    assert response.status_code == 200
    [card] = feedback.cards
    assert card.tester == pseudonym(_INSTALLATION, "test-secret")
    assert card.opportunity_id == _CARD
    assert card.reason == "dont_support"
    assert card.note == "Finde ich falsch."
    assert card.ranking == {**_RANKING, "exploration": False}
    assert card.app_version == "0.3.0+12"
    assert feedback.commits == 1


def test_blank_note_is_kept_as_none() -> None:
    feedback = FakeFeedback()
    client = _client(feedback)
    client.post("/v1/feedback/card", json=_card_body(note="   "), headers=_auth(client))
    assert feedback.cards[0].note is None


@pytest.mark.parametrize(
    "overrides",
    [
        {"reason": "seh_ich_anders"},
        {"note": "x" * 501},
        # Anything beyond the score parts is refused, so no profile data
        # can slip in through the ranking
        {"ranking": {**_RANKING, "plz": "01067"}},
        {"ranking": {**_RANKING, "werte": 1.5}},
    ],
)
def test_invalid_card_feedback_is_rejected(overrides: dict[str, Any]) -> None:
    feedback = FakeFeedback()
    client = _client(feedback)

    response = client.post(
        "/v1/feedback/card", json=_card_body(**overrides), headers=_auth(client)
    )

    assert response.status_code == 422
    assert feedback.cards == []


# --- POST /v1/feedback --------------------------------------------------------


def test_message_is_kept() -> None:
    feedback = FakeFeedback()
    client = _client(feedback)

    response = client.post(
        "/v1/feedback",
        json={
            "kind": "bug",
            "message": "  Die Karte springt.\n",
            "screen": "hand",
            "app_version": "0.3.0",
            "platform": "android",
        },
        headers=_auth(client),
    )

    assert response.status_code == 200
    [message] = feedback.messages_added
    assert message.message == "Die Karte springt."
    assert (message.kind, message.screen, message.platform) == (
        "bug",
        "hand",
        "android",
    )
    assert message.tester == pseudonym(_INSTALLATION, "test-secret")


def test_blank_message_is_rejected() -> None:
    feedback = FakeFeedback()
    client = _client(feedback)
    response = client.post(
        "/v1/feedback",
        json={
            "kind": "idea",
            "message": "   ",
            "app_version": "0.3.0",
            "platform": "android",
        },
        headers=_auth(client),
    )
    assert response.status_code == 422
    assert feedback.messages_added == []


# --- /admin/feedback ----------------------------------------------------------


def _signed_in(feedback: FakeFeedback) -> TestClient:
    client = _client(feedback)
    assert client.post("/admin/login", data={"password": "pw"}).status_code == 303
    return client


def test_feedback_page_needs_session() -> None:
    client = _client(FakeFeedback())
    assert client.get("/admin/feedback").headers["location"] == "/admin/login"
    assert client.get("/admin/feedback.csv").headers["location"] == "/admin/login"
    message_id = uuid.uuid4()
    response = client.post(f"/admin/feedback/{message_id}/handled")
    assert response.headers["location"] == "/admin/login"


def test_feedback_page_shows_reasons_cards_notes_and_messages() -> None:
    feedback = FakeFeedback()
    feedback.counts = ReasonCounts(
        by_reach={"too_far": {"stadt": 3, None: 1}}, testers={"too_far": 2}
    )
    feedback.dismissed = [
        DismissedCard(
            opportunity_id=_CARD,
            title="Radweg <Elbe>",
            source_url="https://example.org/radweg",
            count=4,
            testers=3,
            reasons={"too_far": 3, "unclear_text": 1},
        )
    ]
    feedback.notes = [
        CardNote(
            day=date(2026, 11, 20),
            tester="abc123def456",
            reason="dont_support",
            note="Zu teuer",
            title="Radweg",
        )
    ]
    message_id = uuid.uuid4()
    feedback.stored = [
        StoredMessage(
            id=message_id,
            day=date(2026, 11, 21),
            tester="abc123def456",
            kind="idea",
            message="Dunkler Modus",
            screen="profil",
            app_version="0.3.0",
            platform="android",
            handled=False,
        )
    ]

    page = _signed_in(feedback).get("/admin/feedback").text

    assert "<th>Zu weit weg <span class=muted>(Ort-Ranking)</span></th>" in page
    # Gesamt, Tester, then Viertel, Ort, Stadt, Umland, ohne
    assert "<td>4</td><td>2</td><td>0</td><td>0</td><td>3</td><td>0</td><td>1</td>" in (
        page
    )
    assert "Radweg &lt;Elbe&gt;" in page
    assert "4 Mal, von 3 Testern · 3 Zu weit weg · 1 Text unklar oder falsch" in page
    assert "Zu teuer" in page
    assert "Dunkler Modus" in page
    assert f'action="/admin/feedback/{message_id}/handled"' in page


def test_handled_checkbox_saves() -> None:
    feedback = FakeFeedback()
    client = _signed_in(feedback)
    message_id = uuid.uuid4()

    response = client.post(
        f"/admin/feedback/{message_id}/handled", data={"handled": "on"}
    )
    client.post(f"/admin/feedback/{message_id}/handled", data={})

    assert response.headers["location"] == "/admin/feedback#nachrichten"
    assert feedback.handled == [(message_id, True), (message_id, False)]


def test_csv_export_flattens_lists() -> None:
    feedback = FakeFeedback()
    feedback.export = [
        {"day": "2026-11-20", "reason": "too_far", "lebenslagen": ["eltern", "rad"]},
        {"day": "2026-11-21", "reason": "other", "ranking_score": 0.4},
    ]

    response = _signed_in(feedback).get("/admin/feedback.csv")

    assert response.headers["content-type"].startswith("text/csv")
    lines = response.text.splitlines()
    assert lines[0] == "day,reason,lebenslagen,ranking_score"
    assert lines[1] == "2026-11-20,too_far,eltern;rad,"
    assert lines[2] == "2026-11-21,other,,0.4"


# --- Postgres store -----------------------------------------------------------


async def _empty_store(session: AsyncSession) -> PostgresFeedbackRepository:
    # Rolled back after the test like everything else in db_session
    await session.execute(delete(CardFeedbackRecord))
    await session.execute(delete(BetaFeedbackRecord))
    return PostgresFeedbackRepository(session)


async def _opportunity(session: AsyncSession) -> OpportunityRecord:
    await PostgresOpportunityRepository(session).sync(
        [make_listing("feedback-a")], complete_source_ids={"src"}, observed_at=NOW
    )
    result = await session.execute(
        select(OpportunityRecord).where(OpportunityRecord.external_id == "feedback-a")
    )
    record = result.scalar_one()
    record.title = "Radweg"
    record.reach = "stadt"
    record.enrichment_input_hash = "h1"
    return record


def _card(
    opportunity_id: uuid.UUID, tester: str, reason: str, *, day: date, note: str = ""
) -> CardFeedback:
    return CardFeedback(
        tester=tester,
        day=day,
        opportunity_id=opportunity_id,
        reason=reason,  # type: ignore[arg-type]
        note=note or None,
        ranking={"position": 1, "score": 0.5},
        app_version="0.3.0",
    )


async def test_store_counts_reasons_and_cards(db_session: AsyncSession) -> None:
    store = await _empty_store(db_session)
    card = await _opportunity(db_session)
    day = date(2026, 11, 20)

    await store.add_card(_card(card.id, "t1", "too_far", day=day))
    await store.add_card(_card(card.id, "t1", "too_far", day=day))
    await store.add_card(_card(card.id, "t2", "unclear_text", day=day, note="Wirr"))
    # A card that is gone by now still counts, without a link
    await store.add_card(_card(uuid.uuid4(), "t3", "too_far", day=day))
    await db_session.flush()

    counts = await store.reason_counts(date(2026, 11, 1))
    assert counts.by_reach == {
        "too_far": {"stadt": 2, None: 1},
        "unclear_text": {"stadt": 1},
    }
    assert counts.testers == {"too_far": 2, "unclear_text": 1}

    [dismissed] = await store.most_dismissed(date(2026, 11, 1), limit=20)
    assert (dismissed.title, dismissed.count, dismissed.testers) == ("Radweg", 3, 2)
    assert dismissed.reasons == {"too_far": 2, "unclear_text": 1}

    [note] = await store.card_notes(limit=10)
    assert (note.note, note.title) == ("Wirr", "Radweg")

    stored = (await db_session.scalars(select(CardFeedbackRecord))).all()
    assert {row.enrichment_input_hash for row in stored} == {"h1", None}

    rows = await store.export_cards()
    assert len(rows) == 4
    linked = next(row for row in rows if row["opportunity_id"] == str(card.id))
    assert linked["reach"] == "stadt"
    assert linked["ranking_score"] == 0.5


async def test_store_keeps_messages_open_first(db_session: AsyncSession) -> None:
    store = await _empty_store(db_session)
    for day, text in ((date(2026, 11, 20), "alt"), (date(2026, 11, 21), "neu")):
        await store.add_message(
            Message(
                tester="t1",
                day=day,
                kind="idea",
                message=text,
                screen=None,
                app_version="0.3.0",
                platform="android",
            )
        )
    await db_session.flush()
    [newest, oldest] = await store.messages(limit=10)
    await store.set_handled(newest.id, True)

    assert [m.message for m in await store.messages(limit=10)] == ["alt", "neu"]
    assert oldest.message == "alt"


async def test_store_prunes_old_days(db_session: AsyncSession) -> None:
    store = await _empty_store(db_session)
    card = await _opportunity(db_session)
    await store.add_card(_card(card.id, "t1", "other", day=date(2026, 5, 1)))
    await store.add_card(_card(card.id, "t1", "other", day=date(2026, 11, 1)))
    await db_session.flush()

    assert await store.prune(date(2026, 6, 1)) == 1
    remaining = (await db_session.scalars(select(CardFeedbackRecord))).all()
    assert [row.created_on for row in remaining] == [date(2026, 11, 1)]
