"""Lab reports: the model extracts, the code computes status, the user confirms."""

from typing import Any

from askmedi.domain.audit import AuditEvent, AuditLogger
from askmedi.domain.common import NotFound, Unprocessable, UpstreamUnavailable, disclaimer
from askmedi.domain.llm import LLMProvider
from askmedi.domain.reports import (
    LabValue,
    ReportRepository,
    normalise_value,
    parse_report_date,
)
from askmedi.domain.search import (
    DocumentReader,
    UnreadableDocument,
    VisionUnavailable,
    WebSearch,
)
from askmedi.safety.output_guard import OutputGuard
from askmedi.services import prompts
from askmedi.services.support import dedupe_sources, guarded_json, research, safe_audit, str_list

MAX_VALUES = 80

SAFE_SUMMARY = {
    "en": "Please go through these results with your doctor.",
    "hi": "कृपया इन नतीजों को अपने डॉक्टर के साथ देखें।",
    "mr": "कृपया हे निकाल तुमच्या डॉक्टरांसोबत पाहा.",
}


def normalise_values(raw_values: Any) -> list[LabValue]:
    if not isinstance(raw_values, list):
        return []
    values = [normalise_value(v) for v in raw_values if isinstance(v, dict)]
    return [v for v in values if v is not None][:MAX_VALUES]


def values_text(values: list[LabValue]) -> str:
    lines = []
    for v in values:
        rng = v.ref_text or (
            f"{v.ref_low if v.ref_low is not None else ''}-{v.ref_high if v.ref_high is not None else ''}"
        )
        value = "unreadable" if v.value is None else f"{v.value:g}"
        lines.append(f"- {v.test_name}: {value} {v.unit or ''} (range {rng}) -> {v.status}")
    return "\n".join(lines)


class ReportService:
    def __init__(
        self,
        *,
        reader: DocumentReader,
        search: WebSearch,
        llm: LLMProvider,
        guard: OutputGuard,
        repo: ReportRepository,
        audit: AuditLogger,
    ) -> None:
        self._reader = reader
        self._search = search
        self._llm = llm
        self._guard = guard
        self._repo = repo
        self._audit = audit

    async def parse(self, user_id: str, data: bytes, mime_type: str) -> dict[str, Any]:
        # The file is only passed to the vision model; it is never stored.
        try:
            parsed = await self._reader.read_json(prompts.REPORT_PARSE_PROMPT, data, mime_type)
        except VisionUnavailable as exc:
            raise UpstreamUnavailable("llm_unavailable") from exc
        except UnreadableDocument as exc:
            raise Unprocessable("unreadable_report") from exc
        values = normalise_values(parsed.get("values"))
        if not values:
            raise Unprocessable("unreadable_report")
        report_date = parse_report_date(parsed.get("report_date"))
        lab = str(parsed.get("lab") or "").strip()[:200] or None
        report_id = await self._repo.create_draft(user_id, report_date, lab, values)
        await safe_audit(
            self._audit,
            AuditEvent(user_id=user_id, type="report_parse", payload={"values": len(values)}),
        )
        return {
            "report_id": report_id,
            "report_date": report_date.isoformat() if report_date else None,
            "lab": lab,
            "values": [v.to_dict() for v in values],
        }

    async def confirm(
        self, user_id: str, report_id: str, raw_values: list[dict[str, Any]], language: str
    ) -> dict[str, Any]:
        report = await self._repo.get(user_id, report_id)
        if report is None:
            raise NotFound("report_not_found")
        values = normalise_values(raw_values)
        text = values_text(values)

        flagged = [v.test_name for v in values if v.status in ("low", "high")]
        grounded = await research(
            self._search,
            prompts.report_research_question(text),
            [f"{name} test" for name in (flagged or [v.test_name for v in values])[:3]],
        )
        data, violations, result = await guarded_json(
            self._llm,
            self._guard,
            "respond",
            prompts.report_summary_messages(
                values_text=text, research=grounded.text, language=language
            ),
        )
        fallback = SAFE_SUMMARY.get(language, SAFE_SUMMARY["en"])
        summary = str((data or {}).get("summary") or "").strip()[:1500] or fallback
        highlights = str_list((data or {}).get("highlights"), 5)
        sources = dedupe_sources(grounded.sources)

        await self._repo.confirm(
            user_id,
            report_id,
            values,
            {"summary": summary, "highlights": highlights, "language": language},
            language,
            sources,
        )
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=user_id,
                type="report_confirm",
                payload={
                    "values": len(values),
                    "out_of_range": sum(v.status in ("low", "high") for v in values),
                    "sources": len(sources),
                    "guard_violations": violations,
                },
                model=result.model,
                latency_ms=result.latency_ms,
            ),
        )
        return {
            "report_id": report_id,
            "summary": summary,
            "highlights": highlights,
            "values": [v.to_dict() for v in values],
            "sources": [s.to_dict() for s in sources],
            "disclaimer": disclaimer(language),
        }
