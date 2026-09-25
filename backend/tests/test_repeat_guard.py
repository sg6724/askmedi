import pytest

from askmedi.safety.repeat_guard import RepeatQueryGuard, canonical_symptoms
from tests.fakes import FakeChatRepo


@pytest.mark.parametrize(("prior", "expected"), [(0, False), (1, False), (2, True), (5, True)])
async def test_three_episodes_in_a_week_is_a_repeat(prior, expected):
    guard = RepeatQueryGuard(FakeChatRepo(recent_similar=prior))
    assert await guard.is_repeat("u", "e", ["fever"]) is expected


async def test_no_symptoms_is_never_a_repeat():
    guard = RepeatQueryGuard(FakeChatRepo(recent_similar=10))
    assert await guard.is_repeat("u", "e", []) is False


def test_canonical_symptoms_lowercases_and_dedupes():
    assert canonical_symptoms(["Fever", " fever ", "Head  ache", ""]) == ["fever", "head ache"]


def test_message_is_localised():
    assert "doctor" in RepeatQueryGuard.message("en")
    assert "डॉक्टर" in RepeatQueryGuard.message("hi")
    assert "डॉक्टर" in RepeatQueryGuard.message("mr")
