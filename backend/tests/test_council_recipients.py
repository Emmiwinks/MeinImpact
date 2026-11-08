"""Letter recipients for council decisions: OParl member sync, the
recipient rules, the weekly sync gate, storage and the endpoint.

Person payloads are trimmed from the live Dresden endpoint (2026-11-08).
"""

import dataclasses
import uuid
from collections.abc import Collection, Mapping, Sequence
from datetime import UTC, date, datetime, timedelta
from typing import Any
from uuid import uuid4

import httpx
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.api.dependencies import (
    get_council_repository,
    get_opportunity_repository,
)
from meinimpact.core.config import Settings
from meinimpact.domain.entities import Opportunity
from meinimpact.infrastructure.council.oparl_members import (
    CouncilMember,
    fetch_council_members,
    members_of_person,
)
from meinimpact.infrastructure.council.postgres_council_repository import (
    PostgresCouncilRepository,
)
from meinimpact.infrastructure.listings.http import CrawlPolicy, PoliteHttpClient
from meinimpact.infrastructure.listings.sources.oparl import DRESDEN
from meinimpact.infrastructure.pipeline.ingestion import IngestionSummary
from meinimpact.main import create_app
from meinimpact.services.ingestion import sync_council_members
from meinimpact.services.recipients import Office, resolve_recipients
from tests.test_draft_service import DECISION

TODAY = date(2026, 11, 9)
_HTTP = "http://oparl.dresden.de/bodies/0001"
_ORG = "https://oparl.dresden.de/bodies/0001/organizations/gr"

NAMES = {
    f"{_ORG}/1": "Stadtrat",
    f"{_ORG}/157": "Ausschuss für Stadtentwicklung, Bau, Verkehr und Liegenschaften",
    f"{_ORG}/167": "Stadtbezirksbeirat Blasewitz",
    f"{_ORG}/120": "Fraktion Alternative für Deutschland",
    f"{_ORG}/30": "Fraktion Bündnis 90/Die Grünen",
    f"{_ORG}/198": "Fraktion Freie Wähler/Freie Bürger Dresden",
    f"{_ORG}/90": "Integrations- und Ausländerbeirat",
}


def _membership(org: str, **fields: Any) -> dict[str, Any]:
    return {"organization": f"{_HTTP}/organizations/gr/{org}", **fields}


def _person(number: int, name: str, *memberships: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": f"{_HTTP}/people/{number}",
        "name": name,
        "membership": list(memberships),
    }


SUSANNE = _person(
    1938,
    "Susanne Dagen",
    _membership("120", role="Mitglied", votingRight=True, startDate="2024-06-22"),
    _membership("1", role="Stadtrat", votingRight=True, startDate="2024-08-08"),
    _membership("157", role="Mitglied", votingRight=True, startDate="2024-08-23"),
    # Deputy seat: no voting right
    _membership("167", role="Stellvertretendes Mitglied", startDate="2023-04-06"),
    # Ended seat and ended Fraktion
    _membership("90", votingRight=True, startDate="2019-09-05", endDate="2022-09-20"),
    _membership("198", votingRight=True, startDate="2022-09-20", endDate="2024-08-07"),
)


def test_a_person_holds_current_voting_seats_with_their_fraktion() -> None:
    members = members_of_person(SUSANNE, NAMES, DRESDEN, TODAY)

    assert [m.organization_name for m in members] == [
        "Stadtrat",
        "Ausschuss für Stadtentwicklung, Bau, Verkehr und Liegenschaften",
    ]
    assert {m.fraktion_name for m in members} == {
        "Fraktion Alternative für Deutschland"
    }
    assert members[0].person_url == "https://oparl.dresden.de/bodies/0001/people/1938"


def test_the_latest_fraktion_wins_over_one_left_open() -> None:
    switched = _person(
        3,
        "Bernd Wechsel",
        # Ended in 2024, but OParl never closed the membership
        _membership("198", votingRight=True, startDate="2022-09-20"),
        _membership("120", votingRight=True, startDate="2024-08-12"),
        _membership("1", votingRight=True, startDate="2024-08-08"),
    )

    [member] = members_of_person(switched, NAMES, DRESDEN, TODAY)

    assert member.fraktion_name == "Fraktion Alternative für Deutschland"


def test_a_person_without_a_fraktion_still_counts() -> None:
    mayor = _person(
        7, "Dirk Hilbert", _membership("1", role="Vorsitz", votingRight=True)
    )

    [member] = members_of_person(mayor, NAMES, DRESDEN, TODAY)

    assert (member.fraktion_url, member.fraktion_name) == (None, None)


async def _no_sleep(_: float) -> None:
    return None


async def test_fetch_walks_organizations_and_people_pages() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        path, page = request.url.path, request.url.params.get("page")
        if path == "/robots.txt":
            return httpx.Response(404)
        if path.endswith("/organizations"):
            orgs = [
                {"id": url.replace("https", "http"), "name": n}
                for url, n in NAMES.items()
            ]
            return httpx.Response(200, json={"data": orgs, "links": {}})
        if path.endswith("/people") and not page:
            return httpx.Response(
                200,
                json={"data": [SUSANNE], "links": {"next": f"{_HTTP}/people?page=2"}},
            )
        if path.endswith("/people"):
            green = _person(
                5,
                "Agnes Scharnetzky",
                _membership("30", votingRight=True),
                _membership("157", votingRight=True),
            )
            return httpx.Response(200, json={"data": [green], "links": {}})
        return httpx.Response(404)

    http = PoliteHttpClient(
        policy=CrawlPolicy(default_delay_s=0),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        sleep=_no_sleep,
    )

    members = await fetch_council_members(http, DRESDEN, today=TODAY)

    committee = [m for m in members if m.organization_url == f"{_ORG}/157"]
    assert sorted(m.person_name for m in committee) == [
        "Agnes Scharnetzky",
        "Susanne Dagen",
    ]


def _member(
    name: str, fraktion: str | None, *, body: str = "Ausschuss für Bildung"
) -> CouncilMember:
    return CouncilMember(
        organization_url=f"https://x/{body}",
        organization_name=body,
        person_url=f"https://x/people/{name}",
        person_name=name,
        fraktion_url=f"https://x/{fraktion}" if fraktion else None,
        fraktion_name=fraktion,
    )


def test_one_office_per_fraktion_in_alphabetical_order() -> None:
    offices = {
        "https://x/SPD-Fraktion": "spd-fraktion@dresden.de",
        "https://x/CDU-Fraktion": "cdu-fraktion@dresden.de",
    }
    members = [
        _member("Zora Zander", "SPD-Fraktion"),
        _member("Anton Amsel", "CDU-Fraktion"),
        _member("Bea Berg", "SPD-Fraktion"),
        _member("Carl Neu", "Neue Fraktion"),
        _member("Dirk Ohne", None),
    ]

    recipients = resolve_recipients(members, offices)

    assert recipients.bodies == ["Ausschuss für Bildung"]
    assert [m.name for m in recipients.members] == [
        "Anton Amsel",
        "Bea Berg",
        "Carl Neu",
        "Dirk Ohne",
        "Zora Zander",
    ]
    assert recipients.offices == [
        Office("CDU-Fraktion", "cdu-fraktion@dresden.de"),
        # Known Fraktion, unknown address: shown, not silently dropped
        Office("Neue Fraktion", None),
        Office("SPD-Fraktion", "spd-fraktion@dresden.de"),
    ]


def test_a_renamed_fraktion_under_two_ids_gets_one_office() -> None:
    members = [_member("A", "BSW Fraktion"), _member("B", "Fraktion BSGWV")]
    offices = {
        "https://x/BSW Fraktion": "bsw-fraktion@dresden.de",
        "https://x/Fraktion BSGWV": "bsw-fraktion@dresden.de",
    }

    assert len(resolve_recipients(members, offices).offices) == 1


def test_district_councils_get_names_only() -> None:
    members = [_member("A", "SPD-Fraktion", body="Stadtbezirksbeirat Blasewitz")]

    recipients = resolve_recipients(
        members, {"https://x/SPD-Fraktion": "spd-fraktion@dresden.de"}
    )

    assert [m.name for m in recipients.members] == ["A"]
    assert recipients.offices == []


class FakeCouncilRepository:
    def __init__(
        self,
        last: datetime | None = None,
        members: Sequence[CouncilMember] = (),
    ) -> None:
        self.last = last
        self.members = list(members)
        self.replaced: list[CouncilMember] | None = None

    async def last_synced(self, source_id: str) -> datetime | None:
        return self.last

    async def replace(
        self, source_id: str, members: Sequence[CouncilMember], *, synced_at: datetime
    ) -> None:
        self.replaced = list(members)

    async def members_of(
        self, organization_urls: Collection[str]
    ) -> list[CouncilMember]:
        return [m for m in self.members if m.organization_url in organization_urls]


async def test_member_sync_runs_at_most_weekly() -> None:
    now = datetime(2026, 11, 9, tzinfo=UTC)
    repository = FakeCouncilRepository(last=now - timedelta(days=3))

    await sync_council_members(
        None,  # type: ignore[arg-type]  # never reached: the sync is fresh
        repository,  # type: ignore[arg-type]
        IngestionSummary(),
        now=now,
    )

    assert repository.replaced is None


async def test_member_sync_reports_fraktionen_without_an_office(
    monkeypatch: Any,
) -> None:
    members = [
        _member("A", "Neue Fraktion"),
        _member("B", None),
        # Left open in OParl, but only on a district council: not reported
        _member("C", "Alte Fraktion", body="Stadtbezirksbeirat Cotta"),
    ]

    async def fake_fetch(*_: Any, **__: Any) -> list[CouncilMember]:
        return members

    monkeypatch.setattr(
        "meinimpact.services.ingestion.fetch_council_members", fake_fetch
    )
    repository = FakeCouncilRepository()
    summary = IngestionSummary()

    await sync_council_members(
        None,  # type: ignore[arg-type]
        repository,  # type: ignore[arg-type]
        summary,
        now=datetime(2026, 11, 9, tzinfo=UTC),
    )

    assert repository.replaced == members
    assert summary.council_members == 3
    assert summary.errors == ["Fraktion ohne Büro-Adresse: Neue Fraktion"]


async def test_repository_replaces_members_per_source(db_session: AsyncSession) -> None:
    repository = PostgresCouncilRepository(db_session)
    first = datetime(2026, 11, 2, tzinfo=UTC)
    later = datetime(2026, 11, 9, tzinfo=UTC)

    await repository.replace("dresden", [_member("Alt", None)], synced_at=first)
    await repository.replace(
        "dresden",
        [_member("Neu", "SPD-Fraktion"), _member("Andere", None, body="Stadtrat")],
        synced_at=later,
    )

    assert await repository.last_synced("dresden") == later
    assert await repository.last_synced("leipzig") is None
    [member] = await repository.members_of(["https://x/Ausschuss für Bildung"])
    assert (member.person_name, member.fraktion_name) == ("Neu", "SPD-Fraktion")
    assert await repository.members_of([]) == []


# ── Endpoint ──────────────────────────────────────────────────────────────────

_COMMITTEE = f"{_ORG}/157"
_DECISION = dataclasses.replace(DECISION, recipient_bodies=(_COMMITTEE,))
_PETITION = dataclasses.replace(DECISION, id=uuid.UUID(int=8), kind="petition")


class FakeOpportunities:
    async def get(self, opportunity_id: uuid.UUID) -> Opportunity | None:
        return {o.id: o for o in (_DECISION, _PETITION)}.get(opportunity_id)


def _client(members: Sequence[CouncilMember]) -> TestClient:
    app = create_app(Settings(jwt_secret="test-secret"))
    app.dependency_overrides[get_opportunity_repository] = FakeOpportunities
    app.dependency_overrides[get_council_repository] = lambda: FakeCouncilRepository(
        members=members
    )
    return TestClient(app)


def _auth(client: TestClient) -> Mapping[str, str]:
    response = client.post(
        "/v1/auth/anonymous-session",
        json={"installation_id": str(uuid4()), "app_version": "0.1.0"},
    )
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_recipients_endpoint_returns_members_and_offices() -> None:
    green = dataclasses.replace(
        _member("Agnes Scharnetzky", "Fraktion Bündnis 90/Die Grünen"),
        organization_url=_COMMITTEE,
        fraktion_url=f"{_ORG}/30",
    )
    client = _client([green])

    response = client.get(
        f"/v1/opportunities/{_DECISION.id}/recipients", headers=_auth(client)
    )

    assert response.status_code == 200
    assert response.json() == {
        "bodies": ["Ausschuss für Bildung"],
        "members": [
            {"name": "Agnes Scharnetzky", "fraktion": "Fraktion Bündnis 90/Die Grünen"}
        ],
        "offices": [
            {
                "fraktion": "Fraktion Bündnis 90/Die Grünen",
                "email": "gruene-fraktion@dresden.de",
            }
        ],
    }


def test_recipients_endpoint_rejects_unknown_and_non_decisions() -> None:
    client = _client([])
    headers = _auth(client)

    unknown = client.get(
        f"/v1/opportunities/{uuid.UUID(int=99)}/recipients", headers=headers
    )
    petition = client.get(
        f"/v1/opportunities/{_PETITION.id}/recipients", headers=headers
    )

    assert unknown.status_code == 404
    assert petition.status_code == 400
