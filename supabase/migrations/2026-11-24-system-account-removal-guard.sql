-- ===========================================================================
-- THE SYSTEM ACCOUNT CANNOT BE REMOVED BY A DIRECT WRITE (2026-11-24)
-- ===========================================================================
-- WHY: the code review of everything since 2026-11-09 found that
-- `team_members_system_guard` held a system account's active flag, access
-- dates, role, admin flag and email, but not `removed_at` or `erased_at`.
-- `team_admin_guard` leaves the system account's row to this guard, and
-- `team_super_ok()` answers true for every caller once no active system
-- account stands unremoved. So any admin could write `removed_at` on the
-- system account's row straight through PostgREST and from then on make
-- admins and change admin groups, the super admin's alone (2026-11-14).
--
-- WHAT IT CHANGES
--   * `team_members_system_guard` also refuses a change to `removed_at` or
--     `erased_at` on a system account's row by anybody but that account.
--     `team_member_remove` already refused the system account; the direct
--     write now meets the same refusal.
--
-- ORDER: this alone; no page changes.
--
-- ROLLBACK: run SYSTEM ACCOUNT's `team_members_system_guard` again (which
-- reopens the gap).
-- ===========================================================================

create or replace function public.team_members_system_guard()
returns trigger
language plpgsql set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if who = '' or pg_trigger_depth() > 1 then return new; end if;
  if new.system is distinct from old.system then
    raise exception 'system-account' using hint = 'A system account is set from the database.';
  end if;
  if old.system and lower(old.email) <> who and (
       new.active is distinct from old.active
    or new.access_until is distinct from old.access_until
    or new.access_until_time is distinct from old.access_until_time
    or new.role is distinct from old.role
    or new.is_admin is distinct from old.is_admin
    or new.removed_at is distinct from old.removed_at
    or new.erased_at is distinct from old.erased_at
    or lower(new.email) is distinct from lower(old.email)) then
    raise exception 'system-account' using hint = 'This is a system account.';
  end if;
  return new;
end $$;
revoke all on function public.team_members_system_guard() from public, anon, authenticated;

-- END OF THE SYSTEM ACCOUNT CANNOT BE REMOVED BY A DIRECT WRITE -------------

select public.functions_tidy();
