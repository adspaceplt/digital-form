-- ===========================================================================
-- A CLIENT'S INVOICES ON ITS PORTAL (2026-11-25)
-- ===========================================================================
-- WHY: the user approved a client reading its own invoices on the client
-- portal (number, dates, amount, balance, state, Download PDF), read from
-- Bukku, never another client's.
--
-- WHAT IT CHANGES: adds `portal_invoice_contacts(p_client)`, the Bukku
-- contacts linked to a client the signed-in contact may open.
--
-- ORDER: this file, then `bukku-sync` (its `portal` action asks it), then
-- the pages. An old page never asks; a function deployed before this file
-- answers `needs-update` and the page leaves the card out.
-- Safe to run twice.
-- ROLLBACK: drop function public.portal_invoice_contacts(uuid);
-- ===========================================================================

-- A CLIENT'S INVOICES ON ITS PORTAL ----------------------------------------
-- The client portal lists the client's own invoices read from Bukku
-- (2026-11-25): `bukku-sync` `portal` asks this as the signed-in contact,
-- and reads Bukku for the contacts it answers alone. A client the contact
-- may not open (another client's, a Past or inactive one) is refused as
-- `get_portal` refuses it; a company billing other brands too is left
-- out, as a month's invoices leave it (`month_invoice_contacts`).
create or replace function public.portal_invoice_contacts(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cid uuid;
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select p into cid from public.portal_clients() p where p = p_client limit 1;
  if cid is null then return jsonb_build_object('error', 'no-access'); end if;
  return jsonb_build_object('contacts', to_jsonb(public.month_invoice_contacts(cid)));
end $$;
revoke all on function public.portal_invoice_contacts(uuid) from public, anon;
grant execute on function public.portal_invoice_contacts(uuid) to authenticated;

-- END OF A CLIENT'S INVOICES ON ITS PORTAL -----------------------------------

select public.functions_tidy();
