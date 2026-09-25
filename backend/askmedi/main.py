from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from askmedi.api import chat, health, hospitals, me, medicine, reports, voice
from askmedi.api.errors import install_error_handlers
from askmedi.config import DEFAULT_CORS_ORIGIN_REGEX
from askmedi.container import Container


def create_app(container: Container, cors_origin_regex: str = DEFAULT_CORS_ORIGIN_REGEX) -> FastAPI:
    app = FastAPI(title="AskMedi API", version="0.1.0")
    app.state.container = container
    # Bearer tokens only (no cookies), so credentials stay off.
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=cors_origin_regex,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["authorization", "content-type"],
    )
    install_error_handlers(app)
    for module in (health, me, chat, medicine, reports, hospitals, voice):
        app.include_router(module.router)
    return app
