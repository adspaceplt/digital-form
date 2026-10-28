-- ===========================================================================
-- OVERDUE REMINDER ON ITS CLIENT — a reminder is filed under the client's
-- name, so its record shows it (2026-10-29)
-- ===========================================================================
-- WHY (the code review of 2026-10-29, finding 2): `invoice_email_done`
-- filed the reminder under the registered name (LAMAN CITRA SDN BHD), but
-- a client's Record of changes and Recent activity read the rows filed
-- under its name (Laman Citra), so no reminder ever showed there.
--
-- WHAT IT CHANGES
--   `invoice_email_done` (restated whole from OVERDUE INVOICE REMINDERS)
--   files the row under the client's name, else, where the client has
--   gone, the registered name the reminder was sent to.
--
-- ORDER: this file (connector). No page changes with it. Safe to run twice.
--
-- ROLLBACK: run invoice_email_done from OVERDUE INVOICE REMINDERS again.
-- ===========================================================================

create or replace function public.invoice_email_done(p_id uuid, p_status text, p_provider text, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e public.invoice_emails;
  m public.team_members;
begin
  if p_status not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into e from public.invoice_emails x where x.id = p_id and x.status = 'sending' for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.invoice_emails x set status = p_status, provider_id = nullif(p_provider, ''),
    error = left(nullif(p_error, ''), 480), sent_at = case when p_status = 'sent' then now() end
   where x.id = p_id;
  select * into m from public.team_members x where x.id = e.sent_by;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, 'system'), 'client.edited',
          coalesce((select c.name from public.clients c where c.id = e.client_id), e.client_name),
          'Overdue reminder ' ||
          case p_status when 'sent' then 'emailed to ' when 'unknown' then 'emailed, not confirmed, to ' else 'not emailed to ' end ||
          e.to_email || coalesce(', cc ' || e.cc_email, '') || ' · ' ||
          (select string_agg(x->>'number', ', ') from jsonb_array_elements(e.invoices) x));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.invoice_email_done(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.invoice_email_done(uuid, text, text, text) to service_role;

-- END OF OVERDUE REMINDER ON ITS CLIENT -------------------------------------

select public.functions_tidy();
