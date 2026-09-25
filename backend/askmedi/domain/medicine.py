"""Medicine lookups: ports plus deterministic pharmacist checks (no LLM involved)."""

import re
from dataclasses import dataclass, field
from typing import Any, Protocol

from askmedi.domain.common import Source
from askmedi.domain.profile import Profile

# Indian (INN/BAN) names that US labels (openFDA) list under a different name.
US_NAME_SYNONYMS: dict[str, str] = {
    "paracetamol": "acetaminophen",
    "salbutamol": "albuterol",
    "adrenaline": "epinephrine",
    "noradrenaline": "norepinephrine",
    "frusemide": "furosemide",
    "glibenclamide": "glyburide",
    "lignocaine": "lidocaine",
    "pethidine": "meperidine",
    "levosalbutamol": "levalbuterol",
    "rifampicin": "rifampin",
    "cyclosporin": "cyclosporine",
    "amoxycillin": "amoxicillin",
    "phenobarbitone": "phenobarbital",
}


def us_label_name(name: str) -> str:
    key = name.strip().lower()
    return US_NAME_SYNONYMS.get(key, key)


@dataclass(frozen=True)
class DrugLabel:
    generic_names: list[str]
    brand_names: list[str]
    substances: list[str]
    indications: str
    warnings: str  # warnings + boxed warning + do-not-use + ask-a-doctor, joined
    interactions: str
    contraindications: str
    pregnancy: str
    inactive_ingredients: str
    source: Source

    @property
    def safety_text(self) -> str:
        parts = (self.warnings, self.interactions, self.contraindications, self.pregnancy)
        return " ".join(parts).lower()


class DrugLabelSource(Protocol):
    async def find_label(self, name: str) -> DrugLabel | None: ...


class DrugLabelUnavailable(Exception):
    pass


_GENERIC_WORDS = {
    "disease",
    "diseases",
    "disorder",
    "problem",
    "problems",
    "chronic",
    "acute",
    "high",
    "low",
    "severe",
    "mild",
    "type",
    "condition",
    "history",
    "failure",
    "issues",
    "and",
    "with",
    "the",
    "of",
    "blood",
    "pressure",
}

# Everyday names -> words that appear on labels.
_CONDITION_ALIASES: dict[str, list[str]] = {
    "bp": ["high blood pressure", "hypertension"],
    "high bp": ["high blood pressure", "hypertension"],
    "hypertension": ["high blood pressure", "hypertension"],
    "high blood pressure": ["high blood pressure", "hypertension"],
    "sugar": ["diabetes"],
    "diabetes": ["diabetes", "diabetic"],
    "asthma": ["asthma"],
    "liver": ["liver"],
    "kidney": ["kidney", "renal"],
    "ulcer": ["ulcer", "bleeding"],
    "heart": ["heart"],
    "thyroid": ["thyroid"],
}

_REASONS: dict[str, dict[str, str]] = {
    "condition": {
        "en": "Check with your pharmacist because you listed {x}.",
        "hi": "अपने फार्मासिस्ट से पूछें, क्योंकि आपने {x} बताया है।",
        "mr": "तुमच्या फार्मासिस्टला विचारा, कारण तुम्ही {x} नमूद केले आहे.",
    },
    "allergy": {
        "en": "Check with your pharmacist because you listed an allergy to {x}.",
        "hi": "अपने फार्मासिस्ट से पूछें, क्योंकि आपने {x} से एलर्जी बताई है।",
        "mr": "तुमच्या फार्मासिस्टला विचारा, कारण तुम्ही {x} ची ॲलर्जी नमूद केली आहे.",
    },
    "medicine": {
        "en": "Check with your pharmacist because you already take {x}.",
        "hi": "अपने फार्मासिस्ट से पूछें, क्योंकि आप पहले से {x} लेते हैं।",
        "mr": "तुमच्या फार्मासिस्टला विचारा, कारण तुम्ही आधीच {x} घेता.",
    },
    "pregnancy": {
        "en": "Check with your pharmacist or doctor because you are pregnant.",
        "hi": "अपने फार्मासिस्ट या डॉक्टर से पूछें, क्योंकि आप गर्भवती हैं।",
        "mr": "तुमच्या फार्मासिस्ट किंवा डॉक्टरांना विचारा, कारण तुम्ही गर्भवती आहात.",
    },
}


def _reason(kind: str, language: str, x: str = "") -> str:
    templates = _REASONS[kind]
    return templates.get(language, templates["en"]).format(x=x)


def _terms_for(text: str) -> list[str]:
    key = text.strip().lower()
    if key in _CONDITION_ALIASES:
        return _CONDITION_ALIASES[key]
    words = [w for w in re.findall(r"[a-z]+", key) if len(w) >= 4 and w not in _GENERIC_WORDS]
    return [key, *words] if key else words


def _mentions(haystack: str, term: str) -> bool:
    return bool(term) and re.search(rf"\b{re.escape(term)}", haystack) is not None


def pharmacist_flags(
    profile: Profile,
    *,
    label: DrugLabel | None,
    salts: list[str],
    language: str,
) -> list[dict[str, str]]:
    """Deterministic profile checks against the label text. Returns [{"reason": ...}]."""
    flags: list[str] = []
    salt_names = {us_label_name(s) for s in salts if s} | {s.strip().lower() for s in salts if s}
    if label:
        salt_names |= {n.lower() for n in label.generic_names + label.substances}
    safety = label.safety_text if label else ""
    ingredients = (label.inactive_ingredients.lower() if label else "") + " " + " ".join(salt_names)

    for condition in profile.conditions:
        if safety and any(_mentions(safety, t) for t in _terms_for(condition)):
            flags.append(_reason("condition", language, condition))

    for allergy in profile.allergies:
        terms = _terms_for(allergy)
        if any(_mentions(ingredients, t) for t in terms) or any(
            _mentions(safety, f"allergic to {t}") for t in terms
        ):
            flags.append(_reason("allergy", language, allergy))

    for med in profile.medicines:
        med_key = med.strip().lower()
        same_salt = med_key in salt_names or us_label_name(med_key) in salt_names
        interacts = bool(safety) and (
            _mentions(safety, med_key) or _mentions(safety, us_label_name(med_key))
        )
        if same_salt or interacts:
            flags.append(_reason("medicine", language, med))

    if profile.pregnant and (not label or "pregnan" in safety):
        flags.append(_reason("pregnancy", language))

    return [{"reason": r} for r in dict.fromkeys(flags)]


class MedicineRepository(Protocol):
    async def save_lookup(
        self,
        user_id: str,
        *,
        language: str,
        query: str,
        brand: str | None,
        salts: list[dict[str, Any]],
        info: dict[str, Any],
        flags: list[dict[str, str]],
        sources: list[Source],
    ) -> str: ...


@dataclass(frozen=True)
class MedicineCandidate:
    brand: str | None
    salts: list[dict[str, str | None]] = field(default_factory=list)
    form: str | None = None
    manufacturer: str | None = None
    confidence: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "brand": self.brand,
            "salts": self.salts,
            "form": self.form,
            "manufacturer": self.manufacturer,
            "confidence": self.confidence,
        }
