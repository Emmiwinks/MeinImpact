"""Mistral embeddings client — used for opportunity de-duplication.

Embeds `decision_object` only (never the full title/summary/content) —
see specs discussion in project_tavily_retrieval_calibration.md and the
rebuild plan section 4: a short, source-agnostic phrasing of "what is
being decided" is what makes cosine similarity actually catch the same
real-world thing described differently by different sources.
"""

import httpx


class MistralEmbeddingClient:
    """Wraps the Mistral embeddings API. One call, one input, one vector —
    callers needing many embeddings call this concurrently rather than
    this class batching internally, keeping it a single-purpose component.
    """

    def __init__(self, api_key: str, base_url: str, model: str) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._model = model

    async def embed(self, text: str) -> list[float]:
        """Returns the embedding vector for `text`.

        Raises on any API error — unlike other adapters in this codebase
        that degrade to an empty/false result, a failed embedding means
        the caller cannot de-duplicate this item at all, so silently
        continuing would risk inserting an undetected duplicate.
        """
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }
        payload = {"model": self._model, "input": [text]}
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{self._base_url}/embeddings", headers=headers, json=payload
            )
            response.raise_for_status()
        data = response.json()
        return list(data["data"][0]["embedding"])
