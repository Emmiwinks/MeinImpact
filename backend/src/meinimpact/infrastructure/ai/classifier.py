"""Mistral classification client for the ingestion pipeline.

Separate from MistralTextGenerator (streaming letter drafts); this client
calls the non-streaming JSON-mode endpoint for action classification.
"""

import json
import logging

import httpx

from meinimpact.infrastructure.pipeline.types import ClassifiedAction
from meinimpact.infrastructure.sources.protocol import RawSourceItem

logger = logging.getLogger(__name__)

_CLASSIFICATION_PROMPT = """\
You are a German civic action classifier. Analyse the following item and return
ONLY valid JSON with this exact structure:

{{
  "is_civic_policy": <bool>,
  "urgency": "high" | "mid" | "low",
  "werte_relevanz": {{
    "wirtschaft": <float -1.0 to 1.0>,
    "diplomatie": <float -1.0 to 1.0>,
    "freiheit": <float -1.0 to 1.0>,
    "wandel": <float -1.0 to 1.0>
  }},
  "pro_argumente": ["...", "..."],
  "contra_argumente": ["...", "..."],
  "action_types": ["brief", "petition", "anfrage"],
  "is_controversial": <bool>,
  "position_required": <bool>
}}

is_civic_policy: true ONLY if the item concerns public policy, legislation, or
collective political decisions that affect society broadly. Set false for:
- complaints about a single school exam or local institutional decision
- personal or consumer grievances with no legislative angle
- internal organisational matters
- anything a citizen cannot meaningfully influence by contacting their MdB

urgency rules:
- high: parliamentary status is 2./3. Beratung OR deadline within 14 days
- mid: Ausschussberatung OR deadline within 60 days OR active public debate
- low: ongoing, no imminent deadline

werte_relevanz: 0.0 = axis not relevant, positive = positive pole,
negative = negative pole. All four axes required even if 0.0.

is_controversial: true if reasonable people with different values would
strongly disagree.
position_required: true if a letter can only be written from a clear political position.

Action and context:
Title: {title}
Description: {description}
Parliamentary status: {status}
Web context: {tavily_context}
"""

_REQUIRED_FIELDS = {
    "is_civic_policy",
    "urgency",
    "werte_relevanz",
    "pro_argumente",
    "contra_argumente",
    "action_types",
    "is_controversial",
    "position_required",
}


class MistralClassifier:
    """Classifies a RawSourceItem using Mistral's JSON-mode chat completion."""

    def __init__(self, api_key: str, base_url: str, model: str) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._model = model

    async def classify(self, item: RawSourceItem) -> ClassifiedAction | None:
        """Returns a ClassifiedAction or None on error / malformed output."""
        prompt = _CLASSIFICATION_PROMPT.format(
            title=item["title"],
            description=item.get("description", ""),  # type: ignore[misc]
            status=item.get("status", ""),  # type: ignore[misc]
            tavily_context=item.get("tavily_context", ""),  # type: ignore[misc]
        )
        payload = {
            "model": self._model,
            "messages": [{"role": "user", "content": prompt}],
            "response_format": {"type": "json_object"},
            "max_tokens": 500,
            "temperature": 0.1,
        }
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self._base_url}/chat/completions",
                    headers={"Authorization": f"Bearer {self._api_key}"},
                    json=payload,
                )
                response.raise_for_status()
            data: dict[str, object] = response.json()
            content = str(
                data["choices"][0]["message"]["content"]  # type: ignore[index]
            )
            classification: dict[str, object] = json.loads(content)
        except Exception as exc:
            logger.warning("Mistral classification failed: %s", exc)
            return None

        if not _REQUIRED_FIELDS.issubset(classification.keys()):
            logger.warning("Mistral returned incomplete classification, skipping")
            return None

        if not classification.get("is_civic_policy", True):
            logger.info("Classifier rejected non-civic item: %s", item["title"][:60])
            return None

        return ClassifiedAction(
            **item,  # type: ignore[misc]
            urgency=str(classification.get("urgency") or "low"),
            werte_relevanz=dict(classification.get("werte_relevanz") or {}),  # type: ignore[arg-type]
            pro_argumente=list(classification.get("pro_argumente") or []),  # type: ignore[arg-type]
            contra_argumente=list(classification.get("contra_argumente") or []),  # type: ignore[arg-type]
            action_types=list(classification.get("action_types") or []),  # type: ignore[arg-type]
            is_controversial=bool(classification.get("is_controversial", False)),
            position_required=bool(classification.get("position_required", False)),
            momentum_score=0.3,
        )
