"""AI provider interfaces."""

from collections.abc import AsyncIterator
from typing import Protocol


class AiTextGenerator(Protocol):
    """Interface for streaming generated text."""

    def stream_text(self, prompt: str) -> AsyncIterator[str]:
        """Streams generated text chunks for a prompt."""
