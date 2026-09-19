-- AskMedi core schema (Phase 0). Every user-owned table: user_id default auth.uid() + RLS.

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  language text not null default 'en' check (language in ('en', 'hi', 'mr')),
  birth_year int check (birth_year between 1900 and 2100),
  sex text check (sex in ('female', 'male', 'other', 'prefer_not')),
  pregnant boolean,
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.health_conditions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 120),
  created_at timestamptz not null default now()
);

create table public.user_medicines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  salt text not null check (length(salt) between 1 and 120),
  brand text,
  since date,
  created_at timestamptz not null default now()
);

create table public.allergies (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  substance text not null check (length(substance) between 1 and 120),
  created_at timestamptz not null default now()
);

-- Append-only consent log; current state = latest row per purpose.
create table public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  purpose text not null check (purpose in
    ('age_18_plus', 'terms', 'history', 'media', 'voice', 'location')),
  granted boolean not null,
  created_at timestamptz not null default now()
);

create table public.saved_places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  label text not null check (length(label) between 1 and 40),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  pincode text check (pincode ~ '^[1-9][0-9]{5}$'),
  created_at timestamptz not null default now()
);

create table public.episodes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('symptom', 'medicine', 'report', 'hospital')),
  started_at timestamptz not null default now(),
  language text not null check (language in ('en', 'hi', 'mr')),
  symptoms text[] not null default '{}',
  urgency text check (urgency in ('emergency', 'see_doctor_today', 'see_doctor_soon', 'self_care')),
  followup_count int not null default 0,
  outcome jsonb,
  red_flag_rule_id text,
  repeat_flag boolean not null default false
);

create table public.turns (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  episode_id uuid not null references public.episodes(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  text_original text not null,
  text_normalised text,
  lang text,
  created_at timestamptz not null default now()
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  episode_id uuid references public.episodes(id) on delete cascade,
  type text not null check (length(type) between 1 and 40),
  payload jsonb not null default '{}',
  model text,
  latency_ms int,
  created_at timestamptz not null default now()
);

create table public.citations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  episode_id uuid not null references public.episodes(id) on delete cascade,
  turn_id uuid references public.turns(id) on delete cascade,
  source_id text not null,
  created_at timestamptz not null default now()
);

create index on public.health_conditions (user_id);
create index on public.user_medicines (user_id);
create index on public.allergies (user_id);
create index on public.consents (user_id, purpose, created_at desc);
create index on public.saved_places (user_id);
create index on public.episodes (user_id, started_at desc);
create index on public.turns (episode_id, created_at);
create index on public.audit_events (user_id, created_at desc);
create index on public.citations (episode_id);

create view public.current_consents with (security_invoker = true) as
  select distinct on (user_id, purpose) user_id, purpose, granted, created_at
  from public.consents
  order by user_id, purpose, created_at desc;

-- updated_at trigger for profiles
create function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- RLS: full CRUD on own rows
do $$
declare t text;
begin
  foreach t in array array['profiles', 'health_conditions', 'user_medicines',
                           'allergies', 'saved_places', 'episodes', 'turns', 'citations']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format($p$create policy own_rows on public.%I for all to authenticated
                     using (user_id = auth.uid()) with check (user_id = auth.uid())$p$, t);
  end loop;
end $$;

-- RLS: append-only tables (select + insert only)
do $$
declare t text;
begin
  foreach t in array array['consents', 'audit_events']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert on public.%I to authenticated', t);
    execute format($p$create policy own_select on public.%I for select to authenticated
                     using (user_id = auth.uid())$p$, t);
    execute format($p$create policy own_insert on public.%I for insert to authenticated
                     with check (user_id = auth.uid())$p$, t);
  end loop;
end $$;

grant select on public.current_consents to authenticated;
revoke all on public.profiles, public.health_conditions, public.user_medicines,
  public.allergies, public.saved_places, public.episodes, public.turns,
  public.citations from anon;
