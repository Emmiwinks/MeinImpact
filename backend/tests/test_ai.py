"""AI adapter tests."""

import json
from collections.abc import AsyncIterator
from types import TracebackType

import httpx
import pytest

from meinimpact.infrastructure.ai.mistral_client import (
    MistralTextGenerator,
    parse_mistral_sse_line,
)


def test_parse_mistral_sse_line_extracts_delta() -> None:
    payload: dict[str, object] = {"choices": [{"delta": {"content": "Hello"}}]}
    line = "data: " + json.dumps(payload)
    assert parse_mistral_sse_line(line) == "Hello"


def test_parse_mistral_sse_line_ignores_done_and_non_data() -> None:
    assert parse_mistral_sse_line("data: [DONE]") is None
    assert parse_mistral_sse_line(": keep-alive") is None


def test_parse_mistral_sse_line_ignores_missing_content() -> None:
    payload: dict[str, object] = {"choices": [{"delta": {}}]}
    assert parse_mistral_sse_line("data: " + json.dumps(payload)) is None


@pytest.mark.asyncio
async def test_mistral_text_generator_streams_deltas(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(httpx, "AsyncClient", _FakeAsyncClient)
    generator = MistralTextGenerator(
        api_key="secret",
        base_url="https://api.example.test/v1/",
        model="model-name",
    )

    chunks = [chunk async for chunk in generator.stream_text("Draft this.")]

    assert chunks == ["Hello", " world"]


class _FakeAsyncClient:
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

    def stream(
        self,
        method: str,
        url: str,
        headers: dict[str, str],
        json: dict[str, object],
    ) -> _FakeStreamResponse:
        assert self.timeout == 30.0
        assert method == "POST"
        assert url == "https://api.example.test/v1/chat/completions"
        assert headers["Authorization"] == "Bearer secret"
        assert json["model"] == "model-name"
        assert json["stream"] is True
        return _FakeStreamResponse()


class _FakeStreamResponse:
    async def __aenter__(self) -> _FakeStreamResponse:
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        del exc_type, exc, traceback

    def raise_for_status(self) -> None:
        return None

    async def aiter_lines(self) -> AsyncIterator[str]:
        yield 'data: {"choices":[{"delta":{"content":"Hello"}}]}'
        yield 'data: {"choices":[{"delta":{"content":" world"}}]}'
        yield "data: [DONE]"
