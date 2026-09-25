from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from askmedi.domain.common import ServiceError


def install_error_handlers(app: FastAPI) -> None:
    """Service errors become `{"detail": "<code>"}` with the error's HTTP status."""

    @app.exception_handler(ServiceError)
    async def _service_error(_: Request, exc: ServiceError) -> JSONResponse:
        return JSONResponse({"detail": exc.code}, status_code=exc.status_code)
