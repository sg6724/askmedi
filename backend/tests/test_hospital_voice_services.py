import pytest

from askmedi.domain.common import NotFound, UpstreamUnavailable
from askmedi.domain.geo import Place
from askmedi.services.hospitals import DirectoryError, HospitalService
from askmedi.services.voice import VoiceService
from tests.fakes import FakeAudit, FakeGeo, FakeVoice


async def test_hospital_search_by_pincode_sorted_and_logged_with_rounded_coords():
    geo = FakeGeo(places=[Place("B", 18.54, 73.86), Place("A", 18.521, 73.861)])
    audit = FakeAudit()
    out = await HospitalService(geocoder=geo, places=geo, audit=audit).search(
        "u", pincode="411001", radius_km=5
    )
    assert out["location"] == {"lat": 18.52, "lng": 73.86, "label": "Pune 411001"}
    assert [h["name"] for h in out["hospitals"]] == ["A", "B"]
    assert geo.radius_seen == [5000]
    payload = audit.events[0].payload
    assert payload["lat"] == 18.52 and payload["by"] == "pincode"


async def test_hospital_search_by_coords_uses_reverse_label():
    geo = FakeGeo()
    out = await HospitalService(geocoder=geo, places=geo, audit=FakeAudit()).search(
        "u", lat=18.5204123, lng=73.8567456
    )
    assert out["location"]["label"] == "Shivajinagar, Pune"
    assert out["location"]["lat"] == 18.5204123


async def test_hospital_location_not_found():
    geo = FakeGeo(point=None)
    with pytest.raises(NotFound) as exc:
        await HospitalService(geocoder=geo, places=geo, audit=FakeAudit()).search("u", q="zzz")
    assert exc.value.code == "location_not_found"


async def test_hospital_directory_down_is_502():
    geo = FakeGeo(fail=True)
    with pytest.raises(DirectoryError) as exc:
        await HospitalService(geocoder=geo, places=geo, audit=FakeAudit()).search("u", q="Pune")
    assert (exc.value.status_code, exc.value.code) == (502, "directory_unavailable")


async def test_voice_unavailable_without_key():
    service = VoiceService(stt=None, tts=None, audit=FakeAudit())
    with pytest.raises(UpstreamUnavailable) as exc:
        await service.speak("u", "hello", "en")
    assert exc.value.code == "voice_unavailable"


async def test_voice_round_trip():
    voice = FakeVoice()
    service = VoiceService(stt=voice, tts=voice, audit=FakeAudit())
    assert await service.transcribe("u", b"a", "a.webm", "audio/webm") == {
        "text": "mujhe bukhar hai",
        "language": "hi",
    }
    assert await service.speak("u", "नमस्ते", "mr") == b"ID3fake-mp3"
