"""Router tests: auth, validation and happy paths, with fake services behind the container."""

import uuid

import pytest
from fastapi.testclient import TestClient

from askmedi.domain.common import NotFound, UpstreamUnavailable
from askmedi.main import create_app
from askmedi.services.hospitals import DirectoryError
from askmedi.services.voice import VoiceService
from tests.fakes import FakeAudit, FakeVoice

AUTH = {"Authorization": "Bearer good-token"}
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 32


class Recorder:
    """A fake service: records calls and returns (or raises) a canned result."""

    def __init__(self, result=None, error=None):
        self.result, self.error, self.calls = result, error, []

    async def _run(self, name, *args, **kwargs):
        self.calls.append((name, args, kwargs))
        if self.error:
            raise self.error
        return self.result

    async def handle(self, *a, **k):
        return await self._run("handle", *a, **k)

    async def scan(self, *a, **k):
        return await self._run("scan", *a, **k)

    async def lookup(self, *a, **k):
        return await self._run("lookup", *a, **k)

    async def parse(self, *a, **k):
        return await self._run("parse", *a, **k)

    async def confirm(self, *a, **k):
        return await self._run("confirm", *a, **k)

    async def search(self, *a, **k):
        return await self._run("search", *a, **k)


@pytest.fixture
def make_client(fake_container):
    def _make(**services):
        for name, service in services.items():
            setattr(fake_container, name, service)
        return TestClient(create_app(fake_container))

    return _make


ENDPOINTS = [
    ("post", "/chat", {"json": {"message": "hi"}}),
    ("post", "/medicine/scan", {"files": {"image": ("a.png", PNG, "image/png")}}),
    ("post", "/medicine/lookup", {"json": {"name": "Paracetamol"}}),
    ("post", "/reports/parse", {"files": {"file": ("a.png", PNG, "image/png")}}),
    ("post", f"/reports/{uuid.uuid4()}/confirm", {"json": {"values": [{"test_name": "Hb"}]}}),
    ("get", "/hospitals?pincode=411001", {}),
    (
        "post",
        "/voice/transcribe",
        {"files": {"audio": ("a.webm", b"\x1a\x45\xdf\xa3", "audio/webm")}},
    ),
    ("post", "/voice/speak", {"json": {"text": "hi"}}),
]


@pytest.mark.parametrize(("method", "path", "kwargs"), ENDPOINTS)
def test_every_feature_endpoint_requires_auth(make_client, method, path, kwargs):
    client = make_client(
        chat=Recorder({}),
        medicine=Recorder({}),
        reports=Recorder({}),
        hospitals=Recorder({}),
        voice=VoiceService(stt=FakeVoice(), tts=FakeVoice(), audit=FakeAudit()),
    )
    assert getattr(client, method)(path, **kwargs).status_code == 401
    bad = {"Authorization": "Bearer nope"}
    assert getattr(client, method)(path, headers=bad, **kwargs).status_code == 401


# ------------------------------------------------------------------ chat


def test_chat_happy_path_passes_user_and_request(make_client):
    chat = Recorder({"episode_id": "e", "type": "followup"})
    client = make_client(chat=chat)
    eid = str(uuid.uuid4())
    r = client.post(
        "/chat",
        headers=AUTH,
        json={"episode_id": eid, "message": "  bukhar hai ", "language": "hi"},
    )
    assert r.status_code == 200 and r.json()["type"] == "followup"
    req = chat.calls[0][1][0]
    assert (req.user_id, req.episode_id, req.message, req.language) == (
        "user-1",
        eid,
        "bukhar hai",
        "hi",
    )


@pytest.mark.parametrize(
    "body",
    [
        {"message": ""},
        {"message": "   "},
        {"message": "x" * 2001},
        {"message": "hi", "language": "fr"},
        {"message": "hi", "episode_id": "not-a-uuid"},
    ],
)
def test_chat_validation(make_client, body):
    assert make_client(chat=Recorder({})).post("/chat", headers=AUTH, json=body).status_code == 422


@pytest.mark.parametrize(
    ("error", "status", "code"),
    [
        (NotFound("episode_not_found"), 404, "episode_not_found"),
        (UpstreamUnavailable("llm_unavailable"), 503, "llm_unavailable"),
    ],
)
def test_chat_errors_map_to_codes(make_client, error, status, code):
    r = make_client(chat=Recorder(error=error)).post("/chat", headers=AUTH, json={"message": "hi"})
    assert r.status_code == status and r.json() == {"detail": code}


# ------------------------------------------------------------------ medicine


def test_medicine_scan_happy_path_and_octet_stream_is_sniffed(make_client):
    med = Recorder({"candidates": []})
    client = make_client(medicine=med)
    r = client.post(
        "/medicine/scan", headers=AUTH, files={"image": ("blob", PNG, "application/octet-stream")}
    )
    assert r.status_code == 200
    assert med.calls[0][1][2] == "image/png"


def test_medicine_scan_rejects_type_and_size(make_client):
    client = make_client(medicine=Recorder({}))
    r = client.post(
        "/medicine/scan", headers=AUTH, files={"image": ("a.gif", b"GIF89a", "image/gif")}
    )
    assert r.status_code == 415 and r.json() == {"detail": "unsupported_media_type"}
    big = PNG + b"0" * (8 * 1024 * 1024)
    r = client.post("/medicine/scan", headers=AUTH, files={"image": ("a.png", big, "image/png")})
    assert r.status_code == 413 and r.json() == {"detail": "file_too_large"}


def test_medicine_lookup(make_client):
    med = Recorder({"name": "Paracetamol"})
    client = make_client(medicine=med)
    r = client.post(
        "/medicine/lookup",
        headers=AUTH,
        json={"name": "Paracetamol", "brand": "Crocin 500", "language": "mr"},
    )
    assert r.status_code == 200
    assert med.calls[0][1] == ("user-1", "Paracetamol", "Crocin 500", "mr")
    assert client.post("/medicine/lookup", headers=AUTH, json={"name": ""}).status_code == 422


# ------------------------------------------------------------------ reports


def test_reports_parse_accepts_pdf_and_rejects_text(make_client):
    rep = Recorder({"report_id": "r"})
    client = make_client(reports=rep)
    r = client.post(
        "/reports/parse", headers=AUTH, files={"file": ("r.pdf", b"%PDF-1.4 x", "application/pdf")}
    )
    assert r.status_code == 200 and rep.calls[0][1][2] == "application/pdf"
    r = client.post(
        "/reports/parse", headers=AUTH, files={"file": ("r.txt", b"hello", "text/plain")}
    )
    assert r.status_code == 415
    big = b"%PDF" + b"0" * (10 * 1024 * 1024)
    r = client.post(
        "/reports/parse", headers=AUTH, files={"file": ("r.pdf", big, "application/pdf")}
    )
    assert r.status_code == 413


def test_reports_confirm(make_client):
    rep = Recorder({"report_id": "r", "summary": "s"})
    client = make_client(reports=rep)
    rid = str(uuid.uuid4())
    body = {
        "values": [
            {
                "test_name": "Hb",
                "value": 11.2,
                "unit": "g/dL",
                "ref_low": 12,
                "ref_high": 15.5,
                "ref_text": "12-15.5",
                "status": "low",
            }
        ],
        "language": "hi",
    }
    r = client.post(f"/reports/{rid}/confirm", headers=AUTH, json=body)
    assert r.status_code == 200
    user_id, report_id, values, language = rep.calls[0][1]
    assert (user_id, report_id, language) == ("user-1", rid, "hi")
    assert values[0]["test_name"] == "Hb"
    assert client.post("/reports/nope/confirm", headers=AUTH, json=body).status_code == 422
    assert (
        client.post(f"/reports/{rid}/confirm", headers=AUTH, json={"values": []}).status_code == 422
    )


def test_reports_confirm_not_found(make_client):
    client = make_client(reports=Recorder(error=NotFound("report_not_found")))
    r = client.post(
        f"/reports/{uuid.uuid4()}/confirm", headers=AUTH, json={"values": [{"test_name": "Hb"}]}
    )
    assert r.status_code == 404 and r.json() == {"detail": "report_not_found"}


# ------------------------------------------------------------------ hospitals


def test_hospitals_happy_path(make_client):
    hosp = Recorder({"location": {}, "hospitals": []})
    client = make_client(hospitals=hosp)
    r = client.get("/hospitals?lat=18.52&lng=73.86&radius_km=10&specialty=eye", headers=AUTH)
    assert r.status_code == 200
    kwargs = hosp.calls[0][2]
    assert (kwargs["lat"], kwargs["lng"], kwargs["radius_km"], kwargs["specialty"]) == (
        18.52,
        73.86,
        10,
        "eye",
    )


@pytest.mark.parametrize(
    "query",
    [
        "",
        "?lat=18.5",
        "?pincode=12345",
        "?pincode=011001",
        "?q=Pune&radius_km=30",
        "?q=Pune&radius_km=0",
        "?lat=100&lng=0",
    ],
)
def test_hospitals_validation(make_client, query):
    assert (
        make_client(hospitals=Recorder({})).get(f"/hospitals{query}", headers=AUTH).status_code
        == 422
    )


@pytest.mark.parametrize(
    ("error", "status", "code"),
    [
        (NotFound("location_not_found"), 404, "location_not_found"),
        (DirectoryError(), 502, "directory_unavailable"),
    ],
)
def test_hospitals_errors(make_client, error, status, code):
    r = make_client(hospitals=Recorder(error=error)).get("/hospitals?q=Pune", headers=AUTH)
    assert r.status_code == status and r.json() == {"detail": code}


# ------------------------------------------------------------------ voice


def test_voice_unavailable_without_key(make_client):
    client = make_client(voice=VoiceService(stt=None, tts=None, audit=FakeAudit()))
    r = client.post("/voice/speak", headers=AUTH, json={"text": "hi"})
    assert r.status_code == 503 and r.json() == {"detail": "voice_unavailable"}
    r = client.post(
        "/voice/transcribe",
        headers=AUTH,
        files={"audio": ("a.webm", b"\x1a\x45\xdf\xa3", "audio/webm")},
    )
    assert r.status_code == 503 and r.json() == {"detail": "voice_unavailable"}


def test_voice_transcribe_and_speak(make_client):
    voice = FakeVoice()
    client = make_client(voice=VoiceService(stt=voice, tts=voice, audit=FakeAudit()))
    r = client.post(
        "/voice/transcribe",
        headers=AUTH,
        files={"audio": ("rec.m4a", b"\x00\x00\x00\x18ftypM4A ", "audio/x-m4a")},
    )
    assert r.status_code == 200 and r.json() == {"text": "mujhe bukhar hai", "language": "hi"}
    r = client.post("/voice/speak", headers=AUTH, json={"text": "नमस्ते", "language": "hi"})
    assert r.status_code == 200
    assert r.headers["content-type"] == "audio/mpeg" and r.content == b"ID3fake-mp3"


def test_voice_validation(make_client):
    voice = FakeVoice()
    client = make_client(voice=VoiceService(stt=voice, tts=voice, audit=FakeAudit()))
    assert client.post("/voice/speak", headers=AUTH, json={"text": "x" * 1501}).status_code == 422
    assert (
        client.post("/voice/speak", headers=AUTH, json={"text": "hi", "language": "ta"}).status_code
        == 422
    )
    r = client.post(
        "/voice/transcribe", headers=AUTH, files={"audio": ("a.txt", b"hello", "text/plain")}
    )
    assert r.status_code == 415
