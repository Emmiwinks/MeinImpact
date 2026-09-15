"""Server-Sent Events helpers."""

import json
from collections.abc import Mapping


def encode_sse(
    event: str,
    data: str,
    event_id: str | None = None,
    retry_milliseconds: int | None = None,
) -> str:
    """Encodes one Server-Sent Event message."""
    lines: list[str] = []
    if event_id is not None:
        lines.append(f"id: {event_id}")
    lines.append(f"event: {event}")
    if retry_milliseconds is not None:
        lines.append(f"retry: {retry_milliseconds}")
    # split('\n'), not splitlines(): per the SSE spec, N `data:` lines
    # reconstruct as their values joined by '\n' — split('\n') is the exact
    # inverse of that join, including a trailing/lone newline in `data`
    # (splitlines() drops the trailing empty segment, which would silently
    # lose that newline on the client's reconstruction).
    payload_lines = data.split("\n")
    lines.extend(f"data: {line}" for line in payload_lines)
    return "\n".join(lines) + "\n\n"


def encode_json_sse(event: str, data: Mapping[str, object]) -> str:
    """Encodes a JSON payload as an SSE message."""
    return encode_sse(event=event, data=json.dumps(data, separators=(",", ":")))
