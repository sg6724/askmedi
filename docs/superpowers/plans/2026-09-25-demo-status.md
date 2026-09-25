# AskMedi demo build — status and demo script (2026-09-25)

Branch `phase-0-foundation`, fast-forwarded into `main`. CI on `main` is green (backend, database
pgTAP + integration, mobile). Backend live at https://askmedi-api.vercel.app. APK built by the
**Android APK** workflow.

## What works (verified against the live services)

The live end-to-end suite `mobile/test_live` drives the app's real repositories against production and
passed 10/10 on 2026-09-25:

| Step | Result |
|---|---|
| Email + password sign-in (wrong password rejected) | ✅ |
| Consent + health profile saved and read back | ✅ |
| Emergency: "mujhe seene mein bahut dard ho raha hai" | ✅ `chest_pain`, call 112 / 108, no AI involved |
| Marathi symptom chat | ✅ 3 follow-ups, then an answer with likelihood bands and 6 web sources |
| Medicine strip photo → "Crocin 500 (Paracetamol)" → lookup | ✅ pharmacist flag for the user's liver disease |
| Lab report PDF → values → confirm → Hindi summary → trend | ✅ Hb low, glucose normal, TSH high (flags computed in code) |
| Hospitals by PIN 411001 and by "Kothrud, Pune" | ✅ 30 each |
| ElevenLabs voice (Hindi TTS; STT round-trip checked separately) | ✅ |
| History (episodes, medicines, reports, report values) | ✅ |
| Delete account and all data | ✅ no rows left in any table |

Also: Google sign-in (Supabase provider + redirect URLs configured), the web build in Chrome, and the
Android APK (built in CI; install check on a real phone pending).

Tests: backend 264 unit (+ integration); mobile 97 widget/unit; pgTAP RLS tests in CI.

## Bugs found by the live test and fixed

1. Red flags missed extra words ("seene mein **bahut** dard"). Chest-pain and breathing rules now
   also fire on a body-part word plus a symptom word anywhere in the message (en/hi/mr/romanised).
2. Every report summary fell back to the generic text: the dose guard treated "96 mg/dL" as a dose.
   Lab concentrations (unit per dL/L/mL) are now allowed; "mg/day" still blocked.
3. When Gemini's vision quota was used up, scans and image reports failed. Groq vision now reads
   images as the fallback.

## Phone-test fixes (2026-09-26)

| Report | Cause | Fix |
|---|---|---|
| No intro to the app | — | Welcome slides after the language choice |
| "Server connected" on Home | Debug line | Removed |
| Slow voice | `eleven_v3` TTS (4.6 s) + long replies | `eleven_turbo_v2_5` for en/hi (~0.5 s), `scribe_v2`, 64 kbps audio, short spoken text: speak + transcribe now ~1 s each |
| Talk looks like chat | Same screen | Voice-first Talk screen (orb, Listening/Thinking/Speaking) |
| "File too large" on reports | Full camera photos > Vercel's 4.5 MB request limit | Photos resized on the phone (1600 px JPEG); PDF > 4 MB stopped with a message |
| "Zady 500" not identified | Indian brand unknown to openFDA; Gemini grounding out of quota | Groq browser search first (found azithromycin 500 mg with DailyMed/Practo sources); the ingredient's label is looked up |
| Latency everywhere | Free-tier limits: Groq 8k tokens/min and **200k tokens/day** per model, Gemini 20 requests/day per model; SDK retries waited ~40 s on each 429 | No hidden retries, per-model cooldown after 429, shorter timeouts, caches for searches and map lookups |

**Most important for the demo:** on the free tiers a single day of testing used up Groq's 200k-token
daily budget for `gpt-oss-120b` and Gemini's daily quota, after which answers fall back to smaller
models and MedlinePlus (and medicine lookups lose their web sources). Groq's Dev Tier (pay-as-you-go,
~$0.15 per million input tokens for gpt-oss-120b) or Gemini billing removes this. Otherwise avoid heavy
testing before the demo (Gemini resets at 12:30 PM IST; Groq's daily window is rolling).

## Known limits and risks

- **Gemini free tier: 20 requests/day per model.** Chat runs on Groq; grounded search falls back to
  MedlinePlus; image reading falls back to Groq. **PDF reports need Gemini** — use a photo of the
  report if Gemini is out. Enabling billing on the Gemini key removes this risk.
- **Hospital search** can take 10–20 s when OpenStreetMap's Overpass server is busy (Nominatim
  fallback kicks in after 8 s).
- **Chat turns take 2–20 s** (web search + model). Emergency detection is instant.
- Not built from the original spec (deferred): PM-JAY filter, Jan Aushadhi generic alternatives,
  on-device PII redaction of reports (report files are sent to Gemini and not stored), doctor-visit
  summary PDF, saved places and offline hospital cache on the Emergency screen, LangGraph agent
  (a simpler follow-up loop is used), a stored knowledge corpus (replaced by live web search, owner's
  decision). Read-back chips are not editable; History items are not tappable; changing language in
  Profile does not update `profiles.language`.
- Red-flag rules are **source-derived, not clinician-reviewed** (`review_status: source-derived`).
- Voice recording, camera, GPS and file pickers are covered by fakes in tests; check them by hand in
  Chrome and on the phone.

## Demo script (≈10 minutes)

Before: open http://localhost:7357 (serve `mobile/build/web`) or install the APK. Have a medicine strip
and a lab report (photo or PDF) ready. Allow microphone and location when asked.

1. **Onboarding (1 min).** Choose मराठी or हिंदी → sign in with Google (or create an email account) →
   18+ and consent toggles → health profile (add a condition, e.g. "Liver disease").
2. **Emergency (1 min).** Home → Check symptoms → type `mujhe seene mein bahut dard ho raha hai`.
   The red Emergency screen opens instantly with 112 / 108 and the MedlinePlus source. Point out: no AI
   in this path; rules are in `safety/rules/v1.yaml` with a cited source each.
3. **Symptom triage (2 min).** New chat: `मला दोन दिवसांपासून ताप आणि अंगदुखी आहे`. Answer the tappable
   follow-ups. Show the answer card: urgency, causes as More likely / Possible / Less likely (never
   percentages), what to do now, when to seek care, sources (tap one), disclaimer, Find a hospital.
4. **Voice (1 min).** Talk → tap the mic → say a symptom in Hindi → the reply is spoken back (ElevenLabs).
5. **Medicine (1 min).** Scan medicine → photo of a strip → confirm "Is this …?" → pharmacist flag
   based on the profile condition, uses, warnings, sources.
6. **Report (2 min).** Upload report → edit a value if needed → confirm → Summary / Key values
   (low/normal/high computed from the report's own range) / Chart.
7. **Hospitals (1 min).** Hospitals tab → Use my location (or PIN `411001`) → call / directions.
8. **History & privacy (1 min).** History → Timeline filters, Analytics charts built from this account's
   own data. Profile → Delete account and all data (explain: one RPC, cascades to every table).

Architecture talking points: FastAPI with ports/adapters (swap any provider in `container.py` or
`models.yaml`); row-level security on every table; deterministic safety layer before and after the model;
free tiers only; CI runs backend, database (pgTAP) and app tests, and builds the APK.
