-- ===========================================================================
-- A SUPPLIER'S DETAILS UPDATED BY LINK — approval ends the details form, an
-- approved supplier is sent an update link, a bank change is approved again
-- (2026-10-20)
-- ===========================================================================
-- WHY (the user, 2026-10-20, on BRIQ PACKAGING's record: an Active supplier
-- whose details form stood open until 2 Nov, and "if one supplier that has
-- been registered and approved by our company would like to change record,
-- how could this be done from supplier side?"): a form link outlived the
-- step it was made for, and a supplier asked to change its details had to
-- type every field again, its bank account included.
--
-- WHAT IT CHANGES
--   * `supplier_forms.purpose`: `details` (the first form, a Pending
--     supplier's) or `update` (a supplier already approved).
--   * `supplier_link`: a supplier that is not Pending is sent an update link
--     (Request update), filed Update link created / reset.
--   * `supplier_set_status`: a move of status ends every open link of the
--     supplier, filed with the move (… · details form link closed);
--     approving from Pending stamps who approved and when, every time.
--   * `supplier_form_read`: an update link answers the details held but the
--     NRIC and the bank details (`current`), and whether they are held
--     (`bank_held`, `nric_held`); never their values.
--   * `supplier_form_submit`: on an update link the NRIC and the bank details
--     left blank keep what is held (the bank account blank keeps the payee,
--     bank, account, SWIFT and bank address together); the team is told
--     "Supplier details update received".
--   * `supplier_get`: the form's `purpose` and `bank_changed` (its answers'
--     payee, bank or account differ from what is held), so a colleague
--     without Supplier bank details still reads that they changed.
--   * `supplier_save`: an Active supplier whose payee, bank or account
--     changes goes back to Pending until approved again (`repending`), filed.
--   * `supplier_json`: `approved_by` names a colleague, never a system
--     account.
--
-- ORDER: this file, then the pages. An old page reads `purpose` as absent
-- and shows the update link as a details form, which still works. Safe to
-- run twice. Rollback: SUPPLIERS, A SECTION OF THEIR OWN's and SUPPLIERS
-- LINKED TO CLIENTS's definitions of these functions, and SUPPLIERS's
-- `supplier_json`; the column may stay.
-- ===========================================================================

alter table public.supplier_forms add column if not exists purpose text not null default 'details';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'supplier_forms_purpose_check') then
    alter table public.supplier_forms add constraint supplier_forms_purpose_check check (purpose in ('details', 'update'));
  end if;
end $$;
/* A link open on a supplier already approved is an update link. */
update public.supplier_forms f set purpose = 'update'
  from public.suppliers s
 where s.id = f.supplier_id and s.status <> 'pending' and f.purpose = 'details'
   and f.submitted_at is null and f.voided_at is null and f.expires_at > now();

create or replace function public.supplier_json(s public.suppliers, p_pay boolean)
returns jsonb
language sql stable set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', s.id, 'code', s.code, 'name', s.name, 'kind', s.kind, 'brn', s.brn, 'tin', s.tin, 'sst_no', s.sst_no,
    'phone', s.phone, 'address', s.address, 'contact_name', s.contact_name, 'designation', s.designation,
    'email', s.email, 'mobile', s.mobile, 'payment_term', s.payment_term, 'currency', s.currency,
    'finance_email', s.finance_email, 'status', s.status, 'created_at', s.created_at, 'updated_at', s.updated_at,
    'approved_at', s.approved_at,
    'approved_by', (select m.name from public.team_members m where m.id = s.approved_by and not coalesce(m.system, false)))
    || case when p_pay then jsonb_strip_nulls(jsonb_build_object(
      'nric', s.nric, 'payee_name', s.payee_name, 'bank_name', s.bank_name, 'bank_account', s.bank_account,
      'swift', s.swift, 'bank_address', s.bank_address)) else '{}'::jsonb end)
$$;
revoke all on function public.supplier_json(public.suppliers, boolean) from public, anon, authenticated;

create or replace function public.supplier_link(p_id uuid, p_reset boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  f     public.supplier_forms;
  v_key text;
  v_days int;
  v_purpose text;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_purpose := case when s.status = 'pending' then 'details' else 'update' end;
  select * into f from public.supplier_forms x
   where x.supplier_id = p_id and x.voided_at is null and x.submitted_at is null and x.expires_at > now()
   order by x.created_at desc limit 1;
  if f.id is not null and not coalesce(p_reset, false) then
    return jsonb_build_object('ok', true, 'id', f.id, 'key', f.access_key, 'expires_at', f.expires_at, 'purpose', f.purpose);
  end if;
  update public.supplier_forms x set voided_at = now()
   where x.supplier_id = p_id and x.voided_at is null and x.submitted_at is null;
  loop
    v_key := public.new_link_key();
    exit when not exists (select 1 from public.supplier_forms x where x.access_key = v_key);
  end loop;
  v_days := coalesce(public.app_setting('details_form_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 14)::int;
  insert into public.supplier_forms (supplier_id, access_key, created_by, expires_at, purpose)
  values (p_id, v_key, me.id, now() + make_interval(days => v_days), v_purpose)
  returning * into f;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', coalesce(s.name, s.code),
          s.code || ' · ' || case when v_purpose = 'update' then 'Update link' else 'Details form link' end ||
          case when coalesce(p_reset, false) then ' reset' else ' created' end);
  return jsonb_build_object('ok', true, 'id', f.id, 'key', f.access_key, 'expires_at', f.expires_at, 'purpose', f.purpose);
end $$;
revoke all on function public.supplier_link(uuid, boolean) from public, anon;
grant execute on function public.supplier_link(uuid, boolean) to authenticated;

create or replace function public.supplier_set_status(p_id uuid, p_status text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s  public.suppliers;
  n  int;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('active', 'inactive') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if s.status = p_status then return jsonb_build_object('ok', true, 'status', s.status); end if;
  if p_status = 'active' and (s.name is null or s.kind is null or s.tin is null or s.address is null or s.email is null
      or s.payment_term is null or s.bank_account is null) then
    return jsonb_build_object('error', 'incomplete');
  end if;
  update public.suppliers x set status = p_status, updated_at = now(),
    approved_at = case when p_status = 'active' and x.status = 'pending' then now() else x.approved_at end,
    approved_by = case when p_status = 'active' and x.status = 'pending' then me.id else x.approved_by end
   where x.id = p_id;
  /* A link is made for one step: a move of status ends every one open. */
  update public.supplier_forms x set expires_at = now()
   where x.supplier_id = p_id and x.voided_at is null and x.submitted_at is null and x.expires_at > now();
  get diagnostics n = row_count;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, case when s.status = 'pending' then 'supplier.approved' else 'supplier.edited' end, coalesce(s.name, s.code),
          s.code || ' · ' || initcap(s.status) || ' → ' || initcap(p_status) ||
          case when n > 0 then ' · details form link closed' else '' end);
  return jsonb_build_object('ok', true, 'status', p_status, 'closed', n);
end $$;
revoke all on function public.supplier_set_status(uuid, text) from public, anon;
grant execute on function public.supplier_set_status(uuid, text) to authenticated;

create or replace function public.supplier_form_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f public.supplier_forms;
  s public.suppliers;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into f from public.supplier_forms x where x.access_key = p_key and x.voided_at is null;
  if f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into s from public.suppliers x where x.id = f.supplier_id;
  if f.purpose = 'update' then
    return jsonb_build_object('ok', true, 'name', s.name, 'code', s.code, 'expires_at', f.expires_at, 'purpose', 'update',
      'current', jsonb_strip_nulls(jsonb_build_object(
        'kind', s.kind, 'name', s.name, 'brn', s.brn, 'tin', s.tin, 'sst_no', s.sst_no, 'phone', s.phone,
        'address', s.address, 'contact_name', s.contact_name, 'designation', s.designation, 'email', s.email,
        'mobile', s.mobile, 'payment_term', s.payment_term, 'currency', s.currency, 'finance_email', s.finance_email)),
      'bank_held', s.bank_account is not null, 'nric_held', s.nric is not null);
  end if;
  return jsonb_build_object('ok', true, 'name', s.name, 'code', s.code, 'expires_at', f.expires_at, 'purpose', 'details');
end $$;
revoke all on function public.supplier_form_read(text) from public;
grant execute on function public.supplier_form_read(text) to anon, authenticated;

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
  values (v->>'contact_name', 'supplier.edited', coalesce(s.name, v->>'name'), s.code || ' · ' ||
          case when f.purpose = 'update' then 'Details update received on the update link' else 'Details received on the details form' end);
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

create or replace function public.supplier_get(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s   public.suppliers;
  f   public.supplier_forms;
  pay boolean := public.ops_granted('suppliers.pay', 'view');
  work boolean := public.allowed('suppliers', 'work');
  cv  boolean := public.allowed('clients', 'view');
  a   jsonb;
  cl  jsonb;
  mt  jsonb;
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into s from public.suppliers x where x.id = p_id;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into f from public.supplier_forms x where x.supplier_id = p_id and x.voided_at is null
   order by x.created_at desc limit 1;
  a := f.answers;
  if a is not null and not pay then
    a := a - array['nric', 'payee_name', 'bank_name', 'bank_account', 'swift', 'bank_address'];
  end if;
  if s.client_id is not null then
    select case when cv and public.client_seen(c.id, 'view')
                then jsonb_build_object('id', c.id, 'slug', c.slug, 'code', c.client_code, 'name', c.name)
                else jsonb_build_object('hidden', true) end
      into cl from public.clients c where c.id = s.client_id;
  elsif work and cv and s.brn is not null then
    select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.client_code, 'name', c.name) order by c.client_code, c.name)
      into mt from public.clients c
     where regexp_replace(coalesce(c.company_no, ''), '[^0-9]', '', 'g') = s.brn
       and public.client_seen(c.id, 'view');
  end if;
  return jsonb_build_object('ok', true, 'pay', pay, 'supplier', public.supplier_json(s, pay),
    'client', cl, 'match', mt,
    'form', case when f.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'id', f.id, 'purpose', f.purpose,
      'key', case when work and f.submitted_at is null and f.expires_at > now() then f.access_key end,
      'state', case when f.used_at is not null then 'used' when f.submitted_at is not null then 'submitted'
                    when f.expires_at <= now() then 'expired' else 'open' end,
      'created_at', f.created_at, 'expires_at', f.expires_at, 'submitted_at', f.submitted_at, 'used_at', f.used_at,
      'answers', case when f.submitted_at is not null then a end,
      'bank_changed', case when f.submitted_at is not null and f.used_at is null and s.bank_account is not null then
        (f.answers->>'payee_name') is distinct from s.payee_name or (f.answers->>'bank_name') is distinct from s.bank_name
        or (f.answers->>'bank_account') is distinct from s.bank_account end)) end);
end $$;
revoke all on function public.supplier_get(uuid) from public, anon;
grant execute on function public.supplier_get(uuid) to authenticated;

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
  word  constant jsonb := '{"code":"Supplier ID","name":"Name","kind":"Type","brn":"BRN","tin":"TIN","sst_no":"SST no.",
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

-- END OF A SUPPLIER'S DETAILS UPDATED BY LINK ------------------------------
select public.functions_tidy();
