"""POST /v1/letters/stream."""

import dataclasses
import uuid
from collections.abc import AsyncIterator
from datetime import date
from uuid import uuid4

from fastapi.testclient import TestClient

from meinimpact.api.dependencies import get_ai_generator, get_opportunity_repository
from meinimpact.core.config import Settings
from meinimpact.domain.entities import Opportunity
from meinimpact.main import create_app
from tests.test_draft_service import DECISION

PETITION = dataclasses.replace(DECISION, id=uuid.UUID(int=8), kind="petition")


class FakeRepository:
    async def list_open(self, today: date) -> list[Opportunity]:
        return [DECISION, PETITION]

    async def get(self, opportunity_id: uuid.UUID) -> Opportunity | None:
        return {o.id: o for o in (DECISION, PETITION)}.get(opportunity_id)


class RecordingGenerator:
    def __init__(self) -> None:
        self.prompts: list[str] = []

    async def stream_text(self, prompt: str) -> AsyncIterator[str]:
        self.prompts.append(prompt)
        for token in ("Sehr geehrte", " Damen und Herren,\n", "Gruß"):
            yield token


def _client(generator: RecordingGenerator) -> TestClient:
    app = create_app(Settings(jwt_secret="test-secret"))
    app.dependency_overrides[get_opportunity_repository] = FakeRepository
    app.dependency_overrides[get_ai_generator] = lambda: generator
    return TestClient(app)


def _auth(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/v1/auth/anonymous-session",
        json={"installation_id": str(uuid4()), "app_version": "0.1.0"},
    )
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_streams_a_letter_with_the_users_notes() -> None:
    generator = RecordingGenerator()
    client = _client(generator)

    with client.stream(
        "POST",
        "/v1/letters/stream",
        headers=_auth(client),
        json={"opportunity_id": str(DECISION.id), "notes": "Bitte dafür stimmen."},
    ) as response:
        assert response.status_code == 200
        body = response.read().decode()

    assert "data: Sehr geehrte" in body
    assert body.rstrip().endswith("data: [DONE]")
    [prompt] = generator.prompts
    assert "Bitte dafür stimmen." in prompt


def test_unknown_opportunity_is_404() -> None:
    client = _client(RecordingGenerator())
    response = client.post(
        "/v1/letters/stream",
        headers=_auth(client),
        json={"opportunity_id": str(uuid.UUID(int=99))},
    )
    assert response.status_code == 404


def test_letters_are_only_for_decisions() -> None:
    client = _client(RecordingGenerator())
    response = client.post(
        "/v1/letters/stream",
        headers=_auth(client),
        json={"opportunity_id": str(PETITION.id)},
    )
    assert response.status_code == 400


def test_notes_are_capped_at_1000_characters() -> None:
    client = _client(RecordingGenerator())
    response = client.post(
        "/v1/letters/stream",
        headers=_auth(client),
        json={"opportunity_id": str(DECISION.id), "notes": "x" * 1001},
    )
    assert response.status_code == 422
