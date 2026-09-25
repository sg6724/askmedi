"""Shared value objects used across features."""

from dataclasses import dataclass
from typing import Literal

Language = Literal["en", "hi", "mr"]
LANGUAGES: tuple[str, ...] = ("en", "hi", "mr")

Urgency = Literal["emergency", "see_doctor_today", "see_doctor_soon", "self_care"]
# Least to most urgent. Used to make sure urgency is only ever raised.
URGENCY_ORDER: tuple[str, ...] = ("self_care", "see_doctor_soon", "see_doctor_today", "emergency")

Likelihood = Literal["more_likely", "possible", "less_likely"]
LIKELIHOODS: tuple[str, ...] = ("more_likely", "possible", "less_likely")

DISCLAIMERS: dict[str, str] = {
    "en": "AskMedi gives health information, not a diagnosis. Please consult a doctor.",
    "hi": "AskMedi स्वास्थ्य जानकारी देता है, निदान नहीं। कृपया डॉक्टर से सलाह लें।",
    "mr": "AskMedi आरोग्यविषयक माहिती देते, निदान नाही. कृपया डॉक्टरांचा सल्ला घ्या.",
}


def disclaimer(language: str) -> str:
    return DISCLAIMERS.get(language, DISCLAIMERS["en"])


@dataclass(frozen=True)
class Source:
    title: str
    url: str

    def to_dict(self) -> dict[str, str]:
        return {"title": self.title, "url": self.url}


def raise_urgency(*levels: str | None) -> str:
    """Most urgent of the given levels; unknown/None values are ignored.

    Falls back to see_doctor_soon when nothing valid is given (never self_care by default).
    """
    valid = [lvl for lvl in levels if lvl in URGENCY_ORDER]
    if not valid:
        return "see_doctor_soon"
    return max(valid, key=URGENCY_ORDER.index)


def bump_urgency(level: str) -> str:
    """One step more urgent for uncertainty, capped at see_doctor_today.

    Only a red-flag rule or the model's own assessment can make something an emergency.
    """
    if level == "emergency":
        return level
    idx = URGENCY_ORDER.index(level) if level in URGENCY_ORDER else 1
    return URGENCY_ORDER[min(idx + 1, URGENCY_ORDER.index("see_doctor_today"))]


class ServiceError(Exception):
    """Base for errors that map to an HTTP status and a `{"detail": code}` body."""

    status_code: int = 500
    code: str = "internal_error"

    def __init__(self, code: str | None = None, status_code: int | None = None) -> None:
        if code is not None:
            self.code = code
        if status_code is not None:
            self.status_code = status_code
        super().__init__(self.code)


class NotFound(ServiceError):
    status_code = 404


class Unprocessable(ServiceError):
    status_code = 422


class UpstreamUnavailable(ServiceError):
    status_code = 503
