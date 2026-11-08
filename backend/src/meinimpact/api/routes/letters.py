"""Letter generation route: a letter about an upcoming council decision."""

from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse

from meinimpact.api import schemas
from meinimpact.api.dependencies import (
    get_draft_service,
    get_opportunity_repository,
    require_principal,
)
from meinimpact.api.sse import encode_sse
from meinimpact.domain import repositories
from meinimpact.infrastructure.listings.model import ActionKind
from meinimpact.services.draft_service import DraftService

router = APIRouter(
    prefix="/v1/letters",
    tags=["letters"],
    dependencies=[Depends(require_principal)],
)


@router.post("/stream")
async def stream_letter(
    request: schemas.LetterRequest,
    opportunity_repository: repositories.OpportunityRepository = Depends(
        get_opportunity_repository
    ),
    draft_service: DraftService = Depends(get_draft_service),
) -> StreamingResponse:
    """Streams an AI-drafted letter about a council decision as SSE."""
    opportunity = await opportunity_repository.get(request.opportunity_id)
    if opportunity is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Opportunity not found.",
        )
    if opportunity.kind != ActionKind.DECISION.value:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Letters are drafted for council decisions only.",
        )

    async def event_stream() -> AsyncIterator[str]:
        # Must go through encode_sse, not a raw f"data: {token}\n\n" — a
        # token can legitimately contain an embedded newline (models often
        # emit a bare "\n" token right after sentence-ending punctuation).
        # encode_sse splits multi-line data into multiple `data:` lines per
        # the SSE spec; the naive version let that raw newline corrupt the
        # frame boundary, silently dropping the *next* token client-side —
        # exactly the "missing chunk of text" bug this fixes.
        async for token in draft_service.stream_letter(opportunity, request.notes):
            yield encode_sse(event="message", data=token)
        yield encode_sse(event="message", data="[DONE]")

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-store"},
    )
