-- ===========================================================================
-- A NEW COLLEAGUE IS ADDED PLAIN — a signed-in insert never marks a system
-- account, a removal or an erasure (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 3): `team_members_system_guard` fires on update
-- alone, so a page inserting a colleague at Team Full Access could send
-- `system = true` and make a row that no page could then change or remove;
-- `removed_at` and `erased_at` could be sent the same way, a row born
-- removed or erased.
--
-- WHAT IT CHANGES
--   * Trigger `team_members_insert_guard` (before insert): with a sign-in,
--     `system` true is refused `system-account`, and a `removed_at` or an
--     `erased_at` is refused `removed`. With no sign-in (the connector, the
--     SQL Editor) nothing is held, as the system account is set.
--
-- ORDER: this file alone (Add member never sends these). Safe to run twice.
-- Rollback: `drop trigger team_members_insert_guard on public.team_members`
-- and its function in the SQL Editor.
-- ===========================================================================

create or replace function public.team_members_insert_guard()
returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(auth.jwt() ->> 'email', '') = '' then return new; end if;
  if coalesce(new.system, false) then
    raise exception 'system-account' using hint = 'A system account is set from the database.';
  end if;
  if new.removed_at is not null or new.erased_at is not null then
    raise exception 'removed' using hint = 'A colleague is added as working; removal is its own step.';
  end if;
  return new;
end $$;
revoke all on function public.team_members_insert_guard() from public, anon, authenticated;
create or replace trigger team_members_insert_guard before insert on public.team_members
  for each row execute function public.team_members_insert_guard();

-- END OF A NEW COLLEAGUE IS ADDED PLAIN -------------------------------------

select public.functions_tidy();
