-- ===========================================================================
-- ERASED COLLEAGUE WHATSAPP CLEARED (2026-11-07)
-- ===========================================================================
-- WHY (security audit, 2026-11-07; the user: "fix all"):
-- Erasing a colleague left their mobile in the WhatsApp log for a year.
--
-- WHAT IT CHANGES
--   Trigger `team_members_erased_whatsapp` clears the number and words of
--   every message to a colleague once erased; those erased before are cleared.
--
-- ORDER: this file alone. Safe to run twice.
--
-- ROLLBACK: drop trigger team_members_erased_whatsapp on public.team_members (SQL Editor). Cleared numbers are not restored.
-- ===========================================================================

-- ERASED COLLEAGUE WHATSAPP CLEARED ------------------------------------------

/* Erasing a colleague clears their number from the WhatsApp log too
   (security audit 2026-11-07): the reminders queued to them kept the mobile
   and their name in the message's words, readable in Messages for twelve
   months after the details were erased. Once `erased_at` is set, every
   message to that colleague not on its way loses its number and words, as
   `privacy_retention` clears them at twelve months; the name stays, as on
   their past work. */
create or replace function public.team_members_erased_whatsapp()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.erased_at is not null and old.erased_at is null then
    update public.wa_outbox o
       set to_number = '', params = '[]'::jsonb, button = null
     where o.to_kind = 'colleague' and o.to_id = new.id and o.state <> 'sending';
  end if;
  return null;
end $$;
revoke all on function public.team_members_erased_whatsapp() from public, anon, authenticated;
create or replace trigger team_members_erased_whatsapp after update of erased_at on public.team_members
  for each row execute function public.team_members_erased_whatsapp();

-- Those erased before today.
update public.wa_outbox o
   set to_number = '', params = '[]'::jsonb, button = null
  from public.team_members m
 where o.to_kind = 'colleague' and o.to_id = m.id and m.erased_at is not null
   and o.state <> 'sending' and (o.to_number <> '' or o.params <> '[]'::jsonb);

-- END OF ERASED COLLEAGUE WHATSAPP CLEARED -----------------------------------

select public.functions_tidy();
