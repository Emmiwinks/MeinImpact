"""PoliteHttpClient: robots.txt (RFC 9309) and per-host request spacing."""

from collections.abc import Callable

import httpx
import pytest

from meinimpact.infrastructure.listings.http import (
    CrawlPolicy,
    PoliteHttpClient,
    RobotsDisallowedError,
)


class FakeTime:
    """Deterministic clock whose sleep advances time instead of waiting."""

    def __init__(self) -> None:
        self.now = 1000.0
        self.sleeps: list[float] = []

    def clock(self) -> float:
        return self.now

    async def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.now += seconds


def _client(
    handler: Callable[[httpx.Request], httpx.Response],
    time: FakeTime | None = None,
) -> tuple[PoliteHttpClient, list[httpx.Request]]:
    seen: list[httpx.Request] = []

    def record(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    time = time or FakeTime()
    client = PoliteHttpClient(
        policy=CrawlPolicy(user_agent="TestBot/1.0", default_delay_s=1.0),
        client=httpx.AsyncClient(transport=httpx.MockTransport(record)),
        sleep=time.sleep,
        clock=time.clock,
    )
    return client, seen


def _robots(body: str, status: int = 200) -> Callable[[httpx.Request], httpx.Response]:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(
                status, text=body, headers={"content-type": "text/plain"}
            )
        return httpx.Response(200, text="page")

    return handler


async def test_disallowed_path_is_never_requested() -> None:
    client, seen = _client(_robots("User-agent: *\nDisallow: /private/"))

    with pytest.raises(RobotsDisallowedError):
        await client.get("https://example.org/private/page")

    assert [r.url.path for r in seen] == ["/robots.txt"]


async def test_allowed_path_is_requested_with_policy_user_agent() -> None:
    client, seen = _client(_robots("User-agent: *\nDisallow: /private/"))

    response = await client.get("https://example.org/public")

    assert response.text == "page"
    assert seen[-1].headers["User-Agent"] == "TestBot/1.0"


async def test_missing_robots_allows_everything() -> None:
    client, _ = _client(_robots("", status=404))

    response = await client.get("https://example.org/anything")

    assert response.status_code == 200


async def test_unreachable_robots_disallows_everything() -> None:
    client, _ = _client(_robots("", status=503))

    with pytest.raises(RobotsDisallowedError):
        await client.get("https://example.org/anything")


async def test_html_answer_to_robots_is_treated_as_missing() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(
                200,
                text="<html>Disallow: /</html>",
                headers={"content-type": "text/html"},
            )
        return httpx.Response(200, text="page")

    client, _ = _client(handler)

    assert (await client.get("https://example.org/x")).status_code == 200


async def test_robots_is_fetched_once_per_host() -> None:
    client, seen = _client(_robots("User-agent: *\nAllow: /"))

    await client.get("https://example.org/a")
    await client.get("https://example.org/b")
    await client.get("https://other.org/c")

    robots_hosts = [r.url.host for r in seen if r.url.path == "/robots.txt"]
    assert robots_hosts == ["example.org", "other.org"]


async def test_requests_to_one_host_are_spaced_by_crawl_delay() -> None:
    time = FakeTime()
    client, _ = _client(_robots("User-agent: *\nCrawl-delay: 3"), time)

    await client.get("https://example.org/a")
    await client.get("https://example.org/b")

    # first wait: default delay after the robots fetch; second: crawl-delay
    assert time.sleeps == [1.0, 3.0]


async def test_crawl_delay_below_default_does_not_lower_it() -> None:
    time = FakeTime()
    client, _ = _client(_robots("User-agent: *\nCrawl-delay: 0"), time)

    await client.get("https://example.org/a")
    await client.get("https://example.org/b")

    assert time.sleeps == [1.0, 1.0]


async def test_http_errors_are_raised() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        return httpx.Response(500)

    client, _ = _client(handler)

    with pytest.raises(httpx.HTTPStatusError):
        await client.get("https://example.org/x")


async def test_post_form_sends_form_data_and_headers() -> None:
    client, seen = _client(_robots("", status=404))

    await client.post_form(
        "https://example.org/form", data={"a": "1"}, headers={"X-Test": "yes"}
    )

    request = seen[-1]
    assert request.method == "POST"
    assert request.content == b"a=1"
    assert request.headers["X-Test"] == "yes"


async def test_context_manager_closes_owned_client() -> None:
    async with PoliteHttpClient() as client:
        inner = client._client
    assert inner.is_closed
