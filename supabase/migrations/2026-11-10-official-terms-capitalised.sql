-- WHY: the user, 2026-11-09: "when an item is a proper or professional noun,
--   it is good to capital it isnt it — eg. Passport, Tax Identification
--   Number (TIN)". An official or professional term keeps its capitals
--   wherever it is written, a label included (DESIGN.md §6).
-- WHAT: the words seven functions write capitalise those terms: what
--   bukku_prepare names as missing, the Activity record's lines from
--   bukku_take, client_entity_save, quotation_submit, client_entity_delete
--   and supplier_save, and clients_entity_sync's refusal (Registered
--   Company Name, Business Registration No., Old Registration No., SST
--   Registration No.). Each function is restated
--   otherwise unchanged; nothing else moves.
-- ORDER: the pages, then this file.
-- ROLLBACK: restate the seven functions from their bands before this one in
--   schema.sql (the words alone differ).

-- ===========================================================================

-- OFFICIAL TERMS CAPITALISED -------------------------------------------------

create or replace function public.bukku_take(p_actor uuid, p_kind text, p_id uuid, p_values jsonb, p_hash text,
                                             p_changed text[], p_mode text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  l public.bukku_links; p jsonb; k public.client_contacts;
  v_ent uuid; v_who text; v_name text; v_detail text; v_bc uuid; v_bc_set boolean := false;
  v_changed text[] := coalesce(p_changed, '{}');
  v_open text[];
  v_words constant jsonb := '{"legal_name": "Registered Company Name", "company_no": "Business Registration No.",
    "company_no_old": "Old Registration No.", "tin": "TIN", "sst_no": "SST Registration No.",
    "finance_email": "Finance email", "billing_address": "Billing address", "person": "Billing contact"}';
  v_t text;
  v_new boolean := false;
begin
  if p_kind not in ('client', 'entity') or p_mode not in ('read', 'hold', 'save')
     or jsonb_typeof(p_values) is distinct from 'object' then
    return jsonb_build_object('error', 'bad-request');
  end if;
  l := public.bukku_link_row(p_kind, p_id);
  if l.contact_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  p := public.bukku_portal(p_kind, p_id);
  if p is null then return jsonb_build_object('error', 'not-found'); end if;
  select array_agg(f) into v_changed from unnest(v_changed) f where v_words ? f;
  v_changed := coalesce(v_changed, '{}');
  select array_agg(f) into v_open from unnest(v_changed) f
   where nullif(btrim(coalesce(p->>f, '')), '') is not null;
  v_open := coalesce(v_open, '{}');
  update public.bukku_links x set read_at = now(), read_hash = left(p_hash, 200),
         person = nullif(left(btrim(coalesce(p_values->>'person', '')), 120), '')
   where x.kind = l.kind and x.record_id = l.record_id;
  /* The first read of a link not yet held writes nothing over a detail
     the portal holds: it waits on Send to Bukku or Use Bukku's. */
  if p_mode = 'read' and l.held_at is null and cardinality(v_open) > 0 then
    return jsonb_build_object('ok', true, 'held', false, 'differs', to_jsonb(v_changed));
  end if;

  if p_kind = 'client' then
    v_ent := public.client_main_entity(p_id);
    if v_ent is null then
      insert into public.billing_entities (legal_name) values (nullif(btrim(coalesce(p_values->>'legal_name', '')), ''))
      returning id into v_ent;
      insert into public.client_entities (client_id, entity_id, is_main) values (p_id, v_ent, true);
      v_new := true;
    end if;
  else
    v_ent := p_id;
  end if;
  if p_values ? 'person' and nullif(btrim(coalesce(p_values->>'person', '')), '') is not null then
    k := public.bukku_person_contact(p_kind, p_id, p_values->>'person');
    if k.id is not null then
      v_bc_set := true;
      v_bc := case when k.is_primary and k.client_id = coalesce(case when p_kind = 'client' then p_id end,
                                                                public.entity_home_client(p_id)) then null else k.id end;
    end if;
  end if;
  update public.billing_entities e
     set legal_name = case when p_values ? 'legal_name' and ('legal_name' = any(v_changed) or nullif(btrim(coalesce(e.legal_name, '')), '') is null)
                           then nullif(upper(btrim(regexp_replace(coalesce(p_values->>'legal_name', ''), '\s+', ' ', 'g'))), '')
                           else e.legal_name end,
         company_no = case when p_values ? 'company_no' and ('company_no' = any(v_changed) or nullif(btrim(coalesce(e.company_no, '')), '') is null) then nullif(btrim(coalesce(p_values->>'company_no', '')), '') else e.company_no end,
         company_no_old = case when p_values ? 'company_no_old' and ('company_no_old' = any(v_changed) or nullif(btrim(coalesce(e.company_no_old, '')), '') is null) then nullif(btrim(coalesce(p_values->>'company_no_old', '')), '') else e.company_no_old end,
         tin = case when p_values ? 'tin' and ('tin' = any(v_changed) or nullif(btrim(coalesce(e.tin, '')), '') is null) then nullif(btrim(coalesce(p_values->>'tin', '')), '') else e.tin end,
         sst_no = case when p_values ? 'sst_no' and ('sst_no' = any(v_changed) or nullif(btrim(coalesce(e.sst_no, '')), '') is null) then nullif(btrim(coalesce(p_values->>'sst_no', '')), '') else e.sst_no end,
         finance_email = case when p_values ? 'finance_email' and ('finance_email' = any(v_changed) or nullif(btrim(coalesce(e.finance_email, '')), '') is null) then nullif(lower(btrim(coalesce(p_values->>'finance_email', ''))), '') else e.finance_email end,
         billing_address = case when p_values ? 'billing_address' and ('billing_address' = any(v_changed) or nullif(btrim(coalesce(e.billing_address, '')), '') is null) then nullif(btrim(coalesce(p_values->>'billing_address', '')), '') else e.billing_address end,
         bill_contact_id = case when v_bc_set then v_bc else e.bill_contact_id end,
         updated_at = case when cardinality(v_changed) > 0 or v_new
                             or (v_bc_set and v_bc is distinct from e.bill_contact_id)
                           then clock_timestamp() else e.updated_at end
   where e.id = v_ent;
  -- A client's first entity, made here, is carried to the client's own
  -- columns (audit 2026-10-30: the update changed nothing, so the mirror
  -- never ran).
  if v_new then perform public.billing_entity_put(v_ent, p_id); end if;
  update public.bukku_links x set held_at = coalesce(x.held_at, now())
   where x.kind = l.kind and x.record_id = l.record_id;

  if cardinality(v_changed) > 0 then
    select string_agg(v_words->>f, ', ' order by array_position(array['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no',
             'person', 'finance_email', 'billing_address'], f))
      into v_t from unnest(v_changed) f;
    select x.name into v_who from public.team_members x where x.id = p_actor;
    v_detail := case p_mode when 'read' then 'Read from Bukku: ' when 'save' then 'Saved to Bukku: ' else 'Took Bukku''s details: ' end
                || v_t || ' · ' || coalesce(l.code, l.contact_id::text);
    v_who := case when p_mode = 'read' then 'Bukku' else coalesce(v_who, 'Bukku') end;
    if p_kind = 'entity' then
      perform public.bukku_file_entity(p_id, v_who, v_detail);
    else
      select x.name into v_name from public.clients x where x.id = p_id;
      insert into public.activity_log (actor, action, subject, detail) values (v_who, 'client.billing', v_name, v_detail);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'held', true, 'changed', to_jsonb(v_changed),
    'person_in', v_bc_set or nullif(btrim(coalesce(p_values->>'person', '')), '') is null);
end $$;
revoke all on function public.bukku_take(uuid, text, uuid, jsonb, text, text[], text) from public, anon, authenticated;
grant execute on function public.bukku_take(uuid, text, uuid, jsonb, text, text[], text) to service_role;

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
       the payment details approved last, the Creator ID in the Supplier ID
       field; the ID number goes only at Creator payment details View. */
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
      'our_id', cr.creator_code, 'field_id', b.field_supplier, 'type', 'supplier',
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

create or replace function public.client_entity_save(p_client uuid, p_entity uuid, p_values jsonb,
                                                     p_expected timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_name  text;
  v_vals  jsonb;
  v_was   public.billing_entities;
  v_held  public.billing_entities;
  v_moved text[] := '{}';
  v_at    timestamptz;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  if v_name is null or not exists (select 1 from public.client_entities ce
                                    where ce.client_id = p_client and ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- An entity Bukku holds is saved to Bukku, never here: a portal save would
  -- be read over by Bukku's (audit 2026-10-30).
  if exists (select 1 from public.bukku_links l where l.kind = 'entity' and l.record_id = p_entity and l.held_at is not null) then
    return jsonb_build_object('error', 'held');
  end if;
  select * into v_was from public.billing_entities e where e.id = p_entity for update;
  if p_expected is not null and v_was.updated_at is distinct from p_expected then
    return jsonb_build_object('error', 'stale', 'entity', public.billing_entity_json(p_entity, p_client));
  end if;
  v_vals := public.billing_entity_clean(p_values);
  if v_vals ? 'error' then return v_vals; end if;
  if v_vals ->> 'bill_contact_id' is not null
     and (v_vals ->> 'bill_contact_id')::uuid is distinct from v_was.bill_contact_id
     and not exists (
       select 1 from public.client_contacts k join public.client_entities ce on ce.client_id = k.client_id
        where k.id = (v_vals ->> 'bill_contact_id')::uuid and k.archived_at is null and ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'bad-contact');
  end if;
  if length(regexp_replace(coalesce(v_vals ->> 'company_no', ''), '\D', '', 'g')) > 0 then
    -- One BRN is checked and taken at a time across every client, so two
    -- presses at once never make it twice (audit 2026-11-04).
    perform pg_advisory_xact_lock(hashtextextended('entity-brn:' || regexp_replace(v_vals ->> 'company_no', '\D', '', 'g'), 0));
    select * into v_held from public.billing_entities e
     where e.id <> p_entity
       and regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
       and regexp_replace(coalesce(v_was.company_no, ''), '\D', '', 'g') <> regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
     order by e.created_at limit 1;
    if v_held.id is not null then
      return jsonb_build_object('error', 'brn-taken', 'entity',
                                jsonb_build_object('id', v_held.id, 'legal_name', v_held.legal_name));
    end if;
  end if;
  v_moved := array_remove(array[
    case when v_was.legal_name is distinct from v_vals ->> 'legal_name' then 'Registered Company Name' end,
    case when v_was.company_no is distinct from v_vals ->> 'company_no' then 'Business Registration No.' end,
    case when v_was.company_no_old is distinct from v_vals ->> 'company_no_old' then 'Old Registration No.' end,
    case when v_was.tin is distinct from v_vals ->> 'tin' then 'TIN' end,
    case when v_was.sst_no is distinct from v_vals ->> 'sst_no' then 'SST Registration No.' end,
    case when v_was.bill_contact_id is distinct from (v_vals ->> 'bill_contact_id')::uuid then 'Billing contact' end,
    case when v_was.finance_email is distinct from v_vals ->> 'finance_email' then 'Finance department email' end,
    case when v_was.billing_address is distinct from v_vals ->> 'billing_address' then 'Company billing address' end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true, 'updated_at', v_was.updated_at); end if;
  update public.billing_entities e
     set legal_name = v_vals ->> 'legal_name', company_no = v_vals ->> 'company_no',
         company_no_old = v_vals ->> 'company_no_old', tin = v_vals ->> 'tin', sst_no = v_vals ->> 'sst_no',
         bill_contact_id = (v_vals ->> 'bill_contact_id')::uuid, finance_email = v_vals ->> 'finance_email',
         billing_address = v_vals ->> 'billing_address', updated_at = clock_timestamp()
   where e.id = p_entity
  returning e.updated_at into v_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name, 'Billing entity edited: ' || array_to_string(v_moved, ', '));
  return jsonb_build_object('ok', true, 'updated_at', v_at);
end $$;
revoke all on function public.client_entity_save(uuid, uuid, jsonb, timestamptz) from public, anon;
grant execute on function public.client_entity_save(uuid, uuid, jsonb, timestamptz) to authenticated;

create or replace function public.quotation_submit(p_id uuid, p_reviewer uuid, p_company jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  rv public.team_members;
  v_fix jsonb;
  v_moved jsonb := '[]'::jsonb;
  v_k text;
  v_words text := '';
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is not null and q.returned_at is null then return jsonb_build_object('error', 'in-review'); end if;
  select * into rv from public.team_members where id = p_reviewer;
  if rv.id is null or not public.quote_sign_may_review(rv.id) or not public.quote_sign_member_sees(rv.id, q.client_id) then
    return jsonb_build_object('error', 'bad-reviewer');
  end if;
  if rv.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if p_company is not null and jsonb_typeof(p_company) = 'object' then
    v_fix := public.quote_sign_company((q.signed->'company') || p_company);
    if v_fix ? 'error' then return v_fix; end if;
    for v_k in select jsonb_object_keys(v_fix->'company') loop
      if (v_fix->'company'->>v_k) is distinct from (q.signed->'company'->>v_k) then
        v_moved := v_moved || jsonb_build_array(jsonb_build_object('field', v_k, 'from', q.signed->'company'->v_k,
                     'to', v_fix->'company'->v_k, 'by', me.name, 'at', now()));
        v_words := v_words || '; ' || case v_k when 'legal_name' then 'Registered Company Name' when 'company_no' then 'Business Registration No.'
                                          when 'company_no_old' then 'Old Registration No.' when 'tin' then 'TIN' when 'sst_no' then 'SST Registration No.'
                                          when 'billing_address' then 'Company billing address' when 'finance_email' then 'Finance department email' else v_k end || ': ' || coalesce(q.signed->'company'->>v_k, 'not set') || ' → ' || coalesce(v_fix->'company'->>v_k, 'not set');
      end if;
    end loop;
    if jsonb_array_length(v_moved) > 0 then
      q.signed := q.signed
        || jsonb_build_object('company_signed', coalesce(q.signed->'company_signed', q.signed->'company'))
        || jsonb_build_object('company', v_fix->'company')
        || jsonb_build_object('corrections', coalesce(q.signed->'corrections', '[]'::jsonb) || v_moved);
    end if;
  end if;
  update public.quotations
     set signed = q.signed, submitted_at = now(), submitted_by = me.name, reviewer_id = rv.id, reviewer_name = rv.name,
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · checked and submitted to ' || rv.name || case when v_words <> '' then ' ·' || substr(v_words, 2) else '' end);
  perform public.quote_sign_tell(array[rv.id], 'quote.review', 'Quotation to review · ' || q.brand,
    q.ref || ' · from ' || me.name, q.client_id, q.id::text || ':' || now()::text);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_submit(uuid, uuid, jsonb) from public, anon;
grant execute on function public.quotation_submit(uuid, uuid, jsonb) to authenticated;

create or replace function public.client_entity_delete(p_client uuid, p_entity uuid, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text;
  e      public.billing_entities;
begin
  if me.id is null or not public.allowed('clients.billing', 'manage') or not public.client_seen(p_client, 'manage') then
    return jsonb_build_object('error', 'denied');
  end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  select * into e from public.billing_entities x where x.id = p_entity for update;
  if v_name is null or e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.client_entities ce where ce.entity_id = p_entity and ce.client_id = p_client) then
    return jsonb_build_object('error', 'not-removed');
  end if;
  if exists (select 1 from public.client_entities ce where ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'bills-others');
  end if;
  if e.orphan_of is distinct from p_client then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.bukku_links l where l.kind = 'entity' and l.record_id = p_entity) then
    return jsonb_build_object('error', 'bukku');
  end if;
  if exists (select 1 from public.client_documents d where d.bill_to ->> 'entity_id' = p_entity::text) then
    return jsonb_build_object('error', 'on-letter');
  end if;
  if upper(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'))
     <> upper(regexp_replace(btrim(coalesce(e.legal_name, '')), '\s+', ' ', 'g')) then
    return jsonb_build_object('error', 'bad-name');
  end if;
  delete from public.bukku_links_gone g where g.kind = 'entity' and g.record_id = p_entity;
  delete from public.billing_entities x where x.id = p_entity;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name, 'Billing entity deleted: ' || coalesce(e.legal_name, 'Registered Company Name not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_entity_delete(uuid, uuid, text) from public, anon;
grant execute on function public.client_entity_delete(uuid, uuid, text) to authenticated;

create or replace function public.clients_entity_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_ent uuid;
  v_own boolean := false;
  v_was text := coalesce(current_setting('adspace.entity_sync', true), '');
begin
  if v_was = 'on' then return null; end if;
  if (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.bill_contact_id,
      new.finance_email, new.billing_address)
     is not distinct from
     (old.legal_name, old.company_no, old.company_no_old, old.tin, old.sst_no, old.bill_contact_id,
      old.finance_email, old.billing_address) then
    return null;
  end if;
  select ce.entity_id into v_ent from public.client_entities ce where ce.client_id = new.id and ce.is_main;
  -- A BRN another billing entity holds is refused here too, the Billing
  -- sheet's own write, Use details and a signed quotation's review alike,
  -- one BRN checked at a time (audit 2026-11-04, 2).
  if regexp_replace(coalesce(new.company_no, ''), '\D', '', 'g') <> ''
     and regexp_replace(coalesce(new.company_no, ''), '\D', '', 'g') is distinct from regexp_replace(coalesce(old.company_no, ''), '\D', '', 'g') then
    perform pg_advisory_xact_lock(hashtextextended('entity-brn:' || regexp_replace(new.company_no, '\D', '', 'g'), 0));
    if exists (select 1 from public.billing_entities e
                where e.id is distinct from v_ent
                  and regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = regexp_replace(new.company_no, '\D', '', 'g')) then
      raise exception 'An entity with this Business Registration No. already exists. Add that entity instead.'
        using errcode = '23505', hint = 'brn-taken';
    end if;
  end if;
  if v_ent is null then
    if nullif(btrim(coalesce(new.legal_name, '') || coalesce(new.company_no, '') || coalesce(new.company_no_old, '') ||
                    coalesce(new.tin, '') || coalesce(new.sst_no, '') || coalesce(new.finance_email, '') ||
                    coalesce(new.billing_address, '')), '') is null and new.bill_contact_id is null then
      return null;
    end if;
    insert into public.billing_entities (legal_name, company_no, company_no_old, tin, sst_no, bill_contact_id,
                                         finance_email, billing_address, created_by)
    values (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.bill_contact_id,
            new.finance_email, new.billing_address, (public.ops_me()).id)
    returning id into v_ent;
    insert into public.client_entities (client_id, entity_id, is_main, added_by)
    values (new.id, v_ent, true, (public.ops_me()).id);
    return null;
  end if;
  perform set_config('adspace.entity_sync', 'on', true);
  -- A billing contact chosen on a brand's own sheet is that brand's own
  -- choice where the entity bills other brands too, and the entity's
  -- shared one where it bills this brand alone (2026-10-31).
  if new.bill_contact_id is distinct from old.bill_contact_id then
    v_own := exists (select 1 from public.client_entities ce where ce.entity_id = v_ent and ce.client_id <> new.id);
    update public.client_entities ce set bill_contact_id = case when v_own then new.bill_contact_id end
     where ce.client_id = new.id and ce.entity_id = v_ent;
  end if;
  -- Only what this write changed: another brand's choice (its billing
  -- contact) is never overwritten by a brand that never held it.
  update public.billing_entities e
     set legal_name = case when new.legal_name is distinct from old.legal_name then new.legal_name else e.legal_name end,
         company_no = case when new.company_no is distinct from old.company_no then new.company_no else e.company_no end,
         company_no_old = case when new.company_no_old is distinct from old.company_no_old then new.company_no_old else e.company_no_old end,
         tin = case when new.tin is distinct from old.tin then new.tin else e.tin end,
         sst_no = case when new.sst_no is distinct from old.sst_no then new.sst_no else e.sst_no end,
         bill_contact_id = case when new.bill_contact_id is distinct from old.bill_contact_id and not v_own
                                then new.bill_contact_id else e.bill_contact_id end,
         finance_email = case when new.finance_email is distinct from old.finance_email then new.finance_email else e.finance_email end,
         billing_address = case when new.billing_address is distinct from old.billing_address then new.billing_address else e.billing_address end,
         updated_at = now()
   where e.id = v_ent;
  -- `billing_entity_mirror` carries it to the other brands it is the main of.
  perform set_config('adspace.entity_sync', v_was, true);
  return null;
end $$;
revoke all on function public.clients_entity_sync() from public, anon, authenticated;

create or replace function public.supplier_save(p_id uuid, p_values jsonb, p_form uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  pay   boolean := public.ops_granted('suppliers.pay', 'work');
  v     jsonb;
  v_code text := upper(regexp_replace(coalesce(p_values->>'code', ''), '\s+', '', 'g'));
  moved text[] := '{}';
  k     text;
  word  constant jsonb := '{"code":"Supplier ID","name":"Name","kind":"Type","brn":"BRN","tin":"TIN","sst_no":"SST Registration No.",
    "phone":"Office / mobile","address":"Billing address","contact_name":"Legal name","designation":"Designation",
    "email":"Email","mobile":"Mobile / WhatsApp","payment_term":"Payment term","currency":"Currency",
    "finance_email":"Finance email","nric":"NRIC","payee_name":"Payee name","bank_name":"Bank",
    "bank_account":"Account number","swift":"SWIFT code","bank_address":"Bank address"}';
  secret constant text[] := array['nric', 'payee_name', 'bank_name', 'bank_account', 'swift', 'bank_address'];
  was   jsonb;
  repend boolean := false;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_code !~ '^[A-Z0-9]{2,12}$' then return jsonb_build_object('error', 'bad-code'); end if;
  if exists (select 1 from public.suppliers x where upper(x.code) = v_code and x.id <> p_id) then
    return jsonb_build_object('error', 'code-taken', 'name', (select x.name from public.suppliers x where upper(x.code) = v_code));
  end if;
  v := public.supplier_values_check(coalesce(p_values, '{}'::jsonb), pay);
  if v ? 'error' then return v; end if;
  v := v || jsonb_build_object('code', v_code);
  was := to_jsonb(s);
  for k in select jsonb_object_keys(v) loop
    if (was->>k) is distinct from (v->>k) then
      moved := moved || case when k = any (secret) then (word->>k)
        else (word->>k) || ': ' || coalesce(was->>k, 'not set') || ' → ' || coalesce(v->>k, 'not set') end;
    end if;
  end loop;
  /* A bank account changed on an approved supplier is approved again. */
  repend := pay and s.status = 'active' and s.bank_account is not null and (
    (v->>'payee_name') is distinct from s.payee_name or (v->>'bank_name') is distinct from s.bank_name
    or (v->>'bank_account') is distinct from s.bank_account);
  update public.suppliers x set
    code = v_code, name = v->>'name', kind = v->>'kind', brn = v->>'brn', tin = v->>'tin', sst_no = v->>'sst_no',
    phone = v->>'phone', address = v->>'address', contact_name = v->>'contact_name', designation = v->>'designation',
    email = v->>'email', mobile = v->>'mobile', payment_term = v->>'payment_term', currency = v->>'currency',
    finance_email = v->>'finance_email',
    nric = case when pay then v->>'nric' else x.nric end,
    payee_name = case when pay then v->>'payee_name' else x.payee_name end,
    bank_name = case when pay then v->>'bank_name' else x.bank_name end,
    bank_account = case when pay then v->>'bank_account' else x.bank_account end,
    swift = case when pay then v->>'swift' else x.swift end,
    bank_address = case when pay then v->>'bank_address' else x.bank_address end,
    status = case when repend then 'pending' else x.status end,
    updated_at = now()
   where x.id = p_id;
  if p_form is not null then
    update public.supplier_forms f set used_at = coalesce(f.used_at, now()), used_by = coalesce(f.used_by, me.id)
     where f.id = p_form and f.supplier_id = p_id and f.submitted_at is not null;
  end if;
  if array_length(moved, 1) is not null then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'supplier.edited', v->>'name', v_code || ' · ' || array_to_string(moved, ' · ') ||
            case when p_form is not null then ' · from the details form' else '' end ||
            case when repend then ' · Active → Pending until approved again' else '' end);
  end if;
  return jsonb_build_object('ok', true, 'repending', repend, 'supplier',
    public.supplier_json((select x from public.suppliers x where x.id = p_id), public.ops_granted('suppliers.pay', 'view')));
end $$;
revoke all on function public.supplier_save(uuid, jsonb, uuid) from public, anon;
grant execute on function public.supplier_save(uuid, jsonb, uuid) to authenticated;

-- END OF OFFICIAL TERMS CAPITALISED ------------------------------------------


select public.functions_tidy();
