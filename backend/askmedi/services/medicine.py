"""Medicine scan (vision) and lookup (openFDA label + web-grounded summary)."""

import logging
from typing import Any

from askmedi.domain.audit import AuditEvent, AuditLogger
from askmedi.domain.common import Source, Unprocessable, UpstreamUnavailable, disclaimer
from askmedi.domain.llm import LLMProvider
from askmedi.domain.medicine import (
    DrugLabel,
    DrugLabelSource,
    DrugLabelUnavailable,
    MedicineCandidate,
    MedicineRepository,
    pharmacist_flags,
)
from askmedi.domain.profile import Profile, ProfileRepository
from askmedi.domain.search import (
    DocumentReader,
    UnreadableDocument,
    VisionUnavailable,
    WebSearch,
)
from askmedi.safety.output_guard import OutputGuard
from askmedi.services import prompts
from askmedi.services.support import (
    dedupe_sources,
    guarded_json,
    research,
    safe_audit,
    str_list,
)

logger = logging.getLogger(__name__)

LABEL_EXCERPT_CHARS = 1500

SAFE_SUMMARY = {
    "en": "Please ask your pharmacist or doctor how to use this medicine safely.",
    "hi": "इस दवा को सुरक्षित तरीके से कैसे लें, यह अपने फार्मासिस्ट या डॉक्टर से पूछें।",
    "mr": "हे औषध सुरक्षितपणे कसे घ्यावे हे तुमच्या फार्मासिस्ट किंवा डॉक्टरांना विचारा.",
}


def _opt_str(value: Any, limit: int) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text[:limit] if text and text.lower() != "null" else None


def parse_candidates(data: dict[str, Any]) -> list[MedicineCandidate]:
    out: list[MedicineCandidate] = []
    for raw in data.get("candidates") or []:
        if not isinstance(raw, dict):
            continue
        salts = []
        for s in raw.get("salts") or []:
            if isinstance(s, dict) and (name := _opt_str(s.get("name"), 120)):
                salts.append({"name": name, "strength": _opt_str(s.get("strength"), 60)})
        brand = _opt_str(raw.get("brand"), 200)
        if not brand and not salts:
            continue
        try:
            confidence = max(0.0, min(1.0, float(raw.get("confidence") or 0.0)))
        except (TypeError, ValueError):
            confidence = 0.0
        out.append(
            MedicineCandidate(
                brand=brand,
                salts=salts,
                form=_opt_str(raw.get("form"), 40),
                manufacturer=_opt_str(raw.get("manufacturer"), 200),
                confidence=round(confidence, 2),
            )
        )
    return out[:3]


def label_excerpt(label: DrugLabel | None) -> str:
    if not label:
        return ""
    parts = [
        f"Indications: {label.indications[:LABEL_EXCERPT_CHARS]}",
        f"Warnings: {label.warnings[:LABEL_EXCERPT_CHARS]}",
        f"Interactions: {label.interactions[:600]}",
        f"Contraindications: {label.contraindications[:600]}",
    ]
    return "\n".join(p for p in parts if not p.endswith(": "))


class MedicineService:
    def __init__(
        self,
        *,
        reader: DocumentReader,
        labels: DrugLabelSource,
        search: WebSearch,
        llm: LLMProvider,
        guard: OutputGuard,
        repo: MedicineRepository,
        profiles: ProfileRepository,
        audit: AuditLogger,
    ) -> None:
        self._reader = reader
        self._labels = labels
        self._search = search
        self._llm = llm
        self._guard = guard
        self._repo = repo
        self._profiles = profiles
        self._audit = audit

    async def scan(self, user_id: str, image: bytes, mime_type: str) -> dict[str, Any]:
        try:
            data = await self._reader.read_json(prompts.MEDICINE_SCAN_PROMPT, image, mime_type)
        except VisionUnavailable as exc:
            raise UpstreamUnavailable("llm_unavailable") from exc
        except UnreadableDocument as exc:
            raise Unprocessable("unreadable_image") from exc
        candidates = parse_candidates(data)
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=user_id, type="medicine_scan", payload={"candidates": len(candidates)}
            ),
        )
        if not candidates:
            raise Unprocessable("unreadable_image")
        return {"candidates": [c.to_dict() for c in candidates]}

    async def lookup(
        self, user_id: str, name: str, brand: str | None, language: str
    ) -> dict[str, Any]:
        name = name.strip()
        try:
            label = await self._labels.find_label(name)
        except DrugLabelUnavailable:
            logger.warning("openFDA unavailable; continuing with web search only")
            label = None

        grounded = await research(
            self._search, prompts.medicine_research_question(name, brand), [name]
        )
        data, violations, result = await guarded_json(
            self._llm,
            self._guard,
            "respond",
            prompts.medicine_summary_messages(
                name=name,
                brand=brand,
                label_text=label_excerpt(label),
                research=grounded.text,
                language=language,
            ),
        )
        if data is None:
            info = {
                "uses": [],
                "warnings": [],
                "summary": SAFE_SUMMARY.get(language, SAFE_SUMMARY["en"]),
            }
        else:
            info = {
                "uses": str_list(data.get("uses"), 5),
                "warnings": str_list(data.get("warnings"), 6),
                "summary": str(data.get("summary") or "").strip()[:1200]
                or SAFE_SUMMARY.get(language, SAFE_SUMMARY["en"]),
            }

        salts = self._salts(name, label)
        profile = await self._profile(user_id)
        flags = pharmacist_flags(
            profile, label=label, salts=[s["name"] for s in salts] + [name], language=language
        )
        sources: list[Source] = ([label.source] if label else []) + grounded.sources
        sources = dedupe_sources(sources)

        await self._repo.save_lookup(
            user_id,
            language=language,
            query=name[:200],
            brand=brand,
            salts=salts,
            info=info,
            flags=flags,
            sources=sources,
        )
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=user_id,
                type="medicine_lookup",
                payload={
                    "label_found": label is not None,
                    "sources": len(sources),
                    "flags": len(flags),
                    "guard_violations": violations,
                },
                model=result.model,
                latency_ms=result.latency_ms,
            ),
        )
        return {
            "name": name,
            "brand": brand,
            "salts": salts,
            "uses": info["uses"],
            "warnings": info["warnings"],
            "pharmacist_flags": flags,
            "summary": info["summary"],
            "sources": [s.to_dict() for s in sources],
            "disclaimer": disclaimer(language),
        }

    @staticmethod
    def _salts(name: str, label: DrugLabel | None) -> list[dict[str, Any]]:
        names = (label.substances or label.generic_names) if label else []
        if not names:
            return [{"name": name, "strength": None}]
        return [{"name": n.title(), "strength": None} for n in names[:6]]

    async def _profile(self, user_id: str) -> Profile:
        try:
            return await self._profiles.get_profile(user_id)
        except Exception:
            logger.exception("profile lookup failed")
            return Profile()
