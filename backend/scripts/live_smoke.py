"""Live smoke test of every real integration. Not part of the app or the unit tests.

Usage (from backend/):  uv run --env-file .env python scripts/live_smoke.py [--e2e]

--e2e also runs the chat / medicine / report / hospital use cases end to end against the live
database, as a temporary auth user that is created first and deleted at the end.
"""

import argparse
import asyncio
import sys
import time
import uuid
from pathlib import Path

import psycopg

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.stdout.reconfigure(encoding="utf-8")  # Devanagari output on Windows consoles

from askmedi.adapters.elevenlabs import ElevenLabsVoice
from askmedi.adapters.gemini import GeminiClient
from askmedi.adapters.litellm_provider import LiteLLMProvider
from askmedi.adapters.medlineplus import MedlinePlusSearch
from askmedi.adapters.openfda import OpenFdaLabels
from askmedi.adapters.osm import OsmDirectory
from askmedi.config import get_settings
from askmedi.container import build_container
from askmedi.services.chat import ChatRequest

if sys.platform == "win32":  # psycopg async needs a selector loop on Windows
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())


def show(name: str, ok: bool, detail: str) -> None:
    print(f"{'PASS' if ok else 'FAIL'} {name:28} {detail}")


def lab_pdf() -> bytes:
    """A tiny one-page PDF with a few printed lab results."""
    lines = [
        "City Diagnostics Lab    Report date: 01/09/2026",
        "Test              Result   Unit     Reference range",
        "Haemoglobin       11.2     g/dL     12.0 - 15.5",
        "Fasting Glucose   96       mg/dL    70 - 100",
        "TSH               5.9      mIU/L    0.4 - 4.0",
    ]
    text = "BT /F1 12 Tf 50 750 Td 16 TL " + " ".join(f"({ln}) '" for ln in lines) + " ET"
    objs = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
            "/Resources << /Font << /F1 5 0 R >> >> >>"
        ),
        f"<< /Length {len(text)} >>\nstream\n{text}\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
    ]
    out = b"%PDF-1.4\n"
    offsets = []
    for i, obj in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n{obj}\nendobj\n".encode()
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += "".join(f"{o:010d} 00000 n \n" for o in offsets).encode()
    out += f"trailer << /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF".encode()
    return out


async def adapters() -> None:
    settings = get_settings()
    llm = LiteLLMProvider.from_yaml(settings.models_config_path)
    gemini = GeminiClient(
        settings.gemini_api_key or "",
        search_models=llm.models_for("search"),
        vision_models=llm.models_for("vision"),
    )

    t = time.perf_counter()
    try:
        g = await gemini.research("Common causes of a one-day fever in adults and warning signs.")
        show(
            "gemini grounded search",
            bool(g.sources),
            f"{g.model} {len(g.text)} chars, "
            f"{len(g.sources)} sources, {time.perf_counter() - t:.1f}s",
        )
        for s in g.sources[:4]:
            print(f"      - {s.title}: {s.url[:100]}")
    except Exception as exc:  # noqa: BLE001
        show("gemini grounded search", False, repr(exc))

    t = time.perf_counter()
    try:
        data = await gemini.read_json(
            'Extract lab results as JSON {"report_date":..., "values":[{"test_name","value",'
            '"unit","ref_text"}]}',
            lab_pdf(),
            "application/pdf",
        )
        show(
            "gemini vision (PDF report)",
            bool(data.get("values")),
            f"{len(data.get('values', []))} values, {time.perf_counter() - t:.1f}s: "
            f"{[(v.get('test_name'), v.get('value')) for v in data.get('values', [])]}",
        )
    except Exception as exc:  # noqa: BLE001
        show("gemini vision (PDF report)", False, repr(exc))

    try:
        m = await MedlinePlusSearch().research("fever", ["fever", "headache"])
        show("medlineplus search", bool(m.sources), f"{[x.url for x in m.sources]}")
    except Exception as exc:  # noqa: BLE001
        show("medlineplus search", False, repr(exc))

    try:
        label = await OpenFdaLabels().find_label("Paracetamol")
        show(
            "openFDA paracetamol",
            label is not None,
            f"{label.generic_names[:1]} {label.source.url}" if label else "no label",
        )
    except Exception as exc:  # noqa: BLE001
        show("openFDA paracetamol", False, repr(exc))

    osm = OsmDirectory(user_agent=settings.osm_user_agent)
    try:
        point = await osm.search(pincode="411001")
        show("nominatim PIN 411001", point is not None, f"{point}")
        await asyncio.sleep(1.1)  # Nominatim policy: max 1 request/second
        places = await osm.nearby_health_places(point.lat, point.lng, 5000)
        named = [p.name for p in places[:5]]
        show("overpass 5 km", bool(places), f"{len(places)} places, e.g. {named}")
    except Exception as exc:  # noqa: BLE001
        show("nominatim/overpass", False, repr(exc))

    if not settings.elevenlabs_api_key:
        show("elevenlabs", False, "ELEVENLABS_API_KEY not set (skipped)")
        return
    voice = ElevenLabsVoice(
        settings.elevenlabs_api_key,
        stt_model=settings.elevenlabs_stt_model,
        tts_model=settings.elevenlabs_tts_model,
        voice_id=settings.elevenlabs_voice_id,
        output_format=settings.elevenlabs_output_format,
    )
    clips = {}
    for lang, text in [
        ("hi", "मुझे कल से बुखार है और सिर में दर्द है।"),
        ("mr", "मला कालपासून ताप आहे आणि डोके दुखत आहे."),
    ]:
        t = time.perf_counter()
        try:
            clips[lang] = await voice.speak(text, lang)
            show(
                f"elevenlabs TTS {lang}",
                clips[lang][:3] in (b"ID3", b"\xff\xfb", b"\xff\xf3"),
                f"{len(clips[lang])} bytes mp3, {time.perf_counter() - t:.1f}s",
            )
        except Exception as exc:  # noqa: BLE001
            show(f"elevenlabs TTS {lang}", False, repr(exc))
    for lang, clip in clips.items():
        t = time.perf_counter()
        try:
            tr = await voice.transcribe(clip, f"{lang}.mp3", "audio/mpeg", None)
            show(
                f"elevenlabs STT ({lang} clip)",
                bool(tr.text),
                f"lang={tr.language} {time.perf_counter() - t:.1f}s: {tr.text}",
            )
        except Exception as exc:  # noqa: BLE001
            show(f"elevenlabs STT ({lang} clip)", False, repr(exc))


async def end_to_end() -> None:
    settings = get_settings()
    user_id = str(uuid.uuid4())
    with psycopg.connect(settings.database_url, autocommit=True, prepare_threshold=None) as admin:
        admin.execute(
            "insert into auth.users (id, email, aud, role) values (%s, %s, 'authenticated', "
            "'authenticated')",
            (user_id, f"smoke-{user_id[:8]}@askmedi.invalid"),
        )
        admin.execute(
            "insert into public.profiles (user_id, birth_year, sex) values (%s, 1990, 'female')",
            (user_id,),
        )
        admin.execute(
            "insert into public.health_conditions (user_id, name) values (%s, 'liver disease')",
            (user_id,),
        )
    c = build_container(settings)
    try:
        t = time.perf_counter()
        out = await c.chat.handle(
            ChatRequest(user_id, None, "mujhe seene mein dard ho raha hai", "hi")
        )
        show(
            "chat emergency",
            out["type"] == "emergency",
            f"{out['emergency']['rule_id']} call={out['emergency']['call']} "
            f"{time.perf_counter() - t:.1f}s",
        )

        t = time.perf_counter()
        out = await c.chat.handle(ChatRequest(user_id, None, "mujhe kal se fever hai", "hi"))
        show(
            "chat turn 1",
            out["type"] in ("followup", "answer"),
            f"type={out['type']} readback={out['readback']} {time.perf_counter() - t:.1f}s",
        )
        print(f"      message: {out['message'][:200]}")
        eid, turns = out["episode_id"], 1
        while out["type"] == "followup" and turns < 5:
            first = out["followup"]["options"][0]
            t = time.perf_counter()
            out = await c.chat.handle(ChatRequest(user_id, eid, first, "hi"))
            turns += 1
            show(
                f"chat turn {turns}",
                out["type"] in ("followup", "answer"),
                f"type={out['type']} (answered {first!r}) {time.perf_counter() - t:.1f}s",
            )
        if out["type"] == "answer":
            a = out["answer"]
            print(f"      urgency={a['urgency']} causes={[x['name'] for x in a['causes']]}")
            print(f"      summary: {a['summary'][:200]}")
            print(f"      sources: {[s['url'][:70] for s in out['sources']]}")

        t = time.perf_counter()
        med = await c.medicine.lookup(user_id, "Paracetamol", "Crocin 500", "en")
        show(
            "medicine lookup",
            bool(med["uses"]),
            f"uses={med['uses'][:2]} flags={med['pharmacist_flags']} "
            f"sources={len(med['sources'])} {time.perf_counter() - t:.1f}s",
        )

        t = time.perf_counter()
        rep = await c.reports.parse(user_id, lab_pdf(), "application/pdf")
        show(
            "report parse",
            bool(rep["values"]),
            f"{[(v['test_name'], v['value'], v['status']) for v in rep['values']]} "
            f"date={rep['report_date']} {time.perf_counter() - t:.1f}s",
        )
        t = time.perf_counter()
        conf = await c.reports.confirm(user_id, rep["report_id"], rep["values"], "mr")
        show(
            "report confirm (mr)",
            bool(conf["summary"]),
            f"{len(conf['highlights'])} highlights, {len(conf['sources'])} sources "
            f"{time.perf_counter() - t:.1f}s",
        )
        print(f"      summary: {conf['summary'][:200]}")

        t = time.perf_counter()
        hosp = await c.hospitals.search(user_id, pincode="411001", radius_km=5)
        show(
            "hospitals PIN 411001",
            bool(hosp["hospitals"]),
            f"{hosp['location']['label']}: {len(hosp['hospitals'])} results, nearest "
            f"{hosp['hospitals'][0]['name'] if hosp['hospitals'] else None} "
            f"{time.perf_counter() - t:.1f}s",
        )

        with psycopg.connect(settings.database_url, prepare_threshold=None) as admin:
            counts = {
                table: admin.execute(
                    f"select count(*) from public.{table} where user_id = %s",
                    (user_id,),
                ).fetchone()[0]
                for table in (
                    "episodes",
                    "turns",
                    "citations",
                    "audit_events",
                    "medicine_lookups",
                    "reports",
                    "report_values",
                )
            }
        show("rows persisted", all(counts.values()), str(counts))
    finally:
        await c.audit._db.close()  # type: ignore[attr-defined]
        with psycopg.connect(
            settings.database_url, autocommit=True, prepare_threshold=None
        ) as admin:
            admin.execute("delete from auth.users where id = %s", (user_id,))
        print("      temporary user deleted")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--e2e", action="store_true")
    args = parser.parse_args()
    asyncio.run(adapters())
    if args.e2e:
        asyncio.run(end_to_end())


if __name__ == "__main__":
    main()
