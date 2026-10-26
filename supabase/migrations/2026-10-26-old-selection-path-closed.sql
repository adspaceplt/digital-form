-- ===========================================================================
-- OLD SELECTION PATH CLOSED — the selection page's autosave counts the
-- creators already booked, and the older confirm is gone (2026-10-26)
-- ===========================================================================
-- WHY (the whole-repo audit of 2026-10-26, finding 7): `save_selection`
-- held a selection to the campaign's slots but not to the slots left once
-- some were booked, so a selection reopened for one free slot shortlisted
-- three, which the team then had to undo. `confirm_selection`, the confirm
-- of a page from before 2026-10-10, files a confirmation with no check of
-- the slots or the rates; every page now confirms through
-- `confirm_selection_with`, and the page's fallback to it is removed in the
-- same release, so it is dropped.
--
-- ORDER: the pages first (the selection page stops falling back to
-- confirm_selection); then part 1 through the connector; then part 2 in
-- the SQL Editor (the connector holds a drop).
--
-- ROLLBACK: part 1, run save_selection from the PAST CLIENT LINKS section
-- again; part 2, run confirm_selection from CONFIRM ONCE again.
-- ===========================================================================

-- Part 1 (connector) ----------------------------------------------------------
create or replace function public.save_selection(
  p_token text, p_selected uuid[], p_backup uuid[], p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
  n integer;
  v_booked integer;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  -- A past client's link acts on nothing, as it reads nothing (second
  -- audit, item 7): answered as a key nobody knows, before the passcode.
  if exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return public.link_locked('selection', c.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;

  n := coalesce(array_length(p_selected, 1), 0);
  /* Closed once the slots were full, until the team reopens it; backups
     alone may still be named where the team opened them. */
  if c.selection_closed_at is not null and not (coalesce(c.backups_open, false) and n = 0) then
    return jsonb_build_object('error', 'closed');
  end if;
  -- The slots left are the slots less the creators already booked, as
  -- confirm_selection_with counts them: a selection reopened for one free
  -- slot never shortlists three.
  v_booked := public.campaign_booked(c.id);
  if n > 0 and n > c.slots - v_booked then
    return jsonb_build_object('error', 'over-slots', 'slots', c.slots, 'booked', v_booked);
  end if;

  -- Anything already confirmed or further along is the team's to change.
  update campaign_options set state = 'option'
   where campaign_id = c.id and state in ('shortlisted', 'backup');

  if n > 0 then
    update campaign_options set state = 'shortlisted'
     where campaign_id = c.id and id = any(p_selected) and state = 'option';
  end if;
  -- Only where the team opened them: the page hides the control, and this is
  -- what makes that a fact rather than a courtesy.
  if coalesce(c.backups_open, false) and coalesce(array_length(p_backup, 1), 0) > 0 then
    update campaign_options set state = 'backup'
     where campaign_id = c.id and id = any(p_backup) and state = 'option';
  end if;

  return jsonb_build_object('ok', true, 'selected', n);
end $$;

revoke all on function public.save_selection(text, uuid[], uuid[], text) from public;
grant execute on function public.save_selection(text, uuid[], uuid[], text) to anon, authenticated;

-- Part 2 (SQL Editor) ---------------------------------------------------------
drop function if exists public.confirm_selection(text, text, text);

-- END OF OLD SELECTION PATH CLOSED --------------------------------------------

select public.functions_tidy();
