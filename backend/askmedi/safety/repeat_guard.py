"""Flags when the same symptom keeps coming back: >=3 symptom episodes in 7 days."""

from askmedi.domain.chat import ChatRepository

REPEAT_WINDOW_DAYS = 7
REPEAT_THRESHOLD = 3  # including the current episode

REPEAT_MESSAGES: dict[str, str] = {
    "en": "You have asked about this symptom several times this week. Please see a doctor "
    "in person so they can examine you properly.",
    "hi": "आपने इस हफ़्ते कई बार इसी लक्षण के बारे में पूछा है। कृपया डॉक्टर से मिलकर जाँच करवाएँ।",
    "mr": "या आठवड्यात तुम्ही याच लक्षणाबद्दल अनेक वेळा विचारले आहे. कृपया डॉक्टरांना प्रत्यक्ष "
    "भेटून तपासणी करून घ्या.",
}


def canonical_symptoms(symptoms: list[str]) -> list[str]:
    out = [" ".join(s.lower().split()) for s in symptoms if s and s.strip()]
    return list(dict.fromkeys(out))[:10]


class RepeatQueryGuard:
    def __init__(self, repo: ChatRepository) -> None:
        self._repo = repo

    async def is_repeat(self, user_id: str, episode_id: str, symptoms: list[str]) -> bool:
        symptoms = canonical_symptoms(symptoms)
        if not symptoms:
            return False
        prior = await self._repo.count_recent_similar(
            user_id, symptoms, days=REPEAT_WINDOW_DAYS, exclude_episode_id=episode_id
        )
        return prior + 1 >= REPEAT_THRESHOLD

    @staticmethod
    def message(language: str) -> str:
        return REPEAT_MESSAGES.get(language, REPEAT_MESSAGES["en"])
