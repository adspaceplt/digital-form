-- ===========================================================================
-- A LEAVER'S TALKS ARE CLOSED — a colleague set inactive, or whose access
-- expires, leaves no health talk open (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 20): `team_members_leaving` withdrew the open talks
-- asked of a colleague only when they were removed. Set inactive, or stood
-- down by `team_expire_access`, they kept talks open that nobody could hold:
-- a colleague's request waited on someone who had left, and the leaver's own
-- request still read "would like to talk" to the colleague asked.
--
-- WHAT IT CHANGES
--   * Trigger `team_members_talks_closed` (after an update of `active`): when
--     a colleague stops being active, for any reason, every open talk they
--     asked or were asked is withdrawn (`closed_at` now). The asker can ask
--     again once both are active. A trigger of its own, so the leaving
--     trigger, which removes devices, is not restated.
--
-- ORDER: this file alone (no page changes). Safe to run twice.
-- Rollback: `drop trigger team_members_talks_closed on public.team_members`
-- and its function in the SQL Editor. Talks it withdrew stay withdrawn.
-- ===========================================================================

create or replace function public.team_members_talks_closed()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.active and not new.active then
    update public.health_talks h set status = 'withdrawn', closed_at = now()
     where (h.with_id = new.id or h.team_member_id = new.id) and h.status = 'open';
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.team_members_talks_closed() from public, anon, authenticated;
create or replace trigger team_members_talks_closed after update of active on public.team_members
  for each row execute function public.team_members_talks_closed();

-- END OF A LEAVER'S TALKS ARE CLOSED ----------------------------------------

select public.functions_tidy();
