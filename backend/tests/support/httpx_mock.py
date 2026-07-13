"""Shared httpx-mocking helpers for source-adapter tests.

Extracted from test_dip_adapter.py's original copy-pasted boilerplate once
enough adapters needed the same "mock an AsyncClient, capture/assert the
outgoing request" pattern (see the architecture plan, section 5).
"""

from unittest.mock import AsyncMock, MagicMock

import httpx


def make_json_response(json_body: object, status: int = 200) -> MagicMock:
    """Builds a fake httpx.Response returning `json_body` from `.json()`."""
    resp = MagicMock()
    resp.status_code = status
    resp.json = MagicMock(return_value=json_body)
    resp.raise_for_status = MagicMock()
    if status >= 400:
        resp.raise_for_status.side_effect = httpx.HTTPStatusError(
            f"HTTP {status}", request=MagicMock(), response=resp
        )
    return resp


def make_text_response(text: str, status: int = 200) -> MagicMock:
    """Builds a fake httpx.Response returning `text` from `.text`."""
    resp = MagicMock()
    resp.status_code = status
    resp.text = text
    resp.raise_for_status = MagicMock()
    if status >= 400:
        resp.raise_for_status.side_effect = httpx.HTTPStatusError(
            f"HTTP {status}", request=MagicMock(), response=resp
        )
    return resp


def make_mock_client(
    *,
    get_side_effect: object = None,
    post_side_effect: object = None,
) -> AsyncMock:
    """Builds a fake httpx.AsyncClient usable as an async context manager."""
    client = AsyncMock()
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    if get_side_effect is not None:
        client.get = AsyncMock(side_effect=get_side_effect)
    if post_side_effect is not None:
        client.post = AsyncMock(side_effect=post_side_effect)
    return client
