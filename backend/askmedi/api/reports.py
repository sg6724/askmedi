from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

from askmedi.api.deps import CurrentUser, get_container
from askmedi.api.schemas import LabValueIn, LanguageField
from askmedi.api.uploads import IMAGE_TYPES, PDF_TYPES, read_upload
from askmedi.container import Container
from askmedi.services.reports import ReportService

router = APIRouter(prefix="/reports")

MAX_REPORT_BYTES = 10 * 1024 * 1024


class ConfirmIn(BaseModel):
    values: list[LabValueIn] = Field(min_length=1, max_length=80)
    language: LanguageField = "en"


def _service(container: Annotated[Container, Depends(get_container)]) -> ReportService:
    if container.reports is None:
        raise HTTPException(503, "service_unavailable")
    return container.reports


Service = Annotated[ReportService, Depends(_service)]


@router.post("/parse")
async def parse(
    user: CurrentUser, service: Service, file: Annotated[UploadFile, File()]
) -> dict[str, Any]:
    # Read into memory only; the file goes to the vision model and is never stored.
    data, mime = await read_upload(
        file, allowed=IMAGE_TYPES | PDF_TYPES, max_bytes=MAX_REPORT_BYTES
    )
    return await service.parse(user.user_id, data, mime)


@router.post("/{report_id}/confirm")
async def confirm(
    report_id: UUID, body: ConfirmIn, user: CurrentUser, service: Service
) -> dict[str, Any]:
    values = [v.model_dump() for v in body.values]
    return await service.confirm(user.user_id, str(report_id), values, body.language)
