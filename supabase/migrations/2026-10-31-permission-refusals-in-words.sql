-- ===========================================================================
-- PERMISSION REFUSALS IN WORDS — a guard that refuses a write says so in a
-- sentence, never a section and a level the screen does not show (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31, the copy review): "Billing details need
-- Clients: Billing at Work." named the stored level `work`, which the screen
-- calls Manage, and read as a setting rather than a sentence.
--
-- WHAT CHANGED
--   * `clients_billing_guard`, `clients_white_label_guard`,
--     `clients_brand_guard` and `campaigns_finance_guard` refuse with "You
--     do not have permission to change … Please ask an admin." Their checks,
--     their error code 42501, the hint `white-label` and the prefix
--     `brand-columns:` (which the page reads) are unchanged.
--
-- ORDER: this file (connector), then the pages. Either order is safe: only
-- the words of a refusal change. Safe to run twice.
--
-- ROLLBACK: run SEC-1's guards again (the band holding BE-4 to BE-6).
-- ===========================================================================

-- PERMISSION REFUSALS IN WORDS ----------------------------------------------

create or replace function public.clients_billing_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- A billing contact removed from Contacts nulls bill_contact_id by the
  -- foreign key, which is a cascade and not a person editing Billing.
  if pg_trigger_depth() > 1 then return new; end if;
  if tg_op = 'INSERT' then
    if coalesce(current_setting('role', true), '') = 'authenticated'
       and (nullif(btrim(coalesce(new.legal_name, '') || coalesce(new.company_no, '') || coalesce(new.company_no_old, '') ||
                         coalesce(new.tin, '') || coalesce(new.sst_no, '') || coalesce(new.finance_email, '') ||
                         coalesce(new.billing_address, '')), '') is not null
            or new.bill_contact_id is not null or new.sst_applies is false or new.bill_sgd is true)
       and not public.allowed('clients.billing', 'work') then
      raise exception 'You do not have permission to change billing details. Please ask an admin.' using errcode = '42501';
    end if;
    return new;
  end if;
  if (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.sst_applies,
      new.bill_contact_id, new.finance_email, new.billing_address, new.bill_sgd)
     is distinct from
     (old.legal_name, old.company_no, old.company_no_old, old.tin, old.sst_no, old.sst_applies,
      old.bill_contact_id, old.finance_email, old.billing_address, old.bill_sgd)
     and not public.allowed('clients.billing', 'work') then
    raise exception 'You do not have permission to change billing details. Please ask an admin.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.clients_billing_guard() from public, anon, authenticated;

create or replace function public.clients_white_label_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() > 1 or (auth.jwt() ->> 'email') is null then return new; end if;
  if tg_op = 'INSERT' then
    if (new.white_label is true or new.report_logo is not null)
       and not public.ops_granted('reports.whitelabel', 'work') then
      raise exception 'You do not have permission to change white label settings. Please ask an admin.' using errcode = '42501', hint = 'white-label';
    end if;
    return new;
  end if;
  if (new.white_label, new.report_logo) is distinct from (old.white_label, old.report_logo)
     and not public.ops_granted('reports.whitelabel', 'work') then
    raise exception 'You do not have permission to change white label settings. Please ask an admin.' using errcode = '42501', hint = 'white-label';
  end if;
  return new;
end $$;
revoke all on function public.clients_white_label_guard() from public, anon, authenticated;

create or replace function public.clients_brand_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  /* A function writing the row has asked its own permission, and a cascade
     is not a person: only a write made on the table through the API. */
  if pg_trigger_depth() > 1 or current_user <> 'authenticated' then
    return new;
  end if;
  if (case when tg_op = 'INSERT' then new.brief is not null or new.brand_notes is not null
           else (new.brief, new.brand_notes) is distinct from (old.brief, old.brand_notes) end)
     and not public.allowed('clients.brand', 'work') then
    raise exception 'brand-columns: You do not have permission to change the content brief and brand notes. Please ask an admin.'
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.clients_brand_guard() from public, anon, authenticated;

create or replace function public.campaigns_finance_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (case when tg_op = 'INSERT'
           then coalesce(current_setting('role', true), '') = 'authenticated'
                and (new.invoice_no, new.invoice_url, new.invoice_uploaded_at) is distinct from (null::text, null::text, null::timestamptz)
           else (new.invoice_no, new.invoice_url, new.invoice_uploaded_at)
                is distinct from (old.invoice_no, old.invoice_url, old.invoice_uploaded_at) end)
     and not public.allowed('campaigns.finance', 'work') then
    raise exception 'You do not have permission to change the campaign invoice. Please ask an admin.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.campaigns_finance_guard() from public, anon, authenticated;

-- END OF PERMISSION REFUSALS IN WORDS ---------------------------------------

select public.functions_tidy();
