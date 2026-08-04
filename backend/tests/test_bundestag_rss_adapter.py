"""Tests for the Bundestag.de MdB RSS position-check adapter."""

from datetime import datetime
from unittest.mock import MagicMock, patch

from meinimpact.infrastructure.sources.bundestag_rss_adapter import (
    BundestagRssPositionAdapter,
)
from meinimpact.infrastructure.sources.protocol import MdbTarget
from tests.support.httpx_mock import make_mock_client, make_text_response

_SINCE = datetime(2026, 4, 1)


def _rss(*items: tuple[str, str, str]) -> str:
    entries = "".join(
        f"<item><title>{title}</title><link>{link}</link><pubDate>{pub_date}</pubDate></item>"
        for title, link, pub_date in items
    )
    return f"<?xml version='1.0'?><rss><channel>{entries}</channel></rss>"


async def test_found_true_when_recent_article_matches() -> None:
    xml = _rss(
        ("Müller zum Klimaschutz", "https://bundestag.de/a1", "Mon, 01 Jun 2026 10:00:00 +0200")
    )
    client = make_mock_client(get_side_effect=[make_text_response(xml)])
    with patch(
        "meinimpact.infrastructure.sources.bundestag_rss_adapter.datetime"
    ) as mock_dt, patch(
        "meinimpact.infrastructure.sources.bundestag_rss_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        mock_dt.now.return_value = datetime(2026, 6, 15)
        adapter = BundestagRssPositionAdapter()
        result = await adapter.check_position(
            MdbTarget(name="Sarah Müller", nachname="mueller", vorname="sarah"),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )
    assert result.found is True
    assert result.source == "bundestag_rss"
    assert result.source_url == "https://bundestag.de/a1"


async def test_found_false_when_article_older_than_60_days() -> None:
    xml = _rss(("Müller zum Klimaschutz", "https://bundestag.de/a1", "Mon, 01 Jan 2026 10:00:00 +0200"))
    client = make_mock_client(get_side_effect=[make_text_response(xml)])
    with patch(
        "meinimpact.infrastructure.sources.bundestag_rss_adapter.datetime"
    ) as mock_dt, patch(
        "meinimpact.infrastructure.sources.bundestag_rss_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        mock_dt.now.return_value = datetime(2026, 6, 15)
        adapter = BundestagRssPositionAdapter()
        result = await adapter.check_position(
            MdbTarget(name="Sarah Müller", nachname="mueller", vorname="sarah"),
            descriptors=["klimaschutz"],
            since=datetime(2026, 1, 1),
        )
    assert result.found is False


async def test_found_false_when_no_title_matches() -> None:
    xml = _rss(("Unrelated topic", "https://bundestag.de/a1", "Mon, 01 Jun 2026 10:00:00 +0200"))
    client = make_mock_client(get_side_effect=[make_text_response(xml)])
    with patch(
        "meinimpact.infrastructure.sources.bundestag_rss_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = BundestagRssPositionAdapter()
        result = await adapter.check_position(
            MdbTarget(name="Sarah Müller", nachname="mueller", vorname="sarah"),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )
    assert result.found is False


async def test_found_false_without_name_parts_falls_back() -> None:
    adapter = BundestagRssPositionAdapter()
    result = await adapter.check_position(
        MdbTarget(name="Sarah Müller"), descriptors=["klimaschutz"], since=_SINCE
    )
    assert result.found is False


async def test_request_uses_nachname_vorname_slug() -> None:
    captured: list[str] = []

    async def _capturing_get(url: str, **_: object) -> MagicMock:
        captured.append(url)
        return make_text_response(_rss())

    client = make_mock_client()
    client.get = _capturing_get
    with patch(
        "meinimpact.infrastructure.sources.bundestag_rss_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = BundestagRssPositionAdapter()
        await adapter.check_position(
            MdbTarget(name="Sarah Müller", nachname="mueller", vorname="sarah"),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )
    assert captured == [
        "https://www.bundestag.de/ajax/filterlist/de/abgeordnete/mueller-sarah/rss"
    ]
