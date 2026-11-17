-- ===========================================================================
-- A COLLEAGUE IN BUKKU (2026-11-17)
-- ===========================================================================
-- WHY: HR-SPEC decision 12 (tests/hr-templates/HR-SPEC.md): a new colleague
-- is pushed to Bukku as an employee contact. Bukku's contacts take the type
-- `employee`, so no supplier stands in for one.
--
-- WHAT IT CHANGES
--   * A colleague is a Bukku contact of kind `member`: sent or linked from
--     their record's Onboarding at Personnel (`team.personnel`), the name as
--     per NRIC, the company email, the mobile and the home address from
--     their employee record; never an NRIC, a bank account or a salary. No
--     Bukku field holds the Employee ID. Filed `team.edited` on them.
--   * `bukku_member_ready()` (internal): true once the SQL Editor part has
--     widened `bukku_links.kind`; until then `bukku_may` offers no
--     colleague, so nothing is made in Bukku that the portal cannot keep.
--   * `bukku_may`, `bukku_record_name`, `bukku_print`, `bukku_prepare`,
--     `bukku_linked` and `bukku_link_only` restated with the colleague.
--
-- ORDER: this file (connector), the pages and `bukku-sync`, then the SQL
-- Editor part (2026-11-17-bukku-employee-editor.sql), which turns it on.
-- Safe to run twice.
--
-- ROLLBACK: run the six functions from CREATOR PAYMENTS (and
-- bukku_prepare from BUKKU'S CREATOR ID FIELD) again; `bukku_member_ready`
-- may stay.
-- ===========================================================================

-- A COLLEAGUE IN BUKKU --------------------------------------------------------

/* Whether a colleague's link can be kept: the SQL Editor part widens
   `bukku_links.kind` to take `member`; until then no colleague is offered
   to Bukku, so nothing is made in Bukku that the portal cannot file. */
create or replace function public.bukku_member_ready()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from pg_constraint c
                  where c.conname = 'bukku_links_kind_check' and pg_get_constraintdef(c.oid) like '%member%')
$$;
revoke all on function public.bukku_member_ready() from public, anon, authenticated;

create or replace function public.bukku_may(p_kind text, p_id uuid, p_level text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return false; end if;
  if p_kind = 'client' then
    return public.allowed('clients.billing', p_level) and public.client_seen(p_id, 'view');
  elsif p_kind = 'supplier' then
    return public.allowed('suppliers', p_level);
  elsif p_kind = 'creator' then
    -- A creator is read at the Creators List; it is sent at Creator payment details.
    return public.allowed('campaigns.creators', 'view')
       and (p_level = 'view' or public.ops_granted('campaigns.pay', 'work'));
  elsif p_kind = 'member' then
    -- A colleague is a Bukku employee at Personnel, once the link can be kept.
    return public.ops_granted('team.personnel', 'manage') and public.bukku_member_ready()
       and exists (select 1 from public.team_members m where m.id = p_id and m.erased_at is null and not coalesce(m.system, false));
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
              when p_kind = 'member'
              then (select x.name from public.team_members x where x.id = p_id)
              when p_kind = 'creator'
              then (select coalesce(x.name, x.creator_code) from public.creators x where x.id = p_id)
              else (select coalesce(x.name, x.code) from public.suppliers x where x.id = p_id) end
$$;
revoke all on function public.bukku_record_name(text, uuid) from public, anon, authenticated;

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
  elsif p_kind = 'creator' then
    select concat_ws('|', r.ref, r.legal_name, r.bill_kind, r.id_no, r.tin, r.address, r.currency, r.email, r.whatsapp, c.creator_code)
      into v
      from public.creators c
      left join lateral (select * from public.creator_pay_requests y where y.creator_id = c.id and y.status = 'approved'
                          order by y.decided_at desc limit 1) r on true
     where c.id = p_id;
  elsif p_kind = 'member' then
    select concat_ws('|', coalesce(nullif(btrim(p.data->>'full_name'), ''), m.name), m.email,
             coalesce(nullif(btrim(p.data->>'mobile'), ''), m.mobile), m.staff_code, p.data->>'nationality',
             p.data->>'address1', p.data->>'address2', p.data->>'postcode', p.data->>'city', p.data->>'state', p.data->>'country')
      into v
      from public.team_members m left join public.personnel_records p on p.team_member_id = m.id
     where m.id = p_id;
  else
    select concat_ws('|', s.name, s.kind, s.brn, s.tin, s.sst_no, s.address, s.email, s.finance_email,
             s.contact_name, s.mobile, s.phone, s.currency, s.code, s.payment_term)
      into v from public.suppliers s where s.id = p_id;
  end if;
  return case when v is null then null else md5(v) end;
end $$;
revoke all on function public.bukku_print(text, uuid) from public, anon, authenticated;

create or replace function public.bukku_prepare(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients; s public.suppliers; ct public.client_contacts; e public.billing_entities;
  l public.bukku_links; b public.bukku_settings; cr public.creators; rq public.creator_pay_requests;
  tm public.team_members; v_pd jsonb; v_foreign boolean;
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
  elsif p_kind = 'member' then
    /* A colleague is an employee in Bukku (HR-SPEC decision 12): the name
       as per NRIC, the company email, the mobile and the home address from
       their record, never an NRIC, a bank account or a salary. No Bukku
       field holds an Employee ID. */
    select * into tm from public.team_members x where x.id = p_id;
    if tm.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select x.data into v_pd from public.personnel_records x where x.team_member_id = tm.id;
    v_pd := coalesce(v_pd, '{}'::jsonb);
    v_foreign := coalesce(nullif(lower(btrim(v_pd->>'nationality')), ''), 'malaysian') not in ('malaysian', 'malaysia');
    select * into l from public.bukku_links x where x.kind = 'member' and x.record_id = tm.id;
    return jsonb_build_object('ok', true, 'kind', 'member', 'id', tm.id,
      'legal_name', public.bukku_name_case(coalesce(nullif(btrim(v_pd->>'full_name'), ''), tm.name), false), 'other_name', tm.name,
      'entity_type', case when v_foreign then 'FOREIGN_INDIVIDUAL' else 'MALAYSIAN_INDIVIDUAL' end,
      'email', nullif(btrim(coalesce(tm.email, '')), ''),
      'phone_no', public.wa_number(coalesce(nullif(btrim(v_pd->>'mobile'), ''), tm.mobile), 'MY'),
      'address', nullif(concat_ws(', ', nullif(btrim(v_pd->>'address1'), ''), nullif(btrim(v_pd->>'address2'), ''),
                   nullif(btrim(concat_ws(' ', nullif(btrim(v_pd->>'postcode'), ''), nullif(btrim(v_pd->>'city'), ''))), ''),
                   nullif(btrim(v_pd->>'state'), ''), nullif(btrim(v_pd->>'country'), '')), ''),
      'country', 'MY', 'currency', 'MYR',
      'person', public.bukku_name_case(coalesce(nullif(btrim(v_pd->>'full_name'), ''), tm.name), false),
      'our_id', tm.staff_code, 'field_id', null, 'type', 'employee',
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
  elsif p_kind = 'member' then
    select x.name, x.staff_code into v_name, v_code from public.team_members x where x.id = p_id;
  elsif p_kind = 'creator' then
    select coalesce(x.name, x.creator_code), x.creator_code into v_name, v_code from public.creators x where x.id = p_id;
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
    values (me.name, case p_kind when 'client' then 'client.edited' when 'creator' then 'creator.updated' when 'member' then 'team.edited' else 'supplier.edited' end, v_name,
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
  elsif p_kind = 'member' then
    select x.name, x.staff_code into v_name, v_code from public.team_members x where x.id = p_id;
  elsif p_kind = 'creator' then
    select coalesce(x.name, x.creator_code), x.creator_code into v_name, v_code from public.creators x where x.id = p_id;
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
    values (me.name, case p_kind when 'client' then 'client.edited' when 'creator' then 'creator.updated' when 'member' then 'team.edited' else 'supplier.edited' end, v_name,
            coalesce(v_code || ' · ', '') || 'Linked to Bukku, nothing sent · ' || coalesce(p_code, p_contact::text));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_link_only(text, uuid, bigint, text) from public, anon;
grant execute on function public.bukku_link_only(text, uuid, bigint, text) to authenticated;

-- END OF A COLLEAGUE IN BUKKU -------------------------------------------------

select public.functions_tidy();
