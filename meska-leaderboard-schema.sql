-- ============================================================
-- Meska AI — Final Project Leaderboard
-- Supabase schema: run this once in Project → SQL Editor
-- ============================================================

-- Profiles = leads (name, email, title, company, linkedin)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  title text,
  company text,
  linkedin text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "select own profile" on public.profiles
  for select using (auth.uid() = id);
create policy "insert own profile" on public.profiles
  for insert with check (auth.uid() = id);
create policy "update own profile" on public.profiles
  for update using (auth.uid() = id);

-- Helper: is the current logged-in user an admin?
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- Cohort Choice roster, managed by email
create table public.roster (
  email text primary key,
  created_at timestamptz not null default now()
);

alter table public.roster enable row level security;

create policy "admin manage roster" on public.roster
  for all using (public.is_admin()) with check (public.is_admin());

-- Lets any logged-in voter check eligibility without reading the whole roster
create or replace function public.is_email_on_roster(check_email text)
returns boolean
language sql
security definer
stable
as $$
  select exists(select 1 from public.roster where lower(email) = lower(check_email));
$$;

-- Projects
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tagline text,
  participant text not null,
  problem text,
  solution text,
  demo_type text not null default 'screenshots',
  demo_shots jsonb not null default '[]'::jsonb,
  impact text,
  tech_stack jsonb not null default '[]'::jsonb,
  hard_problem text,
  creative_twist text,
  live_link text,
  sample boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.projects enable row level security;

create policy "public read projects" on public.projects for select using (true);
create policy "admin write projects" on public.projects
  for all using (public.is_admin()) with check (public.is_admin());

-- Settings (single row)
create table public.settings (
  id boolean primary key default true,
  voting_open boolean not null default true,
  require_view_all boolean not null default true,
  self_voting_allowed boolean not null default false,
  rules_note text not null default 'One vote per person, per category. You can change your vote any time before voting closes.',
  event_name text not null default 'Claude Course for Professionals — Cohort Awards',
  constraint settings_single_row check (id)
);
insert into public.settings (id) values (true);

alter table public.settings enable row level security;
create policy "public read settings" on public.settings for select using (true);
create policy "admin update settings" on public.settings
  for update using (public.is_admin()) with check (public.is_admin());

-- Votes
create table public.votes (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('roi','technical','creative','cohort')),
  project_id uuid not null references public.projects(id) on delete cascade,
  voter_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (category, voter_id)
);

alter table public.votes enable row level security;

create policy "public read votes" on public.votes for select using (true);
create policy "voter insert own vote" on public.votes
  for insert with check (auth.uid() = voter_id);
create policy "voter update own vote" on public.votes
  for update using (auth.uid() = voter_id) with check (auth.uid() = voter_id);
create policy "voter delete own vote" on public.votes
  for delete using (auth.uid() = voter_id);
create policy "admin delete any vote" on public.votes
  for delete using (public.is_admin());

-- Enforce Cohort Choice = roster-only, checked server-side
create or replace function public.check_cohort_eligibility()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.category = 'cohort' then
    if not public.is_email_on_roster((select email from auth.users where id = new.voter_id)) then
      raise exception 'not_on_roster';
    end if;
  end if;
  return new;
end;
$$;

create trigger enforce_cohort_roster
before insert or update on public.votes
for each row execute function public.check_cohort_eligibility();

-- Realtime: so votes update live across every device
alter publication supabase_realtime add table public.votes;
alter publication supabase_realtime add table public.projects;
alter publication supabase_realtime add table public.settings;
