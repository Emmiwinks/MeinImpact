"""Push notification subscription routes."""

from fastapi import APIRouter, Depends

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_push_repository, require_principal
from meinimpact.domain import repositories

router = APIRouter(
    prefix="/v1/push",
    tags=["push"],
    dependencies=[Depends(require_principal)],
)


@router.post("/register")
async def register_push_token(
    request: schemas.PushRegisterRequest,
    push_repo: repositories.PushSubscriptionRepository = Depends(get_push_repository),
) -> schemas.OkResponse:
    """Registers or refreshes a device push token."""
    await push_repo.register(request.push_token, request.platform)
    return schemas.OkResponse()


@router.post("/subscribe")
async def subscribe_to_action(
    request: schemas.PushSubscribeRequest,
    push_repo: repositories.PushSubscriptionRepository = Depends(get_push_repository),
) -> schemas.OkResponse:
    """Subscribes a push token to receive updates for an action."""
    await push_repo.subscribe(request.push_token, request.action_id)
    return schemas.OkResponse()


@router.post("/unsubscribe")
async def unsubscribe_from_action(
    request: schemas.PushSubscribeRequest,
    push_repo: repositories.PushSubscriptionRepository = Depends(get_push_repository),
) -> schemas.OkResponse:
    """Unsubscribes a push token from an action."""
    await push_repo.unsubscribe(request.push_token, request.action_id)
    return schemas.OkResponse()
