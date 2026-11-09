-- ===========================================================================
-- INVOICE RECIPIENTS ASK CONTACTS (2026-11-09)
-- ===========================================================================
-- WHY (security audit run 2, 2026-11-09; the user's scheduled audit: "fix and
-- release confirmed ones"):
-- invoice_recipients listed every contact of a client to a colleague at Clients:
-- Billing View without Clients: Contacts.
--
-- WHAT IT CHANGES
--   invoice_recipients returns only the billing contact and finance email without Contacts View.
--
-- ORDER: this file, then the pages. Safe to run twice.
--
-- ROLLBACK: run the INVOICE RECIPIENTS CHOSEN band's invoice_recipients again.
-- ===========================================================================

-- INVOICE RECIPIENTS ASK CONTACTS --------------------------------------------

/* Review and send offers a client's contacts only to a colleague who may read
   them (security audit 2026-11-09): invoice_recipients asked Clients: Billing
   alone and listed every contact holding an email, its name and role. A
   client's addresses are Clients: Contacts' (as email_recipients and
   client_email_prepare ask since 2026-11-07); without it the list holds only
   what Billing owns, the billing contact and the finance email. */
create or replace function public.invoice_recipients(p_client uuid, p_contact bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  rcp  jsonb;
  opts jsonb;
begin
  if (public.ops_me()).id is null or not public.allowed('clients.billing', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if p_client is null or not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  rcp := public.invoice_recipient_for(p_client, p_contact);
  opts := public.invoice_recipient_options(p_client, p_contact);
  if not public.allowed('clients.contacts', 'view') then
    select coalesce(jsonb_agg(o), '[]'::jsonb) into opts
      from jsonb_array_elements(coalesce(opts, '[]'::jsonb)) o
     where coalesce((o->>'billing')::boolean, false) or coalesce((o->>'finance')::boolean, false);
  end if;
  return jsonb_build_object('ok', true, 'to', nullif(btrim(coalesce(rcp->>'email', '')), ''),
    'cc', nullif(btrim(coalesce(rcp->>'cc', '')), ''), 'options', opts);
end $$;
revoke all on function public.invoice_recipients(uuid, bigint) from public, anon;
grant execute on function public.invoice_recipients(uuid, bigint) to authenticated;

-- END OF INVOICE RECIPIENTS ASK CONTACTS -------------------------------------


select public.functions_tidy();
