-- ===========================================================================
-- BACKEND REVIEW HOLDS — the security and data findings of the 2026-10-22
-- backend review (the user, 2026-10-22: "Fix all"). 2026-10-22. Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in supabase/schema.sql
-- under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED
--   SEC-1. Every guard that held an update holds an insert too
--     (`clients_billing_guard`, `clients_active_billing`,
--     `clients_white_label_guard`, `clients_brand_guard`,
--     `campaigns_finance_guard`, `campaign_deliverables_guard`): a page
--     inserting a client with billing, an Active stage, white label or a
--     brief, a campaign with its invoice, or a file already hidden, is
--     refused as the same update would be.
--   BE-2. A Bukku contact is linked to one record (`bukku_contact_taken`;
--     `bukku_linked` and `bukku_link_only` refuse `taken`), a supplier and
--     its own client sharing one; `bukku_contact_check` lets `bukku-sync`
--     ask before it writes to Bukku.
--   BE-3, CP-2. A public form's typed name is never an actor:
--     `supplier_form_submit` files 'Supplier form' and
--     `quote_website_request` 'Quotation website', the typed name in the
--     detail.
--   BE-4. A quotation's key answers only its own client
--     (`quotation_make`) and its own website visitor (`quote_website_create`).
--   BE-5. `app_setting` reads the first row for an earlier day only where
--     the schema seeded it: a figure the team planned for a later day is not
--     read before it.
--   BE-6. A details link ends when its client moves into Active or Past
--     (trigger `clients_details_close`), and a Past client's link opens
--     nothing (`client_details_read`, `client_details_submit`).
--
-- ORDER: this file, then `bukku-sync` (it asks `bukku_contact_check`), then
--   the pages. A page from before reads as it did; a Bukku sheet open from
--   before meets `taken` from the link functions where it relinks.
--
-- ROLLBACK
--   Each function's definition before this band (CLIENT BILLING, the
--   guards' own bands, BUKKU CONTACTS, SUPPLIER UPDATE LINK, QUOTE WEBSITE
--   GUARDS, BUSINESS SETTINGS, CLIENT DETAILS FORM, CLIENTS AUDIT FIXES),
--   each trigger again as `before update` (clients_active_billing `before
--   update of stage`); trigger clients_details_close and functions
--   bukku_contact_taken and bukku_contact_check removed.
-- ===========================================================================

/* SEC-1: each guard holds an insert as it holds an update. An insert is
   read against a blank row (the column defaults), and only a page's own
   write (the API's `authenticated` role) is held on insert: the functions
   that make a client (the quotation website) set no guarded column. */
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
      raise exception 'Billing details need Clients: Billing at Work.' using errcode = '42501';
    end if;
    return new;
  end if;
  if (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.sst_applies,
      new.bill_contact_id, new.finance_email, new.billing_address, new.bill_sgd)
     is distinct from
     (old.legal_name, old.company_no, old.company_no_old, old.tin, old.sst_no, old.sst_applies,
      old.bill_contact_id, old.finance_email, old.billing_address, old.bill_sgd)
     and not public.allowed('clients.billing', 'work') then
    raise exception 'Billing details need Clients: Billing at Work.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.clients_billing_guard() from public, anon, authenticated;
create or replace trigger clients_billing_guard before insert or update on public.clients
  for each row execute function public.clients_billing_guard();

/* A client keyed in Active holds no contact yet, so a page never makes one
   Active: it is added, then moved through the gate. */
create or replace function public.clients_active_billing()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.stage = 'active' and coalesce(current_setting('role', true), '') = 'authenticated' then
      raise exception 'active-needs-billing';
    end if;
    return new;
  end if;
  if new.stage = 'active' and old.stage is distinct from 'active' and (
       coalesce(btrim(new.legal_name), '') = ''
       or coalesce(btrim(new.company_no), '') = ''
       or coalesce(btrim(new.billing_address), '') = ''
       or not exists (select 1 from public.client_contacts k
                       where k.client_id = new.id and k.archived_at is null
                         and (k.id = new.bill_contact_id or k.is_primary))) then
    raise exception 'active-needs-billing';
  end if;
  return new;
end $$;
revoke all on function public.clients_active_billing() from public, anon, authenticated;
create or replace trigger clients_active_billing before insert or update of stage on public.clients
  for each row execute function public.clients_active_billing();

create or replace function public.clients_white_label_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() > 1 or (auth.jwt() ->> 'email') is null then return new; end if;
  if tg_op = 'INSERT' then
    if (new.white_label is true or new.report_logo is not null)
       and not public.ops_granted('reports.whitelabel', 'work') then
      raise exception 'White label needs Reports: White label at Work.' using errcode = '42501', hint = 'white-label';
    end if;
    return new;
  end if;
  if (new.white_label, new.report_logo) is distinct from (old.white_label, old.report_logo)
     and not public.ops_granted('reports.whitelabel', 'work') then
    raise exception 'White label needs Reports: White label at Work.' using errcode = '42501', hint = 'white-label';
  end if;
  return new;
end $$;
revoke all on function public.clients_white_label_guard() from public, anon, authenticated;
create or replace trigger clients_white_label_guard before insert or update on public.clients
  for each row execute function public.clients_white_label_guard();

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
    raise exception 'brand-columns: the content brief and brand notes need Clients: Brand at Work.'
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.clients_brand_guard() from public, anon, authenticated;
create or replace trigger clients_brand_guard before insert or update on public.clients
  for each row execute function public.clients_brand_guard();

create or replace function public.campaigns_finance_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (case when tg_op = 'INSERT'
           then coalesce(current_setting('role', true), '') = 'authenticated'
                and (new.invoice_no, new.invoice_url, new.invoice_uploaded_at) is distinct from (null::text, null::text, null::timestamptz)
           else (new.invoice_no, new.invoice_url, new.invoice_uploaded_at)
                is distinct from (old.invoice_no, old.invoice_url, old.invoice_uploaded_at) end)
     and not public.allowed('campaigns.finance', 'work') then
    raise exception 'The invoice needs Creator Campaigns: Finance at Work.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.campaigns_finance_guard() from public, anon, authenticated;
create or replace trigger campaigns_finance_guard before insert or update on public.campaigns
  for each row execute function public.campaigns_finance_guard();

/* A file the client approved is the client's record of what they approved:
   a page hides it, and never removes it. Run as the caller, so
   `current_user` tells a page's write from a function's. */
create or replace function public.campaign_deliverables_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if current_user in ('authenticated', 'anon') and (new.hidden_at is not null or new.hidden_by is not null) then
      raise exception 'hide-function' using hint = 'Hide and Restore go through campaign_file_hide.';
    end if;
    return new;
  end if;
  if current_user in ('authenticated', 'anon')
     and new.removed_at is not null and old.removed_at is null
     and exists (select 1 from public.campaign_options o
                  where o.id = new.option_id and o.state in ('scheduled', 'posted', 'completed')) then
    raise exception 'approved-hide' using hint = 'An approved file is hidden, not removed.';
  end if;
  if current_user in ('authenticated', 'anon')
     and (new.hidden_at, new.hidden_by) is distinct from (old.hidden_at, old.hidden_by) then
    raise exception 'hide-function' using hint = 'Hide and Restore go through campaign_file_hide.';
  end if;
  return new;
end $$;
revoke all on function public.campaign_deliverables_guard() from public, anon, authenticated;
create or replace trigger campaign_deliverables_guard
  before insert or update on public.campaign_deliverables
  for each row execute function public.campaign_deliverables_guard();

/* BE-5: a figure is the one in force on the day. The first row stands in
   for an earlier day only where the schema seeded it (no `set_by`), so a
   figure the team plans for a later day (the S$ rate) is not read before
   that day. */
create or replace function public.app_setting(p_key text, p_at date)
returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select s.value from public.app_settings s where s.key = p_key and s.from_date <= coalesce(p_at, (now() at time zone 'Asia/Kuala_Lumpur')::date)
      order by s.from_date desc limit 1),
    (select s.value from public.app_settings s where s.key = p_key and s.set_by is null order by s.from_date limit 1))
$$;
revoke all on function public.app_setting(text, date) from public, anon, authenticated;

/* BE-6: a details link is for the Active gate. A move into Active or Past
   ends every link still open on the client; a Past client's link opens
   nothing. */
create or replace function public.clients_details_close()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.stage in ('active', 'past') and old.stage is distinct from new.stage then
    update public.client_detail_forms f set voided_at = now()
     where f.client_id = new.id and f.voided_at is null and f.submitted_at is null;
  end if;
  return null;
end $$;
revoke all on function public.clients_details_close() from public, anon, authenticated;
create or replace trigger clients_details_close after update of stage on public.clients
  for each row execute function public.clients_details_close();

/* BE-2: one Bukku contact is one record's (a supplier and the client it is
   one contact with). */
create or replace function public.bukku_contact_taken(p_kind text, p_id uuid, p_contact bigint)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.bukku_links l
     where l.contact_id = p_contact
       and not (l.kind = p_kind and l.record_id = p_id)
       and not (p_kind = 'supplier' and l.kind = 'client'
                and l.record_id = (select x.client_id from public.suppliers x where x.id = p_id))
       and not (p_kind = 'client' and l.kind = 'supplier'
                and exists (select 1 from public.suppliers x where x.id = l.record_id and x.client_id = p_id)))
$$;
revoke all on function public.bukku_contact_taken(text, uuid, bigint) from public, anon, authenticated;

create or replace function public.bukku_contact_check(p_kind text, p_id uuid, p_contact bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if public.bukku_contact_taken(p_kind, p_id, p_contact) then return jsonb_build_object('error', 'taken'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_contact_check(text, uuid, bigint) from public, anon;
grant execute on function public.bukku_contact_check(text, uuid, bigint) to authenticated;

create or replace function public.bukku_linked(p_kind text, p_id uuid, p_contact bigint, p_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); v_name text; v_code text; v_client uuid;
begin
  if not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-contact'); end if;
  if p_kind = 'client' then
    select x.name, x.client_code into v_name, v_code from public.clients x where x.id = p_id;
  else
    select coalesce(x.name, x.code), x.code, x.client_id into v_name, v_code, v_client from public.suppliers x where x.id = p_id;
  end if;
  if v_name is null then return jsonb_build_object('error', 'not-found'); end if;
  if public.bukku_contact_taken(p_kind, p_id, p_contact) then return jsonb_build_object('error', 'taken'); end if;
  insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
  values (p_kind, p_id, p_contact, left(p_code, 40), now(), me.id, public.bukku_print(p_kind, p_id))
  on conflict (kind, record_id) do update set contact_id = excluded.contact_id, code = excluded.code,
    sent_at = now(), sent_by = excluded.sent_by, sent_hash = excluded.sent_hash;
  /* One contact for a supplier that is also a client. */
  if v_client is not null then
    insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
    values ('client', v_client, p_contact, left(p_code, 40), now(), me.id, null)
    on conflict (kind, record_id) do update set contact_id = excluded.contact_id, code = excluded.code;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, case when p_kind = 'client' then 'client.edited' else 'supplier.edited' end, v_name,
          coalesce(v_code || ' · ', '') || 'Sent to Bukku · ' || coalesce(p_code, p_contact::text));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_linked(text, uuid, bigint, text) from public, anon;
grant execute on function public.bukku_linked(text, uuid, bigint, text) to authenticated;
create or replace function public.bukku_link_only(p_kind text, p_id uuid, p_contact bigint, p_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); v_name text; v_code text; v_client uuid;
begin
  if not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-contact'); end if;
  if p_kind = 'client' then
    select x.name, x.client_code into v_name, v_code from public.clients x where x.id = p_id;
  else
    select coalesce(x.name, x.code), x.code, x.client_id into v_name, v_code, v_client from public.suppliers x where x.id = p_id;
  end if;
  if v_name is null then return jsonb_build_object('error', 'not-found'); end if;
  if public.bukku_contact_taken(p_kind, p_id, p_contact) then return jsonb_build_object('error', 'taken'); end if;
  insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
  values (p_kind, p_id, p_contact, left(p_code, 40), now(), me.id, public.bukku_print(p_kind, p_id))
  on conflict (kind, record_id) do update set contact_id = excluded.contact_id, code = excluded.code,
    sent_at = now(), sent_by = excluded.sent_by, sent_hash = excluded.sent_hash;
  /* One contact for a supplier that is also a client. */
  if v_client is not null then
    insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
    values ('client', v_client, p_contact, left(p_code, 40), now(), me.id, null)
    on conflict (kind, record_id) do update set contact_id = excluded.contact_id, code = excluded.code;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, case when p_kind = 'client' then 'client.edited' else 'supplier.edited' end, v_name,
          coalesce(v_code || ' · ', '') || 'Linked to Bukku, nothing sent · ' || coalesce(p_code, p_contact::text));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_link_only(text, uuid, bigint, text) from public, anon;
grant execute on function public.bukku_link_only(text, uuid, bigint, text) to authenticated;
create or replace function public.supplier_form_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f public.supplier_forms;
  s public.suppliers;
  v jsonb;
  a jsonb := coalesce(p_answers, '{}'::jsonb);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into f from public.supplier_forms x where x.access_key = p_key and x.voided_at is null for update;
  if f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  if coalesce(a->>'authorise', '') <> 'true' then return jsonb_build_object('error', 'bad-authorise'); end if;
  select * into s from public.suppliers x where x.id = f.supplier_id;
  /* An update keeps the NRIC and the bank details held where left blank. */
  if f.purpose = 'update' then
    if btrim(coalesce(a->>'bank_account', '')) = '' and s.bank_account is not null then
      a := a || jsonb_build_object('payee_name', s.payee_name, 'bank_name', s.bank_name, 'bank_account', s.bank_account,
                                   'swift', s.swift, 'bank_address', s.bank_address);
    end if;
    if btrim(coalesce(a->>'nric', '')) = '' and s.nric is not null then
      a := a || jsonb_build_object('nric', s.nric);
    end if;
  end if;
  v := public.supplier_values_check(a, true);
  if v ? 'error' then return v; end if;
  update public.supplier_forms x set submitted_at = now(), answers = jsonb_strip_nulls(v) where x.id = f.id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Supplier form', 'supplier.edited', coalesce(s.name, v->>'name'), s.code || ' · ' ||
          case when f.purpose = 'update' then 'Details update received on the update link' else 'Details received on the details form' end ||
          coalesce(' from ' || nullif(btrim(v->>'contact_name'), ''), ''));
  insert into public.ops_notifications (team_member_id, kind, title, body, supplier_id, dedupe_key)
  select m.id, 'supplier.details',
         case when f.purpose = 'update' then 'Supplier details update received · ' else 'Supplier details received · ' end || coalesce(s.name, v->>'name'),
         'From ' || (v->>'contact_name') || '. Review them on the supplier.',
         s.id, 'supplier.details:' || f.id || ':' || m.id
    from public.team_members m
   where m.active and not coalesce(m.system, false)
     and (m.is_admin or m.role = 'admin'
          or public.level_rank(m.access ->> 'suppliers') >= 2)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_form_submit(text, jsonb) from public;
grant execute on function public.supplier_form_submit(text, jsonb) to anon, authenticated;
create or replace function public.quote_website_request(p_key text, p_billing jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_q    public.quotations;
  v_sg   boolean;
  v_reg  text := upper(btrim(regexp_replace(coalesce(p_billing->>'registered_name', ''), '\s+', ' ', 'g')));
  v_brn  text := upper(regexp_replace(coalesce(p_billing->>'brn', ''), '[^0-9A-Za-z]', '', 'g'));
  v_addr text := btrim(coalesce(p_billing->>'address', ''));
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into v_q from public.quotations q
   where q.access_key = p_key and q.source = 'website' and q.removed_at is null for update;
  if v_q.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_q.requested_at is not null then return jsonb_build_object('ok', true, 'again', true); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if v_q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  select c.market = 'SG' into v_sg from public.clients c where c.id = v_q.client_id;
  if length(v_reg) < 3 or length(v_reg) > 160 or length(v_addr) < 10 or length(v_addr) > 400
     or (coalesce(v_sg, false) and v_brn !~ '^([0-9]{8,9}[A-Z]|[TSR][0-9]{2}[A-Z]{2}[0-9]{4}[A-Z])$')
     or (not coalesce(v_sg, false) and v_brn !~ '^[0-9]{12}$') then
    return jsonb_build_object('error', 'bad-billing');
  end if;
  update public.quotations
     set billing = jsonb_build_object('registered_name', v_reg, 'brn', v_brn, 'address', v_addr),
         requested_at = now(), status = 'requested'
   where id = v_q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation website', 'client.quotation', v_q.brand,
          v_q.ref || ' · Letter of Offer requested on the website' ||
          coalesce(' by ' || nullif(btrim(v_q.contact->>'name'), ''), ''));
  perform public.quote_tell(v_q.client_id, 'quote.requested', 'Letter of Offer requested · ' || v_q.brand,
    v_q.ref || ' · ' || v_reg, v_q.id::text);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quote_website_request(text, jsonb) from public;
grant execute on function public.quote_website_request(text, jsonb) to anon, authenticated;
create or replace function public.quotation_make(p_client uuid, p_sel jsonb, p_idem text, p_source text,
                                                 p_by text, p_contact jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c public.clients;
  v_card jsonb := public.quote_card();
  v_p jsonb;
  v_q public.quotations;
  v_now timestamptz := now();
  v_days int;
  v_fx numeric;
  v_sel jsonb := case when jsonb_typeof(p_sel) is distinct from 'object' then p_sel
                      when p_source = 'console' then p_sel - 'client'
                      else p_sel - 'edits' - 'client' end;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem and q.client_id = p_client;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_p := public.quote_fx_out(public.quote_adjust(public.quote_price(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id), v_fx),
           v_sel), public.quote_tax_edits(v_sel->'edits')), v_fx);
  if v_p ? 'error' then return v_p; end if;
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  begin
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key)
  values (public.quote_ref(v_c.name, v_now), v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, v_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request'), p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end)
  returning * into v_q;
  -- Two presses at once with one key: the second answers the first's.
  exception when unique_violation then
    select * into v_q from public.quotations q where q.idem = p_idem and q.client_id = p_client;
    if p_idem is null or v_q.id is null then raise; end if;
    return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true);
  end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_by, 'Website'), 'client.quotation', v_c.name,
          v_q.ref || ' sent · ' || coalesce('Monthly incl. SST ' || case when v_fx is null then 'RM ' else 'S$ ' end ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;
create or replace function public.quote_website_create(p_sel jsonb, p_contact jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name  text := btrim(regexp_replace(coalesce(p_contact->>'name', ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_contact->>'email', '')));
  v_wa    text := public.quote_website_number(p_contact->>'whatsapp');
  v_brand text := btrim(regexp_replace(coalesce(p_contact->>'brand', ''), '\s+', ' ', 'g'));
  v_ind   text := nullif(btrim(coalesce(p_contact->>'industry', '')), '');
  v_lang  text := case when p_contact->>'lang' = 'zh' then 'zh' else 'en' end;
  v_sal   text := nullif(btrim(coalesce(p_contact->>'salutation', '')), '');
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_sel   jsonb;
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
  select * into v_q from public.quotations q
   where q.idem = v_idem and q.source = 'website' and lower(q.contact->>'email') = v_email;
  if v_q.id is not null then
    return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key, 'again', true);
  end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 160 then return jsonb_build_object('error', 'bad-email'); end if;
  if v_wa !~ '^(60(1[0-9]{8,9}|7[0-9]{7,8})|65[0-9]{8})$' then return jsonb_build_object('error', 'bad-whatsapp'); end if;
  if length(v_brand) < 2 or length(v_brand) > 120 then return jsonb_build_object('error', 'bad-brand'); end if;
  if v_ind is not null and v_ind not in ('Property', 'F&B', 'Retail', 'Wellness', 'Lifestyle',
                                         'Automotive', 'Tech', 'Education', 'Other') then
    return jsonb_build_object('error', 'bad-industry');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-salutation');
  end if;
  if coalesce((p_contact->>'consent')::boolean, false) is not true then return jsonb_build_object('error', 'consent'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if jsonb_typeof(p_sel->'once') = 'array' and jsonb_array_length(p_sel->'once') > 20
     or jsonb_typeof(p_sel->'extra') = 'object' and (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
    return jsonb_build_object('error', 'bad-selection');
  end if;

  -- What the price reads, and nothing else.
  v_sel := jsonb_strip_nulls(jsonb_build_object(
    'mix', case when jsonb_typeof(p_sel->'mix') = 'string' and length(p_sel->>'mix') <= 20 then p_sel->'mix' end,
    'plan', case when jsonb_typeof(p_sel->'plan') = 'string' and length(p_sel->>'plan') <= 80 then p_sel->'plan' end,
    'term', case when jsonb_typeof(p_sel->'term') in ('number', 'string') and length(p_sel->>'term') <= 4 then p_sel->'term' end,
    'budget', case when jsonb_typeof(p_sel->'budget') in ('number', 'string') and length(p_sel->>'budget') <= 12 then p_sel->'budget' end,
    'translate', case when jsonb_typeof(p_sel->'translate') = 'boolean' then p_sel->'translate' end,
    'platforms', (select jsonb_agg(distinct v) from jsonb_array_elements_text(
                    case when jsonb_typeof(p_sel->'platforms') = 'array' then p_sel->'platforms' else '[]'::jsonb end) v
                   where v in ('meta', 'tiktok', 'rednote', 'linkedin')),
    'langs', (select jsonb_agg(distinct l) from jsonb_array_elements_text(
                case when jsonb_typeof(p_sel->'langs') = 'array' then p_sel->'langs' else '[]'::jsonb end) l
               where l in ('en', 'zh', 'ms')),
    'extra', case when jsonb_typeof(p_sel->'extra') = 'object' then
               (select jsonb_object_agg(left(k, 80), p_sel->'extra'->k) from jsonb_object_keys(p_sel->'extra') k) end,
    'once', case when jsonb_typeof(p_sel->'once') = 'array' then
              (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('slug', left(o->>'slug', 80), 'qty', o->'qty')))
                 from jsonb_array_elements(p_sel->'once') o where jsonb_typeof(o) = 'object') end));

  -- Two posts at once are counted one after the other.
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || least(v_email, v_wa), 0));
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || greatest(v_email, v_wa), 0));
  if (select count(*) from public.quotations q
       where q.source = 'website' and q.issued_at > now() - interval '1 day'
         and (lower(q.contact->>'email') = v_email or q.contact->>'whatsapp' = '+' || v_wa)) >= 5 then
    return jsonb_build_object('error', 'limit');
  end if;

  -- A lead this person already is (the same contact holds both the email
  -- and the number), else a new one.
  select c.* into v_c from public.clients c
    join public.client_contacts k on k.client_id = c.id
   where c.stage in ('lead', 'contacted', 'proposal')
     and k.archived_at is null
     and lower(k.email) = v_email
     and public.quote_website_number(k.whatsapp) = v_wa
   order by c.created_at desc limit 1;
  if v_c.id is null then
    v_base := btrim(regexp_replace(lower(v_brand), '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'client'; end if;
    v_slug := v_base;
    while exists (select 1 from public.clients c where lower(c.slug) = v_slug) loop
      v_n := v_n + 1; v_slug := v_base || '-' || v_n;
    end loop;
    insert into public.clients (name, access_token, stage, industry, source, market, slug, deal_note)
    values (v_brand, public.new_link_key(), 'lead', v_ind, 'website',
            case when v_wa like '65%' then 'SG' else 'MY' end, v_slug,
            'Quotation requested on the website.')
    returning * into v_c;
    insert into public.client_contacts (client_id, salutation, name, email, whatsapp, lang, is_primary)
    values (v_c.id, v_sal, v_name, v_email, '+' || v_wa, v_lang, true);
    insert into public.activity_log (actor, action, subject, detail)
    values ('Website', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
    v_new := true;
  end if;

  v_r := public.quotation_make(v_c.id, v_sel, v_idem, 'website', null,
    jsonb_strip_nulls(jsonb_build_object('salutation', v_sal, 'name', v_name, 'email', v_email,
      'whatsapp', '+' || v_wa, 'lang', v_lang, 'brand', v_brand)));
  if v_r ? 'error' then
    if v_new then raise exception using message = 'quote:' || (v_r->>'error'); end if;
    return v_r;
  end if;
  select * into v_q from public.quotations where id = (v_r->>'id')::uuid;
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation made on the website · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name,
    v_q.id::text);
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;
create or replace function public.client_details_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_f  public.client_detail_forms;
  v_cl public.clients;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_f from public.client_detail_forms f where f.access_key = p_key and f.voided_at is null;
  if v_f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if v_f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  if v_cl.stage = 'past' then return jsonb_build_object('error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'brand', v_cl.name, 'expires_at', v_f.expires_at);
end $$;
revoke all on function public.client_details_read(text) from public;
grant execute on function public.client_details_read(text) to anon, authenticated;
create or replace function public.client_details_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_f    public.client_detail_forms;
  v_cl   public.clients;
  a      jsonb := coalesce(p_answers, '{}'::jsonb);
  t      text;
  v_name text := upper(btrim(regexp_replace(coalesce(a->>'legal_name', ''), '\s+', ' ', 'g')));
  v_brn  text := upper(regexp_replace(coalesce(a->>'company_no', ''), '\s+', '', 'g'));
  v_old  text := nullif(upper(regexp_replace(coalesce(a->>'company_no_old', ''), '\s+', '', 'g')), '');
  v_tin  text := nullif(upper(regexp_replace(coalesce(a->>'tin', ''), '\s+', '', 'g')), '');
  v_sst  text := nullif(upper(regexp_replace(coalesce(a->>'sst_no', ''), '\s+', '', 'g')), '');
  v_addr text := btrim(coalesce(a->>'billing_address', ''));
  v_fin  text := nullif(lower(btrim(coalesce(a->>'finance_email', ''))), '');
  v_sal  text := nullif(btrim(coalesce(a->>'contact_salutation', '')), '');
  v_cn   text := btrim(regexp_replace(coalesce(a->>'contact_name', ''), '\s+', ' ', 'g'));
  v_cp   text := btrim(coalesce(a->>'contact_phone', ''));
  v_ce   text := lower(btrim(coalesce(a->>'contact_email', '')));
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_f from public.client_detail_forms f where f.access_key = p_key and f.voided_at is null for update;
  if v_f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if v_f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  if exists (select 1 from public.clients c where c.id = v_f.client_id and c.stage = 'past') then
    return jsonb_build_object('error', 'not_found');
  end if;
  if length(v_name) < 2 or length(v_name) > 160 then return jsonb_build_object('error', 'bad-legal_name'); end if;
  if v_brn !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-company_no'); end if;
  if v_old is not null and v_old !~ '^[A-Z0-9-]{4,20}$' then return jsonb_build_object('error', 'bad-company_no_old'); end if;
  if v_tin is not null and v_tin !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-tin'); end if;
  if v_sst is not null and v_sst !~ '^[A-Z0-9-]{6,25}$' then return jsonb_build_object('error', 'bad-sst_no'); end if;
  if length(v_addr) < 10 or length(v_addr) > 400 then return jsonb_build_object('error', 'bad-billing_address'); end if;
  if v_fin is not null and (v_fin !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_fin) > 160) then
    return jsonb_build_object('error', 'bad-finance_email');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-contact_salutation');
  end if;
  if length(v_cn) < 2 or length(v_cn) > 80 then return jsonb_build_object('error', 'bad-contact_name'); end if;
  t := regexp_replace(v_cp, '[^0-9]', '', 'g');
  if length(t) < 8 or length(t) > 15 or length(v_cp) > 30 then return jsonb_build_object('error', 'bad-contact_phone'); end if;
  if v_ce !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_ce) > 160 then return jsonb_build_object('error', 'bad-contact_email'); end if;

  update public.client_detail_forms f
     set submitted_at = now(),
         answers = jsonb_strip_nulls(jsonb_build_object(
           'legal_name', v_name, 'company_no', v_brn, 'company_no_old', v_old, 'tin', v_tin, 'sst_no', v_sst,
           'billing_address', v_addr, 'finance_email', v_fin, 'contact_salutation', v_sal,
           'contact_name', v_cn, 'contact_phone', v_cp, 'contact_email', v_ce))
   where f.id = v_f.id;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Details form', 'client.edited', v_cl.name,
          'Billing details received on the details form from ' || coalesce(v_sal || ' ', '') || v_cn);
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.details', 'Billing details received · ' || v_cl.name,
         'From ' || coalesce(v_sal || ' ', '') || v_cn || '. Review them on the client''s Billing.',
         v_cl.id, 'client.details:' || v_f.id || ':' || m.id
    from public.team_members m
   where m.active and not coalesce(m.system, false)
     and (m.is_admin or m.role = 'admin'
          or (public.level_rank(coalesce(m.access ->> 'clients.billing', m.access ->> 'clients')) >= 2
              -- held to the colleague's own client scope, as client_row_seen holds a reader (audit S7)
              and (v_cl.stage not in ('lead', 'contacted', 'proposal', 'past')
                   or public.level_rank(coalesce(m.access ->> case when v_cl.stage = 'past' then 'clients.past' else 'clients.leads' end,
                                                 m.access ->> 'clients')) >= 1)
              and (coalesce(m.client_scope, 'all') <> 'own'
                   or (nullif(btrim(coalesce(v_cl.owner, '')), '') is null and v_cl.stage in ('lead', 'contacted', 'proposal'))
                   or lower(btrim(coalesce(v_cl.owner, ''))) = lower(btrim(coalesce(m.name, ''))))))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

-- END OF BACKEND REVIEW HOLDS ----------------------------------------------

select public.functions_tidy();
