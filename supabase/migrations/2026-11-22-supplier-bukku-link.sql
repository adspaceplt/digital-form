-- ===========================================================================
-- A SUPPLIER LINKED TO BUKKU (2026-11-22)
-- ===========================================================================
-- WHY: the user, 2026-11-22, with a supplier's Send to Bukku sheet: "Link
-- clients, Link creators, But no link suppliers?". A supplier already in
-- Bukku could only be linked by overwriting Bukku with the portal's
-- details, and its bills (matched on its linked contact) read No bills.
-- until it was. A supplier now links as a client does: Link to Bukku links
-- the contact chosen as Bukku holds it, nothing sent; the linked band reads
-- Bukku whenever the record opens, and where the two differ, field by
-- field, offers Send to Bukku and Use Bukku's.
--
-- WHAT IT CHANGES
--   * `bukku_portal(p_kind, p_id)`: answers a supplier's details as Bukku
--     reads them (name, BRN for a company, TIN, SST no., finance email
--     else email, address, person in charge) with `fields`, the details
--     compared: never an NRIC, so an individual's registration no. is
--     neither read from Bukku nor written over (Sensitive details).
--   * `bukku_read_may(p_kind, p_id, p_level)`: takes `supplier`, at
--     Suppliers View to read and Work to use Bukku's (`bukku_may`). Every
--     refusal before it is kept.
--   * `bukku_take(...)`: takes `supplier`. Unlike a client's billing, a
--     supplier's details stay the portal's: a read never writes them (it
--     says what differs, the link held only while nothing does); Use
--     Bukku's (`hold`) writes the differing fields alone into the supplier,
--     filed `supplier.edited` (Took Bukku's details: … · code). `save` is
--     refused for a supplier (`bad-request`).
--   * `bukku_held_links()` is unchanged: the nightly run reads clients and
--     entities alone, so a supplier is read as its record opens.
--
-- ORDER: this file, then the function (`bukku-sync`, which asks `read` and
-- `hold` for a supplier), then the pages. A page from before never asks a
-- supplier's read; the function from before refuses it `bad-request`.
-- Nothing changes in Bukku.
-- Rollback: run `2026-10-30-billing-from-bukku.sql`'s `bukku_portal` and
-- `bukku_read_may`, then OFFICIAL TERMS CAPITALISED's `bukku_take` again.
-- Safe to run twice.
-- ===========================================================================

create or replace function public.bukku_portal(p_kind text, p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.clients; e public.billing_entities; k public.client_contacts; v_market text;
  s public.suppliers; v_company boolean;
begin
  if p_kind = 'client' then
    select * into c from public.clients x where x.id = p_id;
    if c.id is null then return null; end if;
    select * into k from public.client_contacts x where x.id = c.bill_contact_id and x.archived_at is null;
    if k.id is null then
      select * into k from public.client_contacts x where x.client_id = c.id and x.is_primary and x.archived_at is null limit 1;
    end if;
    return jsonb_build_object('legal_name', c.legal_name, 'company_no', c.company_no, 'company_no_old', c.company_no_old,
      'tin', c.tin, 'sst_no', c.sst_no, 'finance_email', c.finance_email, 'billing_address', c.billing_address,
      'person', nullif(public.contact_named(k.salutation, k.name), ''),
      'country', case when c.market = 'SG' then 'SG' else 'MY' end);
  elsif p_kind = 'entity' then
    select * into e from public.billing_entities x where x.id = p_id;
    if e.id is null then return null; end if;
    k := public.entity_contact(e.id);
    select x.market into v_market from public.clients x where x.id = public.entity_home_client(e.id);
    return jsonb_build_object('legal_name', e.legal_name, 'company_no', e.company_no, 'company_no_old', e.company_no_old,
      'tin', e.tin, 'sst_no', e.sst_no, 'finance_email', e.finance_email, 'billing_address', e.billing_address,
      'person', nullif(public.contact_named(k.salutation, k.name), ''),
      'country', case when v_market = 'SG' then 'SG' else 'MY' end);
  elsif p_kind = 'supplier' then
    /* A supplier (2026-11-22): its details as Bukku reads them, and the
       fields compared. An individual's registration no. is an NRIC: never
       compared, read or taken. */
    select * into s from public.suppliers x where x.id = p_id;
    if s.id is null then return null; end if;
    v_company := coalesce(s.kind, 'company') = 'company';
    return jsonb_build_object('legal_name', s.name, 'company_no', case when v_company then s.brn end,
      'tin', s.tin, 'sst_no', s.sst_no, 'finance_email', coalesce(nullif(btrim(coalesce(s.finance_email, '')), ''), s.email),
      'billing_address', s.address,
      'person', nullif(btrim(coalesce(s.contact_name, case when not v_company then s.name end, '')), ''),
      'country', case when s.currency = 'SGD' then 'SG' else 'MY' end,
      'fields', case when v_company
                     then '["legal_name", "company_no", "tin", "sst_no", "person", "finance_email", "billing_address"]'::jsonb
                     else '["legal_name", "tin", "sst_no", "person", "finance_email", "billing_address"]'::jsonb end);
  end if;
  return null;
end $$;
revoke all on function public.bukku_portal(text, uuid) from public, anon, authenticated;

create or replace function public.bukku_read_may(p_kind text, p_id uuid, p_level text default 'view')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.bukku_links; me public.team_members := public.ops_me();
begin
  if p_kind not in ('client', 'entity', 'supplier') or p_level not in ('view', 'work')
     or not public.bukku_may(p_kind, p_id, p_level) then
    return jsonb_build_object('error', 'denied');
  end if;
  if public.bukku_record_name(p_kind, p_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  l := public.bukku_link_row(p_kind, p_id);
  if l.contact_id is null then return jsonb_build_object('ok', true, 'linked', false); end if;
  return jsonb_build_object('ok', true, 'linked', true, 'me', me.id, 'contact_id', l.contact_id, 'code', l.code,
    'held', l.held_at is not null, 'read_at', l.read_at, 'read_hash', l.read_hash,
    'portal', public.bukku_portal(p_kind, p_id));
end $$;
revoke all on function public.bukku_read_may(text, uuid, text) from public, anon;
grant execute on function public.bukku_read_may(text, uuid, text) to authenticated;

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
  s public.suppliers; v_company boolean; v_fields text[];
  v_sw constant jsonb := '{"legal_name": "Name", "company_no": "BRN", "tin": "TIN",
    "sst_no": "SST Registration No.", "person": "Person in charge", "finance_email": "Finance email",
    "billing_address": "Billing address"}';
begin
  if p_kind not in ('client', 'entity', 'supplier') or p_mode not in ('read', 'hold', 'save')
     or (p_kind = 'supplier' and p_mode = 'save')
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
  /* A supplier (2026-11-22): its details stay the portal's. A read writes
     nothing and says what differs, the link held only while nothing does;
     Use Bukku's writes the differing fields alone, never an NRIC or the
     bank details. */
  if p_kind = 'supplier' then
    select * into s from public.suppliers x where x.id = p_id;
    v_company := coalesce(s.kind, 'company') = 'company';
    select array_agg(f) into v_fields from jsonb_array_elements_text(coalesce(p->'fields', '[]'::jsonb)) f;
    select array_agg(f) into v_changed from unnest(v_changed) f where f = any(coalesce(v_fields, '{}'));
    v_changed := coalesce(v_changed, '{}');
    if p_mode = 'read' and cardinality(v_changed) > 0 then
      return jsonb_build_object('ok', true, 'held', false, 'differs', to_jsonb(v_changed));
    end if;
    if cardinality(v_changed) > 0 then
      update public.suppliers x
         set name = case when 'legal_name' = any(v_changed)
                         then coalesce(public.bukku_name_case(p_values->>'legal_name', v_company), x.name) else x.name end,
             brn = case when v_company and 'company_no' = any(v_changed)
                        then nullif(regexp_replace(coalesce(p_values->>'company_no', ''), '[^0-9A-Za-z]', '', 'g'), '') else x.brn end,
             tin = case when 'tin' = any(v_changed) then nullif(btrim(coalesce(p_values->>'tin', '')), '') else x.tin end,
             sst_no = case when 'sst_no' = any(v_changed) then nullif(btrim(coalesce(p_values->>'sst_no', '')), '') else x.sst_no end,
             finance_email = case when 'finance_email' = any(v_changed)
                                  then nullif(lower(btrim(coalesce(p_values->>'finance_email', ''))), '') else x.finance_email end,
             address = case when 'billing_address' = any(v_changed) then nullif(btrim(coalesce(p_values->>'billing_address', '')), '') else x.address end,
             contact_name = case when 'person' = any(v_changed)
                                 then nullif(public.bukku_name_case(p_values->>'person', false), '') else x.contact_name end,
             updated_at = clock_timestamp()
       where x.id = p_id;
      select string_agg(v_sw->>f, ', ' order by array_position(array['legal_name', 'company_no', 'tin', 'sst_no',
               'person', 'finance_email', 'billing_address'], f))
        into v_t from unnest(v_changed) f;
      select x.name into v_who from public.team_members x where x.id = p_actor;
      select coalesce(x.name, x.code) into v_name from public.suppliers x where x.id = p_id;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_who, 'Bukku'), 'supplier.edited', v_name,
              coalesce(s.code || ' · ', '') || 'Took Bukku''s details: ' || v_t || ' · ' || coalesce(l.code, l.contact_id::text));
    end if;
    update public.bukku_links x set held_at = coalesce(x.held_at, now())
     where x.kind = l.kind and x.record_id = l.record_id;
    return jsonb_build_object('ok', true, 'held', true, 'changed', to_jsonb(v_changed), 'person_in', true);
  end if;
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

-- END OF A SUPPLIER LINKED TO BUKKU ------------------------------------------
select public.functions_tidy();
