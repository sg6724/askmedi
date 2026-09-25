"""Deterministic red-flag detection. Never calls an LLM; runs before anything else."""

import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from askmedi.domain.common import Source

DEFAULT_RULES_PATH = Path(__file__).resolve().parent / "rules" / "v1.yaml"

ACTION_NUMBERS: dict[str, list[str]] = {
    "emergency_112": ["112", "108"],
    "emergency_108": ["108", "112"],
}

# Apostrophes are removed (so "can't" == "cant"); other punctuation becomes a space.
_APOSTROPHES = re.compile("['’‘`]")
_PUNCT = re.compile(r"[^\wऀ-ॿ\s]|_")
_SPACES = re.compile(r"\s+")
# Spelling variants that should not change a match: nukta, chandrabindu vs anusvara,
# zero-width joiners, and the Devanagari full stops.
_DEVANAGARI_FOLD = str.maketrans({"़": None, "ँ": "ं", "‌": None, "‍": None, "।": " ", "॥": " "})


def normalise_text(text: str) -> str:
    text = unicodedata.normalize("NFKC", text).lower().translate(_DEVANAGARI_FOLD)
    text = _APOSTROPHES.sub("", text)
    text = _PUNCT.sub(" ", text)
    return _SPACES.sub(" ", text).strip()


@dataclass(frozen=True)
class _Phrase:
    text: str  # normalised
    prefix: bool

    def found_in(self, padded: str) -> bool:
        if not self.text:
            return False
        if self.prefix:
            return f" {self.text}" in padded
        return f" {self.text} " in padded


def _phrase(raw: Any) -> _Phrase:
    raw = str(raw).strip()
    prefix = raw.endswith("*")
    return _Phrase(normalise_text(raw.rstrip("*")), prefix)


@dataclass(frozen=True)
class RedFlagRule:
    id: str
    action: str
    source: Source
    reason: dict[str, str]
    keywords: tuple[_Phrase, ...]
    combos: tuple[tuple[tuple[_Phrase, ...], ...], ...]
    helplines: tuple[str, ...] = ()

    def matches(self, padded: str) -> bool:
        if any(p.found_in(padded) for p in self.keywords):
            return True
        return any(
            all(any(p.found_in(padded) for p in group) for group in combo) for combo in self.combos
        )

    @property
    def call_numbers(self) -> list[str]:
        return list(dict.fromkeys([*self.helplines, *ACTION_NUMBERS[self.action]]))


@dataclass(frozen=True)
class RedFlagMatch:
    rule_id: str
    reason: str
    call: list[str]
    source: Source
    message: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "rule_id": self.rule_id,
            "reason": self.reason,
            "call": self.call,
            "source": self.source.to_dict(),
        }


class RedFlagEngine:
    def __init__(self, rules: list[RedFlagRule], messages: dict[str, str], version: int) -> None:
        self.rules = rules
        self.messages = messages
        self.version = version

    @classmethod
    def from_yaml(cls, path: str | Path = DEFAULT_RULES_PATH) -> "RedFlagEngine":
        data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
        rules: list[RedFlagRule] = []
        for raw in data["rules"]:
            rule_id = raw.get("id")
            if raw.get("action") not in ACTION_NUMBERS:
                raise ValueError(f"rule {rule_id}: unknown action {raw.get('action')!r}")
            src = raw.get("source") or {}
            if not src.get("title") or not str(src.get("url", "")).startswith("https://"):
                raise ValueError(f"rule {rule_id}: a source with a title and https url is required")
            keywords = tuple(
                _phrase(k) for lang_list in (raw.get("keywords") or {}).values() for k in lang_list
            )
            combos = tuple(
                tuple(tuple(_phrase(k) for k in group) for group in combo)
                for combo in raw.get("combos") or []
            )
            rules.append(
                RedFlagRule(
                    id=rule_id,
                    action=raw["action"],
                    source=Source(title=src["title"], url=src["url"]),
                    reason=dict(raw["reason"]),
                    keywords=keywords,
                    combos=combos,
                    helplines=tuple(str(h) for h in raw.get("helplines") or []),
                )
            )
        return cls(rules, dict(data["messages"]), int(data["version"]))

    def check(self, text: str, language: str = "en") -> RedFlagMatch | None:
        padded = f" {normalise_text(text)} "
        for rule in self.rules:
            if rule.matches(padded):
                call = rule.call_numbers
                reason = rule.reason.get(language) or rule.reason["en"]
                template = self.messages.get(language) or self.messages["en"]
                message = f"{reason} {template.format(numbers=' / '.join(call))}"
                return RedFlagMatch(rule.id, reason, call, rule.source, message)
        return None
