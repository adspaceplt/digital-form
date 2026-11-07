-- ===========================================================================
-- QUOTATION SENT WHEN IT WENT (2026-11-07)
-- ===========================================================================
-- WHY (security audit, 2026-11-07; the user: "fix all"):
-- A quotation read as sent out, its lead moved to Proposal sent and its edits
-- locked, while its message was only filed, and stayed so when the send failed.
--
-- WHAT IT CHANGES
--   `quotation_sent_by_message` stamps a quotation sent out once its WhatsApp is
--   queued, sent or not confirmed, or its email sent, on insert or update.
--
-- ORDER: this file alone. Safe to run twice.
--
-- ROLLBACK: restate `quotation_sent_by_message` and its two triggers from the QUOTATION EDITED UNTIL SENT band.
-- ===========================================================================

-- QUOTATION SENT WHEN IT WENT ------------------------------------------------

/* A quotation is sent out once its message went, never while it is only
   filed (audit 2026-11-07): a WhatsApp filed as Sending, or an email filed
   before Resend was asked, stamped the quotation sent out, moved its lead to
   Proposal sent and locked its edits, and a send that then failed undid
   none of it. A WhatsApp counts once queued for the drain, sent or not
   confirmed; an email once sent, delivered, opened or not
   confirmed. Everything else is as QUOTATION EDITED UNTIL SENT left it. */
create or replace function public.quotation_sent_by_message()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if tg_table_name = 'wa_outbox' then
    if new.ref_kind is distinct from 'quotation'
       or coalesce(new.state, '') not in ('queued', 'sent', 'unknown') then return null; end if;
  elsif new.kind is distinct from 'quotation'
     or coalesce(new.status, '') not in ('sent', 'delivered', 'opened', 'unknown') then return null;
  end if;
  v_id := new.ref_id;
  update public.quotations set sent_out_at = now() where id = v_id and sent_out_at is null;
  return null;
exception when others then
  raise warning 'quotation_sent_by_message: %', sqlerrm;
  return null;
end $$;
revoke all on function public.quotation_sent_by_message() from public, anon, authenticated;
create or replace trigger wa_outbox_quotation_sent after insert or update of state on public.wa_outbox
  for each row execute function public.quotation_sent_by_message();
create or replace trigger client_emails_quotation_sent after insert or update of status on public.client_emails
  for each row execute function public.quotation_sent_by_message();

-- END OF QUOTATION SENT WHEN IT WENT -----------------------------------------

select public.functions_tidy();
