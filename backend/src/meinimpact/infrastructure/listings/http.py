"""HTTP client that every listing source must go through.

Crawling rules live here, once, instead of in each source:
- robots.txt is honoured per RFC 9309: a 4xx robots.txt allows everything,
  an unreachable or 5xx one disallows everything.
- Requests to the same host are serialized and spaced by the host's
  Crawl-delay (or a default), so concurrent sources on one host stay polite.
- One honest User-Agent for all requests.
- A GET that fails on the connection (dropped, timed out) is retried a few
  times with growing pauses; long walks over slow servers (OParl: ~200
  requests) otherwise fail on a single hiccup. Error statuses are answers,
  not hiccups, and are never retried.
"""

import asyncio
import time
from collections.abc import Awaitable, Callable, Mapping
from dataclasses import dataclass
from types import TracebackType
from typing import Self
from urllib.parse import urlsplit
from urllib.robotparser import RobotFileParser

import httpx

Sleep = Callable[[float], Awaitable[None]]
Clock = Callable[[], float]


class RobotsDisallowedError(Exception):
    """Raised instead of requesting a URL that robots.txt disallows."""


@dataclass(frozen=True, slots=True)
class CrawlPolicy:
    user_agent: str = "MeinImpactBot/0.1 (civic participation index)"
    default_delay_s: float = 1.0
    timeout_s: float = 30.0
    get_retries: int = 2
    retry_backoff_s: float = 10.0


@dataclass(slots=True)
class _HostState:
    robots: RobotFileParser
    delay_s: float
    lock: asyncio.Lock
    next_allowed_at: float = 0.0


class PoliteHttpClient:
    """Async HTTP client enforcing robots.txt and per-host request spacing.

    Keeps cookies across requests (some registries need a session), so one
    instance should be shared by all sources of a run.
    """

    def __init__(
        self,
        *,
        policy: CrawlPolicy | None = None,
        client: httpx.AsyncClient | None = None,
        sleep: Sleep = asyncio.sleep,
        clock: Clock = time.monotonic,
    ) -> None:
        self._policy = policy or CrawlPolicy()
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            timeout=self._policy.timeout_s, follow_redirects=True
        )
        self._client.headers["User-Agent"] = self._policy.user_agent
        self._sleep = sleep
        self._clock = clock
        self._hosts: dict[str, _HostState] = {}
        self._hosts_lock = asyncio.Lock()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        await self.aclose()

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def get(
        self, url: str, *, params: Mapping[str, str | int] | None = None
    ) -> httpx.Response:
        return await self._request("GET", url, params=params)

    async def post_form(
        self,
        url: str,
        *,
        data: Mapping[str, str],
        headers: Mapping[str, str] | None = None,
    ) -> httpx.Response:
        return await self._request("POST", url, data=data, headers=headers)

    async def _request(
        self,
        method: str,
        url: str,
        *,
        params: Mapping[str, str | int] | None = None,
        data: Mapping[str, str] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> httpx.Response:
        host = await self._host_state(url)
        if not host.robots.can_fetch(self._policy.user_agent, url):
            raise RobotsDisallowedError(f"robots.txt disallows {url}")
        retries = self._policy.get_retries if method == "GET" else 0
        async with host.lock:
            for attempt in range(retries + 1):
                await self._wait_turn(host)
                try:
                    response = await self._client.request(
                        method, url, params=params, data=data, headers=headers
                    )
                    break
                except httpx.TransportError:
                    if attempt == retries:
                        raise
                    host.next_allowed_at = (
                        self._clock() + self._policy.retry_backoff_s * (attempt + 1)
                    )
                    continue
                finally:
                    host.next_allowed_at = max(
                        host.next_allowed_at, self._clock() + host.delay_s
                    )
        response.raise_for_status()
        return response

    async def _wait_turn(self, host: _HostState) -> None:
        wait_s = host.next_allowed_at - self._clock()
        if wait_s > 0:
            await self._sleep(wait_s)

    async def _host_state(self, url: str) -> _HostState:
        parts = urlsplit(url)
        origin = f"{parts.scheme}://{parts.netloc}"
        async with self._hosts_lock:
            if origin not in self._hosts:
                robots = await self._load_robots(origin)
                delay = robots.crawl_delay(self._policy.user_agent)
                self._hosts[origin] = _HostState(
                    robots=robots,
                    delay_s=max(float(delay or 0), self._policy.default_delay_s),
                    lock=asyncio.Lock(),
                    next_allowed_at=self._clock() + self._policy.default_delay_s,
                )
            return self._hosts[origin]

    async def _load_robots(self, origin: str) -> RobotFileParser:
        try:
            response = await self._client.get(f"{origin}/robots.txt")
        except httpx.HTTPError:
            return _robots(_DISALLOW_ALL)
        if response.status_code >= 500:
            return _robots(_DISALLOW_ALL)
        if response.status_code >= 400 or not _is_plain_text(response):
            return _robots(_ALLOW_ALL)
        return _robots(response.text.splitlines())


_ALLOW_ALL: list[str] = []
_DISALLOW_ALL = ["User-agent: *", "Disallow: /"]


def _robots(lines: list[str]) -> RobotFileParser:
    robots = RobotFileParser()
    robots.parse(lines)
    return robots


def _is_plain_text(response: httpx.Response) -> bool:
    """Some servers answer /robots.txt with an HTML error page and status 200."""
    content_type = str(response.headers.get("content-type", "text/plain"))
    return content_type.startswith("text/plain")
