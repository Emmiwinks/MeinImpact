"""News API routes."""

from fastapi import APIRouter, Depends, Query

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_news_repository, require_principal
from meinimpact.domain import repositories

router = APIRouter(
    prefix="/v1/news",
    tags=["news"],
    dependencies=[Depends(require_principal)],
)


@router.get("")
async def list_news(
    limit: int = Query(default=10, ge=1, le=50),
    news_repository: repositories.NewsRepository = Depends(get_news_repository),
) -> schemas.NewsResponse:
    """Returns dummy news items for the initial app integration."""
    news_items = await news_repository.list_recent_news(limit=limit)
    return schemas.NewsResponse(
        news=[schemas.NewsItemResponse.from_domain(item) for item in news_items]
    )
