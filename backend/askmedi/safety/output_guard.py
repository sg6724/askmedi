"""Blocks unsafe wording in model output: doses, diagnoses, prescriptions, false reassurance."""

import re
from collections.abc import Iterable
from typing import Any

_UNITS = (
    r"(?:mg|mcg|µg|μg|g|gm|gms|ml|iu|units?|tablets?|tabs?|capsules?|caps?|pills?|drops?|puffs?"
    r"|मिग्रा|एमजी|गोली|गोलियां|गोलियाँ|गोळी|गोळ्या)"
)

BANNED_PATTERNS: dict[str, re.Pattern[str]] = {
    "dose": re.compile(rf"(?<![\w.])\d+(?:[.,]\d+)?\s*{_UNITS}(?![a-z])", re.IGNORECASE),
    "dose_frequency": re.compile(
        r"\b(?:once|twice|thrice|\d+\s*times)\s+(?:a|per)\s+day\b"
        r"|\bevery\s+\d+\s*(?:hours?|hrs?)\b",
        re.IGNORECASE,
    ),
    "diagnosis": re.compile(
        # "you have X" as a statement; conditionals and questions ("if you have...",
        # "do you have...") are fine.
        r"(?<!if )(?<!when )(?<!do )(?<!whether )(?<!unless )(?<!since )(?<!as )(?<!that )"
        r"\byou\s+(?:definitely\s+|surely\s+|certainly\s+|probably\s+|clearly\s+)?"
        r"(?:have|are\s+suffering\s+from|suffer\s+from)\s+(?:a\s+|an\s+)?"
        r"(?!to\b|been\b|had\b|taken\b|any\b|a\s+doctor|questions?\b|the\s+right\b|other\b)\w+"
        r"|\byou(?:'ve|\s+have)\s+got\s+(?:a\s+|an\s+)?\w+|\byour\s+diagnosis\s+is\b"
        r"|आपको\s+\S+(?:\s+\S+)?\s+(?:हो\s+गया\s+है|ही\s+है)"
        r"|तुम्हाला\s+\S+(?:\s+\S+)?\s+झाला\s+आहे",
        re.IGNORECASE,
    ),
    "no_doctor": re.compile(
        r"\b(?:no|don'?t|do\s+not|doesn'?t|does\s+not|won'?t|will\s+not)\s+need\s+(?:to\s+)?"
        r"(?:see|visit|consult)\s+(?:a\s+|the\s+|your\s+)?doctor\b"
        r"|\bno\s+need\s+(?:for|of)\s+(?:a\s+)?doctor\b"
        r"|डॉक्टर\s+(?:के\s+पास\s+जाने\s+|को\s+दिखाने\s+)?की\s+(?:कोई\s+)?"
        r"(?:ज़रूरत|जरूरत|आवश्यकता)\s+नहीं"
        r"|डॉक्टरकडे\s+जाण्याची\s+(?:काही\s+)?(?:गरज|आवश्यकता)\s+नाही",
        re.IGNORECASE,
    ),
    "prescription": re.compile(
        r"\b(?:i\s+(?:prescribe|recommend\s+taking)|prescrib(?:e|ing)\s+you"
        r"|you\s+should\s+take\s+(?!rest|care|fluids|plenty|a\s+rest)\w+"
        r"|take\s+(?:a|one|two|\d+)\s+(?:tablet|pill|capsule|dose)s?)\b",
        re.IGNORECASE,
    ),
}


def _texts(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for v in value.values():
            yield from _texts(v)
    elif isinstance(value, list | tuple):
        for v in value:
            yield from _texts(v)


class OutputGuard:
    def violations(self, payload: Any) -> list[str]:
        """Names of the banned patterns found anywhere in the strings of `payload`."""
        found: list[str] = []
        for text in _texts(payload):
            for name, pattern in BANNED_PATTERNS.items():
                if name not in found and pattern.search(text):
                    found.append(name)
        return found
