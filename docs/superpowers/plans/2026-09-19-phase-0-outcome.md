# Phase 0 (Foundation) — Outcome, Rulings and Carry-forward

**Branch:** `phase-0-foundation` (30 commits on top of `main` @ 717b44b) · **Plan:** `2026-09-19-phase-0-foundation.md` · **Spec:** `../specs/2026-09-19-askmedi-design.md`

Status: **code-complete, integration unproven.** All 15 plan tasks are implemented, reviewed one by one (spec + quality, with scoped re-reviews after fix rounds), then reviewed as a whole branch (no Critical findings) and given one final fix wave.
Verified locally: backend `pytest` 28 passed + 1 skipped (integration, needs a DB); mobile `flutter analyze` clean, `flutter test` 57 passed; the schema is live on the Supabase project with 19 pgTAP assertions passing (run-copy) and the security advisor clean.

## Owner checklist (nothing below has been done — all need the owner's accounts/devices)
1. **Rotate the database password** (it was pasted in chat). Update `backend/.env` (`DATABASE_URL`, `TEST_DATABASE_URL`).
2. **Supabase Auth dashboard:** Google provider (Google Cloud OAuth *Web* client, redirect `https://<ref>.supabase.co/auth/v1/callback`), add redirect URL `com.askmedi.askmedi://login-callback`, custom SMTP (Resend), Magic-Link template must show `{{ .Token }}`; Project Settings → JWT Keys must be on **asymmetric** signing keys (ES256/RS256).
3. **Gemini + Groq API keys** into `backend/.env`, then `uv run --env-file .env python scripts/llm_smoke.py`; replace unverified model IDs in `backend/config/models.yaml` and its header line.
4. **Vercel deploy** (`npx vercel login`, `vercel link` in `backend/`, env vars `SUPABASE_URL`, `DATABASE_URL` (transaction pooler :6543), `GEMINI_API_KEY`, `GROQ_API_KEY`; watch the first deploy log — if "pattern doesn't match any Serverless Functions" appears for `vercel.json` `functions`, delete that block); then `curl /health` (200) and `/me` (401 without token).
5. **Phone run** (needs Android SDK + a phone): `flutter run --dart-define-from-file=env/dev.json` with `mobile/env/dev.json` from `env/example.json`; walk the Task 14 checklist (language → Google sign-in → email OTP → consent → profile → Home shows "Connected to AskMedi server"; restart lands on Home).
6. **GitHub:** create the repo, add the remote, push; the first CI run is the first real run of `supabase test db` (pgTAP file `supabase/tests/rls_core_test.sql` was previously run only as a run-copy) and of the workflow itself.
7. **Migration history:** see README "Database" — repair the hosted history before any Supabase-CLI `db push`.
8. Decide whether to create a separate prod Supabase project (spec §10 wanted dev + prod; everything currently lives in one project).
9. Docker Desktop's 26 GB data disk on C: (`%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`) is no longer needed by this project — remove it via Docker Desktop if not used elsewhere.

## Rulings made during execution (controller decisions; each with cost if wrong)
Process/environment
- Task 1 done by the controller; work on branch `phase-0-foundation` (branch, not worktree). *Cost: none.*
- Commit trailer "Claude Sonnet 5"; implementers naming themselves (Haiku 4.5) accepted. *Cosmetic.*
- `.mcp.json` committed (project ref only); `.claude/settings.local.json`, `.tools/` ignored. *Cosmetic.*
- Backend pinned to Python 3.12 (`.python-version`). *Re-sync cost.*
- All caches/temp on D: via `/d/.askmedi-cache/*.sh` (C: was full); Flutter SDK cloned into `D:\askmedi\.tools\flutter` (git-ignored). *None.*
- Backend/DB tasks run before Flutter existed; owner-gated steps (Task 5 live model check, Task 7 dashboard/deploy, Task 11 Google/SMTP config, Task 14 phone run, Task 15 push) skipped by implementers and listed above. *~1 h of owner work.*
- Task 2 re-scoped from local Docker to the Supabase MCP (project verified empty first); Task 6/7 integration tests run against the same project via the session pooler (direct host is IPv6-only). *Transient `@test.dev` rows in the main project; fixtures clean up.*
- Plan defect fixed pre-flight: pgTAP DELETE assertion now `throws_ok 42501` (original could never pass); `__tresults__` grant later removed (table does not exist on the project's pgTAP 1.3.3). *First CI run confirms.*
- `.vercelignore` added so `backend/.env` cannot be uploaded to Vercel. *None.*
Security/data model
- RLS hardening as a forward migration (`20260919000002_rls_hardening.sql`): composite `(child_id, user_id)` ownership FKs, `revoke all` + least-privilege regrant (TRUNCATE bypasses RLS), `profiles.user_id default auth.uid()`, `touch_updated_at` search_path pinned. *One more migration on the owner's project.*
- `audit_events.episode_id` → `ON DELETE SET NULL (episode_id)` (a user deleting an episode must not erase the audit trail). *If wrong: audit rows outlive episode deletion — privacy-review question.*
- LLM provider: parse inside the `try`; empty/None/blank content = failed model; error text and logs carry only `"<model>: <ExceptionTypeName>"` (never `str(exc)`, no `exc_info`). *One more fix round if wrong.*
- Backend test hook for Windows event loop only under `sys.platform == "win32"`; `Database` loop-affinity documented (one long-lived loop; single instance built in `build_container`). *A Vercel per-invocation-loop hang would surface at deploy.*
Mobile
- INTERNET permission added to the main manifest; OAuth deep-link route `/login-callback` in `Routes.preApp`; PKCE stays default; OTP email passed via go_router `extra`, not the URL; `signedInProvider` read tolerantly. *A wrong choice would break Google sign-in on device.*
- Language screen: button pinned under an `Expanded(ListView)` (large-text overflow). Chip fields: pending text committed on Save + "+" button (new ARB key `addItem`); text controllers later hoisted into the screen state. `onboardingStatusProvider` and the Home providers have Riverpod retry disabled; Home providers are `autoDispose`; shared `effectiveSignedInProvider` removes the cold-start sign-in flash. *Each ruled after a reviewer proved the defect; costs were one fix round each.*
- Deferred on purpose: auth error taxonomy + OTP resend (Phase 9). *Confusing errors for early testers; back-navigation is the recovery.*
- Tab placeholders use ARB keys (History/Hospitals) instead of English literals. *None.*
Final fix wave (from the whole-branch review)
- Settings `hide_input_in_errors=True`; verifier rejects empty/blank/non-string `sub` and ES256 is pinned by a test; failed onboarding refetch routes to the splash Retry; app label "AskMedi"; README "Database" note.

## Deferred / carry-forward (triaged by the final reviewer)
**Phase 1 (safety core):** every new `public` table migration must `revoke all ... from anon, authenticated` and regrant only what is needed (or `ALTER DEFAULT PRIVILEGES`); users can DELETE their own `episodes`, which erases the symptom history RepeatQueryGuard reads — decide on an append-only snapshot.
**Phase 5 (agent/LLM):** `asyncio.wait_for` backstop for `timeout_s`; CancelledError/malformed-response tests; `citations(turn_id)` and `audit_events(episode_id)` indexes; `unique (id, episode_id)` on turns + composite FK so a citation's turn must be in the citation's episode; `(select auth.uid())` in policies for performance.
**Phase 8 (history/profile/privacy):** `signOut()` error handling; client-settable `created_at` on `consents`/`audit_events` (column-level insert grants) + `current_consents` tie-breaker; consent notice/terms version column; `profiles` select with explicit `.eq('user_id', …)`; profile-EDIT must use a transactional RPC (`replace_health_profile`) instead of `saveOnboardingProfile`; validate `LocaleController` saved code against `supportedAppLocales`; hoisted chip fields still silently ignore >120-char text (show an error).
**Phase 9 (hardening/release):** auth error taxonomy + OTP resend/change email (log `AuthException.code` only); JWKS outage → 503 (needs a wider `TokenVerifier` port) and no JWKS refetch on arbitrary `kid`; `WWW-Authenticate` on 401, HS256/`alg=none`/missing-claim tests; consent AI-notice wording ("don't enter real medical info" if desired) and danger-red contrast (~4.2:1 < 4.5:1); hi/mr gender-neutral wording pass by a native speaker (`howCanIHelp`: hi masculine, mr feminine); CI tuning after the first run (pin Postgres major/CLI version, `cancel-in-progress` only for PRs, SHA-pin actions); template leftovers (mobile README, `cupertino_icons`, Play signing).
**Accepted as-is:** `AppStatus` lacks `==`/`hashCode`, loose `startsWith(Routes.signIn)`, GoRouter never disposed, backend lint/typing polish.

## Known unproven areas
No test runs the real `SupabaseAuthRepository`/`SupabaseConsentRepository`/`SupabaseProfileRepository`/`SupabaseOnboardingRepository` (all mobile tests use fakes); the wire contract (tables, columns, purposes) was verified by hand against the schema. The CI workflow, the Vercel deploy and the phone flow have never run. `models.yaml` model IDs are unverified against live providers.
