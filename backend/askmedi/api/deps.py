from fastapi import Request

from askmedi.container import Container


def get_container(request: Request) -> Container:
    return request.app.state.container
