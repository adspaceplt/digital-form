-- ===========================================================================
-- CLIENT BILLING COLUMNS — a client's billing details are read only by the
-- people Clients: Billing admits.
-- 2026-09-28. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   `clients_read` lets anybody with Clients, Content Review, Creator
--   Campaigns or Reports at View read the whole row, so the registered name,
--   the registration numbers, the tax numbers, the billing contact, the
--   finance email and the billing address reached people the Billing part
--   refuses, through the API if not on the page. A policy cannot hide a
--   column, so the columns themselves are withheld:
--   - the table's SELECT is taken from anon and authenticated, and given back
--     column by column for every column except the billing ones (worked out
--     from the table as it stands, so a column added later is granted by
--     running this section again);
--   - `client_billing(p_ids)` answers the billing columns to Clients: Billing
--     at View, and only the registered name and billing address to
--     Documents at Work (a letter is addressed to them). Every row also
--     names the required fields left blank (`billing_missing`), which
--     Clients at View reads without the values, so the Active gate still
--     says what is missing. Anybody else gets no rows.
--   Writes are unchanged: `clients_billing_guard` still asks Clients: Billing
--   at Work for a change to these columns.
--
-- ROLLBACK
--   grant select on table public.clients to authenticated;
--   drop function if exists public.client_billing(uuid[]);
-- ===========================================================================

revoke select on table public.clients from anon, authenticated;

do $$
declare cols text;
begin
  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position) into cols
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'clients'
     and c.column_name not in ('legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no',
                               'bill_contact', 'bill_contact_email', 'bill_contact_phone',
                               'bill_contact_id', 'finance_email', 'billing_address');
  execute format('grant select (%s) on table public.clients to authenticated', cols);
end $$;

-- Dropped first, so a later change to what it returns re-creates it.
drop function if exists public.client_billing(uuid[]);
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
           case when coalesce(btrim(c.billing_address), '') = '' then 'billing_address' end], null)
    from public.clients c,
         (select public.allowed('clients.billing', 'view') as bill,
                 public.register_may('client', 'work') as docs,
                 public.allowed('clients', 'view') as cv) p
   where (p.bill or p.docs or p.cv)
     and (p_ids is null or c.id = any(p_ids))
$$;
revoke all on function public.client_billing(uuid[]) from public, anon;
grant execute on function public.client_billing(uuid[]) to authenticated;

-- END OF CLIENT BILLING COLUMNS ----------------------------------------------
