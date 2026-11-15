-- ===========================================================================
-- SLOTS HOLD EVERY BOOKING (2026-11-15)
-- ===========================================================================
-- WHY: the whole-portal audit of 2026-11-15: Reinstate wrote a withdrawn
-- creator straight back to Confirmed, so a campaign of three slots could hold
-- four bookings. The slots were held only by the confirm functions and by
-- `campaigns_slots_floor` on the campaign.
--
-- WHAT IT CHANGES
--   * Trigger `campaign_options_slots_hold` refuses a booking moved in from
--     outside the booked states while every slot is booked (`over-slots`),
--     whoever writes it. Moves between booked states are not counted.
--
-- ORDER: the pages (they say the refusal in words), then this file.
-- Safe to run twice.
--
-- ROLLBACK:
-- drop trigger campaign_options_slots_hold on public.campaign_options;
-- drop function public.campaign_options_slots_hold();
-- ===========================================================================

-- SLOTS HOLD EVERY BOOKING ----------------------------------------------------

create or replace function public.campaign_options_slots_hold()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_slots integer;
  v_booked text[] := array['confirmed', 'pending_visit', 'pending_draft', 'submitted',
                           'reviewing', 'changes', 'scheduled', 'posted', 'completed'];
begin
  if not (new.state = any (v_booked)) or old.state = any (v_booked) then return new; end if;
  select c.slots into v_slots from public.campaigns c where c.id = new.campaign_id for update;
  if v_slots is not null and public.campaign_booked(new.campaign_id) >= v_slots then
    raise exception 'over-slots: every slot is booked'
      using errcode = '23514', hint = 'over-slots';
  end if;
  return new;
end $$;
revoke all on function public.campaign_options_slots_hold() from public, anon, authenticated;
create or replace trigger campaign_options_slots_hold
  before update of state on public.campaign_options
  for each row execute function public.campaign_options_slots_hold();

-- END OF SLOTS HOLD EVERY BOOKING ---------------------------------------------

select public.functions_tidy();
