"""ElevenLabs speech-to-text (Scribe) and text-to-speech. Model and voice IDs come from config."""

import logging
from collections.abc import Mapping

import httpx

from askmedi.domain.voice import Transcript, VoiceFailed

logger = logging.getLogger(__name__)

API_BASE = "https://api.elevenlabs.io/v1"

# Scribe returns ISO 639-3 codes; the app uses en | hi | mr.
_ISO3_TO_APP = {"eng": "en", "hin": "hi", "mar": "mr", "en": "en", "hi": "hi", "mr": "mr"}
_APP_TO_ISO3 = {"en": "eng", "hi": "hin", "mr": "mar"}


def app_language(code: str | None, fallback: str = "en") -> str:
    return _ISO3_TO_APP.get((code or "").lower(), fallback)


class ElevenLabsVoice:
    """Implements the SpeechToText and TextToSpeech ports."""

    def __init__(
        self,
        api_key: str,
        *,
        stt_model: str,
        tts_model: str,
        voice_id: str,
        tts_models_by_language: Mapping[str, str] | None = None,
        output_format: str = "mp3_44100_128",
        timeout_s: float = 60.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._headers = {"xi-api-key": api_key}
        self._stt_model = stt_model
        self._tts_model = tts_model
        # Per-language override: a low-latency model where it supports the language,
        # the default model (e.g. eleven_v3, the only one with Marathi) elsewhere.
        self._tts_models = dict(tts_models_by_language or {})
        self._voice_id = voice_id
        self._output_format = output_format
        self._timeout_s = timeout_s
        self._transport = transport

    def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            timeout=self._timeout_s, headers=self._headers, transport=self._transport
        )

    async def transcribe(
        self, audio: bytes, filename: str, mime_type: str, language_hint: str | None
    ) -> Transcript:
        data = {"model_id": self._stt_model, "tag_audio_events": "false"}
        if language_hint in _APP_TO_ISO3:
            data["language_code"] = _APP_TO_ISO3[language_hint]
        try:
            async with self._client() as client:
                resp = await client.post(
                    f"{API_BASE}/speech-to-text",
                    data=data,
                    files={"file": (filename or "audio", audio, mime_type)},
                )
        except httpx.HTTPError as exc:
            raise VoiceFailed(type(exc).__name__) from exc
        if resp.status_code >= 400:
            logger.warning("ElevenLabs STT HTTP %s", resp.status_code)
            raise VoiceFailed(f"stt HTTP {resp.status_code}")
        body = resp.json()
        text = str(body.get("text") or "").strip()
        return Transcript(
            text=text, language=app_language(body.get("language_code"), language_hint or "en")
        )

    async def speak(self, text: str, language: str) -> bytes:
        url = f"{API_BASE}/text-to-speech/{self._voice_id}"
        model = self._tts_models.get(language, self._tts_model)
        body = {"text": text, "model_id": model, "language_code": language}
        try:
            async with self._client() as client:
                resp = await client.post(
                    url, params={"output_format": self._output_format}, json=body
                )
                if resp.status_code in (400, 422):
                    # Some models reject language_code; retry and let the model detect it.
                    body.pop("language_code")
                    resp = await client.post(
                        url, params={"output_format": self._output_format}, json=body
                    )
        except httpx.HTTPError as exc:
            raise VoiceFailed(type(exc).__name__) from exc
        if resp.status_code >= 400:
            logger.warning("ElevenLabs TTS HTTP %s", resp.status_code)
            raise VoiceFailed(f"tts HTTP {resp.status_code}")
        return resp.content
