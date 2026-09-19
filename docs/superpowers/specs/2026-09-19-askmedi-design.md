# AskMedi — Design Spec

**Date:** 2026-09-19
**Status:** Draft for review
**Tagline:** "Your Health, Our Concern"

---

## 1. Purpose

AskMedi is a mobile health assistant for India that people can use in English, Hindi or Marathi. They can speak, type or mix languages. It does five things:

1. Asks follow-up questions before giving guidance. It does not dump search results.
2. Grounds every answer in a named, licensed source.
3. Reads medicine strips and medical reports.
4. Finds hospitals that are relevant to the problem.
5. Remembers each user across sessions and shows history and analytics back to them.

It is a final-year project that is built to grow into a public product.

### 1.1 Goals

- A working, deployed app with real account creation, login and per-account data.
- An agentic assistant that plans its own steps, calls tools and keeps memory. It stays inside deterministic safety guards that it cannot bypass.
- Everything runs on free tiers.
- Swapping a provider (moving to paid tiers or to other vendors) is a configuration change, not a rewrite.

### 1.2 Non-goals (v1)

- Diagnosis, prescriptions or dosing advice.
- Autonomous emergency calling. The user always taps the dial button.
- Identifying loose pills by shape or colour.
- Telemedicine ("Talk to a Doctor"), which needs a licensed partner under the Telemedicine Practice Guidelines 2020.
- Users under 18. The Gemini API terms prohibit apps likely to be used by minors.
- ABHA/ABDM integration (deferred).
- Family or dependent profiles (deferred, because consent gets complicated).
- iOS release. The Flutter codebase supports iOS, but only Android is shipped and tested in v1.

---

## 2. Constraints and decisions already made

| # | Decision | Rationale |
|---|---|---|
| D1 | **Free tiers only** for now | Owner's requirement |
| D2 | **Languages: English, Hindi, Marathi only.** Code-mixed speech and romanised Hindi ("mujhe kal se fever hai") are supported | Owner's requirement. All three use the Latin or Devanagari scripts. |
| D3 | **Real accounts and real data. No seed data.** | Owner's requirement. Owner accepts that the free Gemini tier may use prompts for training and human review. We mitigate this with data minimisation (§9). |
| D4 | **No clinician on the team.** All medical content and every safety rule must trace to a licensed, published source. The system is conservative by default. | Owner's requirement (§7) |
| D5 | **Login: Google sign-in and email OTP** through Supabase Auth. Phone OTP comes later. | Free. SMS OTP costs money and needs DLT registration. |
| D6 | **Backend deployed on Vercel**, in the Mumbai region (`bom1`) | Owner's requirement. Vercel limits shape the design (§10). |
| D7 | **Voice: ElevenLabs Agents** with the Eleven v3 Conversational voice, the only ElevenLabs model that speaks Marathi. The agent uses **our backend as its "Custom LLM"**. | Owner's requirement. This way voice and text share one brain and one safety core. |
| D8 | **Models: Gemini (free tier) and Groq (free tier)**, routed through LiteLLM | Owner's requirement |
| D9 | **Likelihood bands, not percentages**, on the possible-causes screen | Model probabilities are not calibrated. CDSCO's 2025 guidance on medical-device software applies to diagnosis-like output. |
| D10 | **Mobile: Flutter.** Backend: **Python FastAPI + LangGraph.** Data: **Supabase** (Postgres, pgvector, Auth, Storage) in the Mumbai region | Result of the stack research |

---

## 3. System architecture

```
┌──────────────────────── Flutter app (Android) ────────────────────────┐
│ Screens · Riverpod state · go_router · Drift local cache              │
│ ML Kit OCR (Latin + Devanagari, on-device) · PII redaction            │
│ ElevenLabs Agents SDK (voice) · Supabase SDK (auth, storage)         │
└───────┬───────────────────────────┬──────────────────────────┬───────┘
        │ HTTPS + JWT (SSE stream)  │ WebRTC/WebSocket voice   │ signed upload
        ▼                           ▼                          ▼
┌─── FastAPI on Vercel (bom1) ───┐  ┌── ElevenLabs Agent ──┐  ┌─ Supabase ─┐
│ /chat  (text turns, SSE)       │◄─┤ Custom LLM → calls   │  │ Postgres   │
│ /v1/chat/completions (voice)   │  │ our endpoint (SSE)   │  │ pgvector   │
│ /medicine/scan  /report/parse  │  └──────────────────────┘  │ Auth       │
│ /hospitals  /history  /profile │                            │ Storage    │
│ /analytics  /voice/session     │───────────────────────────►│            │
│                                │                            └────────────┘
│  Safety Core ── Agent (LangGraph) ── Tools ── Providers (LiteLLM)      │
└──────────────────────────────────────────────────────────────────────┘
        │                         │
        ▼                         ▼
  Gemini (chat, vision,     Groq (fast routing,
  PDF, embeddings)          fallback, vision fallback)
```

### 3.1 Backend layering (SOLID: dependency inversion)

```
api/            FastAPI routers. Thin: auth, validation, streaming.
safety/         RedFlagEngine, OutputGuard, RepeatQueryGuard, AuditLogger
agent/          LangGraph graph, state, prompts, tool bindings
tools/          get_profile, ask_followup, search_knowledge, lookup_medicine,
                read_report, find_hospitals, get_history_pattern, save_history
domain/         Pure models and interfaces (ports): LLMProvider, Embedder,
                KnowledgeRetriever, DrugCatalog, FacilityDirectory,
                DocumentExtractor, Repository interfaces
adapters/       Implementations: LiteLLMProvider (Gemini/Groq), SupabaseRepo,
                PgVectorRetriever, GooglePlacesDirectory, OSMDirectory,
                PmjayDirectory, OpenFdaInteractions, GeminiVisionExtractor
ingest/         Offline jobs: knowledge corpus, drug catalogue, PM-JAY list
```

`domain/` depends on nothing. `adapters/` depend on `domain/`. `agent/`, `tools/` and `safety/` depend only on `domain/` interfaces. Adapters are wired in one composition root (`app/container.py`). Every external service is therefore replaceable and easy to mock in tests.

### 3.2 Flutter layering

This is a feature-first clean architecture:

```
lib/
  core/        theme (design tokens from UI board), l10n (en/hi/mr ARB),
               network (Dio + SSE), auth guard, error types
  features/
    onboarding/  splash, language, consent, age gate, profile setup
    auth/        Google sign-in, email OTP
    home/        dashboard, quick tips
    chat/        conversational triage, read-back chips, results
    emergency/   full-screen red-flag screen (works offline)
    medicine/    scan, confirm, result, generic alternative
    reports/     upload, confirm extracted values, summary/key values/chart
    hospitals/   map + list, filters (relevant / nearest / PM-JAY)
    history/     timeline, filters, analytics dashboard, visit summary
    profile/     health profile, consents, delete account, language
  shared/      widgets, charts (fl_chart)
```

Each feature is split into `data/` (repositories and DTOs), `domain/` (entities and use cases) and `presentation/` (widgets and Riverpod notifiers).

---

## 4. Screens (from the UI board, plus changes)

| # | Screen | Changes to the UI board |
|---|---|---|
| 1 | Splash | Unchanged |
| 2 | Language | **English, हिंदी, मराठी only.** Show script samples, not flags. |
| 2a | **Sign in** (new) | Google button, then an email OTP fallback |
| 2b | **Consent and age gate** (new) | Confirm 18+. Separate toggles for: history storage, report and photo processing, voice processing, location. Plain-language notice that free AI services (Google, Groq, ElevenLabs) process the data and may review it. States that AskMedi gives health information, not medical advice. |
| 2c | **Health profile** (new) | Age, sex, pregnancy (if applicable), known conditions, current medicines, allergies. Every field is skippable and editable later. |
| 3 | Home | Unchanged. The "Care+" tab is **dropped in v1**, leaving 4 tabs: Home, History, Hospitals, Profile. |
| 4 | Conversational triage | Adds **read-back chips** after each user turn ("Fever · 2 days · body ache — correct?"), which the user can edit. The follow-up question options stay tappable. |
| 4a | **Emergency** (new) | Full-screen red alert. Plain reason plus cited source. One-tap **112** and **108** (and **102** for pregnancy). Shows nearest saved hospitals. Works offline. |
| 5 | Possible causes | **Likelihood bands** ("More likely / Possible / Less likely") replace percentages. Every cause has a cited source. The "Talk to a Doctor" button is replaced by **"Find a hospital"** and **"Doctor visit summary"**. "Save to history" is automatic. |
| 6 | Scan medicine | Adds a **confirm step** ("Is this Paracetamol 500 mg?"). Shows a **Jan Aushadhi generic alternative** where one exists. Suitability wording becomes "Check with your pharmacist" plus the specific flags. |
| 7 | Upload report | Upload goes straight to Supabase Storage. Adds a **confirm extracted values** table before explaining. |
| 8 | Report summary | Unchanged tabs (Summary / Key values / Chart). High/low flags are **computed in code** from the report's own printed range. Adds a trend chart across reports. |
| 9 | Hospitals | Location bar at the top: "Current location", PIN code, area search or saved place (§6.3). Filters: Relevant to your problem, Nearest, **Accepts Ayushman card (PM-JAY)**. "Top rated" comes from Places ratings. |
| 10 | History | Filters: All, Symptoms, Medicines, Reports. Plus an **Analytics** tab (§8). |
| 11 | **Doctor visit summary** (new) | One page covering: symptoms timeline, answers given, medicines looked up, report values. Shared as PDF or WhatsApp. |
| 12 | **Profile and privacy** (new) | Edit profile, manage consents, export data, **delete account and all data**. |

---

## 5. The agent

### 5.1 Turn pipeline

Every text or voice turn goes through the same pipeline:

```
user turn
  → [1] Normalise: detect language (en/hi/mr/mixed), translate to canonical
        English symptom terms (LLM, structured output), keep original text
  → [2] RedFlagEngine (deterministic rules on normalised terms + raw text
        keyword lists in all 3 languages)
        └─ match → EMERGENCY response (fixed, pre-translated template +
                   cited rule source). Agent is NOT invoked. Audit logged.
  → [3] RepeatQueryGuard (reads audit history: same symptom cluster ≥3 times
        in 7 days → flat "please see a doctor" response + hospitals)
  → [4] Agent (LangGraph) plans + calls tools until it can respond
  → [5] OutputGuard validates the draft:
        - at least one valid citation for any medical claim
        - no banned patterns (diagnosis statements, doses, "you have X",
          "no need to see a doctor")
        - schema-valid structured output
        └─ fail → one repair attempt → still fail → safe fallback template
  → [6] Localise response to user's language; audit log; stream to client
```

### 5.2 Agent graph (LangGraph)

The nodes are `plan → act (tool calls) → observe → decide`, and the loop can stop at any point.

The agent can end a turn in three ways:
- **`ask_followup`.** Needed information is missing (duration, severity, age context, pregnancy, current medicines). The agent emits one question with 2–5 tappable options. The graph **interrupts** and resumes on the next user turn. At most 3 follow-ups per episode. After that, the agent must answer with what it has, conservatively.
- **`answer`.** Structured result: urgency level (Self-care / See a doctor soon / See a doctor today), possible causes with likelihood bands, what to do now, when to seek care, and citations.
- **`handoff`.** Hospital search, medicine lookup or report explanation, when the user's intent is one of those.

State is saved to Postgres after every step with the LangGraph Postgres checkpointer, keyed by `episode_id`. The Vercel functions are stateless, so this is what gives the agent memory between turns.

### 5.3 Tools

| Tool | Does | Backed by |
|---|---|---|
| `get_profile` | Returns a minimised profile: age band, sex, pregnancy, conditions, medicines, allergies | Supabase |
| `get_history_pattern` | Past episodes for similar symptoms and recent medicine lookups | Supabase (audit tables) |
| `ask_followup` | Emits a follow-up question and options, then interrupts | — |
| `search_knowledge` | Hybrid search (BM25 + vector) over the licensed corpus. Returns passages with `source_id`, title, URL and date | pgvector + Postgres full-text search |
| `lookup_medicine` | Brand or salt text → canonical salt(s), strength, uses, interaction and contraindication flags, Jan Aushadhi alternative | Drug catalogue + openFDA/RxNorm |
| `read_report` | Structured lab values from a stored report | Report tables |
| `find_hospitals` | Location + specialty hint → ranked list | Google Places + PM-JAY + OSM |
| `save_history` | Writes the episode summary (the audit trail is written automatically) | Supabase |

### 5.4 Model routing (LiteLLM)

| Task | Primary | Fallback |
|---|---|---|
| Language detection and symptom normalisation | Groq (small, fast model) | Gemini Flash |
| Agent reasoning and tool calls | Gemini Flash | Groq (larger model) |
| Final response in Hindi or Marathi | Gemini Flash | Groq (larger model) |
| Vision (strip) and document (report) extraction | Gemini Flash | Groq vision model |
| Embeddings | Gemini embedding model | — (the corpus is re-embedded if this changes) |

Exact model IDs live in config (`models.yaml`), never in code. They are checked against the providers' live model lists at implementation time, because free-tier model lineups change often.

On a rate-limit (429) or timeout, LiteLLM retries with backoff and then moves to the fallback. If every provider fails, the user sees "Service is busy — please try again in a minute". The emergency path never depends on an LLM.

### 5.5 Voice (ElevenLabs)

- **Session start.** The app calls `POST /voice/session`. The backend checks the user's JWT, creates a short-lived signed conversation URL through the ElevenLabs API, and passes a one-time `session_ref` as a dynamic variable.
- **Custom LLM.** The ElevenLabs agent is configured with our endpoint `/v1/chat/completions` (OpenAI-compatible, SSE). Each voice turn runs the §5.1 pipeline, the same one as text. `session_ref` maps to the user.
- The ElevenLabs agent handles STT, turn-taking and TTS (Eleven v3 Conversational voice).
- **Emergency during voice.** The response contains a spoken emergency message. The backend also pushes an `emergency` event to the app through Supabase Realtime, and the app opens the emergency screen.
- **Fallback when free minutes run out** (15 min/month on the free plan): push-to-talk. The app records a clip and uploads it; the backend sends the audio to Gemini for transcription and the normal pipeline runs; the phone's built-in text-to-speech reads the answer. Built-in TTS supports hi-IN and mr-IN, and the app checks at runtime.

> **To verify during implementation:** how ElevenLabs forwards dynamic variables or extra body fields to the Custom LLM endpoint, and whether the free plan allows a Custom LLM.

---

## 6. Multimodal pipelines

The rule is: **the model extracts, the code decides, the user confirms.**

### 6.1 Medicine strip

1. The camera captures the strip. ML Kit (Latin + Devanagari) OCRs it on the phone and the text is shown straight away.
2. The image and OCR text go to `/medicine/scan`. Gemini vision returns JSON: `{brand, salts[{name, strength}], form, manufacturer, expiry?, confidence}`.
3. Fuzzy match against the drug catalogue by brand and salt (trigram similarity).
4. The app shows the best match and asks the user to confirm. If the user rejects it, they see alternatives or can type the name.
5. The explanation comes from catalogue fields and licensed sources. Profile checks (conditions, allergies, other medicines) are deterministic lookups against interaction and contraindication data, phrased as "Check with your pharmacist because…".
6. A Jan Aushadhi alternative is shown when one exists with the same salt and strength.

### 6.2 Medical report

1. The user picks a PDF or image. On the phone, ML Kit OCR finds and blanks lines that match a name, phone number, patient ID or address (regex plus a list of label keywords). Images are redacted by drawing boxes. PDFs are rasterised page by page and redacted.
2. The redacted file is uploaded straight to Supabase Storage (signed URL, 10 MB limit).
3. `/report/parse`: Gemini extracts `[{test_name, value, unit, ref_low, ref_high, ref_text, page}]` along with the report date and lab type.
4. Validation in code: units are normalised; physiologically impossible values are rejected; any row without a parsable value is marked "unreadable".
5. The user confirms or edits the extracted table.
6. In code: status is set to low, normal or high **from the report's own printed range**. If the report has no range, the MedlinePlus reference is used and marked as such.
7. The LLM writes the plain-language summary, citing MedlinePlus lab-test pages. Chart data comes from stored values.
8. Values are stored per test, per date, and feed the trend charts.

---

## 6.3 User location (for hospital search and emergency)

**Resolution order:**
1. **Device GPS**, via `geolocator`, with a just-in-time permission prompt. The prompt appears the first time the user opens Hospitals, the Emergency screen or "Find a hospital", never at signup. Only foreground, "while using the app" permission (`ACCESS_COARSE_LOCATION` + `ACCESS_FINE_LOCATION`). No background location.
2. **Manual entry** when permission is denied or GPS fails:
   - **PIN code (6 digits):** looked up in the data.gov.in All-India Pincode Directory, which has coordinates. It is bundled as a compact on-device table, so the lookup is free and offline.
   - **Area/city text:** OSM Nominatim search, called by the backend with a proper User-Agent, rate-limited to 1 req/s and cached.
3. **Saved places** (Home, Work, custom labels), for one-tap reuse or searching for someone elsewhere.
4. **Last known location + last nearby-hospitals result**, cached on the device so the Emergency screen works offline.

**Privacy rules:**
- Coordinates are sent **only** to the `find_hospitals` tool's backend adapter, as request context from the app. They are never put in LLM prompts. The LLM sees `location_available: true|false` and receives hospital names and distances.
- Coordinates are rounded to 2 decimal places (about 1 km) before logging. There is no location history: only user-created `saved_places` are stored.
- There is a separate consent purpose, `location`. Manual PIN entry works without it.

**Emergency screen:** adds a **"Share my location"** button. It opens WhatsApp or SMS with a Google Maps link to the current position. The user sends it. The app never sends or calls on its own.

---

## 7. Knowledge and safety content (no clinician, so sources are the authority)

### 7.1 Licensed corpus (RAG)

| Source | Use | Licence handling |
|---|---|---|
| MedlinePlus health topics, medical tests, "when to call for help" sections | Stored and embedded | Public domain (US government). Credit "MedlinePlus.gov". Do **not** ingest the copyrighted ADAM encyclopedia or drug monographs. |
| WHO fact sheets | Citation plus short quotes with a link | CC BY-NC-SA 3.0 IGO. Fine for a non-commercial prototype. Needs permission before monetising. |
| ICMR Standard Treatment Workflows | Citation plus link. Red-flag rules reference their "refer immediately" criteria | No explicit reuse licence. Link, don't bulk copy. Email ICMR for permission before launch. |
| NLEM 2022, Jan Aushadhi product list | Drug catalogue | Government publications, cited |
| openFDA labels (CC0) and RxNorm | Salt-level interactions and contraindications | Free |
| Kaggle A–Z Indian medicine dataset | **Brand → salt mapping only.** Its prices are never shown. | Licence unclear. Replaceable adapter. |

Excluded: NHS (licensed for UK users only), Mayo Clinic (paid licence), DDInter (non-commercial licence), Manchester Triage System and NHS Pathways (proprietary).

**Ingest.** Chunks of about 500 tokens with heading context. Each chunk stores `source_id, title, url, publisher, retrieved_at, licence`. English is canonical. Answers are generated in the user's language, and each citation links to the original page. The corpus is rebuilt by a GitHub Actions job.

**Retrieval.** Hybrid search: BM25 via Postgres full-text search, plus pgvector cosine similarity, merged with reciprocal rank fusion, top 6.

**Grounding contract.** The agent must cite `source_id`s that appear in that turn's retrieved set, and OutputGuard rejects any other citation. If nothing relevant is retrieved, the answer is: "I couldn't find a trusted source for this — please consult a doctor."

### 7.2 Red-flag rules (deterministic)

- Stored as versioned YAML (`safety/rules/v1.yaml`). Each rule has an `id`, trigger conditions (normalised symptom terms plus age/pregnancy qualifiers), trilingual keyword lists, the action (`emergency_112`, `emergency_108`, `urgent_today`), and a **mandatory `source` citation** (WHO ETAT, ICMR STW or MedlinePlus).
- The v1 rule set covers:
  - chest pain or pressure
  - stroke signs (FAST)
  - difficulty breathing
  - severe bleeding
  - loss of consciousness or seizure
  - suicidal thoughts (plus the Tele-MANAS helpline, **number to be verified from an official source before shipping**)
  - poisoning or overdose
  - severe allergic reaction
  - high fever with stiff neck, rash or confusion
  - pregnancy with bleeding or severe abdominal pain
  - severe dehydration signs
  - high fever in an infant (not applicable in v1 because users are 18+; kept for the future)
- **Bias.** When a rule partly matches, the agent must ask about the missing qualifier as its next follow-up.
- **Unreviewed by a clinician.** The rules are labelled `review_status: source-derived` so a clinician can sign them off later without code changes.

### 7.3 Conservative defaults

- No doses, no prescription recommendations, no "you have X" and no "no need to see a doctor".
- If signals are uncertain or conflicting, the urgency level is raised, never lowered.
- Every result screen carries: "AskMedi gives health information, not a diagnosis. Please consult a doctor."
- An AI disclosure is shown at the start of each conversation. ElevenLabs requires this too.

---

## 8. History and account analytics

Every analytic is computed from the audit and history tables (§11), per account:

| Widget | Source |
|---|---|
| Symptom trends over time (bar chart, weekly) | `episodes.symptoms` |
| Most frequent concerns (bar chart) | `episodes.symptoms` aggregated |
| Report values over time (line chart per test) | `report_values` |
| Medicine log (timeline) | `medicine_lookups` |
| Average number of follow-ups (metric) | `episodes.followup_count` |
| Repeat-query flag (banner) | RepeatQueryGuard results |

Aggregations run as Postgres views or RPCs, protected by row-level security, so the app reads them directly from Supabase with the user's JWT.

---

## 9. Auth, privacy and data minimisation

- **Auth.** Supabase Auth with Google OAuth and email OTP. FastAPI verifies the Supabase JWT on every request.
- **RLS.** Every user table has `user_id = auth.uid()` policies. The backend uses the user's JWT for user data and the service role only in ingest jobs.
- **Minimisation.** Name, email, phone and `user_id` are **never** sent to Gemini, Groq or ElevenLabs. The LLM context uses an `episode_id` and a minimised profile only.
- **Redaction.** Reports are redacted on the phone before upload (§6.2).
- **Consents.** Stored per purpose with a timestamp. Withdrawing one purpose disables that feature and deletes its data.
- **Delete account.** A cascade delete across every table and the storage bucket, confirmed by the user.
- **Export.** JSON export of the user's data.
- **Retention.** Raw uploaded files are deleted 30 days after extraction. The extracted values stay.
- **Security.** Secrets are Vercel environment variables. Nothing secret ships in the app except the Supabase anon key, which RLS protects. Rate limiting per user on expensive endpoints.

---

## 10. Deployment (Vercel)

- One FastAPI app deployed as a Vercel Python function in region `bom1`, with Fluid compute. Streaming responses (SSE) are used for chat and the Custom LLM endpoint.
- **Limits and how the design handles them:**
  - Duration is 300 s on Hobby, and one turn is well under that.
  - Request and response bodies are capped at 4.5 MB, so files go through Supabase Storage signed uploads.
  - The functions are stateless, so agent state is saved by the LangGraph Postgres checkpointer.
- **Scheduled jobs** (knowledge re-ingest, PM-JAY and Jan Aushadhi refresh, deleting raw files after 30 days) run on GitHub Actions cron, which is free. A daily Vercel cron handles the lightweight retention job.
- **Environments.** `dev` and `prod` Supabase projects. Vercel preview deployments point at `dev`.
- **Portability.** The same FastAPI app runs in Docker, so Cloud Run, Render or Fly are an easy move if Vercel's limits start to hurt.
- **Android distribution.** Signed APK for testers, then Play Store internal testing (health apps declaration and privacy policy URL required).

Note: the Vercel Hobby plan is for personal, non-commercial use. Public launch needs Pro.

---

## 11. Data model (Postgres)

```
profiles(user_id PK→auth.users, display_name, language, birth_year, sex,
         pregnant bool null, created_at)
health_conditions(id, user_id, name, code null)
user_medicines(id, user_id, salt, brand null, since null)
allergies(id, user_id, substance)
consents(id, user_id, purpose[age_18_plus|terms|history|media|voice|location],
         granted bool, at)                                -- append-only log
saved_places(id, user_id, label, lat, lng, pincode null, created_at)

episodes(id, user_id, kind[symptom|medicine|report|hospital], started_at,
         language, symptoms text[], urgency, followup_count, outcome jsonb,
         red_flag_rule_id null, repeat_flag bool)
turns(id, user_id, episode_id, role, text_original, text_normalised, lang, at)
audit_events(id, user_id, episode_id null,
             type[redflag|tool_call|guard_reject|answer|…],
             payload jsonb, model null, latency_ms, at)      -- append-only
citations(id, user_id, episode_id, turn_id, source_id)

-- Every user-owned table carries user_id (default auth.uid()) so RLS is a
-- simple `user_id = auth.uid()` check. The backend's direct Postgres
-- connection runs each unit of work as `authenticated` with the caller's JWT
-- claims set, so RLS applies to backend writes too.

medicine_lookups(id, user_id, episode_id, brand, salts jsonb, confirmed bool,
                 at)
reports(id, user_id, storage_path, report_date, lab_type, status, at)
report_values(id, report_id, user_id, test_code, test_name, value, unit,
              ref_low, ref_high, status[low|normal|high|unknown])

kb_sources(id, title, url, publisher, licence, retrieved_at)
kb_chunks(id, source_id, heading, content, lang, embedding vector, tsv)
drugs(id, brand, salts jsonb, form, manufacturer, source)
jan_aushadhi(id, name, salts jsonb, strength, mrp)
facilities(id, name, lat, lng, pmjay bool, specialties text[], source)

langgraph checkpoint tables (managed by library)
```

---

## 12. Error handling

| Failure | Behaviour |
|---|---|
| LLM 429 or timeout | LiteLLM fallback chain; if all fail, "busy, try again". The emergency path is unaffected. |
| OutputGuard rejects the draft twice | Safe template: "I can't give a reliable answer to this. Please consult a doctor." Plus the hospitals button. |
| Retrieval finds nothing | The "No trusted source" response |
| OCR or vision confidence is low | Ask the user to retake the photo or type the name |
| Report value can't be parsed | The row is marked "unreadable" and never guessed |
| ElevenLabs quota used up or error | Switch to push-to-talk mode, with a banner |
| No network | Emergency screen, emergency numbers and saved hospitals work offline. Chat shows an offline state. |
| Places API over quota | OSM and PM-JAY directory only |

---

## 13. Testing

- **Backend unit tests (pytest):**
  - A table-driven test for every red-flag rule, with positive and negative cases in en, hi, mr and code-mixed text.
  - OutputGuard patterns.
  - Report status calculation.
  - Drug fuzzy matching.
  - Retrieval ranking.
  - All providers are mocked through the domain interfaces.
- **Agent evals.** A golden set of about 60 scripted conversations (20 per language, including code-mixed ones) with expected properties, never exact text:
  - the red flag triggered, or it didn't
  - at least one follow-up asked when duration was missing
  - citations present and valid
  - no banned patterns
  - response in the right language

  Runs in CI against the real free-tier APIs on a nightly schedule. Mocks run on each PR.
- **Extraction evals.** 15–20 real, redacted strip photos and sample reports, checked against expected JSON.
- **Flutter.** Unit tests for use cases, widget tests for the key screens (chat chips, emergency, report confirmation), and one integration test for the login → chat → history flow.
- **Manual device testing** on a low-end Android phone (2–3 GB RAM).

---

## 14. Build phases

| Phase | Deliverable |
|---|---|
| 0. Foundation | Repos, CI, Supabase dev/prod, schema and RLS, FastAPI skeleton on Vercel, Flutter shell with theme and l10n, auth (Google + email OTP), consent, age gate, profile, audit logger, provider interfaces and LiteLLM |
| 1. Safety core | RedFlagEngine and rules v1 with tests, emergency screen (offline), OutputGuard, RepeatQueryGuard |
| 2. Knowledge | Ingest pipeline, hybrid retrieval, grounding contract |
| 3. Hospitals | Places + OSM + PM-JAY directory, map/list, filters |
| 4. Medicine scan | ML Kit OCR, vision extraction, drug catalogue, confirm flow, Jan Aushadhi |
| 5. Text agent | LangGraph graph, tools, follow-ups, results screen, read-back chips |
| 6. Reports | Redaction, upload, extraction, confirm, summary, charts |
| 7. Voice | ElevenLabs agent + Custom LLM endpoint, push-to-talk fallback |
| 8. History and analytics | Timeline, analytics dashboard, doctor visit summary, export/delete |
| 9. Hardening | Evals, low-end device performance, Play internal testing |

---

## 15. Open items to verify during implementation

1. Current free-tier model IDs and limits for Gemini and Groq (check the live model lists).
2. Whether the free ElevenLabs plan allows a Custom LLM, and how dynamic variables reach the endpoint.
3. That the Gemini embedding model and its dimension are available on the free tier.
4. Whether the phone's built-in TTS has hi-IN and mr-IN voices on the test devices.
5. The Tele-MANAS helpline number, from an official MoHFW source.
6. Whether Google Places free usage covers testing volume. The free monthly allowance must be confirmed in the Google Cloud console.
7. Whether PM-JAY hospital list access is stable enough to scrape, or whether we fall back to the published PDFs.
