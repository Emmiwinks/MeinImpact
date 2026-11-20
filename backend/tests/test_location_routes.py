"""POST /v1/location: a PLZ's Kreis, point and members of the Bundestag."""

import logging
from uuid import uuid4

from fastapi.testclient import TestClient

from meinimpact.api.dependencies import get_plz_index
from meinimpact.core.config import Settings
from meinimpact.infrastructure.geo.plz import PlzIndex, PlzLocation, Point
from meinimpact.infrastructure.mdb.wks_service import MdbInfo, WksService
from meinimpact.main import create_app

_MDB = MdbInfo(
    wahlkreis_nr=154,
    wahlkreis_name="Meißen",
    mdb_name="Test Person",
    mdb_party="Test Partei",
    mdb_link=None,
)


def _client(*, wks_healthy: bool = True) -> TestClient:
    app = create_app(Settings(jwt_secret="test-secret"))
    app.dependency_overrides[get_plz_index] = lambda: PlzIndex(
        {"01689": PlzLocation("14627", Point(51.144, 13.5707))}
    )
    wks = WksService()
    if wks_healthy:
        wks._index = {"01689": [_MDB]}
    else:
        wks._load_error = "HTTP 404"
    app.state.wks_service = wks
    return TestClient(app)


def _auth(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/v1/auth/anonymous-session",
        json={"installation_id": str(uuid4()), "app_version": "0.1.0"},
    )
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_location_requires_a_session() -> None:
    response = _client().post("/v1/location", json={"plz": "01689"})
    assert response.status_code == 401


def test_location_returns_kreis_point_and_wahlkreise() -> None:
    client = _client()

    response = client.post("/v1/location", json={"plz": "01689"}, headers=_auth(client))

    assert response.status_code == 200
    assert response.json() == {
        "kreis": "14627",
        "lat": 51.144,
        "lon": 13.5707,
        "wahlkreise": [
            {
                "wahlkreis_nr": 154,
                "wahlkreis_name": "Meißen",
                "mdb_name": "Test Person",
                "mdb_party": "Test Partei",
                "mdb_link": None,
            }
        ],
        # Landkreis Meißen: Saxony's topics, none of its own yet.
        "coverage": "land",
    }


def test_location_without_bundestag_data_still_locates() -> None:
    client = _client(wks_healthy=False)

    response = client.post("/v1/location", json={"plz": "01689"}, headers=_auth(client))

    assert response.status_code == 200
    assert (response.json()["kreis"], response.json()["wahlkreise"]) == ("14627", [])


def test_location_unknown_plz_is_404_and_malformed_is_422() -> None:
    client = _client()
    headers = _auth(client)

    assert (
        client.post("/v1/location", json={"plz": "99999"}, headers=headers).status_code
        == 404
    )
    assert (
        client.post("/v1/location", json={"plz": "1234"}, headers=headers).status_code
        == 422
    )


def test_access_log_skips_the_old_mdb_lookup_with_its_plz() -> None:
    create_app(Settings(jwt_secret="test-secret"))
    access = logging.getLogger("uvicorn.access")
    record = access.makeRecord(
        "uvicorn.access",
        logging.INFO,
        __file__,
        0,
        '%s - "%s %s HTTP/%s" %d',
        ("10.0.0.1:5000", "GET", "/v1/mdb?plz=01689", "1.1", 200),
        None,
    )

    assert not access.filter(record)
