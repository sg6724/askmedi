from dataclasses import dataclass
from typing import TYPE_CHECKING

from askmedi.config import Settings
from askmedi.domain.audit import AuditLogger
from askmedi.domain.auth import TokenVerifier
from askmedi.domain.llm import LLMProvider

if TYPE_CHECKING:  # services are only needed for typing here; keeps domain imports light
    from askmedi.services.chat import ChatService
    from askmedi.services.hospitals import HospitalService
    from askmedi.services.medicine import MedicineService
    from askmedi.services.reports import ReportService
    from askmedi.services.voice import VoiceService


@dataclass
class Container:
    token_verifier: TokenVerifier
    llm: LLMProvider
    audit: AuditLogger
    chat: "ChatService | None" = None
    medicine: "MedicineService | None" = None
    reports: "ReportService | None" = None
    hospitals: "HospitalService | None" = None
    voice: "VoiceService | None" = None


def build_container(settings: Settings) -> Container:
    # Imported here so domain-only imports of Container stay dependency-free.
    from askmedi.adapters.database import Database
    from askmedi.adapters.elevenlabs import ElevenLabsVoice
    from askmedi.adapters.gemini import GeminiClient
    from askmedi.adapters.groq_search import GroqWebSearch
    from askmedi.adapters.litellm_provider import LiteLLMProvider
    from askmedi.adapters.litellm_vision import LiteLLMVisionReader
    from askmedi.adapters.medlineplus import MedlinePlusSearch
    from askmedi.adapters.openfda import OpenFdaLabels
    from askmedi.adapters.osm import OsmDirectory
    from askmedi.adapters.postgres_audit import PostgresAuditLogger
    from askmedi.adapters.postgres_repos import (
        PostgresChatRepository,
        PostgresMedicineRepository,
        PostgresProfileRepository,
        PostgresReportRepository,
    )
    from askmedi.adapters.reader_chain import DocumentReaderChain
    from askmedi.adapters.search_chain import WebSearchChain
    from askmedi.adapters.supabase_jwt import SupabaseJwtVerifier, jwks_key_resolver
    from askmedi.safety.output_guard import OutputGuard
    from askmedi.safety.red_flags import RedFlagEngine
    from askmedi.safety.repeat_guard import RepeatQueryGuard
    from askmedi.services.chat import ChatService
    from askmedi.services.hospitals import HospitalService
    from askmedi.services.medicine import MedicineService
    from askmedi.services.reports import ReportService
    from askmedi.services.voice import VoiceService

    # Database is constructed exactly once, here, and shared by every repository; never
    # build one per request. Its connection pool opens lazily and binds to the event loop of
    # the first request, so the app relies on one long-lived event loop per process.
    db = Database(settings.database_url)
    llm = LiteLLMProvider.from_yaml(settings.models_config_path)
    audit = PostgresAuditLogger(db)
    gemini = GeminiClient(
        settings.gemini_api_key or "",
        search_models=llm.models_for("search"),
        vision_models=llm.models_for("vision"),
    )
    # Groq browser search first (free tier, no Gemini quota), then Gemini + Google Search
    # grounding, then MedlinePlus search so answers stay sourced when both are unavailable.
    searches = [gemini, MedlinePlusSearch()]
    if settings.groq_api_key:
        searches.insert(
            0, GroqWebSearch(settings.groq_api_key, models=llm.models_for("web_search"))
        )
    search = WebSearchChain(searches)
    # Gemini reads images and PDFs; non-Gemini vision models (Groq) take over for images when
    # the Gemini free-tier quota is used up.
    fallback_vision = [m for m in llm.models_for("vision") if not m.startswith("gemini")]
    reader = DocumentReaderChain([gemini, LiteLLMVisionReader(fallback_vision)])
    guard = OutputGuard()
    profiles = PostgresProfileRepository(db)
    chat_repo = PostgresChatRepository(db)
    osm = OsmDirectory(user_agent=settings.osm_user_agent)

    speech = None
    if settings.elevenlabs_api_key:
        speech = ElevenLabsVoice(
            settings.elevenlabs_api_key,
            stt_model=settings.elevenlabs_stt_model,
            tts_model=settings.elevenlabs_tts_model,
            tts_models_by_language=settings.elevenlabs_tts_models_by_language,
            voice_id=settings.elevenlabs_voice_id,
            output_format=settings.elevenlabs_output_format,
        )

    return Container(
        token_verifier=SupabaseJwtVerifier(
            issuer=settings.supabase_issuer,
            audience=settings.jwt_audience,
            key_resolver=jwks_key_resolver(settings.supabase_jwks_url),
        ),
        llm=llm,
        audit=audit,
        chat=ChatService(
            llm=llm,
            search=search,
            repo=chat_repo,
            profiles=profiles,
            audit=audit,
            red_flags=RedFlagEngine.from_yaml(),
            guard=guard,
            repeat_guard=RepeatQueryGuard(chat_repo),
        ),
        medicine=MedicineService(
            reader=reader,
            labels=OpenFdaLabels(),
            search=search,
            llm=llm,
            guard=guard,
            repo=PostgresMedicineRepository(db),
            profiles=profiles,
            audit=audit,
        ),
        reports=ReportService(
            reader=reader,
            search=search,
            llm=llm,
            guard=guard,
            repo=PostgresReportRepository(db),
            audit=audit,
        ),
        hospitals=HospitalService(geocoder=osm, places=osm, audit=audit),
        voice=VoiceService(stt=speech, tts=speech, audit=audit),
    )
