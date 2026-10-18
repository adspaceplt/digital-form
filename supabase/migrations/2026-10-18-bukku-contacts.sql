-- ===========================================================================
-- BUKKU CONTACTS — a client's billing and a supplier's details sent to Bukku
-- by hand, one contact each, linked once (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18, Phase 1 approved): Bukku issues the quotations,
-- invoices and purchase orders, and its contacts were typed again by hand.
--
-- WHAT IT CHANGES
--   * `bukku_settings`: one row, which Bukku custom contact field holds the
--     Client ID and which the Supplier ID (`field_client`,
--     `field_supplier`, Bukku's own ids). Read by `bukku_config()` (Clients
--     Billing or Suppliers at Work, or Business settings); set by
--     `bukku_config_set(p_client, p_supplier)` (`team.settings`), filed
--     `team.changed` under Bukku. RLS on, no policy, no grant.
--   * `bukku_links`: a client or a supplier and the Bukku contact it is
--     linked to (`contact_id`), with who sent it last and when, and the
--     print of the details as sent (`sent_hash`, `bukku_print`), so the
--     record says Changed since. RLS on, no policy, no grant.
--   * `bukku_prepare(p_kind, p_id)`: what a send needs, read as the caller:
--     a client at Clients: Billing Work in scope (its registered name, BRN,
--     old BRN, TIN, SST no., billing address, finance email, market and
--     Client ID, the billing contact, else the main contact); a supplier at
--     Suppliers Work (its details, the NRIC only at `suppliers.pay` View).
--     A company's name is in capitals, a person's each word's first letter
--     (the user, 2026-10-18). A supplier linked to a client answers that
--     client's contact (one contact, both types). Refuses `incomplete` with
--     what is missing.
--   * `bukku_link_get(p_kind, p_id)`: the link and its last send, at View,
--     and whether the details changed since (`changed`).
--   * `bukku_linked(p_kind, p_id, p_contact, p_code)`: files a
--     send made by `bukku-sync` as the caller (the same checks as prepare),
--     linking a supplier's client to the same contact; filed
--     `client.edited` / `supplier.edited` · Sent to Bukku.
--
-- ORDER: this file, then `bukku-sync`, then the pages. Safe to run twice.
-- Rollback: drop the functions and the two tables; the pages from before.
-- ===========================================================================

create table if not exists public.bukku_settings (
  id             int primary key default 1 check (id = 1),
  field_client   bigint,
  field_supplier bigint,
  set_by         uuid references public.team_members(id) on delete set null,
  set_at         timestamptz not null default now()
);
alter table public.bukku_settings enable row level security;
revoke all on table public.bukku_settings from public, anon, authenticated;

create table if not exists public.bukku_links (
  kind       text not null check (kind in ('client', 'supplier')),
  record_id  uuid not null,
  contact_id bigint not null,
  code       text,
  sent_at    timestamptz not null default now(),
  sent_by    uuid references public.team_members(id) on delete set null,
  sent_hash  text,
  primary key (kind, record_id)
);
alter table public.bukku_links enable row level security;
revoke all on table public.bukku_links from public, anon, authenticated;

/* A company's name in capitals; a person's with each word's first letter
   capital (Lee Kim Kee), the rest as typed in lower case. */
create or replace function public.bukku_name_case(p_name text, p_company boolean)
returns text language sql immutable set search_path = public as $$
  select case when p_name is null or btrim(p_name) = '' then null
              when p_company then upper(regexp_replace(btrim(p_name), '\s+', ' ', 'g'))
              else initcap(lower(regexp_replace(btrim(p_name), '\s+', ' ', 'g'))) end
$$;
revoke all on function public.bukku_name_case(text, boolean) from public, anon, authenticated;

create or replace function public.bukku_may(p_kind text, p_id uuid, p_level text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return false; end if;
  if p_kind = 'client' then
    return public.allowed('clients.billing', p_level) and public.client_seen(p_id, 'view');
  elsif p_kind = 'supplier' then
    return public.allowed('suppliers', p_level);
  end if;
  return false;
end $$;
revoke all on function public.bukku_may(text, uuid, text) from public, anon, authenticated;

create or replace function public.bukku_config()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b public.bukku_settings;
begin
  if (public.ops_me()).id is null or not (public.allowed('clients.billing', 'work') or public.allowed('suppliers', 'work')
      or public.ops_granted('team.settings', 'work')) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into b from public.bukku_settings where id = 1;
  return jsonb_build_object('ok', true, 'field_client', b.field_client, 'field_supplier', b.field_supplier, 'set_at', b.set_at);
end $$;
revoke all on function public.bukku_config() from public, anon;
grant execute on function public.bukku_config() to authenticated;

create or replace function public.bukku_config_set(p_client bigint, p_supplier bigint)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); b public.bukku_settings;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if (p_client is not null and p_client <= 0) or (p_supplier is not null and p_supplier <= 0) then
    return jsonb_build_object('error', 'bad-value');
  end if;
  select * into b from public.bukku_settings where id = 1;
  if b.id is not null and b.field_client is not distinct from p_client and b.field_supplier is not distinct from p_supplier then
    return jsonb_build_object('ok', true);
  end if;
  insert into public.bukku_settings (id, field_client, field_supplier, set_by, set_at)
  values (1, p_client, p_supplier, me.id, now())
  on conflict (id) do update set field_client = excluded.field_client, field_supplier = excluded.field_supplier,
    set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Bukku', 'Client ID field: ' || coalesce(b.field_client::text, 'not set') || ' → ' || coalesce(p_client::text, 'not set')
    || '; Supplier ID field: ' || coalesce(b.field_supplier::text, 'not set') || ' → ' || coalesce(p_supplier::text, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_config_set(bigint, bigint) from public, anon;
grant execute on function public.bukku_config_set(bigint, bigint) to authenticated;

/* The print of what a send carries, so a change since is seen without
   asking Bukku. */
create or replace function public.bukku_print(p_kind text, p_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v text;
begin
  if p_kind = 'client' then
    select concat_ws('|', c.legal_name, c.company_no, c.company_no_old, c.tin, c.sst_no, c.billing_address,
             c.finance_email, c.client_code, c.market, ct.name, ct.email, ct.phone)
      into v
      from public.clients c
      left join public.client_contacts ct on ct.id = coalesce(c.bill_contact_id,
        (select y.id from public.client_contacts y where y.client_id = c.id and y.is_primary and y.archived_at is null limit 1))
     where c.id = p_id;
  else
    select concat_ws('|', s.name, s.kind, s.brn, s.tin, s.sst_no, s.address, s.email, s.finance_email,
             s.contact_name, s.mobile, s.phone, s.currency, s.code, s.payment_term)
      into v from public.suppliers s where s.id = p_id;
  end if;
  return case when v is null then null else md5(v) end;
end $$;
revoke all on function public.bukku_print(text, uuid) from public, anon, authenticated;

create or replace function public.bukku_link_get(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare l public.bukku_links; v_by text;
begin
  if not public.bukku_may(p_kind, p_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into l from public.bukku_links x where x.kind = p_kind and x.record_id = p_id;
  if l.contact_id is null then return jsonb_build_object('ok', true); end if;
  select t.name into v_by from public.team_members t where t.id = l.sent_by;
  return jsonb_build_object('ok', true, 'contact_id', l.contact_id, 'code', l.code, 'sent_at', l.sent_at,
    'sent_by', v_by, 'changed', l.sent_hash is distinct from public.bukku_print(p_kind, p_id));
end $$;
revoke all on function public.bukku_link_get(text, uuid) from public, anon;
grant execute on function public.bukku_link_get(text, uuid) to authenticated;

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

-- END OF BUKKU CONTACTS -----------------------------------------------------
select public.functions_tidy();
