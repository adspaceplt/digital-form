-- ===========================================================================
-- ACCESS ENDS ON THE MINUTE — a colleague whose access date has passed is
-- off the team at once, not at the next expiry run (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 15): `team_expire_access()` stands a colleague down
-- every five minutes, and until it ran `is_team()`, `allowed()` and
-- `ops_me()` still answered for them, so a colleague whose access ended at
-- 17:00 could read and write until 17:05.
--
-- WHAT IT CHANGES
--   * `is_team()`, `allowed(p_section, p_level)`, `ops_me()` and `me()` (the
--     console's own read of who is signed in) count a colleague only while their access date has not
--     passed (`team_access_ends`, Malaysia's day and time; no date is no
--     end). The check sits in each query, with no function of its own, so
--     every policy pays for it once, in the row it already reads.
--     `allowed('admin')` asks only whether an active colleague is an admin,
--     and so needs no change.
--   * An admin is not held by it: the expiry run never stands down the
--     last admin with access, and an admin's own date is the run's to apply.
--   * `my_access_expired()` also answers for a colleague whose date has
--     passed and whom the run has not reached, so sign-in reads Access
--     expired, not Access denied.
--
-- ORDER: this file; the pages need nothing. Safe to run twice.
-- Rollback: the five functions as TEAM ACCESS EXPIRY and ACCESS left them.
-- ===========================================================================

create or replace function public.is_team()
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.team_members t
    where t.active and lower(t.email) = lower(auth.jwt() ->> 'email')
      and (t.access_until is null or t.is_admin or t.role = 'admin'
           or public.team_access_ends(t.access_until, t.access_until_time) > now()))
$$;
grant execute on function public.is_team() to authenticated;

create or replace function public.allowed(p_section text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members;
  k text := lower(coalesce(p_section, ''));
  lv text;
begin
  select * into t from public.team_members x
    where lower(x.email) = lower(auth.jwt() ->> 'email') and x.active
      and (x.access_until is null or x.is_admin or x.role = 'admin'
           or public.team_access_ends(x.access_until, x.access_until_time) > now())
    limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  lv := t.access ->> k;
  if lv is null and position('.' in k) > 0 then
    lv := t.access ->> split_part(k, '.', 1);
  end if;
  return public.level_rank(lv) >= public.level_rank(p_level);
end $$;
grant execute on function public.allowed(text, text) to authenticated;

create or replace function public.ops_me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members t
   where t.active and lower(t.email) = lower(auth.jwt() ->> 'email')
     and (t.access_until is null or t.is_admin or t.role = 'admin'
          or public.team_access_ends(t.access_until, t.access_until_time) > now())
   limit 1
$$;
grant execute on function public.ops_me() to authenticated;

create or replace function public.me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members t
  where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active
    and (t.access_until is null or t.is_admin or t.role = 'admin'
         or public.team_access_ends(t.access_until, t.access_until_time) > now())
  limit 1
$$;
grant execute on function public.me() to authenticated;

create or replace function public.my_access_expired()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.team_members t
                  where lower(t.email) = lower(auth.jwt() ->> 'email')
                    and ((not t.active and t.expired_at is not null)
                         or (t.active and t.access_until is not null and not (t.is_admin or t.role = 'admin')
                             and public.team_access_ends(t.access_until, t.access_until_time) <= now())))
$$;
grant execute on function public.my_access_expired() to authenticated;
-- END OF ACCESS ENDS ON THE MINUTE ------------------------------------------

select public.functions_tidy();
