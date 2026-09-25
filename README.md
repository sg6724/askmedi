# AskMedi — Your Health, Our Concern

Multilingual (English · हिंदी · मराठी) health assistant for India. It asks follow-up questions
before answering, cites the sources it used, catches emergencies with fixed rules (no AI in that
path), reads medicine strips and lab reports, finds nearby hospitals, talks by voice, and keeps a
per-account history with analytics. It gives health information, not a diagnosis.

| Part | Where | What |
|---|---|---|
| `backend/` | https://askmedi-api.vercel.app (Vercel, Mumbai `bom1`) | FastAPI: chat, medicine, reports, hospitals, voice |
| `mobile/` | Chrome (web build) and Android APK (built by GitHub Actions) | Flutter app |
| `supabase/` | Supabase project `ahgdhxjfdjbrguhcnnum` | Postgres schema, row-level security, pgTAP tests |
| `docs/` | | Design spec, plans, API contract, status |

Status and demo script: `docs/superpowers/plans/2026-09-25-demo-status.md`.
API contract: `docs/superpowers/plans/2026-09-25-demo-build-contract.md`.

## Services (all free tiers)

- **Auth and data:** Supabase (Google sign-in, email + password; every table protected by RLS).
- **AI:** Groq `gpt-oss-120b` for chat, Gemini for reading images/PDFs and for Google-Search-grounded
  answers; MedlinePlus search is the source fallback when the Gemini free quota (20 requests/day per
  model) runs out, and Groq vision reads images when Gemini vision is out. Model IDs live only in
  `backend/config/models.yaml`.
- **Medicine data:** openFDA drug labels. **Hospitals:** OpenStreetMap (Nominatim + Overpass).
- **Voice:** ElevenLabs speech-to-text (`scribe_v1`) and text-to-speech (`eleven_v3`, Hindi + Marathi).

## Layout

```
backend/askmedi/
  api/        thin FastAPI routers           domain/    ports (interfaces) + pure logic
  safety/     red-flag rules (rules/v1.yaml), output guard, repeat-query guard
  services/   use cases: chat, medicine, reports, hospitals, voice
  adapters/   Gemini, Groq/LiteLLM, ElevenLabs, openFDA, OSM, MedlinePlus, Postgres
  container.py  wires adapters into services
backend/tests/          unit tests with fakes (no network)
mobile/lib/features/<feature>/{data,domain,presentation}
mobile/test/            widget/unit tests with fake repositories (no network)
mobile/test_live/       live end-to-end test against the deployed services
```

## Run

Backend (Python 3.12, uv). `backend/.env` needs `SUPABASE_URL`, `DATABASE_URL`, `GEMINI_API_KEY`,
`GROQ_API_KEY`, `ELEVENLABS_API_KEY` (see `backend/.env.example`).

```sh
cd backend
uv run pytest -q                      # unit tests
uv run --env-file .env pytest -m integration   # needs TEST_DATABASE_URL
vercel deploy --prod --yes            # deploy (env vars are set on the Vercel project)
```

App (Flutter). `mobile/env/dev.json` holds `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable key)
and `API_BASE_URL` (see `mobile/env/example.json`; git-ignored).

```sh
cd mobile
flutter gen-l10n && flutter analyze && flutter test
flutter build web --release --dart-define-from-file=env/dev.json   # then serve build/web
flutter test test_live --dart-define-from-file=env/dev.json ...     # see mobile/test_live/README.md
```

Android APK: GitHub Actions → **Android APK** workflow (runs on every push to `main` that touches
`mobile/`, or manually). It reads the repository variables `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`API_BASE_URL`, and uploads `askmedi-apk` as an artifact:
`gh run download <run-id> -R sg6724/askmedi -n askmedi-apk`.

## Database

The schema lives in `supabase/migrations/`. The hosted project's schema was applied through the
Supabase MCP `apply_migration`, so the hosted `supabase_migrations` history holds generated versions
`20260919170115` (core_schema), `20260919170926` (rls_hardening) and `20260925123914` (features)
instead of the file prefixes `20260919000001` / `20260919000002` / `20260925000003`. Before the first
Supabase-CLI `db push`, reconcile them so the CLI does not replay them:

```
supabase migration repair --status reverted 20260919170115 20260919170926 20260925123914
supabase migration repair --status applied 20260919000001 20260919000002 20260925000003
```

(or rename the local files to the remote versions).

New tables must `revoke all ... from anon, authenticated` and re-grant only what is needed:
Supabase's default privileges grant everything, including `TRUNCATE`, which bypasses RLS.
