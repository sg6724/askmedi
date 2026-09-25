"""Symptom chat use case: red flags -> repeat guard -> LLM turn -> output guard -> persist."""

import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from askmedi.domain.audit import AuditEvent, AuditLogger
from askmedi.domain.chat import MAX_FOLLOWUPS, ChatRepository, Episode, EpisodeUpdate, Turn
from askmedi.domain.common import (
    LIKELIHOODS,
    URGENCY_ORDER,
    NotFound,
    Source,
    bump_urgency,
    disclaimer,
    raise_urgency,
)
from askmedi.domain.llm import LLMProvider
from askmedi.domain.profile import Profile, ProfileRepository
from askmedi.domain.search import WebSearch
from askmedi.safety.output_guard import OutputGuard
from askmedi.safety.red_flags import RedFlagEngine, RedFlagMatch
from askmedi.safety.repeat_guard import RepeatQueryGuard, canonical_symptoms
from askmedi.services import prompts
from askmedi.services.support import (
    complete_json,
    dedupe_sources,
    guarded_json,
    research,
    safe_audit,
    str_list,
)

logger = logging.getLogger(__name__)

FALLBACK_TEXT: dict[str, dict[str, Any]] = {
    "en": {
        "summary": "I could not prepare a safe, reliable answer for this. Please consult a doctor "
        "about these symptoms.",
        "do_now": [
            "Rest and drink enough fluids.",
            "Note when the symptoms started and how they change.",
        ],
        "seek_care_if": [
            "Symptoms get worse or new symptoms appear.",
            "You feel very unwell or are worried.",
        ],
    },
    "hi": {
        "summary": "मैं इसके लिए सुरक्षित और भरोसेमंद जवाब नहीं बना सका। कृपया इन लक्षणों के बारे में "
        "डॉक्टर से सलाह लें।",
        "do_now": ["आराम करें और पर्याप्त पानी पिएँ।", "लक्षण कब शुरू हुए और कैसे बदल रहे हैं, यह लिख लें।"],
        "seek_care_if": ["लक्षण बढ़ें या नए लक्षण दिखें।", "आप बहुत अस्वस्थ महसूस करें या चिंता हो।"],
    },
    "mr": {
        "summary": "मी यासाठी सुरक्षित आणि विश्वासार्ह उत्तर तयार करू शकलो नाही. कृपया या लक्षणांबद्दल "
        "डॉक्टरांचा सल्ला घ्या.",
        "do_now": [
            "विश्रांती घ्या आणि पुरेसे पाणी प्या.",
            "लक्षणे कधी सुरू झाली आणि कशी बदलत आहेत ते लिहून ठेवा.",
        ],
        "seek_care_if": [
            "लक्षणे वाढली किंवा नवीन लक्षणे दिसली.",
            "तुम्हाला खूप अस्वस्थ वाटले किंवा काळजी वाटली.",
        ],
    },
}


@dataclass(frozen=True)
class ChatRequest:
    user_id: str
    episode_id: str | None
    message: str
    language: str


def _response(
    episode_id: str,
    type_: str,
    language: str,
    *,
    message: str,
    readback: list[str] | None = None,
    followup: dict[str, Any] | None = None,
    answer: dict[str, Any] | None = None,
    emergency: dict[str, Any] | None = None,
    sources: list[Source] | None = None,
) -> dict[str, Any]:
    return {
        "episode_id": episode_id,
        "type": type_,
        "readback": readback or [],
        "followup": followup,
        "answer": answer,
        "emergency": emergency,
        "message": message,
        "sources": [s.to_dict() for s in sources or []],
        "disclaimer": disclaimer(language),
    }


def _valid_followup(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    question = str(raw.get("question") or "").strip()
    options = str_list(raw.get("options"), 5, 80)
    if not question or len(options) < 2:
        return None
    return {"question": question[:300], "options": options}


def normalise_answer(raw: dict[str, Any]) -> dict[str, Any]:
    """Coerces model output into the contract shape. Invalid urgency -> see_doctor_today."""
    urgency = raw.get("urgency")
    if urgency not in URGENCY_ORDER:
        urgency = "see_doctor_today"
    causes = []
    for c in raw.get("causes") or []:
        if not isinstance(c, dict) or not str(c.get("name") or "").strip():
            continue
        likelihood = c.get("likelihood")
        causes.append(
            {
                "name": str(c["name"]).strip()[:120],
                "likelihood": likelihood if likelihood in LIKELIHOODS else "possible",
                "explanation": str(c.get("explanation") or "").strip()[:400],
            }
        )
    return {
        "urgency": urgency,
        "summary": str(raw.get("summary") or "").strip()[:1200],
        "causes": causes[:4],
        "do_now": str_list(raw.get("do_now"), 5),
        "seek_care_if": str_list(raw.get("seek_care_if"), 5),
    }


class ChatService:
    def __init__(
        self,
        *,
        llm: LLMProvider,
        search: WebSearch,
        repo: ChatRepository,
        profiles: ProfileRepository,
        audit: AuditLogger,
        red_flags: RedFlagEngine,
        guard: OutputGuard,
        repeat_guard: RepeatQueryGuard,
    ) -> None:
        self._llm = llm
        self._search = search
        self._repo = repo
        self._profiles = profiles
        self._audit = audit
        self._red_flags = red_flags
        self._guard = guard
        self._repeat = repeat_guard

    async def handle(self, req: ChatRequest) -> dict[str, Any]:
        # (1) Deterministic red flags on the raw text. No LLM, and no dependency on the DB.
        match = self._red_flags.check(req.message, req.language)
        if match:
            return await self._emergency(req, match)

        episode = await self._load_or_create(req)
        await self._repo.add_turn(req.user_id, episode.id, "user", req.message, lang=req.language)
        profile = await self._profile(req.user_id)
        profile_text = prompts.profile_summary(profile, datetime.now(UTC).year)
        must_answer = episode.followup_count >= MAX_FOLLOWUPS

        # (3a) Intake step: symptoms, readback, and follow-up vs answer.
        decision, result = await complete_json(
            self._llm,
            "reason",
            prompts.chat_reason_messages(
                turns=episode.turns,
                message=req.message,
                language=req.language,
                profile_text=profile_text,
                followups_used=episode.followup_count,
                max_followups=MAX_FOLLOWUPS,
                must_answer=must_answer,
            ),
        )
        symptoms = canonical_symptoms(episode.symptoms + str_list(decision.get("symptoms"), 10, 60))
        readback = str_list(decision.get("readback"), 5, 60)

        # (2) Repeat guard (needs the normalised symptoms from the intake step).
        if not episode.repeat_flag and await self._repeat.is_repeat(
            req.user_id, episode.id, symptoms
        ):
            return await self._repeat_response(req, episode, symptoms, readback)

        followup = _valid_followup(decision.get("followup"))
        if (
            decision.get("action") == "followup"
            and followup
            and not must_answer
            and not self._guard.violations(followup)
        ):
            await self._repo.add_turn(
                req.user_id, episode.id, "assistant", followup["question"], lang=req.language
            )
            await self._repo.update_episode(
                req.user_id,
                episode.id,
                EpisodeUpdate(symptoms=symptoms, followup_count=episode.followup_count + 1),
            )
            await safe_audit(
                self._audit,
                AuditEvent(
                    user_id=req.user_id,
                    episode_id=episode.id,
                    type="followup",
                    payload={"followup_count": episode.followup_count + 1},
                    model=result.model,
                    latency_ms=result.latency_ms,
                ),
            )
            return _response(
                episode.id,
                "followup",
                req.language,
                message=followup["question"],
                readback=readback,
                followup=followup,
            )

        search_query = str(decision.get("search_query") or " ".join(symptoms) or req.message)
        return await self._answer(
            req, episode, symptoms, readback, profile_text, search_query[:300]
        )

    # ------------------------------------------------------------------ paths

    async def _answer(
        self,
        req: ChatRequest,
        episode: Episode,
        symptoms: list[str],
        readback: list[str],
        profile_text: str,
        search_query: str,
    ) -> dict[str, Any]:
        grounded = await research(
            self._search,
            prompts.chat_research_question(search_query, symptoms, profile_text),
            symptoms or [search_query],
        )
        data, first_violations, result = await guarded_json(
            self._llm,
            self._guard,
            "respond",
            prompts.chat_answer_messages(
                turns=episode.turns,
                message=req.message,
                language=req.language,
                profile_text=profile_text,
                research=grounded.text,
            ),
        )
        fallback = data is None
        if data is None:
            fb = FALLBACK_TEXT.get(req.language, FALLBACK_TEXT["en"])
            answer = {
                "urgency": raise_urgency(episode.urgency, "see_doctor_soon"),
                "summary": fb["summary"],
                "causes": [],
                "do_now": list(fb["do_now"]),
                "seek_care_if": list(fb["seek_care_if"]),
            }
            message = fb["summary"]
            sources: list[Source] = []
        else:
            answer = normalise_answer(data)
            # Urgency is never lowered: keep the episode's earlier level, and go one step up
            # when the model is unsure or the web search found nothing to ground the answer.
            urgency = raise_urgency(answer["urgency"], episode.urgency)
            if data.get("confidence") == "low" or not grounded.sources:
                urgency = bump_urgency(urgency)
            answer["urgency"] = urgency
            message = str(data.get("message") or answer["summary"]).strip()[:1200]
            if self._guard.violations(message):
                message = answer["summary"]
            sources = dedupe_sources(grounded.sources)

        turn_id = await self._repo.add_turn(
            req.user_id, episode.id, "assistant", message, lang=req.language
        )
        if sources:
            await self._repo.add_citations(req.user_id, episode.id, turn_id, sources)
        await self._repo.update_episode(
            req.user_id,
            episode.id,
            EpisodeUpdate(
                symptoms=symptoms,
                urgency=answer["urgency"],
                outcome={"type": "answer", "answer": answer, "fallback": fallback},
            ),
        )
        if first_violations:
            await safe_audit(
                self._audit,
                AuditEvent(
                    user_id=req.user_id,
                    episode_id=episode.id,
                    type="output_guard_fallback" if fallback else "output_guard_repair",
                    payload={"violations": first_violations},
                ),
            )
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=req.user_id,
                episode_id=episode.id,
                type="answer",
                payload={
                    "urgency": answer["urgency"],
                    "sources": len(sources),
                    "search_model": grounded.model,
                    "fallback": fallback,
                },
                model=result.model,
                latency_ms=result.latency_ms,
            ),
        )
        return _response(
            episode.id,
            "answer",
            req.language,
            message=message,
            readback=readback,
            answer=answer,
            sources=sources,
        )

    async def _emergency(self, req: ChatRequest, match: RedFlagMatch) -> dict[str, Any]:
        episode_id = str(uuid.uuid4())
        persisted = False
        try:
            episode = await self._load_or_create(req, create_if_missing=True)
            episode_id = episode.id
            await self._repo.add_turn(
                req.user_id, episode_id, "user", req.message, lang=req.language
            )
            await self._repo.add_turn(
                req.user_id, episode_id, "assistant", match.message, lang=req.language
            )
            await self._repo.add_citations(req.user_id, episode_id, None, [match.source])
            await self._repo.update_episode(
                req.user_id,
                episode_id,
                EpisodeUpdate(
                    urgency="emergency",
                    red_flag_rule_id=match.rule_id,
                    outcome={"type": "emergency", "rule_id": match.rule_id},
                ),
            )
            persisted = True
        except Exception:
            logger.exception("could not persist emergency episode")
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=req.user_id,
                episode_id=episode_id if persisted else None,
                type="red_flag",
                payload={"rule_id": match.rule_id, "rules_version": self._red_flags.version},
            ),
        )
        return _response(
            episode_id,
            "emergency",
            req.language,
            message=match.message,
            emergency=match.to_dict(),
            sources=[match.source],
        )

    async def _repeat_response(
        self, req: ChatRequest, episode: Episode, symptoms: list[str], readback: list[str]
    ) -> dict[str, Any]:
        message = self._repeat.message(req.language)
        await self._repo.add_turn(req.user_id, episode.id, "assistant", message, lang=req.language)
        await self._repo.update_episode(
            req.user_id,
            episode.id,
            EpisodeUpdate(
                symptoms=symptoms,
                urgency=raise_urgency(episode.urgency, "see_doctor_soon"),
                repeat_flag=True,
                outcome={"type": "repeat"},
            ),
        )
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=req.user_id,
                episode_id=episode.id,
                type="repeat_guard",
                payload={"symptoms": symptoms},
            ),
        )
        return _response(episode.id, "repeat", req.language, message=message, readback=readback)

    # ------------------------------------------------------------------ helpers

    async def _load_or_create(self, req: ChatRequest, create_if_missing: bool = False) -> Episode:
        if req.episode_id:
            episode = await self._repo.get_episode(req.user_id, req.episode_id)
            if episode is not None:
                return episode
            if not create_if_missing:
                raise NotFound("episode_not_found")
        new_id = await self._repo.create_episode(req.user_id, req.language)
        return Episode(id=new_id, language=req.language)

    async def _profile(self, user_id: str) -> Profile:
        try:
            return await self._profiles.get_profile(user_id)
        except Exception:
            logger.exception("profile lookup failed")
            return Profile()


__all__ = ["ChatRequest", "ChatService", "Turn", "normalise_answer"]
