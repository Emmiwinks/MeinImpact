"""SSE helper tests."""

from meinimpact.api.sse import encode_json_sse, encode_sse


def test_encode_sse_formats_multiline_payload() -> None:
    event = encode_sse("message", "line one\nline two", event_id="42")
    assert event == "id: 42\nevent: message\ndata: line one\ndata: line two\n\n"


def test_encode_sse_supports_retry_and_empty_payload() -> None:
    event = encode_sse("ping", "", retry_milliseconds=3000)
    assert event == "event: ping\nretry: 3000\ndata: \n\n"


def test_encode_json_sse_uses_compact_json() -> None:
    event = encode_json_sse("message", {"ok": True})
    assert event == 'event: message\ndata: {"ok":true}\n\n'


def test_encode_sse_preserves_a_lone_trailing_newline() -> None:
    """Regression: a streamed token that is itself just "\\n" (models often
    emit a bare newline right after sentence-ending punctuation) must round
    -trip through two `data:` lines, not collapse to one and lose the
    newline — splitlines() used to drop the trailing empty segment here."""
    event = encode_sse("message", "\n")
    assert event == "event: message\ndata: \ndata: \n\n"
