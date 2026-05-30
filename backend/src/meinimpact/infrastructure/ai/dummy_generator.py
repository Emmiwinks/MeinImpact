"""Deterministic AI generator used without external credentials."""

from collections.abc import AsyncIterator


class DummyTextGenerator:
    """Streams a safe deterministic draft for local development and tests."""

    async def stream_text(self, prompt: str) -> AsyncIterator[str]:
        """Streams a small placeholder draft."""
        del prompt  # The dummy generator intentionally ignores prompt content.
        text = (
            "Dear representative, I am writing as a resident who wants clear, "
            "evidence-based decisions and transparent follow-up on this issue."
        )
        for word in text.split(" "):
            yield f"{word} "
