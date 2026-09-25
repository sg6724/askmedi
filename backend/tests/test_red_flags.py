import pytest
import yaml

from askmedi.safety.red_flags import DEFAULT_RULES_PATH, RedFlagEngine, normalise_text


@pytest.fixture(scope="module")
def engine() -> RedFlagEngine:
    return RedFlagEngine.from_yaml()


FIRES = [
    # (text, language, rule_id)
    ("I have severe chest pain since morning", "en", "chest_pain"),
    ("There is a tightness in my chest.", "en", "chest_pain"),
    ("mujhe seene mein dard ho raha hai", "hi", "chest_pain"),
    ("Mujhe SEENE ME DARD hai!!", "hi", "chest_pain"),
    ("मुझे सीने में दर्द हो रहा है", "hi", "chest_pain"),
    ("माझ्या छातीत दुखत आहे", "mr", "chest_pain"),
    ("chhatit dukhat aahe", "mr", "chest_pain"),
    ("my father's face is drooping on one side", "en", "stroke_signs"),
    ("papa ka chehra tedha ho gaya", "hi", "stroke_signs"),
    ("मुँह टेढ़ा हो गया और हाथ सुन्न है", "hi", "stroke_signs"),
    ("आजोबांना बोलता येत नाही", "mr", "stroke_signs"),
    ("I can't breathe properly", "en", "breathing_difficulty"),
    ("I cannot breathe", "en", "breathing_difficulty"),
    ("saans lene mein takleef ho rahi hai", "hi", "breathing_difficulty"),
    ("मुझे सांस लेने में दिक्कत है", "hi", "breathing_difficulty"),
    ("श्वास घेता येत नाही", "mr", "breathing_difficulty"),
    ("the bleeding won't stop after the cut", "en", "severe_bleeding"),
    ("khoon ruk nahi raha", "hi", "severe_bleeding"),
    ("रक्त थांबत नाही", "mr", "severe_bleeding"),
    ("he passed out in the bathroom", "en", "unconscious_or_seizure"),
    ("bhai behosh ho gaya", "hi", "unconscious_or_seizure"),
    ("ती बेशुद्ध झाली", "mr", "unconscious_or_seizure"),
    ("my son is having a seizure", "en", "unconscious_or_seizure"),
    ("I want to kill myself", "en", "suicidal_thoughts"),
    ("main aatmahatya karna chahta hoon", "hi", "suicidal_thoughts"),
    ("मी आत्महत्या करणार आहे", "mr", "suicidal_thoughts"),
    ("मुझे जीना नहीं चाहता", "hi", "suicidal_thoughts"),
    ("she took too many pills", "en", "poisoning_overdose"),
    ("usne zeher kha liya", "hi", "poisoning_overdose"),
    ("त्याने विष घेतले", "mr", "poisoning_overdose"),
    ("my throat is swelling after eating peanuts", "en", "severe_allergic_reaction"),
    ("gale mein sujan aur khujli", "hi", "severe_allergic_reaction"),
    ("high fever and a stiff neck", "en", "fever_with_danger_signs"),
    ("tez bukhar hai aur gardan akad gayi", "hi", "fever_with_danger_signs"),
    ("खूप ताप आहे आणि मान ताठ झाली आहे", "mr", "fever_with_danger_signs"),
    ("I am pregnant and have bleeding", "en", "pregnancy_emergency"),
    ("main pregnant hoon aur khoon aa raha hai", "hi", "pregnancy_emergency"),
    ("मी गरोदर आहे आणि रक्तस्राव होत आहे", "mr", "pregnancy_emergency"),
    ("vomiting all day and I haven't urinated since morning", "en", "severe_dehydration"),
    ("dast ke baad peshab nahi aa raha", "hi", "severe_dehydration"),
    ("जुलाब झाले आणि लघवी होत नाही", "mr", "severe_dehydration"),
]

# Extra words between the body part and the symptom must not hide a red flag.
FIRES_WITH_WORDS_BETWEEN = [
    ("mujhe seene mein bahut dard ho raha hai", "hi", "chest_pain"),
    ("mere seene me subah se tez dard hai", "hi", "chest_pain"),
    ("मेरे सीने में बहुत तेज़ दर्द है", "hi", "chest_pain"),
    ("माझ्या छातीत खूप दुखत आहे", "mr", "chest_pain"),
    ("there is a heavy pain in the middle of my chest", "en", "chest_pain"),
    ("my chest feels very tight", "en", "chest_pain"),
    ("saans lene mein bahut dikkat ho rahi hai", "hi", "breathing_difficulty"),
    ("मुझे सांस लेने में बहुत तकलीफ हो रही है", "hi", "breathing_difficulty"),
    ("मला श्वास घ्यायला खूप त्रास होत आहे", "mr", "breathing_difficulty"),
]


@pytest.mark.parametrize(("text", "language", "rule_id"), FIRES_WITH_WORDS_BETWEEN)
def test_rule_fires_with_words_between(engine, text, language, rule_id):
    match = engine.check(text, language)
    assert match is not None, text
    assert match.rule_id == rule_id


DOES_NOT_FIRE = [
    ("mujhe kal se fever hai", "hi"),
    ("I have a mild headache and a runny nose", "en"),
    ("माझे डोके दुखत आहे", "mr"),
    ("पेट में हल्का दर्द है", "hi"),
    ("I had food poisoning last year, now I have a cough", "en"),
    ("my neck is stiff from sleeping badly", "en"),  # stiff neck alone, no fever
    ("I am pregnant and want to know about diet", "en"),  # pregnancy alone
    ("Vishal has a cold", "en"),  # 'vish' must match whole words only
    ("I have a chest cold and a cough", "en"),  # chest without pain words
    ("my back pain is worse today", "en"),  # pain without chest
]


@pytest.mark.parametrize(("text", "language", "rule_id"), FIRES)
def test_rule_fires(engine, text, language, rule_id):
    match = engine.check(text, language)
    assert match is not None, text
    assert match.rule_id == rule_id


@pytest.mark.parametrize(("text", "language"), DOES_NOT_FIRE)
def test_rule_does_not_fire(engine, text, language):
    assert engine.check(text, language) is None


def test_every_rule_has_source_keywords_in_all_languages():
    data = yaml.safe_load(DEFAULT_RULES_PATH.read_text(encoding="utf-8"))
    ids = {r["id"] for r in data["rules"]}
    assert {
        "chest_pain",
        "stroke_signs",
        "breathing_difficulty",
        "severe_bleeding",
        "unconscious_or_seizure",
        "suicidal_thoughts",
        "poisoning_overdose",
        "severe_allergic_reaction",
        "fever_with_danger_signs",
        "pregnancy_emergency",
        "severe_dehydration",
    } <= ids
    for rule in data["rules"]:
        assert rule["source"]["title"] and rule["source"]["url"].startswith("https://")
        assert set(rule["keywords"]) >= {"en", "hi", "mr", "romanised"}, rule["id"]
        assert set(rule["reason"]) == {"en", "hi", "mr"}, rule["id"]


def test_emergency_response_is_localised_with_numbers_and_source(engine):
    match = engine.check("seene mein dard", "hi")
    assert match.call == ["112", "108"]
    assert "112" in match.message and "कॉल" in match.message
    assert match.to_dict()["source"]["url"].startswith("https://medlineplus.gov/")


def test_suicide_rule_lists_tele_manas_first(engine):
    match = engine.check("I want to end my life", "en")
    assert match.call[0] == "14416"
    assert "112" in match.call
    assert "telemanas.mohfw.gov.in" in match.source.url


def test_normalise_text_folds_case_punctuation_and_nukta():
    assert normalise_text("Can't   BREATHE!!") == "cant breathe"
    assert normalise_text("ज़हर") == normalise_text("जहर")


def test_unknown_action_is_rejected(tmp_path):
    bad = tmp_path / "rules.yaml"
    bad.write_text(
        "version: 1\nmessages: {en: x}\nrules:\n  - id: r\n    action: shout\n"
        "    source: {title: t, url: 'https://x.org'}\n    reason: {en: r}\n",
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="unknown action"):
        RedFlagEngine.from_yaml(bad)


def test_rule_without_source_is_rejected(tmp_path):
    bad = tmp_path / "rules.yaml"
    bad.write_text(
        "version: 1\nmessages: {en: x}\nrules:\n  - id: r\n    action: emergency_112\n"
        "    reason: {en: r}\n",
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="source"):
        RedFlagEngine.from_yaml(bad)
