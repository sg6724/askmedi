from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class Transcript:
    text: str
    language: str  # en | hi | mr


class VoiceFailed(Exception):
    """The speech provider rejected or failed the request."""


class SpeechToText(Protocol):
    async def transcribe(
        self, audio: bytes, filename: str, mime_type: str, language_hint: str | None
    ) -> Transcript: ...


class TextToSpeech(Protocol):
    async def speak(self, text: str, language: str) -> bytes: ...
