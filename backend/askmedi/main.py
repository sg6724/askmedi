from fastapi import FastAPI

from askmedi.api import health, me
from askmedi.container import Container


def create_app(container: Container) -> FastAPI:
    app = FastAPI(title="AskMedi API", version="0.1.0")
    app.state.container = container
    app.include_router(health.router)
    app.include_router(me.router)
    return app
