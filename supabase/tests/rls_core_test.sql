begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

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

select * from finish();
rollback;
