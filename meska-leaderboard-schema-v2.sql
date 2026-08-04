-- ============================================================
-- Meska AI — Final Project Leaderboard
-- Schema v2 — matches the current build (project HTML pages,
-- mobile capture, vote timestamps, reveal lock).
-- Run once in Supabase → SQL Editor → New query → Run.
-- Safe to re-run: everything is guarded.
-- ============================================================

-- ---------- 1. PROFILES (your lead list) ----------
create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  name              text not null,
  email             text not null,
  mobile            text,
  wants_courses     boolean not null default false,
  community_member  boolean not null default false,
  is_admin          boolean not null default false,
  created_at        timestamptz not null default now()
);
-- Upgrade path for an already-created table (this create is a no-op there).
alter table public.profiles add column if not exists wants_courses boolean not null default false;
alter table public.profiles add column if not exists community_member boolean not null default false;
alter table public.profiles enable row level security;

drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "create own profile" on public.profiles;
create policy "create own profile" on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles
  for update using (auth.uid() = id);

-- Is the caller an admin? SECURITY DEFINER so it can read past RLS.
create or replace function public.is_admin()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce((select is_admin from public.profiles where id = auth.uid()), false) $$;

drop policy if exists "admins read all profiles" on public.profiles;
create policy "admins read all profiles" on public.profiles
  for select using (public.is_admin());


-- ---------- 2. COHORT LIST ----------
-- One list, two powers: who may submit, and who may vote Cohort Choice.
create table if not exists public.roster (
  email       text primary key,
  created_at  timestamptz not null default now()
);
alter table public.roster enable row level security;

drop policy if exists "admins manage roster" on public.roster;
create policy "admins manage roster" on public.roster
  for all using (public.is_admin()) with check (public.is_admin());

-- Lets a signed-in user check their own eligibility without reading the list.
create or replace function public.is_on_roster(check_email text)
returns boolean language sql security definer stable
set search_path = public
as $$ select exists(select 1 from public.roster where lower(email) = lower(check_email)) $$;

create or replace function public.i_am_cohort()
returns boolean language sql security definer stable
set search_path = public
as $$
  select exists(
    select 1 from public.roster r
    join auth.users u on lower(u.email) = lower(r.email)
    where u.id = auth.uid()
  )
$$;


-- ---------- 3. SETTINGS (single row) ----------
create table if not exists public.settings (
  id                  boolean primary key default true,
  voting_open         boolean not null default true,
  require_view_all    boolean not null default false,
  self_voting_allowed boolean not null default false,
  results_revealed    boolean not null default false,
  rules_note          text not null default 'One vote per person, per category. You can change your vote any time before voting closes.',
  event_name          text not null default 'Claude Course for Professionals — Cohort Awards',
  -- Which course cohorts are currently open to voters. Empty = no
  -- restriction, every approved project is votable (today's behavior).
  open_cohorts        jsonb not null default '[]'::jsonb,
  constraint settings_single_row check (id)
);
alter table public.settings add column if not exists open_cohorts jsonb not null default '[]'::jsonb;
insert into public.settings (id) values (true) on conflict (id) do nothing;

alter table public.settings enable row level security;

drop policy if exists "anyone reads settings" on public.settings;
create policy "anyone reads settings" on public.settings for select using (true);

drop policy if exists "admins update settings" on public.settings;
create policy "admins update settings" on public.settings
  for update using (public.is_admin()) with check (public.is_admin());


-- ---------- 4. PROJECTS ----------
-- project_html holds the participant's own page (~20 KB of text),
-- screenshot/photo hold small data URIs. No object storage needed.
create table if not exists public.projects (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  tagline        text,
  participant    text not null,
  photo          text,
  problem        text,
  solution       text,
  impact         text,
  course_name    text,
  cohort_tag     text,
  project_html   text,
  project_url    text,
  demo_link      text,
  screenshot     text,
  tech_stack     jsonb not null default '[]'::jsonb,
  hard_problem   text,
  creative_twist text,
  live_link      text,
  status         text not null default 'pending'
                 check (status in ('pending','approved','rejected')),
  reject_reason  text,
  submitted_by   text,
  created_at     timestamptz not null default now()
);
-- Upgrade path for an already-created table (this create is a no-op there).
-- course_name / cohort_tag are admin-only classification, never shown on
-- the public voter card. cohort_tag is a short free-text label for the
-- intake, e.g. "Wave 10", "C1", "O5" — not a file. demo_link is a
-- YouTube/Drive/Vimeo/Loom URL, embedded via the videoEmbed()/videoMeta()
-- render helpers.
alter table public.projects add column if not exists course_name text;
alter table public.projects add column if not exists cohort_tag text;
alter table public.projects add column if not exists demo_link text;
alter table public.projects enable row level security;

-- Voters only ever see approved projects.
drop policy if exists "anyone reads approved projects" on public.projects;
create policy "anyone reads approved projects" on public.projects
  for select using (status = 'approved');

drop policy if exists "authors read own project" on public.projects;
create policy "authors read own project" on public.projects
  for select using (
    submitted_by is not null
    and lower(submitted_by) = lower((select email from auth.users where id = auth.uid()))
  );

drop policy if exists "admins read all projects" on public.projects;
create policy "admins read all projects" on public.projects
  for select using (public.is_admin());

-- Only cohort members may submit, and only as themselves.
drop policy if exists "cohort submits own project" on public.projects;
create policy "cohort submits own project" on public.projects
  for insert with check (
    public.i_am_cohort()
    and lower(submitted_by) = lower((select email from auth.users where id = auth.uid()))
    and status = 'pending'
  );

drop policy if exists "authors update own project" on public.projects;
create policy "authors update own project" on public.projects
  for update using (
    lower(submitted_by) = lower((select email from auth.users where id = auth.uid()))
  );

drop policy if exists "admins write projects" on public.projects;
create policy "admins write projects" on public.projects
  for all using (public.is_admin()) with check (public.is_admin());


-- ---------- 5. VOTES ----------
-- The UNIQUE constraint IS the "one vote per person per category" rule.
create table if not exists public.votes (
  id          uuid primary key default gen_random_uuid(),
  category    text not null check (category in ('roi','technical','creative','cohort')),
  project_id  uuid not null references public.projects(id) on delete cascade,
  voter_id    uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (category, voter_id)
);
alter table public.votes enable row level security;

-- Nobody reads raw votes except their own — this is what keeps the
-- standings genuinely hidden rather than merely unrendered.
drop policy if exists "read own votes" on public.votes;
create policy "read own votes" on public.votes
  for select using (auth.uid() = voter_id);

drop policy if exists "admins read all votes" on public.votes;
create policy "admins read all votes" on public.votes
  for select using (public.is_admin());

drop policy if exists "cast own vote" on public.votes;
create policy "cast own vote" on public.votes
  for insert with check (auth.uid() = voter_id);

drop policy if exists "change own vote" on public.votes;
create policy "change own vote" on public.votes
  for update using (auth.uid() = voter_id) with check (auth.uid() = voter_id);

drop policy if exists "withdraw own vote" on public.votes;
create policy "withdraw own vote" on public.votes
  for delete using (auth.uid() = voter_id);

drop policy if exists "admins delete votes" on public.votes;
create policy "admins delete votes" on public.votes
  for delete using (public.is_admin());

-- Cohort Choice is enforced here, not in the browser.
create or replace function public.check_vote_rules()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  voter_email text;
  is_open boolean;
begin
  select voting_open into is_open from public.settings where id = true;
  if not coalesce(is_open, false) then
    raise exception 'voting_closed';
  end if;

  if new.category = 'cohort' then
    select email into voter_email from auth.users where id = new.voter_id;
    if not public.is_on_roster(voter_email) then
      raise exception 'not_on_roster';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_vote_rules on public.votes;
create trigger enforce_vote_rules
  before insert or update on public.votes
  for each row execute function public.check_vote_rules();


-- ---------- 6. SAFE AGGREGATES ----------
-- Totals voters are allowed to see: overall and per award, never per project.
create or replace function public.vote_totals()
returns table (category text, votes bigint)
language sql security definer stable
set search_path = public
as $$ select v.category, count(*)::bigint from public.votes v group by v.category $$;

-- Per-project standings — only once revealed, or for an admin.
create or replace function public.standings()
returns table (project_id uuid, category text, votes bigint)
language plpgsql security definer stable
set search_path = public
as $$
begin
  if not (coalesce((select results_revealed from public.settings where id = true), false)
          or public.is_admin()) then
    raise exception 'results_not_revealed';
  end if;
  return query
    select v.project_id, v.category, count(*)::bigint
    from public.votes v group by v.project_id, v.category;
end;
$$;

grant execute on function public.vote_totals()  to anon, authenticated;
grant execute on function public.standings()    to anon, authenticated;
grant execute on function public.is_on_roster(text) to authenticated;
grant execute on function public.i_am_cohort()  to authenticated;


-- ---------- 7. REALTIME ----------
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.votes';    exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table public.projects'; exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table public.settings'; exception when others then null; end;
end $$;


-- ============================================================
-- AFTER RUNNING THIS
--   1. Register through the site with your own email.
--   2. Come back here and run, with your address:
--        update public.profiles set is_admin = true where email = 'you@meska.ai';
--   3. That account now unlocks the Admin tab.
-- ============================================================
