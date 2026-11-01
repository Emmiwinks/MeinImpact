"""Structured (JSON-mode) completions from Mistral.

`JsonCompleter` is the seam: enrichment depends on the protocol, tests on a
fake, production on `MistralJsonCompleter`.
"""

import asyncio
import json
from collections.abc import Awaitable, Callable
from typing import Any, Protocol

import httpx

Sleep = Callable[[float], Awaitable[None]]

_RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 504})


class JsonCompleter(Protocol):
    async def complete_json(self, prompt: str) -> dict[str, Any]:
        """Returns the model's JSON object; raises if there is none."""
        ...


class MistralJsonCompleter:
    """Mistral chat completions in JSON mode, retrying rate limits and
    transient server errors with exponential backoff."""

    def __init__(
        self,
        *,
        api_key: str,
        base_url: str,
        model: str,
        max_tokens: int = 1200,
        attempts: int = 4,
        client: httpx.AsyncClient | None = None,
        sleep: Sleep = asyncio.sleep,
    ) -> None:
        self._url = f"{base_url.rstrip('/')}/chat/completions"
        self._headers = {"Authorization": f"Bearer {api_key}"}
        self._model = model
        self._max_tokens = max_tokens
        self._attempts = attempts
        self._client = client or httpx.AsyncClient(timeout=60.0)
        self._sleep = sleep

    async def aclose(self) -> None:
        await self._client.aclose()

    async def complete_json(self, prompt: str) -> dict[str, Any]:
        body = {
            "model": self._model,
            "temperature": 0.1,
            "max_tokens": self._max_tokens,
            "response_format": {"type": "json_object"},
            "messages": [{"role": "user", "content": prompt}],
        }
        response = await self._post_with_retry(body)
        content = response.json()["choices"][0]["message"]["content"]
        parsed = json.loads(content)
        if not isinstance(parsed, dict):
            raise ValueError(f"expected a JSON object, got {type(parsed).__name__}")
        return parsed

    async def _post_with_retry(self, body: dict[str, Any]) -> httpx.Response:
        for attempt in range(self._attempts):
            response = await self._client.post(
                self._url, headers=self._headers, json=body
            )
            last_attempt = attempt == self._attempts - 1
            if response.status_code not in _RETRYABLE_STATUS or last_attempt:
                response.raise_for_status()
                return response
            await self._sleep(2.0**attempt)
        raise AssertionError("unreachable")  # pragma: no cover
