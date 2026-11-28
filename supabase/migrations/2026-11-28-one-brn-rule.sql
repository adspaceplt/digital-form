-- ===========================================================================
-- ONE BRN RULE (2026-11-28)
-- ===========================================================================
-- WHY: four checks of a business registration number disagreed (docs/MAP.md
-- risk 10): /quote/'s intake held the user's rule of 27 Nov (12 digits, a
-- year, the entity code), the details form and a quotation's signing took
-- any 6 to 20 letters or digits, and the supplier form and a creator's
-- payment details took any 12 digits.
-- WHAT IT CHANGES
--   * `brn_check(p_no, p_market, p_kind)`, the one reading, answering null
--     where the number holds, else `bad-brn` or `brn-kind`. Spaces and
--     dashes are dropped first. Malaysia: 12 digits, the first four a year
--     from 1900 to this year, the next two the entity code, a company 01,
--     02 or 04 and a sole proprietorship or partnership 03 (`p_kind`
--     `company` or `soleprop` holds the code to the choice; none takes any
--     of the four). A Singapore client (`SG`) bills through either
--     country's company, so a UEN or a BRN; no market given, the same.
--   * `quote_intake_check` reads it (refusals unchanged).
--   * `client_details_read` answers the client's `market`, and
--     `client_details_submit` refuses `bad-company_no` by its rule.
--   * `quote_sign_company` refuses `bad-company_no` by it, a BRN or a UEN
--     (the client's market is not passed to it).
--   * `supplier_values_check` and `creator_pay_check` (`bad-brn`,
--     `id_no`) read it for Malaysia. The three checks become stable, as
--     the year moves.
-- ORDER: this file first, then the pages. An open tab served before meets
-- the stricter refusal at its submit, said in the words it already holds.
-- Stored values are not touched: a number kept before is read again only
-- when a form sends it.
-- ROLLBACK: run the latest earlier bands of the six functions again, then
-- `drop function if exists public.brn_check(text, text, text);`.
-- ===========================================================================

-- ONE BRN RULE ---------------------------------------------------------------

create or replace function public.brn_check(p_no text, p_market text default 'MY', p_kind text default null)
returns text
language plpgsql stable set search_path = public as $$
declare
  v      text := upper(regexp_replace(coalesce(p_no, ''), '[\s-]+', '', 'g'));
  v_uen  boolean;
  v_code text;
begin
  v_uen := v ~ '^([0-9]{8,9}[A-Z]|[TSR][0-9]{2}[A-Z]{2}[0-9]{4}[A-Z])$';
  if (p_market is null or p_market = 'SG') and v_uen then return null; end if;
  if v !~ '^[0-9]{12}$' then return 'bad-brn'; end if;
  if left(v, 4)::int < 1900 or left(v, 4)::int > extract(year from (now() at time zone 'Asia/Kuala_Lumpur'))::int then
    return 'bad-brn';
  end if;
  v_code := substr(v, 5, 2);
  if v_code not in ('01', '02', '03', '04') then return 'bad-brn'; end if;
  if p_kind = 'soleprop' and v_code <> '03' then return 'brn-kind'; end if;
  if p_kind = 'company' and v_code = '03' then return 'brn-kind'; end if;
  return null;
end $$;
revoke all on function public.brn_check(text, text, text) from public, anon, authenticated;

create or replace function public.quote_intake_check(p jsonb, p_fields text[])
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_kind text := nullif(btrim(coalesce(p->>'kind', '')), '');
  v_brn  text := regexp_replace(coalesce(p->>'brn', ''), '[\s-]+', '', 'g');
  v_code text;
  v_legal text := upper(btrim(regexp_replace(coalesce(p->>'legal', ''), '\s+', ' ', 'g')));
  v_site text := btrim(coalesce(p->>'website', ''));
  v_none boolean := coalesce(p->>'no_site', '') = 'true';
  v_plat text := nullif(btrim(coalesce(p->>'platform', '')), '');
  v_hdl  text := regexp_replace(btrim(coalesce(p->>'handle', '')), '^@+', '');
  v_ind  text := nullif(btrim(coalesce(p->>'industry', '')), '');
  v_start text := nullif(btrim(coalesce(p->>'commence', '')), '');
  v_on_t text := nullif(btrim(coalesce(p->>'commence_on', '')), '');
  v_on   date;
  v_out  jsonb := '{}'::jsonb;
begin
  if p_fields is null or jsonb_typeof(coalesce(p, 'null'::jsonb)) <> 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  if 'registration' = any(p_fields) then
    if v_kind is null or v_kind not in ('company', 'soleprop') then return jsonb_build_object('error', 'bad-kind'); end if;
    v_code := public.brn_check(v_brn, 'MY', v_kind);
    if v_code = 'bad-brn' then return jsonb_build_object('error', 'bad-brn'); end if;
    if v_code = 'brn-kind' then
      return jsonb_build_object('error', 'brn-kind', 'kind', case when v_kind = 'company' then 'soleprop' else 'company' end);
    end if;
    if length(v_legal) < 2 or length(v_legal) > 150 or v_legal ~* public.quote_link_like() then
      return jsonb_build_object('error', 'bad-legal');
    end if;
    v_out := v_out || jsonb_build_object('kind', v_kind, 'brn', v_brn, 'legal', v_legal);
  end if;
  if 'industry' = any(p_fields) then
    if v_ind is null then return jsonb_build_object('error', 'need-industry'); end if;
    if not exists (select 1 from public.industries i where i.name = v_ind) then return jsonb_build_object('error', 'bad-industry'); end if;
    v_out := v_out || jsonb_build_object('industry', v_ind);
  end if;
  if 'online' = any(p_fields) then
    if v_site <> '' then
      if v_site !~* '^https?://' then v_site := 'https://' || v_site; end if;
      if length(v_site) > 200 or v_site !~* '^https?://[^\s"''<>`\\/]+\.[^\s"''<>`\\]{2,}$' then
        return jsonb_build_object('error', 'bad-site');
      end if;
      v_none := false;
    elsif not v_none then
      return jsonb_build_object('error', 'need-site');
    end if;
    if v_hdl <> '' then
      if v_plat is null or v_plat not in ('instagram', 'facebook', 'tiktok', 'xhs') then return jsonb_build_object('error', 'bad-platform'); end if;
      if v_hdl !~ '^[A-Za-z0-9._-]{1,60}$' then return jsonb_build_object('error', 'bad-handle'); end if;
    elsif v_none then
      return jsonb_build_object('error', 'need-handle');
    end if;
    v_out := v_out || jsonb_build_object('website', nullif(v_site, ''), 'no_site', v_none,
      'platform', case when v_hdl <> '' then v_plat end, 'handle', case when v_hdl <> '' then '@' || v_hdl end);
  end if;
  if 'commence' = any(p_fields) then
    if v_start is null or v_start not in ('1_3', '3_6', '6_plus') then return jsonb_build_object('error', 'bad-commence'); end if;
    if v_on_t is not null then
      if v_on_t !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error', 'bad-start-date'); end if;
      begin
        v_on := v_on_t::date;
      exception when others then
        return jsonb_build_object('error', 'bad-start-date');
      end;
      if v_on < (now() at time zone 'Asia/Kuala_Lumpur')::date or v_on > date '2099-12-31' then
        return jsonb_build_object('error', 'bad-start-date');
      end if;
    end if;
    v_out := v_out || jsonb_build_object('commence', v_start, 'commence_on', v_on);
  end if;
  return jsonb_strip_nulls(v_out);
end $$;
revoke all on function public.quote_intake_check(jsonb, text[]) from public, anon, authenticated;

create or replace function public.client_details_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_f  public.client_detail_forms;
  v_cl public.clients;
  m    public.team_members;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_f from public.client_detail_forms f where f.access_key = p_key and f.voided_at is null;
  if v_f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_f.submitted_at is not null then return jsonb_build_object('error', 'submitted', 'request_ref', v_f.request_ref); end if;
  if v_f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  if v_cl.stage = 'past' then return jsonb_build_object('error', 'not_found'); end if;
  -- The billing details form is a quotation's step: Sales by alone
  -- (CLIENT REPRESENTATIVE, 2026-11-27).
  select * into m from public.team_members x where x.id = public.client_rep(v_cl.id, 'sales');
  -- The market picks the registration's shape: a Singapore client's UEN
  -- or BRN, every other client's 12-digit BRN (ONE BRN RULE, 2026-11-28).
  return jsonb_build_object('ok', true, 'brand', v_cl.name, 'expires_at', v_f.expires_at,
    'market', case when v_cl.market = 'SG' then 'SG' else 'MY' end,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end);
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
  v_ref  text;
  v_mk   text;
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
  select c.market into v_mk from public.clients c where c.id = v_f.client_id;
  if public.brn_check(v_brn, case when v_mk = 'SG' then 'SG' else 'MY' end, null) is not null then
    return jsonb_build_object('error', 'bad-company_no');
  end if;
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
   where f.id = v_f.id
  returning f.request_ref into v_ref;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Details form', 'client.edited', v_cl.name,
          'Billing details received on the details form from ' || coalesce(v_sal || ' ', '') || v_cn || coalesce(' · ' || v_ref, ''));
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.details', 'Billing details received · ' || v_cl.name,
         'From ' || coalesce(v_sal || ' ', '') || v_cn || '. Review them on the client''s Billing.',
         v_cl.id, 'client.details:' || v_f.id || ':' || m.id
    from public.team_members m
   where m.active and m.removed_at is null
     and (m.is_admin or m.role = 'admin'
          or (public.allowed_of(m.id, 'clients.billing', 'work')
              -- held to the colleague's own client scope, as client_row_seen holds a reader (audit S7)
              and (v_cl.stage not in ('lead', 'contacted', 'proposal', 'past')
                   or public.level_rank(coalesce(m.access ->> case when v_cl.stage = 'past' then 'clients.past' else 'clients.leads' end,
                                                 m.access ->> 'clients')) >= 1)
              and (coalesce(m.client_scope, 'all') <> 'own'
                   or (nullif(btrim(coalesce(v_cl.owner, '')), '') is null and v_cl.stage in ('lead', 'contacted', 'proposal'))
                   or v_cl.owner_id = m.id
                   or v_cl.sales_by = m.id)))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true, 'request_ref', v_ref);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

create or replace function public.quote_sign_company(a jsonb)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_name text := upper(btrim(regexp_replace(coalesce(a->>'legal_name', ''), '\s+', ' ', 'g')));
  v_brn  text := upper(regexp_replace(coalesce(a->>'company_no', ''), '\s+', '', 'g'));
  v_old  text := nullif(upper(regexp_replace(coalesce(a->>'company_no_old', ''), '\s+', '', 'g')), '');
  v_tin  text := nullif(upper(regexp_replace(coalesce(a->>'tin', ''), '\s+', '', 'g')), '');
  v_sst  text := nullif(upper(regexp_replace(coalesce(a->>'sst_no', ''), '\s+', '', 'g')), '');
  v_addr text := btrim(coalesce(a->>'billing_address', ''));
  v_fin  text := nullif(lower(btrim(coalesce(a->>'finance_email', ''))), '');
begin
  if length(v_name) < 2 or length(v_name) > 160 then return jsonb_build_object('error', 'bad-legal_name'); end if;
  -- The client's market is not passed here: a 12-digit BRN or a UEN.
  if public.brn_check(v_brn, null, null) is not null then return jsonb_build_object('error', 'bad-company_no'); end if;
  if v_old is not null and v_old !~ '^[A-Z0-9-]{4,20}$' then return jsonb_build_object('error', 'bad-company_no_old'); end if;
  if v_tin is not null and v_tin !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-tin'); end if;
  if v_sst is not null and v_sst !~ '^[A-Z0-9-]{6,25}$' then return jsonb_build_object('error', 'bad-sst_no'); end if;
  if length(v_addr) < 10 or length(v_addr) > 400 then return jsonb_build_object('error', 'bad-billing_address'); end if;
  if v_fin is not null and (v_fin !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_fin) > 160) then
    return jsonb_build_object('error', 'bad-finance_email');
  end if;
  return jsonb_build_object('company', jsonb_build_object('legal_name', v_name, 'company_no', v_brn, 'company_no_old', v_old,
    'tin', v_tin, 'sst_no', v_sst, 'billing_address', v_addr, 'finance_email', v_fin));
end $$;
revoke all on function public.quote_sign_company(jsonb) from public, anon, authenticated;

create or replace function public.supplier_values_check(p jsonb, p_pay boolean)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  o jsonb := '{}'::jsonb;
  v text;
  k text;
  kind text := nullif(btrim(coalesce(p->>'kind', '')), '');
  banks constant text[] := array['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank',
    'Bank Islam', 'Public Bank', 'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital',
    '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB', '[SG] CIMB', '[SG] Maybank', '[SG] Bank of China'];
  mail constant text := '^[^@\s]+@[^@\s]+\.[^@\s]+$';
begin
  if kind is null or kind not in ('company', 'individual') then return jsonb_build_object('error', 'bad-kind'); end if;
  o := o || jsonb_build_object('kind', kind);
  v := btrim(regexp_replace(coalesce(p->>'name', ''), '\s+', ' ', 'g'));
  if length(v) < 2 or length(v) > 160 then return jsonb_build_object('error', 'bad-name'); end if;
  o := o || jsonb_build_object('name', v);
  v := regexp_replace(coalesce(p->>'brn', ''), '[^0-9]', '', 'g');
  if (kind = 'company' or v <> '') and public.brn_check(v, 'MY', null) is not null then return jsonb_build_object('error', 'bad-brn'); end if;
  o := o || jsonb_build_object('brn', nullif(v, ''));
  v := upper(regexp_replace(coalesce(p->>'tin', ''), '\s+', '', 'g'));
  if v !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('error', 'bad-tin'); end if;
  o := o || jsonb_build_object('tin', v);
  v := upper(regexp_replace(coalesce(p->>'sst_no', ''), '\s+', '', 'g'));
  if v <> '' and v !~ '^[A-Z][0-9]{2}-[0-9]{4}-[0-9]{8}$' then return jsonb_build_object('error', 'bad-sst_no'); end if;
  o := o || jsonb_build_object('sst_no', nullif(v, ''));
  foreach k in array array['phone', 'mobile'] loop
    if not public.supplier_number_ok(p->>k, k = 'mobile') then return jsonb_build_object('error', 'bad-' || k); end if;
    o := o || jsonb_build_object(k, btrim(p->>k));
  end loop;
  v := btrim(coalesce(p->>'address', ''));
  if length(v) < 10 or length(v) > 400 then return jsonb_build_object('error', 'bad-address'); end if;
  o := o || jsonb_build_object('address', v);
  foreach k in array array['contact_name', 'designation'] loop
    v := btrim(regexp_replace(coalesce(p->>k, ''), '\s+', ' ', 'g'));
    if length(v) < 2 or length(v) > 80 then return jsonb_build_object('error', 'bad-' || k); end if;
    o := o || jsonb_build_object(k, v);
  end loop;
  foreach k in array array['email', 'finance_email'] loop
    v := lower(btrim(coalesce(p->>k, '')));
    if v !~ mail or length(v) > 160 then return jsonb_build_object('error', 'bad-' || k); end if;
    o := o || jsonb_build_object(k, v);
  end loop;
  v := coalesce(p->>'payment_term', '');
  if v not in ('NET 7', 'NET 14', 'NET 30', 'NET 45', 'NET 60') then return jsonb_build_object('error', 'bad-payment_term'); end if;
  o := o || jsonb_build_object('payment_term', v);
  v := coalesce(nullif(p->>'currency', ''), 'MYR');
  if v not in ('MYR', 'SGD') then return jsonb_build_object('error', 'bad-currency'); end if;
  o := o || jsonb_build_object('currency', v);
  if not p_pay then return o; end if;
  v := regexp_replace(coalesce(p->>'nric', ''), '[^0-9]', '', 'g');
  if kind = 'individual' then
    if v !~ '^[0-9]{12}$' then return jsonb_build_object('error', 'bad-nric'); end if;
    o := o || jsonb_build_object('nric', substr(v, 1, 6) || '-' || substr(v, 7, 2) || '-' || substr(v, 9, 4));
  else
    o := o || jsonb_build_object('nric', null);
  end if;
  v := btrim(regexp_replace(coalesce(p->>'payee_name', ''), '\s+', ' ', 'g'));
  if length(v) < 2 or length(v) > 120 then return jsonb_build_object('error', 'bad-payee_name'); end if;
  o := o || jsonb_build_object('payee_name', v);
  v := coalesce(p->>'bank_name', '');
  if not (v = any (banks)) then return jsonb_build_object('error', 'bad-bank_name'); end if;
  o := o || jsonb_build_object('bank_name', v);
  v := regexp_replace(coalesce(p->>'bank_account', ''), '[\s-]', '', 'g');
  if v !~ '^[0-9]{6,20}$' then return jsonb_build_object('error', 'bad-bank_account'); end if;
  o := o || jsonb_build_object('bank_account', v);
  v := upper(regexp_replace(coalesce(p->>'swift', ''), '\s+', '', 'g'));
  if v <> '' and v !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then return jsonb_build_object('error', 'bad-swift'); end if;
  o := o || jsonb_build_object('swift', nullif(v, ''));
  v := btrim(coalesce(p->>'bank_address', ''));
  if length(v) > 300 then return jsonb_build_object('error', 'bad-bank_address'); end if;
  o := o || jsonb_build_object('bank_address', nullif(v, ''));
  return o;
end $$;
revoke all on function public.supplier_values_check(jsonb, boolean) from public, anon, authenticated;

create or replace function public.creator_pay_check(p jsonb)
returns jsonb language plpgsql stable set search_path = public as $$
declare
  v_kind text := btrim(coalesce(p->>'bill_kind', ''));
  v_id   text := upper(regexp_replace(coalesce(p->>'id_no', ''), '[\s-]', '', 'g'));
  v_name text := btrim(regexp_replace(coalesce(p->>'legal_name', ''), '\s+', ' ', 'g'));
  v_tin  text := upper(regexp_replace(coalesce(p->>'tin', ''), '\s', '', 'g'));
  v_addr text := btrim(coalesce(p->>'address', ''));
  v_cur  text := upper(btrim(coalesce(p->>'currency', '')));
  v_meth text := btrim(coalesce(p->>'method', ''));
  v_bank text := btrim(coalesce(p->>'bank', ''));
  v_acct text := upper(regexp_replace(coalesce(p->>'account', ''), '[\s-]', '', 'g'));
  v_pay  text := btrim(regexp_replace(coalesce(p->>'payee', ''), '\s+', ' ', 'g'));
  v_mail text := lower(btrim(coalesce(p->>'email', '')));
  v_wa   text := regexp_replace(coalesce(p->>'whatsapp', ''), '\D', '', 'g');
  v_w    text;
  v_banks constant text[] := array['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank', 'Bank Islam',
    'Public Bank', 'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital', '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB',
    '[SG] CIMB', '[SG] Maybank', '[SG] Bank of China'];
begin
  if v_kind not in ('nric', 'passport', 'brn') then return jsonb_build_object('field', 'bill_kind'); end if;
  if v_kind = 'nric' and v_id !~ '^\d{12}$' then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'brn' and public.brn_check(v_id, 'MY', null) is not null then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'passport' and v_id !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'nric' then v_id := substr(v_id, 1, 6) || '-' || substr(v_id, 7, 2) || '-' || substr(v_id, 9, 4); end if;
  if length(v_name) < 2 or length(v_name) > 120 then return jsonb_build_object('field', 'legal_name'); end if;
  -- every word of the name opens on a capital, the rest as typed
  select string_agg(upper(left(w, 1)) || substr(w, 2), ' ' order by n) into v_w
    from regexp_split_to_table(v_name, ' ') with ordinality as t(w, n);
  v_name := v_w;
  -- the bill is issued and paid to the legal name, so the account holder is it
  v_pay := v_name;
  if v_tin <> '' and v_tin !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('field', 'tin'); end if;
  if length(v_addr) < 5 or length(v_addr) > 300 then return jsonb_build_object('field', 'address'); end if;
  if v_cur not in ('MYR', 'SGD') then return jsonb_build_object('field', 'currency'); end if;
  if not ((v_cur = 'MYR' and v_meth in ('bank', 'duitnow', 'tng')) or (v_cur = 'SGD' and v_meth in ('bank', 'paynow'))) then
    return jsonb_build_object('field', 'method');
  end if;
  if v_meth = 'bank' then
    if not (v_bank = any (v_banks)) or ((v_cur = 'SGD') <> (v_bank like '[SG]%')) then
      return jsonb_build_object('field', 'bank');
    end if;
  else
    v_bank := '';
  end if;
  if v_acct !~ '^[A-Z0-9]{6,34}$' then return jsonb_build_object('field', 'account'); end if;
  if length(v_pay) < 2 or length(v_pay) > 120 then return jsonb_build_object('field', 'payee'); end if;
  if v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_mail) > 160 then return jsonb_build_object('field', 'email'); end if;
  if length(v_wa) < 8 or length(v_wa) > 15 then return jsonb_build_object('field', 'whatsapp'); end if;
  if coalesce(p->>'confirm', '') not in ('true', 'on', '1') then return jsonb_build_object('field', 'confirm'); end if;
  return jsonb_build_object('values', jsonb_build_object('bill_kind', v_kind, 'id_no', v_id, 'legal_name', v_name,
    'tin', nullif(v_tin, ''), 'address', v_addr, 'currency', v_cur, 'method', v_meth, 'bank', nullif(v_bank, ''),
    'account', v_acct, 'payee', v_pay, 'email', v_mail, 'whatsapp', v_wa));
end $$;
revoke all on function public.creator_pay_check(jsonb) from public, anon, authenticated;

-- END OF ONE BRN RULE -------------------------------------------------------

select public.functions_tidy();
