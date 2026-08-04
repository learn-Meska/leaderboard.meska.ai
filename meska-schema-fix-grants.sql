-- ============================================================
-- Meska Leaderboard — schema patch: table privileges
--
-- Run this after schema v2, in Supabase → SQL Editor.
--
-- Why: RLS policies decide WHICH ROWS a role may see, but the role
-- still needs a GRANT to touch the table at all. v2 created the
-- policies and forgot the grants, so every request returned 42501.
-- Row security is unchanged — these grants only open the door that
-- the policies then guard.
-- ============================================================

grant usage on schema public to anon, authenticated;

-- Settings: everyone reads (voting open? results revealed?), admins update.
grant select on public.settings to anon, authenticated;
grant update on public.settings to authenticated;

-- Projects: public sees approved ones (policy filters), authors and
-- admins write. Policies already restrict who may do what.
grant select on public.projects to anon, authenticated;
grant insert, update, delete on public.projects to authenticated;

-- Votes: only signed-in users. Policies limit reads to your own vote
-- (or everything, for admins), so raw standings stay unreadable.
grant select, insert, update, delete on public.votes to authenticated;

-- Profiles: your own row; admins read all.
grant select, insert, update on public.profiles to authenticated;

-- Cohort list: admin-managed, policy-guarded.
grant select, insert, update, delete on public.roster to authenticated;

-- Anything added later inherits the same treatment.
alter default privileges in schema public
  grant select on tables to anon, authenticated;
alter default privileges in schema public
  grant insert, update, delete on tables to authenticated;


-- ---------- verify ----------
-- Should list the grants just applied.
select table_name, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated')
group by table_name, grantee
order by table_name, grantee;
