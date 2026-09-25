-- Demo feature set: web-sourced citations, medicine lookups, lab reports, account deletion.
-- New tables follow the Phase 0 rules: RLS own_rows, revoke from anon/authenticated,
-- regrant only what the app needs, composite (id, user_id) ownership FKs.

-- Citations now come from live web search (Gemini + Google Search grounding),
-- so they carry their own title and URL.
alter table public.citations add column title text check (length(title) <= 300);
alter table public.citations add column url text check (url ~ '^https?://' and length(url) <= 2000);

create table public.medicine_lookups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  episode_id uuid,
  query text not null check (length(query) between 1 and 200),
  brand text check (length(brand) <= 200),
  salts jsonb not null default '[]',
  info jsonb not null default '{}',
  flags jsonb not null default '[]',
  created_at timestamptz not null default now(),
  foreign key (episode_id, user_id) references public.episodes (id, user_id) on delete cascade
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  episode_id uuid,
  report_date date,
  lab text check (length(lab) <= 200),
  status text not null default 'draft' check (status in ('draft', 'confirmed')),
  summary jsonb,
  created_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (episode_id, user_id) references public.episodes (id, user_id) on delete cascade
);

create table public.report_values (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  report_id uuid not null,
  test_name text not null check (length(test_name) between 1 and 120),
  value numeric,
  unit text check (length(unit) <= 40),
  ref_low numeric,
  ref_high numeric,
  ref_text text check (length(ref_text) <= 200),
  status text not null check (status in ('low', 'normal', 'high', 'unknown', 'unreadable')),
  report_date date,
  created_at timestamptz not null default now(),
  foreign key (report_id, user_id) references public.reports (id, user_id) on delete cascade
);

create index on public.medicine_lookups (user_id, created_at desc);
create index on public.reports (user_id, created_at desc);
create index on public.report_values (user_id, test_name, report_date);
create index on public.report_values (report_id);
create index on public.citations (turn_id);

do $$
declare t text;
begin
  foreach t in array array['medicine_lookups', 'reports', 'report_values']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format($p$create policy own_rows on public.%I for all to authenticated
                     using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))$p$, t);
  end loop;
end $$;

-- "Delete account and all data": removing the auth user cascades to every table.
create function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
