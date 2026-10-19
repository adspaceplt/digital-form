-- ===========================================================================
-- BUKKU AS BUKKU HOLDS IT — the billing person's salutation goes to Bukku,
-- and a contact may be linked without anything sent. 2026-10-19. Safe to
-- run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/bukkusql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-19: "the bukku address follow Address
-- line 1, address line 2, postal code, city, state, country … also can
-- allow link or sync without changing info"; "your salutation didnt follow
-- over")
--   1. bukku_prepare answers the client's billing contact's salutation
--      (`salutation`) beside the name; bukku-sync puts it before the name.
--   2. bukku_link_only(p_kind, p_id, p_contact, p_code) files the link as
--      bukku_linked does, the record's details as they stand marked sent,
--      and files "Linked to Bukku, nothing sent" (Link only: Bukku's
--      contact is not changed).
--   The address is read into Bukku's parts by bukku-sync itself.
--
-- ORDER
--   This file, then bukku-sync, then the pages (the sheet's Link only asks
--   the function's `link`).
--
-- ROLLBACK
--   Run bukku_prepare from BUKKU CONTACTS again; bukku_link_only, unused
--   by then, stays harmless.
-- ===========================================================================

create or replace function public.bukku_prepare(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients; s public.suppliers; ct public.client_contacts;
  l public.bukku_links; b public.bukku_settings;
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
    if coalesce(btrim(c.legal_name), '') = '' then v_missing := v_missing || 'Registered name'::text; end if;
    if coalesce(btrim(c.client_code), '') = '' then v_missing := v_missing || 'Client ID'::text; end if;
    if array_length(v_missing, 1) > 0 then return jsonb_build_object('error', 'incomplete', 'missing', to_jsonb(v_missing)); end if;
    select * into l from public.bukku_links x where x.kind = 'client' and x.record_id = c.id;
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
      'currency', case when c.market = 'SG' then 'SGD' else 'MYR' end,
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
  end if;
  return jsonb_build_object('error', 'bad-kind');
end $$;
revoke all on function public.bukku_prepare(text, uuid) from public, anon;
grant execute on function public.bukku_prepare(text, uuid) to authenticated;

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

-- END OF BUKKU AS BUKKU HOLDS IT ---------------------------------------------

select public.functions_tidy();
