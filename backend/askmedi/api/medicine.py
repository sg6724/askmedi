from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, StringConstraints

from askmedi.api.deps import CurrentUser, get_container
from askmedi.api.schemas import LanguageField
from askmedi.api.uploads import IMAGE_TYPES, read_upload
from askmedi.container import Container
from askmedi.services.medicine import MedicineService

router = APIRouter(prefix="/medicine")

MAX_IMAGE_BYTES = 8 * 1024 * 1024
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
Brand = Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)]


class LookupIn(BaseModel):
    name: Name
    brand: Brand | None = None
    language: LanguageField = "en"


def _service(container: Annotated[Container, Depends(get_container)]) -> MedicineService:
    if container.medicine is None:
        raise HTTPException(503, "service_unavailable")
    return container.medicine


Service = Annotated[MedicineService, Depends(_service)]


@router.post("/scan")
async def scan(
    user: CurrentUser, service: Service, image: Annotated[UploadFile, File()]
) -> dict[str, Any]:
    data, mime = await read_upload(image, allowed=IMAGE_TYPES, max_bytes=MAX_IMAGE_BYTES)
    return await service.scan(user.user_id, data, mime)


@router.post("/lookup")
async def lookup(body: LookupIn, user: CurrentUser, service: Service) -> dict[str, Any]:
    return await service.lookup(user.user_id, body.name, body.brand or None, body.language)
