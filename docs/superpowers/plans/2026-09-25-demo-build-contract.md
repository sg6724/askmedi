# Demo build — API contract (backend ⇄ mobile)

**Date:** 2026-09-25 · **Goal:** every tab works end to end against real services for tomorrow's demo.
**Owner rulings:** keep it simple, no RAG corpus. Medical knowledge comes from a **live web search on every question** (Gemini + Google Search grounding), cited from the grounding sources. **Voice uses ElevenLabs** (speech-to-text + text-to-speech). Everything real, no seed data.
**DB:** migration `supabase/migrations/20260925000003_features.sql` is already applied (tables `medicine_lookups`, `reports`, `report_values`; `citations.title/url`; RPC `delete_my_account()`).

Base URL: `https://askmedi-api.vercel.app` (`API_BASE_URL`). Every endpoint except `/health` needs `Authorization: Bearer <supabase access token>` (401 otherwise). Errors: `{"detail": "<code>"}` with codes below. JSON is snake_case. Languages: `en | hi | mr`.

Common objects:
```jsonc
Source    = {"title": "MedlinePlus: Fever", "url": "https://..."}
Urgency   = "emergency" | "see_doctor_today" | "see_doctor_soon" | "self_care"
Likelihood= "more_likely" | "possible" | "less_likely"
```

## 1. Symptom chat — `POST /chat`
Request: `{"episode_id": "uuid|null", "message": "mujhe kal se fever hai", "language": "hi"}` (message 1..2000 chars; null episode_id starts a new episode).
Response 200:
```jsonc
{
  "episode_id": "uuid",
  "type": "followup" | "answer" | "emergency" | "repeat",
  "readback": ["Fever", "1 day"],            // understood symptoms (chips); may be []
  "followup": {"question": "...", "options": ["...", "..."]} | null,   // 2-5 options
  "answer": {                                 // null unless type == answer
    "urgency": Urgency,
    "summary": "...",
    "causes": [{"name": "...", "likelihood": Likelihood, "explanation": "..."}],
    "do_now": ["..."],
    "seek_care_if": ["..."]
  } | null,
  "emergency": {"rule_id": "chest_pain", "reason": "...", "call": ["112", "108"], "source": Source} | null,
  "message": "...",                            // text to show/speak for any type
  "sources": [Source],                         // for answers: web-search sources used
  "disclaimer": "AskMedi gives health information, not a diagnosis. Please consult a doctor."
}
```
Pipeline (in order): (1) deterministic **RedFlagEngine** on the raw text with en/hi/mr + romanised keyword lists from `backend/askmedi/safety/rules/v1.yaml` (every rule has `source`) → `emergency`, LLM not called. (2) **RepeatQueryGuard**: ≥3 symptom episodes in 7 days sharing a symptom → `repeat` ("please see a doctor"). (3) LLM turn: at most 3 follow-ups per episode, then must answer; answers are grounded by a web search. (4) **OutputGuard**: banned patterns (doses like "500 mg", "you have", "no need to see a doctor", prescriptions) → one repair, then a safe fallback. (5) Reply in the user's language. Persist episode (kind `symptom`, symptoms, urgency, followup_count, outcome), turns, citations, audit events. 404 `episode_not_found` for a foreign/unknown episode. 503 `llm_unavailable` if every model fails. The emergency path never depends on an LLM.

## 2. Medicine — `POST /medicine/scan` and `POST /medicine/lookup`
`/medicine/scan`: multipart `image` (jpeg/png/webp, ≤ 8 MB) → Gemini vision:
```jsonc
{"candidates": [{"brand": "Crocin 500", "salts": [{"name": "Paracetamol", "strength": "500 mg"}],
                 "form": "tablet", "manufacturer": "GSK", "confidence": 0.9}]}
```
(413 `file_too_large`, 415 `unsupported_media_type`, 422 `unreadable_image` when nothing found.)
`/medicine/lookup`: `{"name": "Paracetamol", "brand": "Crocin 500"|null, "language": "en"}` →
```jsonc
{"name": "Paracetamol", "brand": "...", "salts": [...], "uses": ["..."], "warnings": ["..."],
 "pharmacist_flags": [{"reason": "Check with your pharmacist because you listed liver disease."}],
 "summary": "...", "sources": [Source], "disclaimer": "..."}
```
Info comes from openFDA drug label API (free, no key) + web-search-grounded summary. `pharmacist_flags` are deterministic: profile conditions/allergies/current medicines matched against label text. No doses. Persists `medicine_lookups` + an episode (kind `medicine`).

## 3. Reports — `POST /reports/parse`, `POST /reports/{id}/confirm`
`/reports/parse`: multipart `file` (image or PDF, ≤ 10 MB). The file is sent to Gemini and **not stored**. →
```jsonc
{"report_id": "uuid", "report_date": "2026-09-01"|null, "lab": "..."|null,
 "values": [{"test_name": "Haemoglobin", "value": 11.2, "unit": "g/dL", "ref_low": 12, "ref_high": 15.5,
             "ref_text": "12.0-15.5", "status": "low"}]}
```
`status` is computed **in code** from the printed range (`unknown` if no range, `unreadable` if no numeric value). Saved as a `draft` report.
`/reports/{id}/confirm`: `{"values": [...same shape, user-edited...], "language": "en"}` → recomputes statuses, replaces the report's `report_values`, marks `confirmed`, returns
`{"report_id", "summary": "...", "highlights": ["..."], "values": [...], "sources": [Source], "disclaimer"}`.

## 4. Hospitals — `GET /hospitals`
Query: either `lat`&`lng`, or `pincode` (6 digits), or `q` (area text); optional `radius_km` (default 5, max 25), `specialty`.
Geocoding via OSM Nominatim (proper User-Agent), places via OSM Overpass (`amenity=hospital|clinic`, `healthcare=*`). →
```jsonc
{"location": {"lat": 18.52, "lng": 73.86, "label": "Pune 411001"},
 "hospitals": [{"name": "...", "lat": 0, "lng": 0, "distance_km": 1.2, "address": "..."|null,
                "phone": "..."|null, "emergency": true|null, "maps_url": "https://www.google.com/maps/search/?api=1&query=LAT,LNG"}]}
```
Sorted by distance, ≤ 30. 404 `location_not_found`, 502 `directory_unavailable`. Coordinates are never sent to an LLM; logs round them to 2 dp.

## 5. Voice (ElevenLabs) — `POST /voice/transcribe`, `POST /voice/speak`
`/voice/transcribe`: multipart `audio` (webm/ogg/m4a/mp3/wav, ≤ 10 MB) → ElevenLabs Speech-to-Text → `{"text": "...", "language": "hi"}`.
`/voice/speak`: `{"text": "...", "language": "mr"}` (≤ 1500 chars) → `audio/mpeg` bytes via ElevenLabs TTS.
The app flow: record → transcribe → `POST /chat` → speak the `message`. 503 `voice_unavailable` when `ELEVENLABS_API_KEY` is not set. Model/voice IDs live in config, not code.

## 6. Read directly from Supabase by the app (RLS, user's JWT) — no backend endpoint
- History list: `episodes` (filter by `kind`), with `medicine_lookups`, `reports`.
- Analytics: symptom episodes per week, most frequent `episodes.symptoms`, `report_values` over time per `test_name`, average `followup_count`, count of `repeat_flag`.
- Profile edit: existing `profiles`, `health_conditions`, `user_medicines`, `allergies`.
- Delete account: `rpc('delete_my_account')`, then sign out.

## Structure rules (owner)
Modular; app code and tests separate. Backend: `api/` thin routers, `domain/` ports + pure logic, `safety/`, `services/` (use cases), `adapters/` (Gemini/Groq/ElevenLabs/openFDA/OSM/Postgres), composition in `container.py`; tests in `backend/tests/` with fakes. Mobile: `lib/features/<feature>/{data,domain,presentation}` where practical; tests in `mobile/test/` with fake repositories. All user-visible strings via ARB (en/hi/mr).
