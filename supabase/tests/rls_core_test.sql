begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

-- pgTAP's result sequence is owned by the connecting role; the tests below
-- run as `authenticated`, which needs to use it (see pgTAP docs, "as another role").
-- (pgTAP 1.3.x has no __tresults__ table; it keeps state in __tcache__, already granted to PUBLIC.)
grant all on sequence __tresults___numb_seq to public;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

insert into public.profiles (user_id, language, birth_year) values
  ('11111111-1111-1111-1111-111111111111', 'en', 1995),
  ('22222222-2222-2222-2222-222222222222', 'hi', 1990);

insert into public.audit_events (user_id, type, payload) values
  ('22222222-2222-2222-2222-222222222222', 'answer', '{}');

insert into auth.users (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'c@test.dev');

-- ownership fixtures (seeded as the table owner, before switching role)
insert into public.episodes (id, user_id, kind, language) values
  ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'symptom', 'en'),
  ('a0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'symptom', 'en'),
  ('b0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'symptom', 'en');
insert into public.turns (id, user_id, episode_id, role, text_original) values
  ('b0000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222',
   'b0000000-0000-0000-0000-000000000001', 'user', 'hello');

-- act as user A
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select count(*) from public.profiles)::int, 1,
  'user A sees only own profile');

select is((select count(*) from public.audit_events)::int, 0,
  'user A cannot see user B audit events');

select lives_ok(
  $$insert into public.consents (purpose, granted) values ('terms', true)$$,
  'user A can insert own consent (user_id defaults to auth.uid())');

select is((select user_id::text from public.consents limit 1),
  '11111111-1111-1111-1111-111111111111',
  'consent user_id defaulted to caller');

select throws_ok(
  $$insert into public.consents (user_id, purpose, granted)
    values ('22222222-2222-2222-2222-222222222222', 'terms', true)$$,
  '42501', null,
  'user A cannot insert a consent for user B');

select throws_ok(
  $$insert into public.consents (purpose, granted) values ('marketing', true)$$,
  '23514', null,
  'unknown consent purpose rejected');

select lives_ok(
  $$insert into public.audit_events (type, payload) values ('answer', '{}')$$,
  'user A can append own audit event');

select throws_ok(
  $$delete from public.audit_events$$,
  '42501', null,
  'audit events are append-only (DELETE privilege is not granted)');

-- hardening (migration 20260919000002)
select is(has_table_privilege('authenticated', 'public.episodes', 'TRUNCATE'), false,
  'authenticated has no TRUNCATE on episodes (TRUNCATE bypasses RLS)');

select is(has_table_privilege('authenticated', 'public.profiles', 'TRUNCATE'), false,
  'authenticated has no TRUNCATE on profiles (TRUNCATE bypasses RLS)');

select throws_ok(
  $$insert into public.turns (episode_id, role, text_original)
    values ('b0000000-0000-0000-0000-000000000001', 'user', 'x')$$,
  '23503', null,
  'user A cannot attach a turn to user B''s episode');

select throws_ok(
  $$insert into public.citations (episode_id, source_id)
    values ('b0000000-0000-0000-0000-000000000001', 's1')$$,
  '23503', null,
  'user A cannot attach a citation to user B''s episode');

select lives_ok(
  $$insert into public.turns (id, episode_id, role, text_original)
    values ('a0000000-0000-0000-0000-000000000003',
            'a0000000-0000-0000-0000-000000000001', 'user', 'x')$$,
  'user A can add a turn to own episode (positive control)');

select lives_ok(
  $$insert into public.citations (episode_id, turn_id, source_id)
    values ('a0000000-0000-0000-0000-000000000001',
            'a0000000-0000-0000-0000-000000000003', 's1')$$,
  'user A can add a citation to own episode and turn (positive control)');

select throws_ok(
  $$insert into public.citations (episode_id, turn_id, source_id)
    values ('a0000000-0000-0000-0000-000000000001',
            'b0000000-0000-0000-0000-000000000002', 's1')$$,
  '23503', null,
  'user A cannot cite user B''s turn');

select throws_ok(
  $$insert into public.audit_events (episode_id, type)
    values ('b0000000-0000-0000-0000-000000000001', 'answer')$$,
  '23503', null,
  'user A cannot attach an audit event to user B''s episode');

-- deleting an episode must not erase its audit trail
insert into public.audit_events (episode_id, type)
  values ('a0000000-0000-0000-0000-000000000002', 'episode_probe');
delete from public.episodes where id = 'a0000000-0000-0000-0000-000000000002';

select is((select count(*) from public.audit_events
           where type = 'episode_probe' and episode_id is null)::int, 1,
  'deleting an episode keeps its audit row with episode_id set to NULL');

-- act as user C (no profile yet): user_id defaults to the caller
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);

select lives_ok(
  $$insert into public.profiles (language) values ('en')$$,
  'user can insert own profile without passing user_id');

select is((select user_id::text from public.profiles),
  '33333333-3333-3333-3333-333333333333',
  'profile user_id defaulted to caller');

select * from finish();
rollback;
