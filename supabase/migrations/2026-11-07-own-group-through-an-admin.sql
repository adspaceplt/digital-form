-- ===========================================================================
-- OWN GROUP THROUGH AN ADMIN (2026-11-07)
-- ===========================================================================
-- WHY (security audit, 2026-11-07; the user: "fix all"):
-- A colleague at Team Full Access could move themselves into a group an
-- admin had given an admin tool, and so hold the tool.
--
-- WHAT IT CHANGES
--   `team_admin_guard` refuses a colleague who is not an admin changing their
--   own group (`admin-only`). The page never offered it.
--
-- ORDER: this file alone. Safe to run twice.
--
-- ROLLBACK: restate `team_admin_guard` from the ADMINS MADE BY ADMINS band.
-- ===========================================================================

-- OWN GROUP THROUGH AN ADMIN -------------------------------------------------

/* A colleague who is not an admin changes nobody's group to their own
   advantage, their own least (security audit 2026-11-07): Team Full Access
   could move itself into a group an admin had given an admin tool, and the
   group's map, copied onto the row, granted it. Only an admin changes their
   own group. Everything else is as ADMINS MADE BY ADMINS left it. */
create or replace function public.team_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who      text := lower(coalesce(auth.jwt() ->> 'email', ''));
  was      boolean;
  will     boolean;
begin
  if who = '' or pg_trigger_depth() > 1 or public.allowed('admin') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op <> 'INSERT' then was := coalesce(old.is_admin, false) or old.role = 'admin'; end if;
  if tg_op <> 'DELETE' then
    will := new.role = 'admin'
         or exists (select 1 from public.team_roles r where r.slug = new.role and r.is_admin);
  end if;
  if tg_op = 'DELETE' then
    if was then
      raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin removes an admin.';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and new.role is distinct from old.role and lower(old.email) = who then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes your own group.';
  end if;
  if will and not coalesce(was, false) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin makes a colleague admin.';
  end if;
  if tg_op = 'UPDATE' and was and (
       new.role is distinct from old.role
    or new.is_admin is distinct from old.is_admin
    or new.access is distinct from old.access
    or new.access_until is distinct from old.access_until
    or new.access_until_time is distinct from old.access_until_time
    or new.active is distinct from old.active
    or new.removed_at is distinct from old.removed_at
    or lower(new.email) is distinct from lower(old.email)) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin.';
  end if;
  return new;
end $$;
revoke all on function public.team_admin_guard() from public, anon, authenticated;

create or replace trigger team_admin_guard before insert or update or delete on public.team_members
  for each row execute function public.team_admin_guard();

-- END OF OWN GROUP THROUGH AN ADMIN ------------------------------------------

select public.functions_tidy();
