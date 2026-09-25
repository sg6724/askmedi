"""Lab report values. The model extracts; this code decides the status."""

import re
from dataclasses import dataclass, replace
from datetime import date
from typing import Any, Protocol

from askmedi.domain.common import Source

# "4,000" is a thousands separator; "12,5" is a decimal comma.
_NUM = r"[-+]?(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:[.,]\d+)?)"
_THOUSANDS_RE = re.compile(r"^[-+]?\d{1,3}(?:,\d{3})+(?:\.\d+)?$")
_RANGE_RE = re.compile(rf"({_NUM})\s*(?:-|–|—|to)\s*({_NUM})", re.IGNORECASE)
_UPPER_RE = re.compile(rf"(?:<=?|≤|up\s*to|upto|below|less\s+than)\s*({_NUM})", re.IGNORECASE)
_LOWER_RE = re.compile(rf"(?:>=?|≥|above|more\s+than|greater\s+than)\s*({_NUM})", re.IGNORECASE)
_VALUE_RE = re.compile(rf"^\s*({_NUM})\s*$")


@dataclass(frozen=True)
class LabValue:
    test_name: str
    value: float | None
    unit: str | None
    ref_low: float | None
    ref_high: float | None
    ref_text: str | None
    status: str = "unknown"

    def to_dict(self) -> dict[str, Any]:
        return {
            "test_name": self.test_name,
            "value": self.value,
            "unit": self.unit,
            "ref_low": self.ref_low,
            "ref_high": self.ref_high,
            "ref_text": self.ref_text,
            "status": self.status,
        }


def _num(text: str) -> float:
    text = text.strip()
    if _THOUSANDS_RE.match(text):
        return float(text.replace(",", ""))
    return float(text.replace(",", "."))


def _to_float(raw: Any) -> float | None:
    if raw is None or isinstance(raw, bool):
        return None
    if isinstance(raw, int | float):
        return float(raw)
    match = _VALUE_RE.match(str(raw))
    return _num(match.group(1)) if match else None


def parse_ref_text(ref_text: str | None) -> tuple[float | None, float | None]:
    """'12.0-15.5' -> (12.0, 15.5); '< 200' -> (None, 200); '>40' -> (40, None)."""
    if not ref_text:
        return None, None
    if m := _RANGE_RE.search(ref_text):
        low, high = _num(m.group(1)), _num(m.group(2))
        return (low, high) if low <= high else (high, low)
    if m := _UPPER_RE.search(ref_text):
        return None, _num(m.group(1))
    if m := _LOWER_RE.search(ref_text):
        return _num(m.group(1)), None
    return None, None


def compute_status(value: float | None, ref_low: float | None, ref_high: float | None) -> str:
    if value is None:
        return "unreadable"
    if ref_low is None and ref_high is None:
        return "unknown"
    if ref_low is not None and value < ref_low:
        return "low"
    if ref_high is not None and value > ref_high:
        return "high"
    return "normal"


def _clean_str(raw: Any, limit: int) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    return text[:limit] or None


def normalise_value(raw: dict[str, Any]) -> LabValue | None:
    """Builds a LabValue from model or user input; status is always recomputed here."""
    name = _clean_str(raw.get("test_name"), 120)
    if not name:
        return None
    value = _to_float(raw.get("value"))
    ref_text = _clean_str(raw.get("ref_text"), 200)
    ref_low, ref_high = _to_float(raw.get("ref_low")), _to_float(raw.get("ref_high"))
    if ref_low is None and ref_high is None:
        ref_low, ref_high = parse_ref_text(ref_text)
    if ref_low is not None and ref_high is not None and ref_low > ref_high:
        ref_low, ref_high = ref_high, ref_low
    lab = LabValue(
        test_name=name,
        value=value,
        unit=_clean_str(raw.get("unit"), 40),
        ref_low=ref_low,
        ref_high=ref_high,
        ref_text=ref_text,
    )
    return replace(lab, status=compute_status(value, ref_low, ref_high))


def parse_report_date(raw: Any) -> date | None:
    if not raw:
        return None
    try:
        return date.fromisoformat(str(raw)[:10])
    except ValueError:
        return None


@dataclass(frozen=True)
class StoredReport:
    id: str
    report_date: date | None
    lab: str | None
    status: str


class ReportRepository(Protocol):
    async def create_draft(
        self, user_id: str, report_date: date | None, lab: str | None, values: list[LabValue]
    ) -> str: ...

    async def get(self, user_id: str, report_id: str) -> StoredReport | None: ...

    async def confirm(
        self,
        user_id: str,
        report_id: str,
        values: list[LabValue],
        summary: dict[str, Any],
        language: str,
        sources: list[Source],
    ) -> str: ...
