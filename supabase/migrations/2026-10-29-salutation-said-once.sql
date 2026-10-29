-- ===========================================================================
-- SALUTATION SAID ONCE — a name after its salutation never carries a second
-- one (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "salutation is Mrs but why would it show Mrs
-- Ms xxx", then "check for other salutation as well"): Send to Bukku put
-- the contact's salutation before the name Bukku held, Ms Agnes Ang, and
-- read Mrs Ms Agnes Ang. Every place a name follows its salutation is held
-- to one rule.
--
-- WHAT CHANGED
--   * `contact_named(p_salutation, p_name)` (internal): the salutation,
--     then the name with any salutation it opens on taken off (Mrs and
--     Ms Agnes Ang read Mrs Agnes Ang; two-word titles whole, never Tan);
--     no salutation, the name as it stands. `ADspaceWords.person` reads it
--     alike on the pages.
--   * `contact_greeting` greets through it where a salutation is set (it
--     said a same salutation once, never a different one).
--   * `invoice_recipient` names the reminder's contact through it.
--
-- ORDER: this file (connector), then the pages. Either order is safe: each
-- side only stops repeating a salutation. Safe to run twice.
--
-- ROLLBACK
--   Run DATA HELD TO ITS LEVEL's contact_greeting and OVERDUE INVOICE
--   REMINDERS' invoice_recipient again, then
--   drop function if exists public.contact_named(text, text);
-- ===========================================================================

-- SALUTATION SAID ONCE ------------------------------------------------------

create or replace function public.contact_named(p_salutation text, p_name text)
returns text
language sql immutable set search_path = public as $$
  select case when x.s = '' then x.n
              else btrim(x.s || ' ' || regexp_replace(x.n,
                '^(dato''? sri|datin sri|datuk sri|tan sri|puan sri|mrs|mr|ms|miss|mdm|madam|dr|prof|dato''?|datin|datuk|tun|tuan|puan|encik|cik)\.?\s+',
                '', 'i')) end
    from (select btrim(coalesce(p_salutation, '')) as s,
                 btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')) as n) x
$$;
revoke all on function public.contact_named(text, text) from public, anon, authenticated;

create or replace function public.contact_greeting(p_salutation text, p_name text)
returns text
language sql immutable set search_path = public as $$
  -- A salutation is said once, however the name was keyed, and the two-word
  -- titles are whole (audit I12): never "Ms Ms Jane Doe", never "Mrs Ms
  -- Jane Doe", never "Tan".
  select case when x.s <> ''
              then public.contact_named(x.s, x.n)
              when lower(x.n) ~ '^(tan sri|puan sri|dato''? sri|datin sri|datuk sri) '
              then x.n
              when lower(split_part(x.n, ' ', 1)) ~ '^(mr|ms|mrs|mdm|dr|prof|dato''?|datin|datuk|puan|tun|tuan|encik|cik|madam|miss)\.?$'
               and position(' ' in x.n) > 0
              then x.n
              else split_part(x.n, ' ', 1) end
    from (select btrim(coalesce(p_salutation, '')) as s,
                 btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')) as n) x
$$;
revoke all on function public.contact_greeting(text, text) from public, anon, authenticated;

/* Who a client's reminder goes to: the billing contact, else the live main
   contact, with their salutation said once; the finance email to copy where
   it differs; the registered name, else the brand. Internal. */
create or replace function public.invoice_recipient(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients;
  k public.client_contacts;
begin
  select * into c from public.clients x where x.id = p_client;
  if c.id is null then return null; end if;
  select * into k from public.client_contacts x
   where x.client_id = c.id and x.archived_at is null and (x.id = c.bill_contact_id or x.is_primary)
   order by (x.id = c.bill_contact_id) desc limit 1;
  return jsonb_build_object(
    'name', nullif(public.contact_named(k.salutation, k.name), ''),
    'email', nullif(btrim(coalesce(k.email, '')), ''),
    'cc', case when nullif(btrim(coalesce(c.finance_email, '')), '') is not null
                and lower(btrim(c.finance_email)) is distinct from lower(btrim(coalesce(k.email, '')))
               then btrim(c.finance_email) end,
    'company', coalesce(nullif(btrim(coalesce(c.legal_name, '')), ''), c.name));
end $$;
revoke all on function public.invoice_recipient(uuid) from public, anon, authenticated;

-- END OF SALUTATION SAID ONCE -----------------------------------------------

select public.functions_tidy();
