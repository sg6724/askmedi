import pytest

from askmedi.domain.common import NotFound, Unprocessable
from askmedi.safety.output_guard import OutputGuard
from askmedi.services.reports import ReportService
from tests.fakes import FakeAudit, FakeReader, FakeReportRepo, FakeSearch, ScriptedLLM

PARSED = {
    "report_date": "2026-09-01",
    "lab": "City Lab",
    "values": [
        {
            "test_name": "Haemoglobin",
            "value": 11.2,
            "unit": "g/dL",
            "ref_low": None,
            "ref_high": None,
            "ref_text": "12.0-15.5",
        },
        {"test_name": "Vitamin D", "value": 25, "unit": "ng/mL", "ref_text": None},
        {"test_name": "TSH", "value": None, "unit": "mIU/L", "ref_low": 0.4, "ref_high": 4.0},
    ],
}


def make(reader=None, llm=None, repo=None):
    return ReportService(
        reader=reader or FakeReader(result=PARSED),
        search=FakeSearch(),
        llm=llm
        or ScriptedLLM(
            {
                "respond": [
                    {"summary": "Haemoglobin is a bit low.", "highlights": ["Low haemoglobin"]}
                ]
            }
        ),
        guard=OutputGuard(),
        repo=repo or FakeReportRepo(),
        audit=FakeAudit(),
    )


async def test_parse_computes_status_in_code_and_saves_draft():
    repo = FakeReportRepo()
    out = await make(repo=repo).parse("u", b"%PDF", "application/pdf")
    statuses = {v["test_name"]: v["status"] for v in out["values"]}
    assert statuses == {"Haemoglobin": "low", "Vitamin D": "unknown", "TSH": "unreadable"}
    assert out["report_date"] == "2026-09-01" and out["lab"] == "City Lab"
    hb = out["values"][0]
    assert (hb["ref_low"], hb["ref_high"], hb["ref_text"]) == (12.0, 15.5, "12.0-15.5")
    assert repo.reports[out["report_id"]]["status"] == "draft"


async def test_parse_without_values_is_422():
    with pytest.raises(Unprocessable):
        await make(reader=FakeReader(result={"values": []})).parse("u", b"x", "image/png")


async def test_confirm_recomputes_status_from_user_edits():
    repo = FakeReportRepo()
    service = make(repo=repo)
    parsed = await service.parse("u", b"x", "image/png")
    edited = [{**parsed["values"][0], "value": 13.1, "status": "low"}]  # client status ignored
    out = await service.confirm("u", parsed["report_id"], edited, "en")
    assert out["values"][0]["status"] == "normal"
    assert out["summary"] == "Haemoglobin is a bit low."
    assert out["highlights"] == ["Low haemoglobin"]
    assert out["sources"] and out["disclaimer"]
    assert repo.reports[parsed["report_id"]]["status"] == "confirmed"


async def test_confirm_unknown_report_is_404():
    with pytest.raises(NotFound) as exc:
        await make().confirm("u", "00000000-0000-0000-0000-000000000000", [], "en")
    assert exc.value.code == "report_not_found"
