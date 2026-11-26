-- ===========================================================================
-- INACTIVE STAMP ON EVERY UPDATE (2026-11-27)
-- ===========================================================================
-- WHY (a review of main, hotfix approved by the user): a leaver's health
-- data could be deleted up to six months early. `team_members_inactive_stamp`
-- fired `before update of active`, so only an update naming `active` ran
-- it. Moving a lapsed colleague's access date names only `access_until`;
-- `team_access_guard` then sets them active, which no `update of active`
-- trigger sees, so their old `inactive_at` stayed on an active row. Set
-- inactive again, `coalesce(new.inactive_at, now())` kept the old stamp and
-- `privacy_retention` counted six months from it that night.
--
-- WHAT IT CHANGES
--   * `team_members_inactive_stamp`: fires before every update and reads
--     the change of `active` itself, after `team_access_guard` (triggers of
--     one timing fire by name); set inactive is stamped now, never kept
--     from before.
--   * Active colleagues carrying a stamp have it cleared, once.
--
-- ORDER: this file alone; no page reads the stamp. Safe to run twice.
-- Holds no drop or delete.
-- ROLLBACK: run RETENTION AND JOBS HELD's `team_members_inactive_stamp`
-- and its trigger again; the cleared stamps belonged to active rows.
-- ===========================================================================

-- INACTIVE STAMP ON EVERY UPDATE -----------------------------------------------

/* When a colleague was set inactive, cleared when they are set active
   again, however `active` changed (an access date moved back sets it in
   `team_access_guard`); privacy_retention counts a leaver's months from it. */
create or replace function public.team_members_inactive_stamp()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.active is distinct from old.active then
    new.inactive_at := case when new.active then null else now() end;
  end if;
  return new;
end $$;
revoke all on function public.team_members_inactive_stamp() from public, anon, authenticated;
create or replace trigger team_members_inactive_stamp before update on public.team_members
  for each row execute function public.team_members_inactive_stamp();

update public.team_members set inactive_at = null where active and inactive_at is not null;

-- END OF INACTIVE STAMP ON EVERY UPDATE ----------------------------------------

select public.functions_tidy();
