-- ============================================================================
-- BUKKU'S CREATOR ID FIELD (2026-11-10)
-- ============================================================================
-- The user, 2026-11-10: "bukku id supplier id, how about Creator id i have
-- added new one". Settings, Money, Bukku chooses a third Bukku contact
-- field, the one that holds the Creator ID:
--
--   1. `bukku_settings.field_creator` (Bukku's own id).
--   2. `bukku_config()` answers it; `bukku_config_set(p_client, p_supplier,
--      p_creator)` sets the three (`team.settings`, filed from and to). The
--      two-argument form stays for a tab opened before, and leaves the
--      Creator ID field as it is.
--   3. `bukku_prepare` sends a creator's Creator ID in that field, else in
--      the Supplier ID field while none is chosen (as before).
--
-- Re-runnable. Rollback: run the CREATOR PAYMENTS section's
-- `bukku_prepare` again, drop the three-argument `bukku_config_set` and
-- the column (SQL Editor).

alter table public.bukku_settings add column if not exists field_creator bigint;

create or replace function public.bukku_config()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b public.bukku_settings;
begin
  if (public.ops_me()).id is null or not (public.allowed('clients.billing', 'work') or public.allowed('suppliers', 'work')
      or public.ops_granted('team.settings', 'work')) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into b from public.bukku_settings where id = 1;
  return jsonb_build_object('ok', true, 'field_client', b.field_client, 'field_supplier', b.field_supplier,
    'field_creator', b.field_creator, 'set_at', b.set_at);
end $$;
revoke all on function public.bukku_config() from public, anon;
grant execute on function public.bukku_config() to authenticated;

create or replace function public.bukku_config_set(p_client bigint, p_supplier bigint, p_creator bigint)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); b public.bukku_settings;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if (p_client is not null and p_client <= 0) or (p_supplier is not null and p_supplier <= 0)
     or (p_creator is not null and p_creator <= 0) then
    return jsonb_build_object('error', 'bad-value');
  end if;
  select * into b from public.bukku_settings where id = 1;
  if b.id is not null and b.field_client is not distinct from p_client and b.field_supplier is not distinct from p_supplier
     and b.field_creator is not distinct from p_creator then
    return jsonb_build_object('ok', true);
  end if;
  insert into public.bukku_settings (id, field_client, field_supplier, field_creator, set_by, set_at)
  values (1, p_client, p_supplier, p_creator, me.id, now())
  on conflict (id) do update set field_client = excluded.field_client, field_supplier = excluded.field_supplier,
    field_creator = excluded.field_creator, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Bukku', 'Client ID field: ' || coalesce(b.field_client::text, 'not set') || ' → ' || coalesce(p_client::text, 'not set')
    || '; Supplier ID field: ' || coalesce(b.field_supplier::text, 'not set') || ' → ' || coalesce(p_supplier::text, 'not set')
    || '; Creator ID field: ' || coalesce(b.field_creator::text, 'not set') || ' → ' || coalesce(p_creator::text, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_config_set(bigint, bigint, bigint) from public, anon;
grant execute on function public.bukku_config_set(bigint, bigint, bigint) to authenticated;

create or replace function public.bukku_prepare(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients; s public.suppliers; ct public.client_contacts; e public.billing_entities;
  l public.bukku_links; b public.bukku_settings; cr public.creators; rq public.creator_pay_requests;
  v_missing text[] := '{}'; v_company boolean; v_id text; v_field bigint; v_pay boolean;
  v_person text; v_out jsonb;
begin
  if not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into b from public.bukku_settings where id = 1;
  if p_kind = 'client' then
    select * into c from public.clients x where x.id = p_id;
    if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into ct from public.client_contacts x
     where x.id = c.bill_contact_id and x.archived_at is null;
    if ct.id is null then
      select * into ct from public.client_contacts x where x.client_id = c.id and x.is_primary and x.archived_at is null;
    end if;
    if coalesce(btrim(c.legal_name), '') = '' then v_missing := v_missing || 'Registered Company Name'::text; end if;
    if coalesce(btrim(c.client_code), '') = '' then v_missing := v_missing || 'Client ID'::text; end if;
    if array_length(v_missing, 1) > 0 then return jsonb_build_object('error', 'incomplete', 'missing', to_jsonb(v_missing)); end if;
    select * into l from public.bukku_links x where x.kind = 'client' and x.record_id = c.id;
    if l.contact_id is null then l.contact_id := (public.bukku_shared('client', c.id)->>'contact_id')::bigint; end if;
    v_person := btrim(coalesce(ct.name, ''));
    return jsonb_build_object('ok', true, 'kind', 'client', 'id', c.id,
      'legal_name', public.bukku_name_case(c.legal_name, true), 'other_name', c.name,
      'entity_type', case when c.market = 'SG' then 'FOREIGN_COMPANY' else 'MALAYSIAN_COMPANY' end,
      'reg_no_type', case when nullif(regexp_replace(coalesce(c.company_no, ''), '[^0-9A-Za-z]', '', 'g'), '') is null then null else 'BRN' end,
      'reg_no', nullif(regexp_replace(coalesce(c.company_no, ''), '[^0-9A-Za-z]', '', 'g'), ''),
      'old_reg_no', nullif(btrim(coalesce(c.company_no_old, '')), ''),
      'tax_id_no', nullif(btrim(coalesce(c.tin, '')), ''), 'sst_reg_no', nullif(btrim(coalesce(c.sst_no, '')), ''),
      'email', nullif(btrim(coalesce(c.finance_email, ct.email, '')), ''),
      'phone_no', public.wa_number(coalesce(ct.phone, ct.whatsapp), coalesce(c.market, 'MY')),
      'address', nullif(btrim(coalesce(c.billing_address, '')), ''),
      'country', case when c.market = 'SG' then 'SG' else 'MY' end,
      'currency', case when public.client_bill_market(c.market, c.bill_sgd) = 'SG' then 'SGD' else 'MYR' end,
      'person', nullif(public.bukku_name_case(v_person, false), ''),
      'salutation', nullif(btrim(coalesce(ct.salutation, '')), ''),
      'our_id', c.client_code, 'field_id', b.field_client, 'type', 'customer',
      'contact_id', l.contact_id);
  elsif p_kind = 'supplier' then
    select * into s from public.suppliers x where x.id = p_id;
    if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if s.status <> 'active' then return jsonb_build_object('error', 'not-active'); end if;
    v_company := coalesce(s.kind, 'company') = 'company';
    v_pay := public.ops_granted('suppliers.pay', 'view');
    select * into l from public.bukku_links x where x.kind = 'supplier' and x.record_id = s.id;
    if l.contact_id is null and s.client_id is not null then
      select * into l from public.bukku_links x where x.kind = 'client' and x.record_id = s.client_id;
    end if;
    return jsonb_build_object('ok', true, 'kind', 'supplier', 'id', s.id,
      'legal_name', public.bukku_name_case(s.name, v_company),
      'entity_type', case when s.currency = 'SGD' then (case when v_company then 'FOREIGN_COMPANY' else 'FOREIGN_INDIVIDUAL' end)
                          else (case when v_company then 'MALAYSIAN_COMPANY' else 'MALAYSIAN_INDIVIDUAL' end) end,
      'reg_no_type', case when v_company and s.brn is not null then 'BRN' when not v_company and v_pay and s.nric is not null then 'NRIC' end,
      'reg_no', case when v_company then s.brn when v_pay then regexp_replace(coalesce(s.nric, ''), '[^0-9]', '', 'g') end,
      'tax_id_no', s.tin, 'sst_reg_no', s.sst_no,
      'email', coalesce(s.finance_email, s.email),
      'phone_no', public.wa_number(coalesce(s.mobile, s.phone), case when s.currency = 'SGD' then 'SG' else 'MY' end),
      'address', s.address, 'country', case when s.currency = 'SGD' then 'SG' else 'MY' end,
      'currency', s.currency,
      'person', public.bukku_name_case(coalesce(s.contact_name, case when not v_company then s.name end), false),
      'payment_term', s.payment_term,
      'our_id', s.code, 'field_id', b.field_supplier, 'type', 'supplier',
      'client_id', s.client_id, 'contact_id', l.contact_id);
  elsif p_kind = 'creator' then
    /* A creator is a supplier in Bukku (2026-11-09, Creator R3): sent from
       the payment details approved last, the Creator ID in Bukku's Creator
       ID field, else the Supplier ID field while none is chosen
       (2026-11-10); the ID number goes only at Creator payment details View. */
    select * into cr from public.creators x where x.id = p_id;
    if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into rq from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
     order by x.decided_at desc limit 1;
    if rq.id is null then return jsonb_build_object('error', 'no-details'); end if;
    if coalesce(btrim(cr.creator_code), '') = '' then return jsonb_build_object('error', 'incomplete', 'missing', to_jsonb(array['Creator ID'])); end if;
    v_company := rq.bill_kind = 'brn';
    v_pay := public.ops_granted('campaigns.pay', 'view');
    select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = cr.id;
    return jsonb_build_object('ok', true, 'kind', 'creator', 'id', cr.id,
      'legal_name', public.bukku_name_case(rq.legal_name, v_company), 'other_name', cr.name,
      'entity_type', case when rq.bill_kind = 'passport' or rq.currency = 'SGD'
                          then (case when v_company then 'FOREIGN_COMPANY' else 'FOREIGN_INDIVIDUAL' end)
                          else (case when v_company then 'MALAYSIAN_COMPANY' else 'MALAYSIAN_INDIVIDUAL' end) end,
      'reg_no_type', case when v_company then 'BRN' when v_pay and rq.bill_kind = 'nric' then 'NRIC'
                          when v_pay and rq.bill_kind = 'passport' then 'PASSPORT' end,
      'reg_no', case when v_company or v_pay then nullif(regexp_replace(rq.id_no, '[^0-9A-Za-z]', '', 'g'), '') end,
      'tax_id_no', nullif(btrim(coalesce(rq.tin, '')), ''), 'email', rq.email,
      'phone_no', public.wa_number(coalesce(rq.whatsapp, cr.whatsapp), case when rq.currency = 'SGD' then 'SG' else 'MY' end),
      'address', rq.address, 'country', case when rq.currency = 'SGD' then 'SG' else 'MY' end,
      'currency', rq.currency,
      'person', case when not v_company then public.bukku_name_case(rq.legal_name, false) end,
      'our_id', cr.creator_code, 'field_id', coalesce(b.field_creator, b.field_supplier), 'type', 'supplier',
      'contact_id', l.contact_id);
  elsif p_kind = 'entity' then
    select * into e from public.billing_entities x where x.id = p_id;
    if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = public.entity_home_client(e.id);
    ct := public.entity_contact(e.id);
    if coalesce(btrim(e.legal_name), '') = '' then v_missing := v_missing || 'Registered Company Name'::text; end if;
    if coalesce(btrim(c.client_code), '') = '' then v_missing := v_missing || 'Client ID'::text; end if;
    if array_length(v_missing, 1) > 0 then return jsonb_build_object('error', 'incomplete', 'missing', to_jsonb(v_missing)); end if;
    select * into l from public.bukku_links x where x.kind = 'entity' and x.record_id = e.id;
    if l.contact_id is null then l.contact_id := (public.bukku_shared('entity', e.id)->>'contact_id')::bigint; end if;
    v_person := btrim(coalesce(ct.name, ''));
    return jsonb_build_object('ok', true, 'kind', 'entity', 'id', e.id,
      'legal_name', public.bukku_name_case(e.legal_name, true), 'other_name', c.name,
      'entity_type', case when c.market = 'SG' then 'FOREIGN_COMPANY' else 'MALAYSIAN_COMPANY' end,
      'reg_no_type', case when nullif(regexp_replace(coalesce(e.company_no, ''), '[^0-9A-Za-z]', '', 'g'), '') is null then null else 'BRN' end,
      'reg_no', nullif(regexp_replace(coalesce(e.company_no, ''), '[^0-9A-Za-z]', '', 'g'), ''),
      'old_reg_no', nullif(btrim(coalesce(e.company_no_old, '')), ''),
      'tax_id_no', nullif(btrim(coalesce(e.tin, '')), ''), 'sst_reg_no', nullif(btrim(coalesce(e.sst_no, '')), ''),
      'email', nullif(btrim(coalesce(e.finance_email, ct.email, '')), ''),
      'phone_no', public.wa_number(coalesce(ct.phone, ct.whatsapp), coalesce(c.market, 'MY')),
      'address', nullif(btrim(coalesce(e.billing_address, '')), ''),
      'country', case when c.market = 'SG' then 'SG' else 'MY' end,
      'currency', case when public.client_bill_market(c.market, c.bill_sgd) = 'SG' then 'SGD' else 'MYR' end,
      'person', nullif(public.bukku_name_case(v_person, false), ''),
      'salutation', nullif(btrim(coalesce(ct.salutation, '')), ''),
      'our_id', c.client_code, 'field_id', b.field_client, 'type', 'customer',
      'contact_id', l.contact_id);
  end if;
  return jsonb_build_object('error', 'bad-kind');
end $$;
revoke all on function public.bukku_prepare(text, uuid) from public, anon;
grant execute on function public.bukku_prepare(text, uuid) to authenticated;

select public.functions_tidy();
