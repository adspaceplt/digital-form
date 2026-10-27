-- ===========================================================================
-- BILLING CONTACT READ WITH THE RECORD — `client_billing` names a missing
-- billing contact too (2026-10-27)
-- ===========================================================================
-- WHY (the user, 2026-10-27): a client's record drew "Billing contact" in
-- its Billing details missing line for a second, then took it away. The
-- page worked the contact out from the client's contacts, which arrive
-- after the record is drawn, so every record opened read the contact as
-- missing until they did.
--
-- WHAT IT CHANGES
--   `client_billing` (restated whole from CLIENT SCOPE) adds
--   `bill_contact_id` to `billing_missing` where no billing contact stands:
--   neither the contact chosen nor a main contact, live, as
--   `clients_active_billing` holds the move into Active. The page reads it
--   until the contacts arrive, then reads the contacts as before. Nothing
--   else moves: the same columns, to the same people.
--
-- ORDER: this file (connector), then the page. An old page reads the list
-- as before and never asks for the contact by this name.
--
-- ROLLBACK: run client_billing from CLIENT SCOPE again.
-- ===========================================================================

create or replace function public.client_billing(p_ids uuid[] default null)
returns table (id uuid, legal_name text, company_no text, company_no_old text, tin text,
               sst_no text, bill_contact_id uuid, bill_contact text, bill_contact_email text,
               bill_contact_phone text, finance_email text, billing_address text,
               billing_missing text[])
language sql stable security definer set search_path = public as $$
  select c.id,
         case when p.bill or p.docs then c.legal_name end,
         case when p.bill then c.company_no end,
         case when p.bill then c.company_no_old end,
         case when p.bill then c.tin end,
         case when p.bill then c.sst_no end,
         case when p.bill then c.bill_contact_id end,
         case when p.bill then c.bill_contact end,
         case when p.bill then c.bill_contact_email end,
         case when p.bill then c.bill_contact_phone end,
         case when p.bill then c.finance_email end,
         case when p.bill or p.docs then c.billing_address end,
         array_remove(array[
           case when coalesce(btrim(c.legal_name), '') = '' then 'legal_name' end,
           case when coalesce(btrim(c.company_no), '') = '' then 'company_no' end,
           case when not exists (select 1 from public.client_contacts k
                                  where k.client_id = c.id and k.archived_at is null
                                    and (k.id = c.bill_contact_id or k.is_primary))
                then 'bill_contact_id' end,
           case when coalesce(btrim(c.billing_address), '') = '' then 'billing_address' end], null)
    from public.clients c,
         (select public.allowed('clients.billing', 'view') as bill,
                 public.register_may('client', 'work') as docs,
                 public.allowed('clients', 'view') as cv) p
   where (p.bill or p.docs or p.cv)
     and (p_ids is null or c.id = any(p_ids))
     and public.client_seen(c.id, 'view')
$$;
revoke all on function public.client_billing(uuid[]) from public, anon;
grant execute on function public.client_billing(uuid[]) to authenticated;

-- END OF BILLING CONTACT READ WITH THE RECORD -------------------------------

select public.functions_tidy();
