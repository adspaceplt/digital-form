-- ===========================================================================
-- SUPPLIERS — the team's suppliers, each invited by a link to fill in their
-- own details, and letters issued to them from Documents (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18: "documents also need to issue to supplier";
-- the supplier sign-up form on Jotform "could jump into the fill in via
-- portal and data sync into it similar as client billing section"; "invite
-- only, with create link and set the supplier id before sending"; "nric only
-- for individuals"; "and 2 also can together")
--
-- WHAT IT ADDS
--   * `suppliers`: one row a supplier (its code, ASxxx, typed by the team;
--     what the form asks; Pending, Active or Inactive). RLS on, no policy,
--     no grant: read and written through the functions below.
--   * Two parts of Documents: `register.suppliers` (follows Documents: the
--     list, the links, the letters) and `register.supplier_pay` (granted, an
--     admin's by itself: the NRIC and the bank details, read at View and
--     written at Work). Without it, those fields are never sent.
--   * `supplier_forms`: one row a link (the supplier, its key, when it ends,
--     the answers once sent, taken in by whom). RLS on, no policy, no grant.
--     A link is open `details_form_days` (14), as a client's details form.
--   * `suppliers_list()`, `supplier_get(p_id)`, `supplier_create(p_code,
--     p_name)`, `supplier_link(p_id, p_reset)`, `supplier_save(p_id,
--     p_values, p_form)`, `supplier_set_status(p_id, p_status)`,
--     `supplier_delete(p_id, p_name)`: the team's, at the levels above.
--   * `supplier_form_read(p_key)` and `supplier_form_submit(p_key,
--     p_answers)` (anon): the supplier's page. The answers are checked as
--     the Jotform form checked them and wait for the team; they never write
--     the record by themselves. The team at Documents: Suppliers Work is
--     told (kind `supplier.details`).
--   * Documents: a family `supplier` (`doc_types`, `documents`), a
--     `documents.supplier_id`, a type Letter to Supplier (code GL),
--     `register_may('supplier', …)` answering `register.suppliers`, and
--     `issue_document` taking `p_supplier` (the reference
--     `ASL/{supplier code}/{YYMMDD}{NN}`); `document_reissue` keeps the
--     supplier.
--   * `activity_section()` files `supplier.*` under Documents.
--
-- ORDER: 2026-10-07-function-hygiene.sql again (its `open_to_anon` now names
-- the two form functions), this file, then the pages. A page served before
-- this file meets no Suppliers tab data ("This needs a database update").
-- Safe to run twice. Rollback: drop the functions below, the two tables,
-- `documents.supplier_id`; put back the family checks without `supplier`
-- (after deleting that family's documents and type), `register_may`,
-- `issue_document` (13 arguments), `document_reissue` and
-- `activity_section` from schema.sql's earlier sections.
-- ===========================================================================

create table if not exists public.suppliers (
  id             uuid primary key default gen_random_uuid(),
  code           text not null,
  name           text not null,
  kind           text check (kind in ('company', 'individual')),
  brn            text,
  nric           text,
  tin            text,
  sst_no         text,
  phone          text,
  address        text,
  contact_name   text,
  designation    text,
  email          text,
  mobile         text,
  payment_term   text check (payment_term in ('NET 7', 'NET 30', 'NET 45', 'NET 60')),
  currency       text not null default 'MYR' check (currency in ('MYR', 'SGD')),
  payee_name     text,
  bank_name      text,
  bank_account   text,
  finance_email  text,
  swift          text,
  bank_address   text,
  status         text not null default 'pending' check (status in ('pending', 'active', 'inactive')),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.team_members(id) on delete set null,
  updated_at     timestamptz not null default now(),
  approved_at    timestamptz,
  approved_by    uuid references public.team_members(id) on delete set null
);
create unique index if not exists suppliers_code_idx on public.suppliers (upper(code));
alter table public.suppliers enable row level security;
revoke all on table public.suppliers from public, anon, authenticated;

create table if not exists public.supplier_forms (
  id           uuid primary key default gen_random_uuid(),
  supplier_id  uuid not null references public.suppliers(id) on delete cascade,
  access_key   text not null unique,
  created_at   timestamptz not null default now(),
  created_by   uuid references public.team_members(id) on delete set null,
  expires_at   timestamptz not null,
  voided_at    timestamptz,
  submitted_at timestamptz,
  answers      jsonb,
  used_at      timestamptz,
  used_by      uuid references public.team_members(id) on delete set null
);
create index if not exists supplier_forms_supplier_idx on public.supplier_forms (supplier_id, created_at desc);
alter table public.supplier_forms enable row level security;
revoke all on table public.supplier_forms from public, anon, authenticated;

/* Documents: a supplier's letters. */
alter table public.documents add column if not exists supplier_id uuid references public.suppliers(id) on delete set null;
create index if not exists documents_supplier_idx on public.documents (supplier_id);
alter table public.documents drop constraint if exists documents_family_check;
alter table public.documents add constraint documents_family_check
  check (family in ('quote_cover', 'client', 'hr', 'other', 'supplier'));
alter table public.doc_types drop constraint if exists doc_types_family_check;
alter table public.doc_types add constraint doc_types_family_check
  check (family in ('quote_cover', 'client', 'hr', 'supplier'));
insert into public.doc_types (id, family, code, name, title, salutation, closing, body_en, signed, position)
select 'supplier_letter', 'supplier', 'GL', 'Letter to Supplier', '', 'Dear Sir/Madam,', 'Yours sincerely,', '', true, 60
 where not exists (select 1 from public.doc_types t where t.id = 'supplier_letter');

/* A notice about a supplier opens it. */
alter table public.ops_notifications add column if not exists supplier_id uuid references public.suppliers(id) on delete cascade;

create or replace function public.register_may(p_family text, p_level text)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when p_family = 'hr'       then public.allowed('register.hr', p_level)
    when p_family = 'other'    then public.allowed('register.documents', p_level)
    when p_family = 'supplier' then public.allowed('register.suppliers', p_level)
    else public.allowed('register.documents', p_level) or public.allowed('clients.documents', p_level)
  end
$$;
grant execute on function public.register_may(text, text) to authenticated;

/* One check of a supplier's answers, the form's and the team's alike: the
   value cleaned, else an error naming the field. NRIC is asked of an
   individual alone, BRN of a company (an individual's checked where given). */
create or replace function public.supplier_values_check(p jsonb, p_pay boolean)
returns jsonb
language plpgsql immutable set search_path = public as $$
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
  if (kind = 'company' or v <> '') and v !~ '^[0-9]{12}$' then return jsonb_build_object('error', 'bad-brn'); end if;
  o := o || jsonb_build_object('brn', nullif(v, ''));
  v := upper(regexp_replace(coalesce(p->>'tin', ''), '\s+', '', 'g'));
  if v !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('error', 'bad-tin'); end if;
  o := o || jsonb_build_object('tin', v);
  v := upper(regexp_replace(coalesce(p->>'sst_no', ''), '\s+', '', 'g'));
  if v <> '' and v !~ '^[A-Z][0-9]{2}-[0-9]{4}-[0-9]{8}$' then return jsonb_build_object('error', 'bad-sst_no'); end if;
  o := o || jsonb_build_object('sst_no', nullif(v, ''));
  foreach k in array array['phone', 'mobile'] loop
    v := regexp_replace(coalesce(p->>k, ''), '[^0-9+]', '', 'g');
    if length(regexp_replace(v, '[^0-9]', '', 'g')) < 8 or length(regexp_replace(v, '[^0-9]', '', 'g')) > 15 then
      return jsonb_build_object('error', 'bad-' || k);
    end if;
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
  if v not in ('NET 7', 'NET 30', 'NET 45', 'NET 60') then return jsonb_build_object('error', 'bad-payment_term'); end if;
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

/* A supplier as the team reads it: the bank details only for Documents:
   Supplier payment at View. */
create or replace function public.supplier_json(s public.suppliers, p_pay boolean)
returns jsonb
language sql stable set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', s.id, 'code', s.code, 'name', s.name, 'kind', s.kind, 'brn', s.brn, 'tin', s.tin, 'sst_no', s.sst_no,
    'phone', s.phone, 'address', s.address, 'contact_name', s.contact_name, 'designation', s.designation,
    'email', s.email, 'mobile', s.mobile, 'payment_term', s.payment_term, 'currency', s.currency,
    'finance_email', s.finance_email, 'status', s.status, 'created_at', s.created_at, 'updated_at', s.updated_at,
    'approved_at', s.approved_at,
    'approved_by', (select m.name from public.team_members m where m.id = s.approved_by))
    || case when p_pay then jsonb_strip_nulls(jsonb_build_object(
      'nric', s.nric, 'payee_name', s.payee_name, 'bank_name', s.bank_name, 'bank_account', s.bank_account,
      'swift', s.swift, 'bank_address', s.bank_address)) else '{}'::jsonb end)
$$;
revoke all on function public.supplier_json(public.suppliers, boolean) from public, anon, authenticated;

/* The list: every supplier, and whether its answers wait. */
create or replace function public.suppliers_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('register.suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(public.supplier_json(s, false) || jsonb_build_object('waiting', exists (
             select 1 from public.supplier_forms f
              where f.supplier_id = s.id and f.voided_at is null and f.submitted_at is not null and f.used_at is null))
           order by upper(s.code))
      from public.suppliers s), '[]'::jsonb));
end $$;
revoke all on function public.suppliers_list() from public, anon;
grant execute on function public.suppliers_list() to authenticated;

/* One supplier, its latest link and the answers sent on it. */
create or replace function public.supplier_get(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s   public.suppliers;
  f   public.supplier_forms;
  pay boolean := public.ops_granted('register.supplier_pay', 'view');
  work boolean := public.allowed('register.suppliers', 'work');
  a   jsonb;
begin
  if (public.ops_me()).id is null or not public.allowed('register.suppliers', 'view') then
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
  return jsonb_build_object('ok', true, 'pay', pay, 'supplier', public.supplier_json(s, pay),
    'form', case when f.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'id', f.id,
      'key', case when work and f.submitted_at is null and f.expires_at > now() then f.access_key end,
      'state', case when f.used_at is not null then 'used' when f.submitted_at is not null then 'submitted'
                    when f.expires_at <= now() then 'expired' else 'open' end,
      'created_at', f.created_at, 'expires_at', f.expires_at, 'submitted_at', f.submitted_at, 'used_at', f.used_at,
      'answers', case when f.submitted_at is not null then a end)) end);
end $$;
revoke all on function public.supplier_get(uuid) from public, anon;
grant execute on function public.supplier_get(uuid) to authenticated;

/* A new link for a supplier, or the one still open. */
create or replace function public.supplier_link(p_id uuid, p_reset boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  f     public.supplier_forms;
  v_key text;
  v_days int;
begin
  if me.id is null or not public.allowed('register.suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into f from public.supplier_forms x
   where x.supplier_id = p_id and x.voided_at is null and x.submitted_at is null and x.expires_at > now()
   order by x.created_at desc limit 1;
  if f.id is not null and not coalesce(p_reset, false) then
    return jsonb_build_object('ok', true, 'id', f.id, 'key', f.access_key, 'expires_at', f.expires_at);
  end if;
  update public.supplier_forms x set voided_at = now()
   where x.supplier_id = p_id and x.voided_at is null and x.submitted_at is null;
  loop
    v_key := public.new_link_key();
    exit when not exists (select 1 from public.supplier_forms x where x.access_key = v_key);
  end loop;
  v_days := coalesce(public.app_setting('details_form_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 14)::int;
  insert into public.supplier_forms (supplier_id, access_key, created_by, expires_at)
  values (p_id, v_key, me.id, now() + make_interval(days => v_days))
  returning * into f;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', s.name,
          s.code || ' · ' || case when coalesce(p_reset, false) then 'Details form link reset' else 'Details form link created' end);
  return jsonb_build_object('ok', true, 'id', f.id, 'key', f.access_key, 'expires_at', f.expires_at);
end $$;
revoke all on function public.supplier_link(uuid, boolean) from public, anon;
grant execute on function public.supplier_link(uuid, boolean) to authenticated;

/* A supplier named and numbered by the team, Pending, with its link. */
create or replace function public.supplier_create(p_code text, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g'));
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_id   uuid;
  r      jsonb;
begin
  if me.id is null or not public.allowed('register.suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_code !~ '^[A-Z0-9]{2,12}$' then return jsonb_build_object('error', 'bad-code'); end if;
  if length(v_name) < 2 or length(v_name) > 160 then return jsonb_build_object('error', 'bad-name'); end if;
  if exists (select 1 from public.suppliers s where upper(s.code) = v_code) then
    return jsonb_build_object('error', 'code-taken', 'name', (select s.name from public.suppliers s where upper(s.code) = v_code));
  end if;
  insert into public.suppliers (code, name, created_by) values (v_code, v_name, me.id) returning id into v_id;
  insert into public.activity_log (actor, action, subject, detail) values (me.name, 'supplier.added', v_name, v_code);
  r := public.supplier_link(v_id, false);
  return jsonb_build_object('ok', true, 'id', v_id, 'key', r->>'key', 'expires_at', r->'expires_at');
end $$;
revoke all on function public.supplier_create(text, text) from public, anon;
grant execute on function public.supplier_create(text, text) to authenticated;

/* The team's own Save: the details, the code and name, the bank details at
   Documents: Supplier payment Work alone; a form's answers taken in with it. */
create or replace function public.supplier_save(p_id uuid, p_values jsonb, p_form uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  pay   boolean := public.ops_granted('register.supplier_pay', 'work');
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
begin
  if me.id is null or not public.allowed('register.suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
    updated_at = now()
   where x.id = p_id;
  if p_form is not null then
    update public.supplier_forms f set used_at = coalesce(f.used_at, now()), used_by = coalesce(f.used_by, me.id)
     where f.id = p_form and f.supplier_id = p_id and f.submitted_at is not null;
  end if;
  if array_length(moved, 1) is not null then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'supplier.edited', v->>'name', v_code || ' · ' || array_to_string(moved, ' · ') ||
            case when p_form is not null then ' · from the details form' else '' end);
  end if;
  return jsonb_build_object('ok', true, 'supplier',
    public.supplier_json((select x from public.suppliers x where x.id = p_id), public.ops_granted('register.supplier_pay', 'view')));
end $$;
revoke all on function public.supplier_save(uuid, jsonb, uuid) from public, anon;
grant execute on function public.supplier_save(uuid, jsonb, uuid) to authenticated;

/* Approve (Pending to Active, the details complete), Set inactive and
   Set active. */
create or replace function public.supplier_set_status(p_id uuid, p_status text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s  public.suppliers;
begin
  if me.id is null or not public.allowed('register.suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('active', 'inactive') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if s.status = p_status then return jsonb_build_object('ok', true, 'status', s.status); end if;
  if p_status = 'active' and (s.kind is null or s.tin is null or s.address is null or s.email is null
      or s.payment_term is null or s.bank_account is null) then
    return jsonb_build_object('error', 'incomplete');
  end if;
  update public.suppliers x set status = p_status, updated_at = now(),
    approved_at = case when p_status = 'active' and x.approved_at is null then now() else x.approved_at end,
    approved_by = case when p_status = 'active' and x.approved_at is null then me.id else x.approved_by end
   where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, case when s.status = 'pending' then 'supplier.approved' else 'supplier.edited' end, s.name,
          s.code || ' · ' || initcap(s.status) || ' → ' || initcap(p_status));
  return jsonb_build_object('ok', true, 'status', p_status);
end $$;
revoke all on function public.supplier_set_status(uuid, text) from public, anon;
grant execute on function public.supplier_set_status(uuid, text) to authenticated;

/* Delete, at Manage, the name typed back. Letters issued keep their words. */
create or replace function public.supplier_delete(p_id uuid, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s  public.suppliers;
begin
  if me.id is null or not public.allowed('register.suppliers', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(btrim(s.name)) then return jsonb_build_object('error', 'bad-name'); end if;
  delete from public.suppliers x where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail) values (me.name, 'supplier.deleted', s.name, s.code);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_delete(uuid, text) from public, anon;
grant execute on function public.supplier_delete(uuid, text) to authenticated;

/* What the supplier's page may know before it is filled in. */
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
  return jsonb_build_object('ok', true, 'name', s.name, 'code', s.code, 'expires_at', f.expires_at);
end $$;
revoke all on function public.supplier_form_read(text) from public;
grant execute on function public.supplier_form_read(text) to anon, authenticated;

/* The supplier's answers, once, checked as the form checks them. */
create or replace function public.supplier_form_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f public.supplier_forms;
  s public.suppliers;
  v jsonb;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into f from public.supplier_forms x where x.access_key = p_key and x.voided_at is null for update;
  if f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  if coalesce(p_answers->>'authorise', '') <> 'true' then return jsonb_build_object('error', 'bad-authorise'); end if;
  v := public.supplier_values_check(coalesce(p_answers, '{}'::jsonb), true);
  if v ? 'error' then return v; end if;
  update public.supplier_forms x set submitted_at = now(), answers = jsonb_strip_nulls(v) where x.id = f.id;
  select * into s from public.suppliers x where x.id = f.supplier_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (v->>'contact_name', 'supplier.edited', s.name, s.code || ' · Details received on the details form');
  insert into public.ops_notifications (team_member_id, kind, title, body, supplier_id, dedupe_key)
  select m.id, 'supplier.details', 'Supplier details received · ' || s.name,
         'From ' || (v->>'contact_name') || '. Review them on the supplier.',
         s.id, 'supplier.details:' || f.id || ':' || m.id
    from public.team_members m
   where m.active and not coalesce(m.system, false)
     and (m.is_admin or m.role = 'admin'
          or public.level_rank(coalesce(m.access ->> 'register.suppliers', m.access ->> 'register')) >= 2)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_form_submit(text, jsonb) from public;
grant execute on function public.supplier_form_submit(text, jsonb) to anon, authenticated;

/* Issue: a supplier's letter names its supplier and is numbered
   ASL/{supplier code}/{YYMMDD}{NN}. The signature grows by p_supplier, so
   the old one goes first. */
drop function if exists public.issue_document(text, uuid, uuid, text, date, text, jsonb, jsonb, jsonb, text[], text, text, boolean);
create or replace function public.issue_document(
  p_type      text,
  p_client    uuid,
  p_member    uuid,
  p_serial    text,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_idem      text,
  p_salutation text default null,
  p_signed    boolean default null,
  p_supplier  uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who     text := lower(auth.jwt() ->> 'email');
  t       public.doc_types%rowtype;
  cl      public.clients%rowtype;
  mb      public.team_members%rowtype;
  sp      public.suppliers%rowtype;
  me      public.team_members%rowtype;
  v_old   public.documents%rowtype;
  v_serial text;
  v_base  text;
  v_n     int;
  v_id    uuid;
  v_langs text[];
  v_signed boolean;
begin
  select * into t from public.doc_types where id = p_type and active;
  if t.id is null then return jsonb_build_object('error', 'no-type'); end if;
  if not public.register_may(t.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;

  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;

  if t.family in ('quote_cover', 'client') then
    if p_client is null then return jsonb_build_object('error', 'no-client'); end if;
    select * into cl from public.clients where id = p_client;
    if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;
  end if;
  if t.family = 'hr' then
    if p_member is null then return jsonb_build_object('error', 'no-member'); end if;
    select * into mb from public.team_members where id = p_member;
    if mb.id is null then return jsonb_build_object('error', 'no-member'); end if;
    if coalesce(btrim(mb.staff_code), '') = '' then return jsonb_build_object('error', 'no-staff-code'); end if;
  end if;
  if t.family = 'supplier' then
    if p_supplier is null then return jsonb_build_object('error', 'no-supplier'); end if;
    select * into sp from public.suppliers where id = p_supplier;
    if sp.id is null then return jsonb_build_object('error', 'no-supplier'); end if;
  end if;

  -- Whether the letter leaves space to be signed is the sheet's tick
  -- (2026-10-01), else the type's own setting. A signed letter is signed by
  -- a person, never by a permission; an unsigned one may still name who
  -- issued it, held to the same test.
  v_signed := coalesce(p_signed, t.signed);
  if coalesce(btrim(p_signatory ->> 'name'), '') <> '' and not public.issuer_name_ok(p_signatory ->> 'name') then
    return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
  end if;
  if v_signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;

  v_serial := nullif(btrim(coalesce(p_serial, '')), '');
  if v_serial is null then
    if t.family = 'quote_cover' then return jsonb_build_object('error', 'serial-required'); end if;
    if t.family in ('client', 'supplier') then
      if t.family = 'client' then
        if coalesce(btrim(cl.client_code), '') = '' then return jsonb_build_object('error', 'no-client-code'); end if;
        v_base := 'ACL/' || upper(btrim(cl.client_code));
      else
        v_base := 'ASL/' || upper(btrim(sp.code));
      end if;
      v_base := v_base || '/' || to_char(coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date), 'YYMMDD');
      -- Two issuers on one client (or supplier) and day wait for each other
      -- here, so the second never reads the first one's number as free.
      perform pg_advisory_xact_lock(hashtext('acl:' || v_base));
      v_n := 1;
      loop
        v_serial := v_base || case when v_n < 10 then '0' else '' end || v_n;
        exit when not public.serial_taken(v_serial);
        v_n := v_n + 1;
        if v_n > 999 then return jsonb_build_object('error', 'no-serial'); end if;
      end loop;
    else
      v_base := 'ADHR/' || upper(mb.staff_code) || '/' || coalesce(t.code, 'GL') ||
                to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');
      v_serial := v_base; v_n := 1;
      while public.serial_taken(v_serial) loop
        v_n := v_n + 1; v_serial := v_base || '-' || v_n;
      end loop;
    end if;
  else
    if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
    if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  end if;

  v_langs := coalesce(p_languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;

  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, supplier_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key)
  values
    (t.id, t.family, t.name, v_serial,
     case when t.family in ('hr', 'supplier') then null else p_client end,
     case when t.family = 'hr' then p_member else null end,
     case when t.family = 'supplier' then p_supplier else null end,
     coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), t.title),
     coalesce(nullif(btrim(p_salutation), ''), t.salutation), t.closing,
     coalesce(p_recipient, '{}'::jsonb), coalesce(p_body, '{}'::jsonb), v_langs,
     case when coalesce(btrim(p_signatory ->> 'name'), '') <> '' then p_signatory else null end, v_signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''))
  returning id into v_id;

  -- The record is told an HR letter was issued and nothing about whom: the
  -- Activity record is read by more people than HR is.
  if t.family = 'hr' then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', 'HR', t.name);
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', case when t.family = 'supplier' then sp.name else cl.name end, v_serial || ' · ' || t.name);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
      end if;
    end if;
    return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.issue_document(text, uuid, uuid, text, date, text, jsonb, jsonb, jsonb, text[], text, text, boolean, uuid) to authenticated;

/* A reissue keeps the supplier its letter was addressed to. */
create or replace function public.document_reissue(
  p_doc       uuid,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_salutation text,
  p_idem      text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  d      public.documents%rowtype;
  v_old  public.documents%rowtype;
  me     public.team_members%rowtype;
  cl     public.clients%rowtype;
  v_id   uuid;
  v_langs text[];
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'portal' then return jsonb_build_object('error', 'not-portal'); end if;
  if not public.register_may(d.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;
  if exists (select 1 from public.documents
              where upper(serial) = upper(d.serial) and voided_at is null and id <> d.id) then
    return jsonb_build_object('error', 'not-current');
  end if;
  if d.signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;
  v_langs := coalesce(p_languages, d.languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  if d.voided_at is null then
    update public.documents set voided_at = now(), voided_by = who, void_reason = 'Reissued' where id = d.id;
  end if;
  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, supplier_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key, replaces)
  values
    (d.type_id, d.family, d.kind, d.serial, d.client_id, d.member_id, d.supplier_id,
     coalesce(p_issued_at, d.issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), d.title),
     coalesce(nullif(btrim(p_salutation), ''), d.salutation), d.closing,
     coalesce(p_recipient, d.recipient), coalesce(p_body, d.body), v_langs,
     case when d.signed then p_signatory else null end, d.signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''), d.id)
  returning id into v_id;

  if d.client_id is not null then select * into cl from public.clients where id = d.client_id; end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.reissued',
          case when d.family = 'hr' then 'HR' else coalesce(cl.name, (select s.name from public.suppliers s where s.id = d.supplier_id), d.recipient ->> 'name', '') end,
          case when d.family = 'hr' then d.kind else d.serial || ' · ' || d.kind end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', d.serial);
exception
  when unique_violation then
    return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.document_reissue(uuid, date, text, jsonb, jsonb, jsonb, text[], text, text) to authenticated;

/* A supplier's steps are filed under Documents. */
create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.file_deleted', 'campaign.file_hidden',
                    'campaign.file_shown', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.whatsapp', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.quotation', 'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_deleted', 'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('wa.sent', 'wa.template') then 'whatsapp'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited', 'supplier.added', 'supplier.approved',
                    'supplier.deleted', 'supplier.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'review.unconfirmed',
                    'set.created', 'set.deleted', 'set.month', 'set.published', 'set.renamed',
                    'set.task_linked', 'set.task_unlinked',
                    'set.withdrawn') then 'review'
    when action in ('script.approved', 'script.changes', 'script.created', 'script.deleted',
                    'script.link', 'script.saved', 'script.shared', 'script.shot',
                    'script.unshared') then 'scripts'
    when action in ('handbook.added', 'handbook.archived', 'handbook.deleted',
                    'handbook.edited', 'handbook.restored', 'handbook.version') then 'handbook'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on', 'service.published') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

-- END OF SUPPLIERS -----------------------------------------------------------
select public.functions_tidy();
