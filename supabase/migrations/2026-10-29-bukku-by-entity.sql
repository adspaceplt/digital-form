-- ===========================================================================
-- BUKKU BY ENTITY — each billing entity is its own Bukku contact, and a
-- client's unpaid invoices and reminders cover every company billing it
-- (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "When four different entities are added in,
-- the unpaid invoices overdue are not shown. It only shows the primary";
-- "The linking with bukku entities mainly for consolidation of one brand
-- into different of their company entities"): a Bukku contact is a company.
-- A brand billed by four companies has four Bukku contacts, and its Billing
-- read the main one's invoices alone.
--
-- WHAT CHANGED
--   * `bukku_links` takes the kind `entity`: a billing entity other than a
--     brand's main is linked to its own Bukku contact (Send to Bukku, Link
--     only, Unlink and its Undo, at Clients: Billing Work on a client it
--     bills that the colleague sees). A brand and its main entity are one
--     company, so they may hold one contact; any other two records may not
--     (`bukku_contact_taken`). A record with no link of its own reads its
--     company's (`bukku_shared`: a brand its main entity's, an entity the
--     brand's it is the main of), said as Linked through.
--   * `bukku_prepare('entity', …)` sends the entity's registered name,
--     numbers, address, finance email and billing contact (else its brand's
--     main contact), with the Client ID and market of the brand it is filed
--     under (`entity_home_client`: the brand it is the main of, else the
--     first to add it). A link is filed on every brand it bills
--     (`client.billing`, the company named).
--   * `invoice_scope()` names, for each Bukku contact, every client its
--     company bills (`clients`) and the company (`company`), and reads the
--     contact's own recipient: the entity's billing contact and finance
--     email (`invoice_recipient_for`, `invoice_entity_recipient`).
--     `invoice_email_begin` greets that recipient.
--
-- ORDER: this file in the SQL Editor (it changes a check constraint and
-- `bukku_unlink`, which the connector holds), then bukku-sync, then the
-- pages. An old page reads as before: every answer only gains keys.
-- Safe to run twice.
--
-- ROLLBACK: remove the entity links (delete from bukku_links where kind =
-- 'entity'), put the check back to client and supplier, and run BUKKU
-- CONTACTS', BUKKU UNLINK's and OVERDUE INVOICE REMINDERS' functions again.
-- ===========================================================================

-- BUKKU BY ENTITY -----------------------------------------------------------

alter table public.bukku_links drop constraint if exists bukku_links_kind_check;
alter table public.bukku_links add constraint bukku_links_kind_check
  check (kind in ('client', 'supplier', 'entity'));

/* The brand an entity is filed and named under: the one whose main entity
   it is, else the first to add it. Internal. */
create or replace function public.entity_home_client(p_entity uuid)
returns uuid
language sql stable security definer set search_path = public as $$
  select ce.client_id from public.client_entities ce
   where ce.entity_id = p_entity
   order by ce.is_main desc, ce.added_at, ce.client_id
   limit 1
$$;
revoke all on function public.entity_home_client(uuid) from public, anon, authenticated;

/* A brand's main entity. Internal. */
create or replace function public.client_main_entity(p_client uuid)
returns uuid
language sql stable security definer set search_path = public as $$
  select ce.entity_id from public.client_entities ce where ce.client_id = p_client and ce.is_main limit 1
$$;
revoke all on function public.client_main_entity(uuid) from public, anon, authenticated;

/* Who an entity's mail is for: its billing contact, else its brand's live
   main contact. Internal. */
create or replace function public.entity_contact(p_entity uuid)
returns public.client_contacts
language sql stable security definer set search_path = public as $$
  select k.* from public.billing_entities e
    join public.client_contacts k on k.archived_at is null
     and (k.id = e.bill_contact_id or (k.client_id = public.entity_home_client(e.id) and k.is_primary))
   where e.id = p_entity
   order by (k.id = e.bill_contact_id) desc
   limit 1
$$;
revoke all on function public.entity_contact(uuid) from public, anon, authenticated;

create or replace function public.bukku_may(p_kind text, p_id uuid, p_level text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return false; end if;
  if p_kind = 'client' then
    return public.allowed('clients.billing', p_level) and public.client_seen(p_id, 'view');
  elsif p_kind = 'supplier' then
    return public.allowed('suppliers', p_level);
  elsif p_kind = 'entity' then
    return public.allowed('clients.billing', p_level)
       and exists (select 1 from public.client_entities ce
                    where ce.entity_id = p_id and public.client_seen(ce.client_id, 'view'));
  end if;
  return false;
end $$;
revoke all on function public.bukku_may(text, uuid, text) from public, anon, authenticated;

create or replace function public.bukku_record_name(p_kind text, p_id uuid)
returns text
language sql stable security definer set search_path = public as $$
  select case when p_kind = 'client'
              then (select x.name from public.clients x where x.id = p_id)
              when p_kind = 'entity'
              then (select coalesce(nullif(btrim(x.legal_name), ''), 'Billing entity') from public.billing_entities x where x.id = p_id)
              else (select coalesce(x.name, x.code) from public.suppliers x where x.id = p_id) end
$$;
revoke all on function public.bukku_record_name(text, uuid) from public, anon, authenticated;

/* An entity's Bukku step filed on every brand it bills. Internal. */
create or replace function public.bukku_file_entity(p_entity uuid, p_actor text, p_detail text)
returns void
language sql volatile security definer set search_path = public as $$
  insert into public.activity_log (actor, action, subject, detail)
  select p_actor, 'client.billing', c.name,
         public.bukku_record_name('entity', p_entity) || ' · ' || p_detail
    from public.client_entities ce join public.clients c on c.id = ce.client_id
   where ce.entity_id = p_entity
$$;
revoke all on function public.bukku_file_entity(uuid, text, text) from public, anon, authenticated;

create or replace function public.bukku_print(p_kind text, p_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v text; v_k public.client_contacts;
begin
  if p_kind = 'client' then
    select concat_ws('|', c.legal_name, c.company_no, c.company_no_old, c.tin, c.sst_no, c.billing_address,
             c.finance_email, c.client_code, c.market, ct.name, ct.email, ct.phone)
      into v
      from public.clients c
      left join public.client_contacts ct on ct.id = coalesce(c.bill_contact_id,
        (select y.id from public.client_contacts y where y.client_id = c.id and y.is_primary and y.archived_at is null limit 1))
     where c.id = p_id;
  elsif p_kind = 'entity' then
    v_k := public.entity_contact(p_id);
    select concat_ws('|', e.legal_name, e.company_no, e.company_no_old, e.tin, e.sst_no, e.billing_address,
             e.finance_email, c.client_code, c.market, v_k.name, v_k.email, v_k.phone)
      into v
      from public.billing_entities e
      left join public.clients c on c.id = public.entity_home_client(e.id)
     where e.id = p_id;
  else
    select concat_ws('|', s.name, s.kind, s.brn, s.tin, s.sst_no, s.address, s.email, s.finance_email,
             s.contact_name, s.mobile, s.phone, s.currency, s.code, s.payment_term)
      into v from public.suppliers s where s.id = p_id;
  end if;
  return case when v is null then null else md5(v) end;
end $$;
revoke all on function public.bukku_print(text, uuid) from public, anon, authenticated;

/* The link a record reads through while it holds none of its own: a brand
   its main entity's, an entity the brand's it is the main of. One company,
   one Bukku contact. Internal. */
create or replace function public.bukku_shared(p_kind text, p_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when p_kind = 'client' then
      (select jsonb_build_object('contact_id', l.contact_id, 'code', l.code, 'via', public.bukku_record_name('entity', l.record_id))
         from public.bukku_links l where l.kind = 'entity' and l.record_id = public.client_main_entity(p_id))
    when p_kind = 'entity' then
      (select jsonb_build_object('contact_id', l.contact_id, 'code', l.code, 'via', c.name)
         from public.client_entities ce
         join public.bukku_links l on l.kind = 'client' and l.record_id = ce.client_id
         join public.clients c on c.id = ce.client_id
        where ce.entity_id = p_id and ce.is_main
        order by c.name limit 1)
  end
$$;
revoke all on function public.bukku_shared(text, uuid) from public, anon, authenticated;

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
                and exists (select 1 from public.suppliers x where x.id = l.record_id and x.client_id = p_id))
       and not (p_kind = 'client' and l.kind = 'entity' and l.record_id = public.client_main_entity(p_id))
       and not (p_kind = 'entity' and l.kind = 'client' and public.client_main_entity(l.record_id) = p_id))
$$;
revoke all on function public.bukku_contact_taken(text, uuid, bigint) from public, anon, authenticated;

create or replace function public.bukku_link_get(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare l public.bukku_links; v_by text; v_sh jsonb;
begin
  if not public.bukku_may(p_kind, p_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into l from public.bukku_links x where x.kind = p_kind and x.record_id = p_id;
  if l.contact_id is null then
    v_sh := public.bukku_shared(p_kind, p_id);
    if v_sh is null then return jsonb_build_object('ok', true); end if;
    return jsonb_build_object('ok', true, 'contact_id', (v_sh->>'contact_id')::bigint, 'code', v_sh->>'code',
      'via', v_sh->>'via', 'changed', false);
  end if;
  select t.name into v_by from public.team_members t where t.id = l.sent_by;
  return jsonb_build_object('ok', true, 'contact_id', l.contact_id, 'code', l.code, 'sent_at', l.sent_at,
    'sent_by', v_by, 'changed', l.sent_hash is distinct from public.bukku_print(p_kind, p_id));
end $$;
revoke all on function public.bukku_link_get(text, uuid) from public, anon;
grant execute on function public.bukku_link_get(text, uuid) to authenticated;

create or replace function public.bukku_prepare(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients; s public.suppliers; ct public.client_contacts; e public.billing_entities;
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
  elsif p_kind = 'entity' then
    select * into e from public.billing_entities x where x.id = p_id;
    if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = public.entity_home_client(e.id);
    ct := public.entity_contact(e.id);
    if coalesce(btrim(e.legal_name), '') = '' then v_missing := v_missing || 'Registered name'::text; end if;
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

create or replace function public.bukku_linked(p_kind text, p_id uuid, p_contact bigint, p_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); v_name text; v_code text; v_client uuid;
begin
  if not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-contact'); end if;
  if p_kind = 'client' then
    select x.name, x.client_code into v_name, v_code from public.clients x where x.id = p_id;
  elsif p_kind = 'entity' then
    v_name := public.bukku_record_name('entity', p_id);
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
  if p_kind = 'entity' then
    perform public.bukku_file_entity(p_id, me.name, 'Sent to Bukku · ' || coalesce(p_code, p_contact::text));
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, case when p_kind = 'client' then 'client.edited' else 'supplier.edited' end, v_name,
            coalesce(v_code || ' · ', '') || 'Sent to Bukku · ' || coalesce(p_code, p_contact::text));
  end if;
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
  elsif p_kind = 'entity' then
    v_name := public.bukku_record_name('entity', p_id);
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
  if p_kind = 'entity' then
    perform public.bukku_file_entity(p_id, me.name, 'Linked to Bukku, nothing sent · ' || coalesce(p_code, p_contact::text));
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, case when p_kind = 'client' then 'client.edited' else 'supplier.edited' end, v_name,
            coalesce(v_code || ' · ', '') || 'Linked to Bukku, nothing sent · ' || coalesce(p_code, p_contact::text));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_link_only(text, uuid, bigint, text) from public, anon;
grant execute on function public.bukku_link_only(text, uuid, bigint, text) to authenticated;

create or replace function public.bukku_unlink(p_kind text, p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.bukku_links;
  v_at timestamptz := clock_timestamp();
  v_n int := 0;
begin
  if p_kind not in ('client', 'supplier', 'entity') or not public.bukku_may(p_kind, p_id, 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  if public.bukku_record_name(p_kind, p_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  for r in select * from public.bukku_pair_links(p_kind, p_id) loop
    if not public.bukku_may(r.kind, r.record_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  end loop;
  for r in select * from public.bukku_pair_links(p_kind, p_id) loop
    insert into public.bukku_links_gone (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash, gone_at, gone_by)
    values (r.kind, r.record_id, r.contact_id, r.code, r.sent_at, r.sent_by, r.sent_hash, v_at, me.id);
    delete from public.bukku_links x where x.kind = r.kind and x.record_id = r.record_id;
    if r.kind = 'entity' then
      perform public.bukku_file_entity(r.record_id, me.name, 'Unlinked from Bukku · ' || coalesce(r.code, r.contact_id::text));
    else
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, case when r.kind = 'client' then 'client.edited' else 'supplier.edited' end,
              public.bukku_record_name(r.kind, r.record_id),
              'Unlinked from Bukku · ' || coalesce(r.code, r.contact_id::text));
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then return jsonb_build_object('error', 'not-linked'); end if;
  return jsonb_build_object('ok', true, 'stamp', v_at, 'records', v_n);
end $$;
revoke all on function public.bukku_unlink(text, uuid) from public, anon;
grant execute on function public.bukku_unlink(text, uuid) to authenticated;

create or replace function public.bukku_unlink_undo(p_kind text, p_id uuid, p_stamp timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  g public.bukku_links_gone;
  v_n int := 0;
begin
  if p_kind not in ('client', 'supplier', 'entity') or not public.bukku_may(p_kind, p_id, 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  if not exists (select 1 from public.bukku_links_gone x
                  where x.gone_at = p_stamp and x.kind = p_kind and x.record_id = p_id) then
    return jsonb_build_object('error', 'not-found');
  end if;
  for g in select * from public.bukku_links_gone x where x.gone_at = p_stamp loop
    if not public.bukku_may(g.kind, g.record_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
    if exists (select 1 from public.bukku_links l where l.kind = g.kind and l.record_id = g.record_id) then
      return jsonb_build_object('error', 'moved');
    end if;
    if public.bukku_contact_taken(g.kind, g.record_id, g.contact_id) then return jsonb_build_object('error', 'taken'); end if;
  end loop;
  for g in select * from public.bukku_links_gone x where x.gone_at = p_stamp loop
    insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
    values (g.kind, g.record_id, g.contact_id, g.code, coalesce(g.sent_at, now()), g.sent_by, g.sent_hash);
    if g.kind = 'entity' then
      perform public.bukku_file_entity(g.record_id, me.name, 'Linked to Bukku again · ' || coalesce(g.code, g.contact_id::text));
    else
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, case when g.kind = 'client' then 'client.edited' else 'supplier.edited' end,
              public.bukku_record_name(g.kind, g.record_id),
              'Linked to Bukku again · ' || coalesce(g.code, g.contact_id::text));
    end if;
    v_n := v_n + 1;
  end loop;
  delete from public.bukku_links_gone x where x.gone_at = p_stamp;
  return jsonb_build_object('ok', true, 'records', v_n);
end $$;
revoke all on function public.bukku_unlink_undo(text, uuid, timestamptz) from public, anon;
grant execute on function public.bukku_unlink_undo(text, uuid, timestamptz) to authenticated;


/* Who an entity's reminder goes to: its billing contact (else its brand's
   main contact), with their salutation; its finance email to copy where it
   differs; its registered name. Internal. */
create or replace function public.invoice_entity_recipient(p_entity uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e public.billing_entities;
  k public.client_contacts;
begin
  select * into e from public.billing_entities x where x.id = p_entity;
  if e.id is null then return null; end if;
  k := public.entity_contact(e.id);
  return jsonb_build_object(
    'name', nullif(public.contact_named(k.salutation, k.name), ''),
    'email', nullif(btrim(coalesce(k.email, '')), ''),
    'cc', case when nullif(btrim(coalesce(e.finance_email, '')), '') is not null
                and lower(btrim(e.finance_email)) is distinct from lower(btrim(coalesce(k.email, '')))
               then btrim(e.finance_email) end,
    'company', coalesce(nullif(btrim(coalesce(e.legal_name, '')), ''),
                        (select c.name from public.clients c where c.id = public.entity_home_client(e.id))));
end $$;
revoke all on function public.invoice_entity_recipient(uuid) from public, anon, authenticated;

/* The company behind a Bukku contact: the entity linked to it, else the
   main entity of the brand linked to it. Internal. */
create or replace function public.bukku_contact_entity(p_contact bigint)
returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select l.record_id from public.bukku_links l where l.kind = 'entity' and l.contact_id = p_contact limit 1),
    (select public.client_main_entity(l.record_id) from public.bukku_links l
      where l.kind = 'client' and l.contact_id = p_contact limit 1))
$$;
revoke all on function public.bukku_contact_entity(bigint) from public, anon, authenticated;

/* A reminder to one of a client's companies goes to that company: an
   entity other than the client's main, its own recipient; else the
   client's, or its main entity's where the client holds no email. Internal. */
create or replace function public.invoice_recipient_for(p_client uuid, p_contact bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ent uuid := public.bukku_contact_entity(p_contact);
  v_r jsonb := public.invoice_recipient(p_client);
begin
  if v_ent is not null and exists (select 1 from public.client_entities ce where ce.client_id = p_client and ce.entity_id = v_ent)
     and (v_ent is distinct from public.client_main_entity(p_client) or v_r->>'email' is null) then
    return public.invoice_entity_recipient(v_ent);
  end if;
  return v_r;
end $$;
revoke all on function public.invoice_recipient_for(uuid, bigint) from public, anon, authenticated;

/* The Bukku contacts a colleague's invoices are read for: every contact
   linked to a client, a supplier that is a client, or a billing entity,
   each with every client its company bills that the colleague sees
   (`clients`), the one it is filed under (`client`: its own, else the
   brand the company is the main of), the company and its recipient. */
create or replace function public.invoice_scope()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('clients.billing', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true,
    'me', jsonb_build_object('id', me.id, 'name', me.name),
    'all', public.client_scope_free('view'),
    'send', public.allowed('clients.billing', 'work'),
    'links', coalesce((
      with lk as (
        select b.contact_id, b.record_id as own, 0 as pref, public.client_main_entity(b.record_id) as ent
          from public.bukku_links b where b.kind = 'client'
        union all
        select b.contact_id, s.client_id, 1, public.client_main_entity(s.client_id)
          from public.bukku_links b join public.suppliers s on s.id = b.record_id
         where b.kind = 'supplier' and s.client_id is not null
        union all
        select b.contact_id, null::uuid, 2, b.record_id
          from public.bukku_links b where b.kind = 'entity'
      ), cl as (
        select lk.contact_id, lk.own as client_id, lk.pref, 0 as rnk, lk.ent from lk where lk.own is not null
        union all
        select lk.contact_id, ce.client_id, lk.pref, case when ce.is_main then 1 else 2 end, lk.ent
          from lk join public.client_entities ce on ce.entity_id = lk.ent
      ), seen as (
        select cl.* from cl join public.clients c on c.id = cl.client_id where public.client_seen(c.id, 'view')
      ), one as (
        select distinct on (s.contact_id) s.contact_id, s.client_id, s.ent,
               (select jsonb_agg(distinct s2.client_id) from seen s2 where s2.contact_id = s.contact_id) as clients
          from seen s join public.clients c on c.id = s.client_id
         order by s.contact_id, s.pref, s.rnk, c.name
      )
      select jsonb_agg(jsonb_build_object('contact', o.contact_id, 'client', c.id, 'name', c.name, 'code', c.client_code,
               'slug', c.slug, 'stage', c.stage, 'clients', o.clients,
               'to', public.invoice_recipient_for(c.id, o.contact_id),
               'company', public.invoice_recipient_for(c.id, o.contact_id)->>'company') order by c.name)
        from one o join public.clients c on c.id = o.client_id), '[]'::jsonb));
end $$;
revoke all on function public.invoice_scope() from public, anon;
grant execute on function public.invoice_scope() to authenticated;

create or replace function public.invoice_email_begin(p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members;
  t      public.invoice_email_template;
  rcp    jsonb;
  inv    jsonb;
  hours  numeric;
  r      public.invoice_emails;
  v_n    int;
  v_to   text;
  v_cc   text;
  v_who  text;
  v_co   text;
  v_tot  text;
  v_nos  text;
  v_list text[];
  v_vals jsonb;
  v_s    text;
  v_b    text;
  v_id   uuid;
begin
  select * into me from public.team_members x where x.id = p_actor and x.active;
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-request'); end if;
  if jsonb_typeof(p_invoices) <> 'array' or jsonb_array_length(p_invoices) < 1 or jsonb_array_length(p_invoices) > 50 then
    return jsonb_build_object('error', 'bad-invoices');
  end if;
  for inv in select value from jsonb_array_elements(p_invoices) loop
    if btrim(coalesce(inv->>'number', '')) = '' or coalesce(inv->>'number', '') !~ '^[^[:cntrl:]]{1,60}$' or coalesce(inv->>'currency', '') !~ '^[A-Z]{3}$'
       or (inv->>'amount') is null or (inv->>'amount')::numeric <= 0
       or (coalesce(inv->>'link', '') <> '' and inv->>'link' !~ '^https://[a-z0-9-]+\.bukku\.my/[A-Za-z0-9/_-]+$') then
      return jsonb_build_object('error', 'bad-invoices');
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('invoice-mail:' || p_contact::text, 0));
  select * into r from public.invoice_emails x
   where x.bukku_contact = p_contact and x.status = 'sending' and x.created_at > now() - interval '10 minutes'
   order by x.created_at desc limit 1;
  if r.id is not null then return jsonb_build_object('error', 'sending'); end if;
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 and not coalesce(p_again, false) then
    select * into r from public.invoice_emails x
     where x.bukku_contact = p_contact and x.status <> 'failed' and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
    if r.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', r.created_at, 'to', r.to_email,
        'by', (select m.name from public.team_members m where m.id = r.sent_by)));
    end if;
  end if;
  rcp := case when p_client is null then null else public.invoice_recipient_for(p_client, p_contact) end;
  v_to := coalesce(rcp->>'email', nullif(btrim(coalesce(p_email, '')), ''));
  if v_to is null or v_to !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'no-email'); end if;
  v_cc := case when coalesce(p_cc, false) and lower(coalesce(rcp->>'cc', '')) <> lower(v_to) then rcp->>'cc' end;
  v_co := coalesce(rcp->>'company', nullif(btrim(coalesce(p_name, '')), ''), 'Client');
  v_who := coalesce(rcp->>'name', 'Sir or Madam');
  v_n := jsonb_array_length(p_invoices);
  select string_agg(public.invoice_money(s.amt, s.cur), ' and ' order by s.cur) into v_tot
    from (select x->>'currency' as cur, sum((x->>'amount')::numeric) as amt
            from jsonb_array_elements(p_invoices) x group by x->>'currency') s;
  select array_agg(x->>'number' order by o) into v_list from jsonb_array_elements(p_invoices) with ordinality as a (x, o);
  v_nos := case when v_n = 1 then v_list[1]
                else array_to_string(v_list[1:v_n - 1], ', ') || ' and ' || v_list[v_n] end;
  v_vals := jsonb_build_object('contact name', v_who, 'client', v_co, 'invoice no', v_nos, 'count', v_n::text,
    'total', v_tot, 'sign off', case when rcp->>'name' is not null then 'Yours sincerely' else 'Yours faithfully' end);
  select * into t from public.invoice_email_template x where x.id = 1;
  v_s := btrim(regexp_replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_subject, '')), ''),
           case when v_n = 1 then t.subject_one else t.subject_many end), v_vals), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_body, '')), ''), t.body), v_vals), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  insert into public.invoice_emails (client_id, bukku_contact, client_name, invoices, to_email, cc_email, subject, body, sent_by)
  values (p_client, p_contact, v_co, p_invoices, v_to, v_cc, v_s, v_b, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', v_cc, 'subject', v_s, 'body', v_b,
    'legal', t.legal, 'disclaimer', t.disclaimer);
end $$;
revoke all on function public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) to service_role;

-- END OF BUKKU BY ENTITY ---------------------------------------------------

select public.functions_tidy();
