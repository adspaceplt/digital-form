-- ===========================================================================
-- THE TEAM LIST HOLDS WHAT EVERY COLLEAGUE NEEDS — a colleague's mobile,
-- access dates and access are read through Team, never from the table
-- (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 6): policy `team_read` let every active colleague
-- read every column of every colleague over REST: the mobile (hidden from
-- the namecard too), the access date and time, the removal and erasure, and
-- the access map.
--
-- WHAT IT CHANGES
--   1. `team_rows()`: every colleague's whole row, for Team at View alone
--      (nothing for anyone else), newest standing first, as the Team section
--      and a colleague's record read it.
--   2. `team_task_takers()`: the ids of the active colleagues who take tasks
--      (`ops_takes_tasks`), for any colleague, so My Work's pickers need no
--      access map.
--   3. The table answers a browser only the columns every page reads: the
--      name, sign-in email, group, standing, Employee ID, position,
--      department, role standard, capacity, the namecard's key, switch and
--      short link, client scope and the system mark. `access`, `mobile`,
--      `access_until`, `access_until_time`, `expired_at`, `removed_at`,
--      `erased_at` and `card_email` are withheld from `authenticated`; anon
--      reads nothing. Writes are as before (the policies decide them). A new
--      column is granted by running part 3 again with it named.
--
-- ORDER: parts 1 and 2, then the pages (they read the functions and name
-- their columns), then part 3 once the Pages build is live. An open tab
-- from before reads Could not load the team until it is reloaded. Safe to
-- run twice.
-- Rollback: `grant select on public.team_members to authenticated;` then
-- the pages from before; the functions may stay.
-- ===========================================================================

create or replace function public.team_rows()
returns setof public.team_members
language sql stable security definer set search_path = public as $$
  select t.* from public.team_members t
   where public.allowed('team', 'view')
   order by t.active desc, t.role, t.name
$$;
revoke all on function public.team_rows() from public, anon, authenticated;
grant execute on function public.team_rows() to authenticated;

create or replace function public.team_task_takers()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_team() then coalesce((
    select jsonb_agg(t.id order by t.id) from public.team_members t
     where t.active and public.ops_takes_tasks(t.id)), '[]'::jsonb) else '[]'::jsonb end
$$;
revoke all on function public.team_task_takers() from public, anon, authenticated;
grant execute on function public.team_task_takers() to authenticated;

revoke select on table public.team_members from anon, authenticated;
grant select (id, name, email, role, active, created_at, updated_at, is_admin,
  can_clients, can_review, can_campaigns, can_links, can_activity, can_billing, can_remove, can_doc_void,
  staff_code, designation, capacity_minutes_week, wip_guidance, department, role_family,
  card_key, card_on, card_slug, card_mobile, client_scope, system)
  on public.team_members to authenticated;

-- END OF THE TEAM LIST HOLDS WHAT EVERY COLLEAGUE NEEDS ----------------------

select public.functions_tidy();
