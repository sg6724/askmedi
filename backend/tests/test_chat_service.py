import pytest

from askmedi.domain.common import NotFound, UpstreamUnavailable
from askmedi.domain.profile import Profile
from askmedi.safety.output_guard import OutputGuard
from askmedi.safety.red_flags import RedFlagEngine
from askmedi.safety.repeat_guard import RepeatQueryGuard
from askmedi.services.chat import ChatRequest, ChatService
from tests.fakes import FakeAudit, FakeChatRepo, FakeProfiles, FakeSearch, ScriptedLLM

USER = "user-1"

FOLLOWUP = {
    "symptoms": ["fever"],
    "readback": ["बुखार", "1 दिन"],
    "action": "followup",
    "followup": {"question": "बुखार कितना है?", "options": ["हल्का", "तेज़", "पता नहीं"]},
    "search_query": "fever 1 day adult",
}
DECIDE_ANSWER = {**FOLLOWUP, "action": "answer", "followup": None}
ANSWER = {
    "urgency": "self_care",
    "confidence": "high",
    "summary": "A short fever is often caused by a viral infection.",
    "causes": [{"name": "Viral fever", "likelihood": "more_likely", "explanation": "Common."}],
    "do_now": ["Rest", "Drink fluids"],
    "seek_care_if": ["Fever lasts more than 3 days"],
    "message": "Rest and drink fluids; see a doctor if it lasts more than 3 days.",
}


def make_service(llm, repo=None, search=None, audit=None, profile=None):
    repo = repo or FakeChatRepo()
    return ChatService(
        llm=llm,
        search=search or FakeSearch(),
        repo=repo,
        profiles=FakeProfiles(profile or Profile(birth_year=1990, sex="female")),
        audit=audit or FakeAudit(),
        red_flags=RedFlagEngine.from_yaml(),
        guard=OutputGuard(),
        repeat_guard=RepeatQueryGuard(repo),
    ), repo


def req(message, episode_id=None, language="hi"):
    return ChatRequest(user_id=USER, episode_id=episode_id, message=message, language=language)


async def test_emergency_never_calls_llm_and_is_persisted():
    llm = ScriptedLLM()
    audit = FakeAudit()
    service, repo = make_service(llm, audit=audit)
    out = await service.handle(req("mujhe seene mein dard ho raha hai"))
    assert out["type"] == "emergency"
    assert out["emergency"]["rule_id"] == "chest_pain"
    assert out["emergency"]["call"] == ["112", "108"]
    assert out["emergency"]["source"]["url"].startswith("https://")
    assert out["answer"] is None and out["followup"] is None
    assert out["disclaimer"]
    assert llm.calls == []
    ep = repo.episodes[out["episode_id"]]
    assert ep["urgency"] == "emergency" and ep["red_flag_rule_id"] == "chest_pain"
    assert "red_flag" in audit.types()


async def test_emergency_survives_storage_failure():
    class BrokenRepo(FakeChatRepo):
        async def create_episode(self, user_id, language):
            raise RuntimeError("db down")

    service, _ = make_service(ScriptedLLM(), repo=BrokenRepo())
    out = await service.handle(req("I can't breathe", language="en"))
    assert out["type"] == "emergency"


async def test_first_turn_asks_followup_and_counts_it():
    llm = ScriptedLLM({"reason": [FOLLOWUP]})
    service, repo = make_service(llm)
    out = await service.handle(req("mujhe kal se fever hai"))
    assert out["type"] == "followup"
    assert out["followup"]["options"] == ["हल्का", "तेज़", "पता नहीं"]
    assert out["message"] == "बुखार कितना है?"
    assert out["readback"] == ["बुखार", "1 दिन"]
    ep = repo.episodes[out["episode_id"]]
    assert ep["followup_count"] == 1 and ep["symptoms"] == ["fever"]
    assert [r for r, _ in ep["turns"]] == ["user", "assistant"]


async def test_answer_is_grounded_and_persists_citations():
    llm = ScriptedLLM({"reason": [DECIDE_ANSWER], "respond": [ANSWER]})
    search = FakeSearch()
    service, repo = make_service(llm, search=search)
    out = await service.handle(req("fever since yesterday, mild", language="en"))
    assert out["type"] == "answer"
    assert out["answer"]["urgency"] == "self_care"
    assert out["answer"]["causes"][0]["likelihood"] == "more_likely"
    assert out["sources"] == [
        {"title": "medlineplus.gov", "url": "https://medlineplus.gov/fever.html"}
    ]
    assert search.questions and "fever" in search.questions[0]
    assert search.keywords == [["fever"]]
    assert repo.citations and repo.citations[0][1] is not None  # tied to the assistant turn
    ep = repo.episodes[out["episode_id"]]
    assert ep["outcome"]["type"] == "answer" and ep["urgency"] == "self_care"


async def test_after_three_followups_it_must_answer():
    repo = FakeChatRepo()
    eid = repo.seed(USER, followup_count=3, symptoms=["fever"])
    llm = ScriptedLLM({"reason": [FOLLOWUP], "respond": [ANSWER]})  # model still wants to ask
    service, _ = make_service(llm, repo=repo)
    out = await service.handle(req("tez hai", episode_id=eid))
    assert out["type"] == "answer"
    system_prompt = llm.calls[0][1][0].content
    assert "MUST choose action" in system_prompt


async def test_urgency_is_never_lowered_and_raised_when_unsure():
    repo = FakeChatRepo()
    eid = repo.seed(USER, urgency="see_doctor_today")
    llm = ScriptedLLM({"reason": [DECIDE_ANSWER], "respond": [ANSWER]})
    service, _ = make_service(llm, repo=repo)
    out = await service.handle(req("better now", episode_id=eid))
    assert out["answer"]["urgency"] == "see_doctor_today"

    llm = ScriptedLLM({"reason": [DECIDE_ANSWER], "respond": [{**ANSWER, "confidence": "low"}]})
    service, _ = make_service(llm)
    out = await service.handle(req("fever"))
    assert out["answer"]["urgency"] == "see_doctor_soon"


async def test_search_failure_answers_more_cautiously_without_sources():
    llm = ScriptedLLM({"reason": [DECIDE_ANSWER], "respond": [ANSWER]})
    service, _ = make_service(llm, search=FakeSearch(fail=True))
    out = await service.handle(req("fever"))
    assert out["type"] == "answer"
    assert out["sources"] == []
    assert out["answer"]["urgency"] == "see_doctor_soon"


async def test_output_guard_repairs_once():
    unsafe = {**ANSWER, "do_now": ["Take paracetamol 500 mg"]}
    llm = ScriptedLLM({"reason": [DECIDE_ANSWER], "respond": [unsafe, ANSWER]})
    audit = FakeAudit()
    service, _ = make_service(llm, audit=audit)
    out = await service.handle(req("fever"))
    assert out["answer"]["do_now"] == ["Rest", "Drink fluids"]
    assert "output_guard_repair" in audit.types()


async def test_output_guard_falls_back_when_repair_is_still_unsafe():
    unsafe = {**ANSWER, "summary": "You have dengue."}
    llm = ScriptedLLM({"reason": [DECIDE_ANSWER], "respond": [unsafe, unsafe]})
    audit = FakeAudit()
    service, _ = make_service(llm, audit=audit)
    out = await service.handle(req("fever", language="mr"))
    assert out["type"] == "answer"
    assert "डॉक्टर" in out["answer"]["summary"]
    assert out["answer"]["urgency"] in ("see_doctor_soon", "see_doctor_today")
    assert out["sources"] == []
    assert "output_guard_fallback" in audit.types()


async def test_repeat_guard_short_circuits():
    repo = FakeChatRepo(recent_similar=2)
    llm = ScriptedLLM({"reason": [FOLLOWUP]})
    audit = FakeAudit()
    service, _ = make_service(llm, repo=repo, audit=audit)
    out = await service.handle(req("fir se bukhar"))
    assert out["type"] == "repeat"
    assert "डॉक्टर" in out["message"]
    ep = repo.episodes[out["episode_id"]]
    assert ep["repeat_flag"] is True and ep["urgency"] == "see_doctor_soon"
    assert "repeat_guard" in audit.types()


async def test_unknown_or_foreign_episode_is_404():
    repo = FakeChatRepo()
    other = repo.seed("someone-else")
    service, _ = make_service(ScriptedLLM(), repo=repo)
    with pytest.raises(NotFound) as exc:
        await service.handle(req("fever", episode_id=other))
    assert exc.value.code == "episode_not_found"


async def test_llm_down_is_503():
    service, _ = make_service(ScriptedLLM(fail=True))
    with pytest.raises(UpstreamUnavailable) as exc:
        await service.handle(req("fever"))
    assert exc.value.code == "llm_unavailable"


async def test_profile_goes_to_prompt_without_location():
    llm = ScriptedLLM({"reason": [FOLLOWUP]})
    service, _ = make_service(llm, profile=Profile(birth_year=1990, conditions=["asthma"]))
    await service.handle(req("fever"))
    user_prompt = llm.calls[0][1][1].content
    assert "asthma" in user_prompt and "age band" in user_prompt
