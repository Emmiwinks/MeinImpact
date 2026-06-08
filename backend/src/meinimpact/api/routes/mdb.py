"""MdB lookup routes — PLZ to Bundestagsabgeordneter."""

import re

from fastapi import APIRouter, Depends, HTTPException, Request, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import require_principal
from meinimpact.infrastructure.mdb.wks_service import WksService

router = APIRouter(
    prefix="/v1/mdb",
    tags=["mdb"],
    dependencies=[Depends(require_principal)],
)

_PLZ_RE = re.compile(r"^\d{5}$")


def _get_wks(request: Request) -> WksService:
    wks: WksService = request.app.state.wks_service
    return wks


@router.get("")
async def get_mdb_for_plz(
    plz: str,
    wks: WksService = Depends(_get_wks),
) -> schemas.MdbResponse:
    """Returns the MdB(s) for a German PLZ.

    Usually returns one result. Returns multiple when a PLZ straddles
    Wahlkreis boundaries — the caller should let the user pick.
    Returns 404 when the PLZ is unknown.
    Returns 503 when the Bundestag WKS data failed to load.
    """
    if not _PLZ_RE.match(plz):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="PLZ must be exactly 5 digits.",
        )

    if not wks.is_healthy:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "MdB lookup is currently unavailable. "
                "The Bundestag data source may have changed. "
                f"Operator: check application logs. Error: {wks.load_error}"
            ),
        )

    results = await wks.lookup_with_fallback(plz)
    if not results:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No Wahlkreis found for PLZ {plz}.",
        )

    return schemas.MdbResponse(
        plz=plz,
        results=[
            schemas.MdbOption(
                wahlkreis_nr=r.wahlkreis_nr,
                wahlkreis_name=r.wahlkreis_name,
                mdb_name=r.mdb_name,
                mdb_party=r.mdb_party,
                mdb_link=r.mdb_link,
            )
            for r in results
        ],
    )
