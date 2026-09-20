# AskMedi — Your Health, Our Concern

Multilingual (English · हिंदी · मराठी) health assistant for India.

- `backend/`  FastAPI, deployed on Vercel (bom1)
- `mobile/`   Flutter Android app
- `supabase/` Database migrations and RLS tests
- `docs/`     Design spec and implementation plans

See `docs/superpowers/specs/2026-09-19-askmedi-design.md`.

## Database

The schema lives in `supabase/migrations/`. The hosted project's schema was
applied through the Supabase MCP `apply_migration`, so the hosted
`supabase_migrations` history holds Supabase-generated versions `20260919170115`
(core_schema) and `20260919170926` (rls_hardening) instead of the file prefixes
`20260919000001` / `20260919000002`. Before the first Supabase-CLI `db push`,
reconcile them so the CLI does not try to replay migration 1:

```
supabase migration repair --status reverted 20260919170115 20260919170926
supabase migration repair --status applied 20260919000001 20260919000002
```

(or rename the local files to the remote versions).

New tables must `revoke all ... from anon, authenticated` and re-grant only what
is needed: Supabase's default privileges grant everything, including `TRUNCATE`,
which bypasses RLS.
