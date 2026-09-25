import pytest

from askmedi.safety.output_guard import OutputGuard

guard = OutputGuard()


@pytest.mark.parametrize(
    ("text", "violation"),
    [
        ("Take paracetamol 500 mg for the fever.", "dose"),
        ("Use 5ml of the syrup.", "dose"),
        ("Take 2 tablets after food.", "dose"),
        ("take it twice a day", "dose_frequency"),
        ("Repeat every 6 hours.", "dose_frequency"),
        ("You have dengue.", "diagnosis"),
        ("You are suffering from a viral infection.", "diagnosis"),
        ("You've got the flu.", "diagnosis"),
        ("There is no need to see a doctor.", "no_doctor"),
        ("You don't need to see a doctor for this.", "no_doctor"),
        ("डॉक्टर के पास जाने की ज़रूरत नहीं है।", "no_doctor"),
        ("डॉक्टरकडे जाण्याची गरज नाही.", "no_doctor"),
        ("I prescribe rest and antibiotics.", "prescription"),
        ("You should take azithromycin.", "prescription"),
        ("आपको डेंगू हो गया है", "diagnosis"),
    ],
)
def test_banned_patterns_are_caught(text, violation):
    assert violation in guard.violations({"summary": text})


@pytest.mark.parametrize(
    "text",
    [
        "If you have trouble breathing, call 112.",
        "Do you have a fever?",
        "Drink plenty of fluids and rest.",
        "See a doctor within 24 hours if it gets worse.",
        "Possible causes include a viral infection.",
        "Ask your pharmacist about a suitable fever medicine.",
        "You should take rest and drink fluids.",
        "Call 108 for an ambulance.",
        "बुखार 3 दिन से ज़्यादा रहे तो डॉक्टर को दिखाएँ।",
    ],
)
def test_safe_text_passes(text):
    assert guard.violations({"summary": text}) == []


def test_nested_structures_are_scanned():
    payload = {"causes": [{"name": "Flu", "explanation": "fine"}], "do_now": ["take 650 mg"]}
    assert guard.violations(payload) == ["dose"]


@pytest.mark.parametrize(
    "text",
    [
        "Your fasting glucose of 96 mg/dL is within the printed range.",
        "Haemoglobin is 11.2 g/dL, below the range of 12.0-15.5 g/dL.",
        "Cholesterol 180 mg / dl is normal.",
        "Vitamin B12 was 250 pg/mL.",
        "आपका हीमोग्लोबिन 11.2 g/dL है।",
    ],
)
def test_lab_concentrations_are_not_doses(text):
    assert guard.violations({"summary": text}) == []


@pytest.mark.parametrize("text", ["Take 500 mg/day", "500 mg twice", "Give 10 ml/kg"])
def test_doses_with_a_slash_are_still_caught(text):
    assert "dose" in guard.violations({"summary": text})
