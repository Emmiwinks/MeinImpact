"""Tests for the Mistral embeddings client."""

from __future__ import annotations

from types import TracebackType
from typing import ClassVar

import httpx
import pytest

from meinimpact.infrastructure.ai.embeddings import MistralEmbeddingClient


class _FakeResponse:
    def __init__(self, payload: dict[str, object], status: int = 200) -> None:
        self._payload = payload
        self.status_code = status

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise httpx.HTTPStatusError("boom", request=None, response=self)  # type: ignore[arg-type]

    def json(self) -> dict[str, object]:
        return self._payload


class _FakeAsyncClient:
    last_call: ClassVar[dict[str, object]] = {}

    def __init__(self, timeout: float) -> None:
        self.timeout = timeout

    async def __aenter__(self) -> _FakeAsyncClient:
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        del exc_type, exc, traceback

    async def post(
        self, url: str, headers: dict[str, str], json: dict[str, object]
    ) -> _FakeResponse:
        _FakeAsyncClient.last_call = {"url": url, "headers": headers, "json": json}
        return _FakeResponse(
            {"data": [{"embedding": [0.1, 0.2, 0.3], "index": 0}]}
        )


@pytest.mark.asyncio
async def test_embed_returns_vector_and_calls_correct_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(httpx, "AsyncClient", _FakeAsyncClient)
    client = MistralEmbeddingClient(
        api_key="secret", base_url="https://api.example.test/v1/", model="mistral-embed"
    )

    vector = await client.embed("Mietendeckel jetzt einführen")

    assert vector == [0.1, 0.2, 0.3]
    call = _FakeAsyncClient.last_call
    assert call["url"] == "https://api.example.test/v1/embeddings"
    assert call["headers"]["Authorization"] == "Bearer secret"
    assert call["json"]["model"] == "mistral-embed"
    assert call["json"]["input"] == ["Mietendeckel jetzt einführen"]


@pytest.mark.asyncio
async def test_embed_raises_on_http_error(monkeypatch: pytest.MonkeyPatch) -> None:
    class _FailingClient(_FakeAsyncClient):
        async def post(
            self, url: str, headers: dict[str, str], json: dict[str, object]
        ) -> _FakeResponse:
            return _FakeResponse({}, status=500)

    monkeypatch.setattr(httpx, "AsyncClient", _FailingClient)
    client = MistralEmbeddingClient(
        api_key="secret", base_url="https://api.example.test/v1", model="mistral-embed"
    )

    with pytest.raises(httpx.HTTPStatusError):
        await client.embed("some text")
