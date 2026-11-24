"""Mistral token usage, measured where it happens and priced in euros.

`track()` opens a meter for the code inside it; every completion made
there (also in tasks it starts) adds to every open meter. So one run-wide
meter and one meter per listing can count at the same time, even while
several listings are enriched concurrently: each listing runs in its own
task with its own meter.
"""

from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass


@dataclass
class Usage:
    calls: int = 0
    prompt_tokens: int = 0
    completion_tokens: int = 0


_open_meters: ContextVar[tuple[Usage, ...]] = ContextVar("mistral_usage", default=())


@contextmanager
def track() -> Iterator[Usage]:
    usage = Usage()
    token = _open_meters.set((*_open_meters.get(), usage))
    try:
        yield usage
    finally:
        _open_meters.reset(token)


def record(prompt_tokens: int, completion_tokens: int) -> None:
    """Called by the completer after every answer Mistral reports usage for."""
    for usage in _open_meters.get():
        usage.calls += 1
        usage.prompt_tokens += prompt_tokens
        usage.completion_tokens += completion_tokens


@dataclass(frozen=True, slots=True)
class Price:
    eur_per_m_input: float
    eur_per_m_output: float

    def cost(self, usage: Usage) -> float:
        return (
            usage.prompt_tokens * self.eur_per_m_input
            + usage.completion_tokens * self.eur_per_m_output
        ) / 1_000_000
