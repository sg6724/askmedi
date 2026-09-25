import pytest

from askmedi.domain.common import Unprocessable
from askmedi.domain.medicine import pharmacist_flags, us_label_name
from askmedi.domain.profile import Profile
from askmedi.domain.search import UnreadableDocument
from askmedi.safety.output_guard import OutputGuard
from askmedi.services.medicine import MedicineService, parse_candidates
from tests.fakes import (
    FakeAudit,
    FakeLabels,
    FakeMedicineRepo,
    FakeProfiles,
    FakeReader,
    FakeSearch,
    ScriptedLLM,
    a_label,
)

SUMMARY = {
    "uses": ["Fever", "Mild pain"],
    "warnings": ["Can harm the liver in large amounts"],
    "summary": "Paracetamol is a common medicine for fever and pain.",
}


def test_indian_names_map_to_us_label_names():
    assert us_label_name("Paracetamol") == "acetaminophen"
    assert us_label_name("ibuprofen") == "ibuprofen"


def test_pharmacist_flags_condition_allergy_medicine_and_pregnancy():
    profile = Profile(
        conditions=["Liver disease", "Asthma"],
        allergies=["Povidone"],
        medicines=["Warfarin", "Paracetamol"],
        pregnant=True,
    )
    flags = pharmacist_flags(profile, label=a_label(), salts=["Paracetamol"], language="en")
    reasons = [f["reason"] for f in flags]
    assert "Check with your pharmacist because you listed Liver disease." in reasons
    assert not any("Asthma" in r for r in reasons)  # not mentioned on the label
    assert any("allergy to Povidone" in r for r in reasons)
    assert any("already take Warfarin" in r for r in reasons)
    assert any("already take Paracetamol" in r for r in reasons)  # same salt: double dosing
    assert any("pregnant" in r for r in reasons)


def test_pharmacist_flags_are_localised_and_empty_for_empty_profile():
    assert pharmacist_flags(Profile(), label=a_label(), salts=["x"], language="hi") == []
    flags = pharmacist_flags(
        Profile(conditions=["liver disease"]), label=a_label(), salts=[], language="hi"
    )
    assert "फार्मासिस्ट" in flags[0]["reason"]


def test_parse_candidates_clamps_and_skips_empty():
    out = parse_candidates(
        {
            "candidates": [
                {
                    "brand": "Crocin 500",
                    "salts": [{"name": "Paracetamol", "strength": "500 mg"}],
                    "form": "tablet",
                    "manufacturer": "GSK",
                    "confidence": 1.7,
                },
                {"brand": None, "salts": []},
            ]
        }
    )
    assert len(out) == 1
    assert out[0].to_dict()["confidence"] == 1.0
    assert out[0].salts == [{"name": "Paracetamol", "strength": "500 mg"}]


def make(reader=None, label=None, llm=None, profile=None, repo=None):
    return MedicineService(
        reader=reader or FakeReader(),
        labels=FakeLabels(label),
        search=FakeSearch(),
        llm=llm or ScriptedLLM({"respond": [SUMMARY]}),
        guard=OutputGuard(),
        repo=repo or FakeMedicineRepo(),
        profiles=FakeProfiles(profile or Profile()),
        audit=FakeAudit(),
    )


async def test_scan_returns_candidates():
    reader = FakeReader(
        result={
            "candidates": [
                {"brand": "Crocin 500", "salts": [{"name": "Paracetamol"}], "confidence": 0.9}
            ]
        }
    )
    out = await make(reader=reader).scan("u", b"img", "image/jpeg")
    assert out["candidates"][0]["brand"] == "Crocin 500"
    assert reader.calls[0][2] == "image/jpeg"


@pytest.mark.parametrize(
    "reader", [FakeReader(result={"candidates": []}), FakeReader(error=UnreadableDocument("x"))]
)
async def test_scan_nothing_found_is_422(reader):
    with pytest.raises(Unprocessable) as exc:
        await make(reader=reader).scan("u", b"img", "image/png")
    assert exc.value.code == "unreadable_image"


async def test_lookup_combines_label_search_and_flags_and_persists():
    repo = FakeMedicineRepo()
    service = make(label=a_label(), profile=Profile(conditions=["liver disease"]), repo=repo)
    out = await service.lookup("u", "Paracetamol", "Crocin 500", "en")
    assert out["name"] == "Paracetamol" and out["brand"] == "Crocin 500"
    assert out["salts"] == [{"name": "Acetaminophen", "strength": None}]
    assert out["uses"] == SUMMARY["uses"]
    assert out["pharmacist_flags"][0]["reason"].endswith("liver disease.")
    urls = [s["url"] for s in out["sources"]]
    assert urls[0].startswith("https://dailymed.nlm.nih.gov/") and len(urls) == 2
    assert out["disclaimer"]
    assert repo.saved[0]["query"] == "Paracetamol"


async def test_lookup_strips_unsafe_summary():
    unsafe = {**SUMMARY, "summary": "Take 500 mg every 6 hours."}
    service = make(llm=ScriptedLLM({"respond": [unsafe, unsafe]}))
    out = await service.lookup("u", "Paracetamol", None, "en")
    assert "500" not in out["summary"]
    assert out["uses"] == []
