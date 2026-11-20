"""Where a PLZ lies: the one request that carries a user's PLZ.

The app asks once, when the PLZ is entered, and keeps the answer on the
device; afterwards it only ever sends the Kreis. The PLZ travels in the
body, so the access log never shows it, and nothing here stores it.
"""

from fastapi import APIRouter, Depends, HTTPException, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_plz_index, require_principal
from meinimpact.api.routes.mdb import get_wks, mdb_options
from meinimpact.infrastructure.geo.plz import PlzIndex
from meinimpact.infrastructure.mdb.wks_service import WksService

router = APIRouter(
    prefix="/v1/location",
    tags=["location"],
    dependencies=[Depends(require_principal)],
)


@router.post("")
async def locate_plz(
    request: schemas.LocationRequest,
    plz_index: PlzIndex = Depends(get_plz_index),
    wks: WksService = Depends(get_wks),
) -> schemas.LocationResponse:
    """Returns the PLZ's Kreis, point and members of the Bundestag.

    404 when the PLZ is unknown. Without the Bundestag data the location
    still comes back, with no Wahlkreise.
    """
    location = plz_index.locate(request.plz)
    if location is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Unknown PLZ."
        )
    wahlkreise = await wks.lookup_with_fallback(request.plz) if wks.is_healthy else []
    return schemas.LocationResponse(
        kreis=location.kreis,
        lat=location.point.lat,
        lon=location.point.lon,
        wahlkreise=mdb_options(wahlkreise),
    )
