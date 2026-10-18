-- ===========================================================================
-- A REMOVAL STANDS — a removed colleague is never made active again through
-- a write of the row, nor by moving their access date (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 4): `team_access_guard` refused a removed colleague
-- made active only by the new row's `removed_at`, so one write sending
-- `active = true` and `removed_at = null` passed it; and a colleague whose
-- access expired and who was then removed kept `expired_at`, so moving the
-- access date brought them back by the expiry's own way back.
--
-- WHAT IT CHANGES
--   * `team_access_guard`: with a sign-in, a `removed_at` or an `erased_at`
--     once set is never changed or cleared (`removed`); a colleague removed
--     before the write is never made active; the expiry's way back (moving
--     the date ahead) passes over a removed colleague. Without a sign-in (the
--     SQL Editor) a removal may still be put right by hand.
--
-- ORDER: this file alone (no page sends these). Safe to run twice.
-- Rollback: run COLLEAGUE LEAVING's `team_access_guard` again.
-- ===========================================================================

create or replace function public.team_access_guard()
returns trigger language plpgsql as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  ends timestamptz := public.team_access_ends(new.access_until, new.access_until_time);
  moved boolean := new.access_until is distinct from old.access_until
                   or new.access_until_time is distinct from old.access_until_time;
begin
  /* A removal and an erasure are kept once made (2026-10-18): with a
     sign-in neither is taken back or moved; the removal function only ever
     sets them from empty. */
  if who <> '' and ((old.removed_at is not null and new.removed_at is distinct from old.removed_at)
                 or (old.erased_at is not null and new.erased_at is distinct from old.erased_at)) then
    raise exception 'removed' using hint = 'A removed colleague does not come back; add them again.';
  end if;
  if moved and who <> '' and lower(old.email) = who then
    raise exception 'own-expiry' using hint = 'Another admin sets your access date.';
  end if;
  if new.active and not old.active and new.removed_at is not null then
    raise exception 'removed' using hint = 'A removed colleague does not come back; add them again.';
  end if;
  if new.active and not old.active then
    if ends is not null and ends <= now() then
      raise exception 'expired-date' using hint = 'Move the access date first.';
    end if;
    new.expired_at := null;
  elsif old.expired_at is not null and moved and new.removed_at is null and (ends is null or ends > now()) then
    new.active := true;
    new.expired_at := null;
  end if;
  return new;
end $$;
create or replace trigger team_access_guard before update on public.team_members
  for each row execute function public.team_access_guard();

-- END OF A REMOVAL STANDS ---------------------------------------------------

select public.functions_tidy();
