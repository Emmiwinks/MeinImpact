"""ClassifyStep — wraps the unchanged MistralClassifier per surviving item.

Items that fail classification (rejected as non-civic-policy, or an API
error) are dropped here — they never reach merge/persist.
"""

import asyncio

from meinimpact.infrastructure.ai.classifier import MistralClassifier
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps


class ClassifyStep:
    """Runs Mistral classification on each item, dropping failures."""

    name = "classify"

    def __init__(self, classifier: MistralClassifier) -> None:
        self._classifier = classifier

    async def process(
        self, items: list[ItemState], deps: PipelineDeps
    ) -> list[ItemState]:
        results = await asyncio.gather(
            *[self._classifier.classify(item.raw) for item in items],
            return_exceptions=True,
        )
        for item, result in zip(items, results, strict=True):
            if isinstance(result, BaseException):
                deps.errors.append(
                    f"Classification error for {item.raw.get('external_id')}: {result}"
                )
                item.classified = None
            else:
                item.classified = result
        return [item for item in items if item.classified is not None]
