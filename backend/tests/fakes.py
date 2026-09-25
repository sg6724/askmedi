"""In-memory fakes for every external service. The default test run never touches the network."""

import json
import uuid
from dataclasses import dataclass, field
from datetime import date
from typing import Any

from askmedi.domain.chat import Episode, EpisodeUpdate, Turn
from askmedi.domain.common import Source
from askmedi.domain.geo import DirectoryUnavailable, GeoPoint, Place
from askmedi.domain.llm import LLMResult, LLMUnavailable
from askmedi.domain.medicine import DrugLabel
from askmedi.domain.profile import Profile
from askmedi.domain.reports import LabValue, StoredReport
from askmedi.domain.search import GroundedText, SearchUnavailable
from askmedi.domain.voice import Transcript


class ScriptedLLM:
    """Returns queued replies per task (dicts are JSON-encoded). Records every call."""

    def __init__(self, replies: dict[str, list[Any]] | None = None, fail: bool = False) -> None:
        self.replies = {k: list(v) for k, v in (replies or {}).items()}
        self.calls: list[tuple[str, list[Any]]] = []
        self.fail = fail

    async def complete(self, task, messages, *, json_mode=False):
        self.calls.append((task, list(messages)))
        if self.fail:
            raise LLMUnavailable("all failed")
        queue = self.replies.get(task) or []
        if not queue:
            raise AssertionError(f"unexpected LLM call for task {task!r}")
        reply = queue.pop(0)
        text = reply if isinstance(reply, str) else json.dumps(reply, ensure_ascii=False)
        return LLMResult(text=text, model=f"fake/{task}", latency_ms=3)


@dataclass
class FakeSearch:
    text: str = "Research notes."
    sources: list[Source] = field(
        default_factory=lambda: [Source("medlineplus.gov", "https://medlineplus.gov/fever.html")]
    )
    fail: bool = False
    questions: list[str] = field(default_factory=list)

    keywords: list[list[str]] = field(default_factory=list)

    async def research(self, question: str, keywords=()) -> GroundedText:
        self.questions.append(question)
        self.keywords.append(list(keywords))
        if self.fail:
            raise SearchUnavailable("down")
        return GroundedText(text=self.text, sources=list(self.sources), model="gemini/fake")


@dataclass
class FakeReader:
    result: dict[str, Any] = field(default_factory=dict)
    calls: list[tuple[str, int, str]] = field(default_factory=list)
    error: Exception | None = None

    async def read_json(self, prompt: str, data: bytes, mime_type: str) -> dict:
        self.calls.append((prompt, len(data), mime_type))
        if self.error:
            raise self.error
        return self.result


@dataclass
class FakeProfiles:
    profile: Profile = field(default_factory=Profile)

    async def get_profile(self, user_id: str) -> Profile:
        return self.profile


@dataclass
class FakeChatRepo:
    episodes: dict[str, dict[str, Any]] = field(default_factory=dict)
    citations: list[tuple[str, str | None, Source]] = field(default_factory=list)
    recent_similar: int = 0
    owner: dict[str, str] = field(default_factory=dict)

    def seed(self, user_id: str, **kwargs: Any) -> str:
        eid = str(uuid.uuid4())
        self.owner[eid] = user_id
        self.episodes[eid] = {
            "language": "en",
            "symptoms": [],
            "urgency": None,
            "followup_count": 0,
            "repeat_flag": False,
            "red_flag_rule_id": None,
            "outcome": None,
            "turns": [],
            **kwargs,
        }
        return eid

    async def get_episode(self, user_id, episode_id):
        ep = self.episodes.get(episode_id)
        if ep is None or self.owner.get(episode_id) != user_id:
            return None
        return Episode(
            id=episode_id,
            language=ep["language"],
            symptoms=list(ep["symptoms"]),
            urgency=ep["urgency"],
            followup_count=ep["followup_count"],
            repeat_flag=ep["repeat_flag"],
            red_flag_rule_id=ep["red_flag_rule_id"],
            turns=[Turn(r, t) for r, t in ep["turns"]],
        )

    async def create_episode(self, user_id, language):
        return self.seed(user_id, language=language)

    async def add_turn(self, user_id, episode_id, role, text, *, normalised=None, lang=None):
        self.episodes[episode_id]["turns"].append((role, text))
        return str(uuid.uuid4())

    async def update_episode(self, user_id, episode_id, update: EpisodeUpdate):
        ep = self.episodes[episode_id]
        for key, value in vars(update).items():
            if value is not None:
                ep[key] = value

    async def add_citations(self, user_id, episode_id, turn_id, sources):
        self.citations.extend((episode_id, turn_id, s) for s in sources)

    async def count_recent_similar(self, user_id, symptoms, *, days, exclude_episode_id):
        return self.recent_similar


@dataclass
class FakeAudit:
    events: list[Any] = field(default_factory=list)

    async def log(self, event) -> None:
        self.events.append(event)

    def types(self) -> list[str]:
        return [e.type for e in self.events]


@dataclass
class FakeLabels:
    label: DrugLabel | None = None

    async def find_label(self, name: str) -> DrugLabel | None:
        return self.label


@dataclass
class FakeMedicineRepo:
    saved: list[dict[str, Any]] = field(default_factory=list)

    async def save_lookup(self, user_id, **kwargs):
        self.saved.append({"user_id": user_id, **kwargs})
        return str(uuid.uuid4())


@dataclass
class FakeReportRepo:
    reports: dict[str, dict[str, Any]] = field(default_factory=dict)

    async def create_draft(self, user_id, report_date, lab, values: list[LabValue]):
        rid = str(uuid.uuid4())
        self.reports[rid] = {
            "user_id": user_id,
            "report_date": report_date,
            "lab": lab,
            "values": values,
            "status": "draft",
            "summary": None,
        }
        return rid

    async def get(self, user_id, report_id):
        r = self.reports.get(report_id)
        if r is None or r["user_id"] != user_id:
            return None
        return StoredReport(report_id, r["report_date"], r["lab"], r["status"])

    async def confirm(self, user_id, report_id, values, summary, language, sources):
        r = self.reports[report_id]
        r.update(values=values, summary=summary, status="confirmed", sources=sources)
        return str(uuid.uuid4())


@dataclass
class FakeGeo:
    point: GeoPoint | None = field(default_factory=lambda: GeoPoint(18.52, 73.86, "Pune 411001"))
    places: list[Place] = field(default_factory=list)
    fail: bool = False
    radius_seen: list[int] = field(default_factory=list)

    async def search(self, *, pincode=None, q=None):
        if self.fail:
            raise DirectoryUnavailable("down")
        return self.point

    async def reverse(self, lat, lng):
        return "Shivajinagar, Pune"

    async def nearby_health_places(self, lat, lng, radius_m):
        if self.fail:
            raise DirectoryUnavailable("down")
        self.radius_seen.append(radius_m)
        return list(self.places)


@dataclass
class FakeVoice:
    transcript: Transcript = field(default_factory=lambda: Transcript("mujhe bukhar hai", "hi"))
    audio: bytes = b"ID3fake-mp3"

    async def transcribe(self, audio, filename, mime_type, language_hint):
        return self.transcript

    async def speak(self, text, language):
        return self.audio


def a_label(**overrides: Any) -> DrugLabel:
    base = dict(  # noqa: C408
        generic_names=["ACETAMINOPHEN"],
        brand_names=["Tylenol"],
        substances=["ACETAMINOPHEN"],
        indications="temporarily relieves minor aches and pains and reduces fever",
        warnings="Liver warning: severe liver damage may occur. Ask a doctor before use if you "
        "have liver disease. Ask a doctor or pharmacist before use if you are taking the blood "
        "thinning drug warfarin.",
        interactions="",
        contraindications="",
        pregnancy="If pregnant or breast-feeding, ask a health professional before use.",
        inactive_ingredients="corn starch, povidone",
        source=Source(
            "U.S. FDA drug label (DailyMed): Acetaminophen",
            "https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=abc",
        ),
    )
    base.update(overrides)
    return DrugLabel(**base)


TODAY = date(2026, 9, 25)
