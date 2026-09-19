"""Vercel entrypoint. Vercel's FastAPI support looks for a module-level `app`."""
from askmedi.config import get_settings
from askmedi.container import build_container
from askmedi.main import create_app

app = create_app(build_container(get_settings()))
