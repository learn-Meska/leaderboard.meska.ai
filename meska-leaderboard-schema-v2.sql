-- ============================================================
-- Meska AI — Final Project Leaderboard
-- Schema v2 — matches the current build: project HTML pages, mobile
-- capture, vote timestamps, reveal lock, and two independent voting
-- tracks (Claude Course / AI Copilot Diploma) each with their own
-- open/closed, reveal, and course+cohort gating.
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

-- Emails that become admin automatically on signup. Admin-managed only.
create table if not exists public.admin_emails (
  email       text primary key,
  created_at  timestamptz not null default now()
);
alter table public.admin_emails enable row level security;
drop policy if exists "admins manage admin_emails" on public.admin_emails;
create policy "admins manage admin_emails" on public.admin_emails
  for all using (public.is_admin()) with check (public.is_admin());

-- is_admin can never be set by the row's own owner — only derived from the
-- allowlist on signup, or changed by an existing admin on update. Without
-- this, the "create own profile" policy above would let anyone self-promote
-- by POSTing is_admin: true on their own registration.
create or replace function public.lock_admin_flag()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    new.is_admin := exists (
      select 1 from public.admin_emails a where lower(a.email) = lower(new.email)
    );
  else
    if new.is_admin is distinct from old.is_admin and not public.is_admin() then
      new.is_admin := old.is_admin;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists enforce_admin_flag on public.profiles;
create trigger enforce_admin_flag
  before insert or update on public.profiles
  for each row execute function public.lock_admin_flag();

-- Promote an already-registered email to admin from the Admin panel,
-- instead of hand-written SQL. Re-checks the caller is already an admin —
-- this is a convenience, not a new privilege boundary. lock_admin_flag()
-- above still fires on the UPDATE underneath and allows the change through
-- precisely because the caller passes that same is_admin() check.
create or replace function public.promote_to_admin(target_email text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'not_authorized';
  end if;
  update public.profiles set is_admin = true where lower(email) = lower(target_email);
  if not found then
    raise exception 'no_such_registered_user';
  end if;
end;
$$;
grant execute on function public.promote_to_admin(text) to authenticated;


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


-- ---------- 3. SETTINGS (one row per voting track) ----------
-- Two independent tracks — claude and diploma — so each can be opened,
-- closed and revealed on its own schedule. Originally a single row
-- (id boolean primary key default true); migrated to track-keyed so the
-- Diploma page didn't have to share Claude's on/off switch.
create table if not exists public.settings (
  track                text primary key check (track in ('claude','diploma')),
  voting_open          boolean not null default true,
  require_view_all     boolean not null default false,
  self_voting_allowed  boolean not null default false,
  results_revealed     boolean not null default false,
  rules_note           text not null default 'One vote per person, per category. You can change your vote any time before voting closes.',
  event_name           text not null default 'Claude Course for Professionals — Cohort Awards',
  -- Which cohort tags are currently open to voters, e.g. "Wave 10". Empty
  -- means no restriction on that axis — every matching approved project
  -- is votable.
  open_cohorts         jsonb not null default '[]'::jsonb,
  -- Diploma only: which course_name values are open (Online / Offline).
  -- Empty means both. Unused by the claude track (only one course).
  open_courses         jsonb not null default '[]'::jsonb
);
-- Upgrade path from the old single-row (id boolean) shape, if it's still
-- around. No-op on an install that already has `track`.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='settings' and column_name='id') then
    alter table public.settings add column if not exists track text;
    update public.settings set track = 'claude' where track is null;
    alter table public.settings drop constraint if exists settings_single_row;
    alter table public.settings drop constraint if exists settings_pkey;
    alter table public.settings add constraint settings_track_check check (track in ('claude','diploma'));
    alter table public.settings add primary key (track);
    alter table public.settings drop column if exists id;
  end if;
end $$;
alter table public.settings add column if not exists open_cohorts jsonb not null default '[]'::jsonb;
alter table public.settings add column if not exists open_courses jsonb not null default '[]'::jsonb;

insert into public.settings (track) values ('claude') on conflict (track) do nothing;
insert into public.settings (track, voting_open, rules_note, event_name)
values ('diploma', false,
        'One vote for your favorite idea. You can change your vote any time before voting closes.',
        'AI Copilot Diploma — Idea Voting')
on conflict (track) do nothing;

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
-- 'idea' is the Diploma page's single vote — the same UNIQUE constraint
-- gives it "one idea vote per voter, changeable" for free.
create table if not exists public.votes (
  id          uuid primary key default gen_random_uuid(),
  category    text not null check (category in ('roi','technical','creative','cohort','idea')),
  project_id  uuid not null references public.projects(id) on delete cascade,
  voter_id    uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (category, voter_id)
);
alter table public.votes drop constraint if exists votes_category_check;
alter table public.votes add constraint votes_category_check
  check (category in ('roi','technical','creative','cohort','idea'));
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

-- Cohort Choice, voting-open, and course/cohort gating are all enforced
-- here, not in the browser. 'idea' votes are checked against the diploma
-- track's settings row; everything else against claude's. Variable names
-- are prefixed v_ to avoid shadowing the settings columns of the same
-- name — a real bug hit here once (ambiguous column reference).
create or replace function public.check_vote_rules()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  voter_email text;
  v_is_open boolean;
  v_trk text;
  proj_course text;
  proj_tag text;
  v_open_courses jsonb;
  v_open_cohorts jsonb;
begin
  v_trk := case when new.category = 'idea' then 'diploma' else 'claude' end;

  select voting_open, open_courses, open_cohorts into v_is_open, v_open_courses, v_open_cohorts
    from public.settings where track = v_trk;

  if not coalesce(v_is_open, false) then
    raise exception 'voting_closed';
  end if;

  select course_name, cohort_tag into proj_course, proj_tag
    from public.projects where id = new.project_id;

  if jsonb_array_length(coalesce(v_open_courses,'[]'::jsonb)) > 0
     and not (v_open_courses ? coalesce(proj_course,'')) then
    raise exception 'course_not_open';
  end if;
  if jsonb_array_length(coalesce(v_open_cohorts,'[]'::jsonb)) > 0
     and not (v_open_cohorts ? coalesce(proj_tag,'')) then
    raise exception 'cohort_not_open';
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

-- Per-project standings — only once revealed, or for an admin. Revealed is
-- tracked per voting track: 'idea' rows gate on the diploma track's
-- results_revealed, everything else on claude's, so revealing one track
-- never leaks the other's standings.
create or replace function public.standings()
returns table (project_id uuid, category text, votes bigint)
language plpgsql security definer stable
set search_path = public
as $$
declare
  claude_revealed boolean;
  diploma_revealed boolean;
begin
  if public.is_admin() then
    return query
      select v.project_id, v.category, count(*)::bigint
      from public.votes v group by v.project_id, v.category;
    return;
  end if;

  select results_revealed into claude_revealed from public.settings where track = 'claude';
  select results_revealed into diploma_revealed from public.settings where track = 'diploma';

  return query
    select v.project_id, v.category, count(*)::bigint
    from public.votes v
    where (v.category = 'idea' and coalesce(diploma_revealed, false))
       or (v.category != 'idea' and coalesce(claude_revealed, false))
    group by v.project_id, v.category;
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
--   1. Pre-authorize your own admin email, before registering:
--        insert into public.admin_emails (email) values ('you@meska.ai');
--   2. Register through the site with that email — you'll land as an
--      admin automatically (lock_admin_flag() derives it from the table
--      above on signup).
--   3. From then on, promote further admins from the Admin panel's
--      "Admin access" button rather than hand SQL — it calls
--      promote_to_admin(), which only works for someone who's already
--      an admin. It requires the target to have registered first.
-- ============================================================
