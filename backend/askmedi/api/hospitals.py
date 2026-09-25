from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query

from askmedi.api.deps import CurrentUser, get_container
from askmedi.container import Container

router = APIRouter()

PINCODE_PATTERN = r"^[1-9][0-9]{5}$"


@router.get("/hospitals")
async def hospitals(
    user: CurrentUser,
    container: Annotated[Container, Depends(get_container)],
    lat: Annotated[float | None, Query(ge=-90, le=90)] = None,
    lng: Annotated[float | None, Query(ge=-180, le=180)] = None,
    pincode: Annotated[str | None, Query(pattern=PINCODE_PATTERN)] = None,
    q: Annotated[str | None, Query(min_length=2, max_length=200)] = None,
    radius_km: Annotated[float, Query(gt=0, le=25)] = 5.0,
    specialty: Annotated[str | None, Query(max_length=60)] = None,
) -> dict[str, Any]:
    if container.hospitals is None:
        raise HTTPException(503, "service_unavailable")
    if (lat is None) != (lng is None):
        raise HTTPException(422, "lat_and_lng_required")
    if lat is None and not pincode and not (q and q.strip()):
        raise HTTPException(422, "location_required")
    return await container.hospitals.search(
        user.user_id,
        lat=lat,
        lng=lng,
        pincode=pincode,
        q=q.strip() if q else None,
        radius_km=radius_km,
        specialty=specialty.strip() if specialty else None,
    )
