"""Abgeordnetenwatch position check — MdB-position source 1.

Per specs/data/sources-federal.md "Source 6: MdB Public Statements".
Public, no API key required.
"""

import logging
from datetime import datetime

import httpx

from meinimpact.infrastructure.sources.protocol import MdbTarget, PositionCheckResult

logger = logging.getLogger(__name__)

_BASE_URL = "https://www.abgeordnetenwatch.de/api/v2"
_SOURCE_NAME = "abgeordnetenwatch"


class AbgeordnetenwatchPositionAdapter:
    """Checks an MdB's public Q&A answers for a topic match."""

    async def check_position(
        self, mdb: MdbTarget, descriptors: list[str], since: datetime
    ) -> PositionCheckResult:
        if mdb.aw_politician_id is None:
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        params = {
            "politician": mdb.aw_politician_id,
            "updated_since": since.date().isoformat(),
        }
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(f"{_BASE_URL}/answers", params=params)
                response.raise_for_status()
            data: dict[str, object] = response.json()
        except Exception as exc:
            logger.warning(
                "Abgeordnetenwatch position check failed for %s: %s", mdb.name, exc
            )
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        answers = data.get("data") or []
        if not isinstance(answers, list):
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        match = _find_matching_answer(answers, descriptors)
        if match is None:
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        return PositionCheckResult(
            found=True,
            source=_SOURCE_NAME,
            statement_summary=str(match.get("text", ""))[:500],
            source_url=str(match.get("url") or match.get("api_url") or "") or None,
        )


def _find_matching_answer(
    answers: list[object], descriptors: list[str]
) -> dict[str, object] | None:
    lowered = [d.lower() for d in descriptors]
    for answer in answers:
        if not isinstance(answer, dict):
            continue
        text = str(answer.get("text", "")).lower()
        if any(d in text for d in lowered):
            return answer
    return None
