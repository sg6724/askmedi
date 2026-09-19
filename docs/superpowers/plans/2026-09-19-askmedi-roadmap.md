# AskMedi: Execution Roadmap

**Spec:** `docs/superpowers/specs/2026-09-19-askmedi-design.md`

This roadmap splits the build into phases. Every phase produces working, testable, deployed software. Each phase gets its own detailed task-by-task plan (`docs/superpowers/plans/2026-09-19-phase-N-*.md`), written just before the phase starts. Later phases depend on facts we can only check at that point: live free-tier model IDs, ElevenLabs Custom LLM details, and data-source access.

## Repository layout (all phases)

```
askmedi/
  backend/        FastAPI + LangGraph (Python 3.12), deployed to Vercel (bom1)
  mobile/         Flutter app (Android first)
  supabase/       SQL migrations, pgTAP tests, config
  ingest/         Offline data jobs (knowledge corpus, drugs, facilities) — Phase 2+
  docs/           Specs and plans
  .github/        CI and scheduled jobs
```

## Phases

| Phase | Plan file | Deliverable | Exit criteria |
|---|---|---|---|
| **0. Foundation** | `2026-09-19-phase-0-foundation.md` (written) | Monorepo and CI. Supabase schema with RLS. FastAPI on Vercel with JWT auth, LLM provider port with fallbacks, and an audit logger. Flutter app with theme, en/hi/mr localisation, Google and email-OTP sign-in, age gate, consent, health profile, and a 4-tab shell. | A real user installs the APK, signs in with Google or email OTP, completes consent and profile, and lands on Home. `/me` on Vercel returns their user id. All tests are green in CI. |
| **1. Safety core** | phase-1-safety.md | RedFlagEngine + `rules/v1.yaml` (every rule sourced), a trilingual keyword matcher, the emergency screen (offline, one-tap 112/108/102, "Share my location" via WhatsApp/SMS), OutputGuard, RepeatQueryGuard | Table-driven tests pass for every rule in en/hi/mr/code-mixed. The emergency screen works in airplane mode. |
| **2. Knowledge (RAG)** | phase-2-knowledge.md | Ingest of MedlinePlus (public-domain parts) and WHO/ICMR citation records; hybrid retrieval (full-text + pgvector, reciprocal rank fusion); grounding contract | Retrieval eval: expected source in the top 6 for ≥80% of 40 test queries. Every chunk carries its source, licence and URL. |
| **3. Hospitals** | phase-3-hospitals.md | Location resolution: GPS with just-in-time permission, offline PIN-code table, Nominatim area search, saved places, cached last location. FacilityDirectory port with Google Places, OSM and PM-JAY adapters; symptom → specialty map; map/list UI with filters | Search returns ranked results for a real location. The PM-JAY filter works. The app falls back to OSM when Places fails. |
| **4. Medicine scan** | phase-4-medicine.md | ML Kit OCR, Gemini vision extraction, drug catalogue (brand→salt, Jan Aushadhi), fuzzy match, confirm flow, interaction flags | 15 real strip photos: correct salt after confirmation in ≥13 of them. A generic alternative is shown where one exists. |
| **5. Text agent** | phase-5-agent.md | LangGraph agent with Postgres checkpointer, tools, follow-ups with interrupt/resume, read-back chips, results screen with likelihood bands and citations, SSE streaming | Golden eval (60 conversations, en/hi/mr/mixed): 100% of red flags routed, 100% of answers cited, 0 banned patterns. |
| **6. Reports** | phase-6-reports.md | On-device PII redaction, signed upload, extraction, confirmation table, deterministic flags, summary, per-test trend charts | 10 sample reports: all values extracted or marked unreadable, with none invented. No PII in uploaded files. |
| **7. Voice** | phase-7-voice.md | ElevenLabs agent (Eleven v3 Conversational voice) → our OpenAI-compatible `/v1/chat/completions`; `/voice/session`; emergency push via Realtime; push-to-talk fallback | Full voice triage in Marathi and Hindi. The emergency path triggers the screen during a call. The fallback works when the quota is exhausted. |
| **8. History and analytics** | phase-8-history.md | Timeline and filters, analytics views/RPCs, doctor-visit summary PDF/share, data export, account deletion | Every analytics widget is computed from real account data. Deleting an account removes every row and file. |
| **9. Hardening and release** | phase-9-release.md | Nightly evals, low-end device performance pass, Play internal testing (health declaration, privacy policy) | App is live on the Play internal track. There are no P1 bugs. |

## Cross-cutting rules for every phase

- TDD: write the failing test first, then the minimal code, then commit.
- No provider SDK is imported outside `backend/askmedi/adapters/`.
- Model IDs live only in `backend/config/models.yaml`.
- Every medical claim shown to a user cites a stored `kb_sources` id.
- User-visible strings go only through ARB files (en, hi, mr).
