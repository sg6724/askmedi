-- AskMedi RLS hardening (Phase 0, fix round 1). Forward migration on top of 20260919000001.

-- 1. profiles.user_id must default to the caller like every other user-owned table.
alter table public.profiles alter column user_id set default auth.uid();

-- 2. Least privilege. Supabase default privileges grant ALL (incl. TRUNCATE, which bypasses RLS,
--    plus REFERENCES and TRIGGER) to anon/authenticated on new public tables; the original
--    migration only added grants. Reset, then grant exactly what the app needs.
do $$
declare t text;
begin
  foreach t in array array['profiles', 'health_conditions', 'user_medicines',
                           'allergies', 'saved_places', 'episodes', 'turns', 'citations']
  loop
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;

  foreach t in array array['consents', 'audit_events']
  loop
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert on public.%I to authenticated', t);
  end loop;
end $$;

revoke all on public.current_consents from anon, authenticated;
grant select on public.current_consents to authenticated;

-- 3. Cross-tenant FK gap. FK checks bypass RLS, so a child row must be tied to a parent
--    owned by the same user_id. Replace the id-only FKs with composite ownership FKs.
alter table public.episodes add constraint episodes_id_user_id_key unique (id, user_id);
alter table public.turns add constraint turns_id_user_id_key unique (id, user_id);

alter table public.turns drop constraint turns_episode_id_fkey;
alter table public.citations drop constraint citations_episode_id_fkey;
alter table public.citations drop constraint citations_turn_id_fkey;
alter table public.audit_events drop constraint audit_events_episode_id_fkey;

alter table public.turns add constraint turns_episode_owner_fkey
  foreign key (episode_id, user_id) references public.episodes (id, user_id) on delete cascade;

alter table public.citations add constraint citations_episode_owner_fkey
  foreign key (episode_id, user_id) references public.episodes (id, user_id) on delete cascade;

-- turn_id is nullable; MATCH SIMPLE skips the check when turn_id is null.
alter table public.citations add constraint citations_turn_owner_fkey
  foreign key (turn_id, user_id) references public.turns (id, user_id) on delete cascade;

-- Deleting an episode must not erase audit rows: null out only episode_id (user_id is NOT NULL).
-- Account deletion still cascades through auth.users.
alter table public.audit_events add constraint audit_events_episode_owner_fkey
  foreign key (episode_id, user_id) references public.episodes (id, user_id)
  on delete set null (episode_id);

-- 4. Pin the trigger function's search_path (advisor: function_search_path_mutable).
alter function public.touch_updated_at() set search_path = '';
