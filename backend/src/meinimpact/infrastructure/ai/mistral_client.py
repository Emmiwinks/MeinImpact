"""Mistral AI streaming client."""

import json
from collections.abc import AsyncIterator
from typing import Any

import httpx


def parse_mistral_sse_line(line: str) -> str | None:
    """Extracts a text delta from one Mistral SSE line."""
    if not line.startswith("data: "):
        return None
    payload = line.removeprefix("data: ").strip()
    if payload == "[DONE]":
        return None
    data: dict[str, Any] = json.loads(payload)
    choices = data.get("choices", [])
    if not choices:
        return None
    delta = choices[0].get("delta", {})
    content = delta.get("content")
    if isinstance(content, str):
        return content
    return None


class MistralTextGenerator:
    """Streams draft text from the Mistral chat completion API."""

    def __init__(self, api_key: str, base_url: str, model: str) -> None:
        """Initializes the Mistral client."""
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._model = model

    async def stream_text(self, prompt: str) -> AsyncIterator[str]:
        """Streams text chunks from Mistral."""
        request = {
            "model": self._model,
            "stream": True,
            "temperature": 0.3,
            "safe_prompt": True,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You draft neutral civic participation text. Do not "
                        "invent facts, do not manipulate, and keep the user's "
                        "agency explicit."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
        }
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        }
        async with (
            httpx.AsyncClient(timeout=30.0) as client,
            client.stream(
                "POST",
                f"{self._base_url}/chat/completions",
                headers=headers,
                json=request,
            ) as response,
        ):
            response.raise_for_status()
            async for line in response.aiter_lines():
                delta = parse_mistral_sse_line(line)
                if delta is not None:
                    yield delta
