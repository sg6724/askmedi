"""Voice: ElevenLabs speech-to-text and text-to-speech behind ports."""

from askmedi.domain.audit import AuditEvent, AuditLogger
from askmedi.domain.common import UpstreamUnavailable
from askmedi.domain.voice import SpeechToText, TextToSpeech, VoiceFailed
from askmedi.services.support import safe_audit


class VoiceService:
    """`stt`/`tts` are None when ELEVENLABS_API_KEY is not configured -> 503 voice_unavailable."""

    def __init__(
        self, *, stt: SpeechToText | None, tts: TextToSpeech | None, audit: AuditLogger
    ) -> None:
        self._stt = stt
        self._tts = tts
        self._audit = audit

    @property
    def available(self) -> bool:
        return self._stt is not None and self._tts is not None

    def ensure_available(self) -> None:
        if not self.available:
            raise UpstreamUnavailable("voice_unavailable")

    async def transcribe(
        self,
        user_id: str,
        audio: bytes,
        filename: str,
        mime_type: str,
        language_hint: str | None = None,
    ) -> dict[str, str]:
        self.ensure_available()
        assert self._stt is not None
        try:
            transcript = await self._stt.transcribe(audio, filename, mime_type, language_hint)
        except VoiceFailed as exc:
            raise UpstreamUnavailable("voice_unavailable") from exc
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=user_id,
                type="voice_transcribe",
                payload={"language": transcript.language, "chars": len(transcript.text)},
            ),
        )
        return {"text": transcript.text, "language": transcript.language}

    async def speak(self, user_id: str, text: str, language: str) -> bytes:
        self.ensure_available()
        assert self._tts is not None
        try:
            audio = await self._tts.speak(text, language)
        except VoiceFailed as exc:
            raise UpstreamUnavailable("voice_unavailable") from exc
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=user_id,
                type="voice_speak",
                payload={"language": language, "chars": len(text)},
            ),
        )
        return audio
