"""Anonymous usage counters, shown on /admin.

The app reports an event by name only; the server adds one to that day's
count and keeps nothing about who sent it. Days are Berlin days, like the
admin page that shows them.
"""

from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_usage_repository, require_principal
from meinimpact.infrastructure.usage.postgres_usage_repository import (
    PostgresUsageRepository,
)

router = APIRouter(
    prefix="/v1/usage",
    tags=["usage"],
    dependencies=[Depends(require_principal)],
)

_BERLIN = ZoneInfo("Europe/Berlin")


@router.post("")
async def count_usage(
    request: schemas.UsageRequest,
    usage: PostgresUsageRepository = Depends(get_usage_repository),
) -> schemas.OkResponse:
    """Adds one to today's count of the event."""
    await usage.count(request.event, datetime.now(_BERLIN).date())
    await usage.commit()
    return schemas.OkResponse()
