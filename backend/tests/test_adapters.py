"""HTTP adapters against httpx.MockTransport (no network)."""

import json

import httpx
import pytest

from askmedi.adapters.elevenlabs import ElevenLabsVoice, app_language
from askmedi.adapters.gemini import GeminiClient
from askmedi.adapters.openfda import OpenFdaLabels
from askmedi.adapters.osm import OsmDirectory, overpass_query, parse_overpass
from askmedi.domain.geo import DirectoryUnavailable
from askmedi.domain.search import SearchUnavailable, UnreadableDocument
from askmedi.domain.voice import VoiceFailed

REDIRECT = "https://vertexaisearch.cloud.google.com/grounding-api-redirect/abc"


def gemini_body(text, chunks=()):
    return {
        "candidates": [
            {
                "content": {"parts": [{"text": text}]},
                "groundingMetadata": {"groundingChunks": list(chunks)},
            }
        ]
    }


async def test_gemini_research_returns_text_and_resolved_sources():
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.method == "HEAD":
            return httpx.Response(302, headers={"location": "https://medlineplus.gov/fever.html"})
        if "gemini-2.5-flash:" in request.url.path:
            return httpx.Response(500)
        body = json.loads(request.content)
        assert body["tools"] == [{"google_search": {}}]
        assert request.headers["x-goog-api-key"] == "k"
        return httpx.Response(
            200,
            json=gemini_body(
                "Fever notes",
                [
                    {"web": {"uri": REDIRECT, "title": "medlineplus.gov"}},
                    {"web": {"uri": REDIRECT, "title": "dup"}},
                    {"retrievedContext": {}},
                ],
            ),
        )

    client = GeminiClient(
        "k",
        search_models=["gemini/gemini-2.5-flash", "gemini/gemini-2.5-flash-lite"],
        vision_models=[],
        transport=httpx.MockTransport(handler),
    )
    out = await client.research("fever?")
    assert out.text == "Fever notes"
    assert [(s.title, s.url) for s in out.sources] == [
        ("medlineplus.gov", "https://medlineplus.gov/fever.html")
    ]
    assert out.model == "gemini/gemini-2.5-flash-lite"


async def test_gemini_research_all_models_fail():
    client = GeminiClient(
        "k",
        search_models=["gemini/x"],
        vision_models=[],
        transport=httpx.MockTransport(lambda r: httpx.Response(429)),
    )
    with pytest.raises(SearchUnavailable):
        await client.research("q")


async def test_gemini_read_json_sends_inline_data_and_json_mode():
    def handler(request):
        body = json.loads(request.content)
        part = body["contents"][0]["parts"][0]["inline_data"]
        assert part["mime_type"] == "application/pdf"
        assert body["generationConfig"]["responseMimeType"] == "application/json"
        return httpx.Response(200, json=gemini_body('```json\n{"values": []}\n```'))

    client = GeminiClient(
        "k",
        search_models=[],
        vision_models=["gemini/gemini-2.5-flash", "groq/qwen/x"],
        transport=httpx.MockTransport(handler),
    )
    assert await client.read_json("p", b"%PDF-1.4", "application/pdf") == {"values": []}


async def test_gemini_read_json_unparseable_is_unreadable():
    client = GeminiClient(
        "k",
        search_models=[],
        vision_models=["gemini/g"],
        transport=httpx.MockTransport(lambda r: httpx.Response(200, json=gemini_body("sorry"))),
    )
    with pytest.raises(UnreadableDocument):
        await client.read_json("p", b"x", "image/png")


FDA_RECORD = {
    "set_id": "abc-123",
    "openfda": {
        "generic_name": ["ACETAMINOPHEN"],
        "brand_name": ["Tylenol"],
        "substance_name": ["ACETAMINOPHEN"],
    },
    "indications_and_usage": ["temporarily relieves minor aches"],
    "warnings": ["Liver warning: severe liver damage may occur"],
    "ask_doctor": ["Ask a doctor before use if you have liver disease"],
}


async def test_openfda_maps_paracetamol_and_falls_through_404():
    queries = []

    def handler(request):
        queries.append(request.url.params["search"])
        if len(queries) == 1:
            return httpx.Response(404, json={"error": {"code": "NOT_FOUND"}})
        return httpx.Response(200, json={"results": [FDA_RECORD]})

    label = await OpenFdaLabels(transport=httpx.MockTransport(handler)).find_label("Paracetamol")
    assert "ACETAMINOPHEN" in queries[0]
    assert label.generic_names == ["ACETAMINOPHEN"]
    assert "liver disease" in label.safety_text
    assert label.source.url == "https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=abc-123"


async def test_openfda_nothing_found_is_none():
    labels = OpenFdaLabels(transport=httpx.MockTransport(lambda r: httpx.Response(404)))
    assert await labels.find_label("Dolo") is None


async def test_nominatim_pincode_label_and_user_agent():
    def handler(request):
        assert request.headers["user-agent"] == "AskMedi/test"
        assert request.url.params["postalcode"] == "411001"
        assert request.url.params["countrycodes"] == "in"
        return httpx.Response(
            200,
            json=[
                {
                    "lat": "18.5204",
                    "lon": "73.8567",
                    "display_name": "Pune City, Pune, Maharashtra, 411001, India",
                }
            ],
        )

    osm = OsmDirectory(user_agent="AskMedi/test", transport=httpx.MockTransport(handler))
    point = await osm.search(pincode="411001")
    assert (point.lat, point.lng, point.label) == (18.5204, 73.8567, "Pune City 411001")


async def test_nominatim_no_result_is_none_and_errors_raise():
    osm = OsmDirectory(
        user_agent="x", transport=httpx.MockTransport(lambda r: httpx.Response(200, json=[]))
    )
    assert await osm.search(q="nowhere") is None
    osm = OsmDirectory(user_agent="x", transport=httpx.MockTransport(lambda r: httpx.Response(503)))
    with pytest.raises(DirectoryUnavailable):
        await osm.search(q="Pune")


def test_parse_overpass_nodes_ways_and_tags():
    places = parse_overpass(
        {
            "elements": [
                {
                    "type": "node",
                    "lat": 18.5,
                    "lon": 73.8,
                    "tags": {
                        "amenity": "hospital",
                        "name": "Ruby Hall",
                        "emergency": "yes",
                        "phone": "+91 20 1234",
                        "addr:street": "Sassoon Road",
                        "addr:city": "Pune",
                    },
                },
                {
                    "type": "way",
                    "center": {"lat": 18.6, "lon": 73.9},
                    "tags": {"healthcare": "clinic", "name": "Care Clinic", "emergency": "no"},
                },
                {"type": "node", "lat": 1, "lon": 1, "tags": {"amenity": "clinic"}},  # no name
            ]
        }
    )
    assert [p.name for p in places] == ["Ruby Hall", "Care Clinic"]
    assert places[0].emergency is True and places[1].emergency is False
    assert places[0].address == "Sassoon Road, Pune"
    assert places[1].lat == 18.6


def test_overpass_query_mentions_hospital_clinic_and_healthcare():
    q = overpass_query(18.52, 73.86, 5000)
    assert "around:5000,18.520000,73.860000" in q
    assert "hospital|clinic" in q and '"healthcare"' in q


async def test_overpass_falls_back_to_second_mirror():
    calls = []

    def handler(request):
        calls.append(str(request.url))
        if len(calls) == 1:
            return httpx.Response(504)
        return httpx.Response(200, json={"elements": []})

    osm = OsmDirectory(
        user_agent="x",
        overpass_urls=["https://a/api", "https://b/api"],
        transport=httpx.MockTransport(handler),
    )
    assert await osm.nearby_health_places(18.5, 73.8, 5000) == []
    assert len(calls) == 2


def test_elevenlabs_language_mapping():
    assert app_language("hin") == "hi"
    assert app_language("mar") == "mr"
    assert app_language("eng") == "en"
    assert app_language("fra", "hi") == "hi"


async def test_elevenlabs_transcribe():
    def handler(request):
        assert request.url.path == "/v1/speech-to-text"
        assert request.headers["xi-api-key"] == "k"
        assert b"scribe_v1" in request.content
        return httpx.Response(200, json={"text": " mujhe bukhar hai ", "language_code": "hin"})

    voice = ElevenLabsVoice(
        "k",
        stt_model="scribe_v1",
        tts_model="eleven_v3",
        voice_id="v",
        transport=httpx.MockTransport(handler),
    )
    t = await voice.transcribe(b"audio", "a.webm", "audio/webm", None)
    assert (t.text, t.language) == ("mujhe bukhar hai", "hi")


async def test_elevenlabs_speak_retries_without_language_code():
    bodies = []

    def handler(request):
        body = json.loads(request.content)
        bodies.append(body)
        assert request.url.path == "/v1/text-to-speech/voice-1"
        if "language_code" in body:
            return httpx.Response(400)
        return httpx.Response(200, content=b"ID3mp3")

    voice = ElevenLabsVoice(
        "k",
        stt_model="s",
        tts_model="eleven_v3",
        voice_id="voice-1",
        transport=httpx.MockTransport(handler),
    )
    assert await voice.speak("नमस्कार", "mr") == b"ID3mp3"
    assert bodies[0]["language_code"] == "mr" and bodies[0]["model_id"] == "eleven_v3"


async def test_elevenlabs_error_raises_voice_failed():
    voice = ElevenLabsVoice(
        "k",
        stt_model="s",
        tts_model="t",
        voice_id="v",
        transport=httpx.MockTransport(lambda r: httpx.Response(401)),
    )
    with pytest.raises(VoiceFailed):
        await voice.speak("hi", "en")


async def test_places_fall_back_to_nominatim_when_overpass_is_down():
    def handler(request):
        if "interpreter" in request.url.path:
            return httpx.Response(504)
        assert request.url.params["bounded"] == "1"
        amenity = request.url.params["amenity"]
        return httpx.Response(
            200,
            json=[
                {
                    "name": f"A {amenity}",
                    "lat": "18.53",
                    "lon": "73.85",
                    "extratags": {"emergency": "yes", "phone": "020"},
                    "address": {"road": "FC Road", "city": "Pune"},
                }
            ],
        )

    osm = OsmDirectory(
        user_agent="x",
        overpass_urls=["https://a/api/interpreter"],
        nominatim_pause_s=0,
        transport=httpx.MockTransport(handler),
    )
    places = await osm.nearby_health_places(18.52, 73.86, 3000)
    assert [p.name for p in places] == ["A hospital", "A clinic"]
    assert places[0].emergency is True and places[0].address == "FC Road, Pune"


async def test_elevenlabs_speak_picks_the_model_for_the_language():
    models = []

    def handler(request):
        models.append(json.loads(request.content)["model_id"])
        return httpx.Response(200, content=b"ID3mp3")

    voice = ElevenLabsVoice(
        "k",
        stt_model="s",
        tts_model="eleven_v3",
        tts_models_by_language={"en": "eleven_turbo_v2_5", "hi": "eleven_turbo_v2_5"},
        voice_id="v",
        transport=httpx.MockTransport(handler),
    )
    for language in ("hi", "en", "mr"):
        await voice.speak("text", language)
    # Fast model where it supports the language; the default (Marathi-capable) otherwise.
    assert models == ["eleven_turbo_v2_5", "eleven_turbo_v2_5", "eleven_v3"]
