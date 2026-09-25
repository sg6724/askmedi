"""Vercel entrypoint. Vercel's FastAPI support looks for a module-level `app`."""
from askmedi.config import get_settings
from askmedi.container import build_container
from askmedi.main import create_app

settings = get_settings()
app = create_app(build_container(settings), cors_origin_regex=settings.cors_origin_regex)
