"""MistralJsonCompleter: JSON mode, retries on rate limits and 5xx."""

import json
from collections.abc import Callable

import httpx
import pytest

from meinimpact.infrastructure.ai.mistral_json import MistralJsonCompleter


def _completion(content: str) -> httpx.Response:
    return httpx.Response(200, json={"choices": [{"message": {"content": content}}]})


def _completer(
    responses: list[httpx.Response], sleeps: list[float]
) -> tuple[MistralJsonCompleter, list[httpx.Request]]:
    requests: list[httpx.Request] = []
    queue = iter(responses)

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return next(queue)

    async def sleep(seconds: float) -> None:
        sleeps.append(seconds)

    completer = MistralJsonCompleter(
        api_key="key",
        base_url="https://api.example/v1/",
        model="mistral-medium-latest",
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        sleep=sleep,
    )
    return completer, requests


async def test_returns_the_json_object_and_requests_json_mode() -> None:
    completer, requests = _completer([_completion('{"ok": true}')], [])

    result = await completer.complete_json("prompt")

    assert result == {"ok": True}
    request = requests[0]
    assert str(request.url) == "https://api.example/v1/chat/completions"
    assert request.headers["Authorization"] == "Bearer key"
    body = json.loads(request.content)
    assert body["response_format"] == {"type": "json_object"}
    assert body["messages"] == [{"role": "user", "content": "prompt"}]


async def test_retries_rate_limits_with_backoff() -> None:
    sleeps: list[float] = []
    completer, requests = _completer(
        [httpx.Response(429), httpx.Response(503), _completion("{}")], sleeps
    )

    assert await completer.complete_json("p") == {}
    assert len(requests) == 3
    assert sleeps == [1.0, 2.0]


@pytest.mark.parametrize(
    "responses",
    [
        lambda: [httpx.Response(400)],
        lambda: [httpx.Response(503)] * 4,
    ],
)
async def test_gives_up_on_client_errors_and_after_all_attempts(
    responses: Callable[[], list[httpx.Response]],
) -> None:
    completer, _ = _completer(responses(), [])

    with pytest.raises(httpx.HTTPStatusError):
        await completer.complete_json("p")


async def test_non_object_json_is_rejected() -> None:
    completer, _ = _completer([_completion("[1, 2]")], [])

    with pytest.raises(ValueError, match="JSON object"):
        await completer.complete_json("p")
