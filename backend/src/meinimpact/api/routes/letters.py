"""Letter and question generation routes."""

from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse

from meinimpact.api import schemas
from meinimpact.api.dependencies import (
    get_action_repository,
    get_draft_service,
    require_principal,
)
from meinimpact.api.sse import encode_sse
from meinimpact.domain import repositories
from meinimpact.services.draft_service import DraftService

router = APIRouter(
    prefix="/v1/letters",
    tags=["letters"],
    dependencies=[Depends(require_principal)],
)


@router.post("/stream")
async def stream_letter(
    request: schemas.LetterRequest,
    action_repository: repositories.CivicActionRepository = Depends(
        get_action_repository
    ),
    draft_service: DraftService = Depends(get_draft_service),
) -> StreamingResponse:
    """Streams an AI-generated letter or public question draft as SSE."""
    action = await action_repository.get_action(request.action_id)
    if action is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Action not found.",
        )

    async def event_stream() -> AsyncIterator[str]:
        # Must go through encode_sse, not a raw f"data: {token}\n\n" — a
        # token can legitimately contain an embedded newline (models often
        # emit a bare "\n" token right after sentence-ending punctuation).
        # encode_sse splits multi-line data into multiple `data:` lines per
        # the SSE spec; the naive version let that raw newline corrupt the
        # frame boundary, silently dropping the *next* token client-side —
        # exactly the "missing chunk of text" bug this fixes.
        async for token in draft_service.stream_letter(request, action):
            yield encode_sse(event="message", data=token)
        yield encode_sse(event="message", data="[DONE]")

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-store"},
    )
