-- ===========================================================================
-- ONE REQUEST REFERENCE FOR EVERY PUBLIC SUBMISSION (2026-11-26)
-- ===========================================================================
-- WHY: the user, 2026-11-26 ("ok"): everything a person sends the team from
-- a public page takes one reference, ADP/REQ{YYMM}-{AAA}, as a website
-- quotation request already does, so a code is unique across every kind
-- within a month and the team finds the record by it.
--
-- WHAT IT CHANGES
--   * `client_detail_forms`, `supplier_forms` and `hiring_candidates` take
--     `request_ref` (unique where set, the reference's shape checked).
--   * `public_request_ref(at)`: the one generator (the `request` row of
--     `id_formats`: three to six consonants from a strong source, a short
--     deny list, drawn again on a clash with any table that holds one,
--     one draw at a time); `quote_request_ref` answers through it, so a
--     website quotation request keeps working unchanged.
--   * A trigger stamps the reference: a details or supplier form when it is
--     submitted, a candidate when the application is added.
--   * `client_details_submit`, `supplier_form_submit`: answer the reference
--     and name it in the Activity record; `client_details_read`,
--     `supplier_form_read`: a form already sent answers its reference.
--   * `client_details_state`, `supplier_get`, `hiring_row`: the record's
--     reference for the team; `careers_read`: the candidate's;
--     `hiring_add`: the candidate's history names it.
--   * `request_ref_find(q)`: console search by the reference or its
--     letters, a client's at Billing, a supplier's at Suppliers (a
--     candidate's is matched in `hiring_list`, through `hiring_row`).
--   * `id_format_set`: the Activity record says Request number, filed under
--     Request and quotation numbers.
--
-- ORDER: this file, then the pages (an open tab reads no reference and
-- draws none). Safe to run twice. No backfill: a submission made before
-- this band keeps no reference. Holds no drop or delete.
-- ROLLBACK: restate each function's last definition before this band
-- (QUOTATIONS CONFIRMED BEFORE THEY GO for `quote_request_ref` and
-- `id_format_set`; the bands each other function was last restated in);
-- `drop trigger client_detail_forms_request_ref`,
-- `supplier_forms_request_ref`, `hiring_candidates_request_ref`; the
-- columns may stay.
-- ===========================================================================

-- ONE REQUEST REFERENCE FOR EVERY PUBLIC SUBMISSION ---------------------------

/* The reference a public submission takes: ADP/{prefix}{YYMM}-{letters},
   the `request` row of `id_formats`, shared with a website quotation
   request, so a code is unique across every kind within a month. */
alter table public.client_detail_forms add column if not exists request_ref text
  check (request_ref is null or request_ref ~ '^ADP/[A-Z]{1,6}[0-9]{4}-[A-Z]{3,6}$');
alter table public.supplier_forms add column if not exists request_ref text
  check (request_ref is null or request_ref ~ '^ADP/[A-Z]{1,6}[0-9]{4}-[A-Z]{3,6}$');
alter table public.hiring_candidates add column if not exists request_ref text
  check (request_ref is null or request_ref ~ '^ADP/[A-Z]{1,6}[0-9]{4}-[A-Z]{3,6}$');
create unique index if not exists client_detail_forms_request_ref_key on public.client_detail_forms (request_ref) where request_ref is not null;
create unique index if not exists supplier_forms_request_ref_key on public.supplier_forms (request_ref) where request_ref is not null;
create unique index if not exists hiring_candidates_request_ref_key on public.hiring_candidates (request_ref) where request_ref is not null;

/* One generator for every public submission: letters drawn at random from
   consonants alone, so it never spells a word nor tells how many came in;
   a clash with any table holding one draws again. */
create or replace function public.public_request_ref(p_at timestamptz)
returns text language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := 'BCDFGHJKLMNPQRSTVWXZ';
  deny constant text[] := array['FCK', 'FKN', 'SHT', 'KKK', 'XXX', 'WTF', 'STD', 'NGR', 'PKM', 'BBW', 'DCK', 'CNT', 'PSS', 'TTS'];
  f public.id_formats;
  v_n int; v_out text; v_ref text; v_bytes bytea; v_i int; v_b int; v_try int := 0;
begin
  -- One draw at a time until the caller's transaction ends, so two
  -- submissions in the same moment never take one number.
  perform pg_advisory_xact_lock(hashtext('public_request_ref'));
  select * into f from public.id_formats where kind = 'request';
  v_n := greatest(3, least(6, coalesce(f.width, 3)));
  loop
    v_try := v_try + 1;
    if v_try > 200 then raise exception 'public_request_ref: no free number'; end if;
    v_out := '';
    v_bytes := gen_random_bytes(32);
    for v_i in 0..31 loop
      v_b := get_byte(v_bytes, v_i);
      if v_b < 240 and length(v_out) < v_n then v_out := v_out || substr(alphabet, 1 + (v_b % 20), 1); end if;
    end loop;
    continue when length(v_out) < v_n or v_out = any (deny);
    v_ref := 'ADP/' || coalesce(nullif(f.prefix, ''), 'REQ') || to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'YYMM') || '-' || v_out;
    exit when not exists (select 1 from public.quotations q where q.ref = v_ref or q.request_ref = v_ref)
          and not exists (select 1 from public.quotation_refs_kept k where k.ref = v_ref)
          and not exists (select 1 from public.client_detail_forms d where d.request_ref = v_ref)
          and not exists (select 1 from public.supplier_forms s where s.request_ref = v_ref)
          and not exists (select 1 from public.hiring_candidates h where h.request_ref = v_ref);
  end loop;
  return v_ref;
end $$;
revoke all on function public.public_request_ref(timestamptz) from public, anon, authenticated;

/* A website quotation request takes its number from the one generator. */
create or replace function public.quote_request_ref(p_at timestamptz)
returns text language sql volatile set search_path = public as $$
  select public.public_request_ref(p_at);
$$;
revoke all on function public.quote_request_ref(timestamptz) from public, anon, authenticated;

/* Stamped by the database, never by a page: a form when it is submitted,
   an application when it is added. */
create or replace function public.request_ref_on_submit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.submitted_at is not null and old.submitted_at is null and new.request_ref is null then
    new.request_ref := public.public_request_ref(new.submitted_at);
  end if;
  return new;
end $$;
revoke all on function public.request_ref_on_submit() from public, anon, authenticated;

create or replace function public.request_ref_on_add()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.request_ref is null then
    new.request_ref := public.public_request_ref(coalesce(new.created_at, now()));
  end if;
  return new;
end $$;
revoke all on function public.request_ref_on_add() from public, anon, authenticated;

drop trigger if exists client_detail_forms_request_ref on public.client_detail_forms;
create trigger client_detail_forms_request_ref before update of submitted_at on public.client_detail_forms
  for each row execute function public.request_ref_on_submit();
drop trigger if exists supplier_forms_request_ref on public.supplier_forms;
create trigger supplier_forms_request_ref before update of submitted_at on public.supplier_forms
  for each row execute function public.request_ref_on_submit();
drop trigger if exists hiring_candidates_request_ref on public.hiring_candidates;
create trigger hiring_candidates_request_ref before insert on public.hiring_candidates
  for each row execute function public.request_ref_on_add();

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
  if v_brn !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-company_no'); end if;
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
                   or lower(btrim(coalesce(v_cl.owner, ''))) = lower(btrim(coalesce(m.name, '')))
                   or v_cl.sales_by = m.id)))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true, 'request_ref', v_ref);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

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
  if nullif(btrim(coalesce(v_cl.owner, '')), '') is not null then
    select * into m from public.team_members x
     where x.active and not coalesce(x.system, false) and x.removed_at is null and x.name = v_cl.owner
     limit 1;
  end if;
  return jsonb_build_object('ok', true, 'brand', v_cl.name, 'expires_at', v_f.expires_at,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end);
end $$;
revoke all on function public.client_details_read(text) from public;
grant execute on function public.client_details_read(text) to anon, authenticated;

create or replace function public.client_details_state(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  v_f  public.client_detail_forms;
  work boolean;
begin
  if me.id is null or not public.allowed('clients.billing', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  work := public.allowed('clients.billing', 'work');
  select * into v_f from public.client_detail_forms f
   where f.client_id = p_client and f.voided_at is null
   order by f.created_at desc limit 1;
  if v_f.id is null then return jsonb_build_object('ok', true); end if;
  return jsonb_build_object('ok', true, 'form', jsonb_strip_nulls(jsonb_build_object(
    'id', v_f.id,
    'key', case when work and v_f.submitted_at is null and v_f.expires_at > now() then v_f.access_key end,
    'state', case when v_f.used_at is not null then 'used' when v_f.submitted_at is not null then 'submitted'
                  when v_f.expires_at <= now() then 'expired' else 'open' end,
    'created_at', v_f.created_at, 'expires_at', v_f.expires_at,
    'submitted_at', v_f.submitted_at, 'used_at', v_f.used_at, 'request_ref', v_f.request_ref,
    'answers', case when v_f.submitted_at is not null then v_f.answers end)));
end $$;
revoke all on function public.client_details_state(uuid) from public, anon;
grant execute on function public.client_details_state(uuid) to authenticated;

create or replace function public.supplier_form_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f public.supplier_forms;
  s public.suppliers;
  v jsonb;
  a jsonb := coalesce(p_answers, '{}'::jsonb);
  v_ref text;
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
  update public.supplier_forms x set submitted_at = now(), answers = jsonb_strip_nulls(v) where x.id = f.id
  returning x.request_ref into v_ref;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Supplier form', 'supplier.edited', coalesce(s.name, v->>'name'), s.code || ' · ' ||
          case when f.purpose = 'update' then 'Details update received on the update link' else 'Details received on the details form' end ||
          coalesce(' from ' || nullif(btrim(v->>'contact_name'), ''), '') || coalesce(' · ' || v_ref, ''));
  insert into public.ops_notifications (team_member_id, kind, title, body, supplier_id, dedupe_key)
  select m.id, 'supplier.details',
         case when f.purpose = 'update' then 'Supplier details update received · ' else 'Supplier details received · ' end || coalesce(s.name, v->>'name'),
         'From ' || (v->>'contact_name') || '. Review them on the supplier.',
         s.id, 'supplier.details:' || f.id || ':' || m.id
    from public.team_members m
   where m.active
     and (m.is_admin or m.role = 'admin'
          or public.level_rank(m.access ->> 'suppliers') >= 2)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true, 'request_ref', v_ref);
end $$;
revoke all on function public.supplier_form_submit(text, jsonb) from public;
grant execute on function public.supplier_form_submit(text, jsonb) to anon, authenticated;

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
  if f.submitted_at is not null then return jsonb_build_object('error', 'submitted', 'request_ref', f.request_ref); end if;
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
      'created_at', f.created_at, 'expires_at', f.expires_at, 'submitted_at', f.submitted_at, 'used_at', f.used_at, 'request_ref', f.request_ref,
      'answers', case when f.submitted_at is not null then a end,
      'bank_changed', case when f.submitted_at is not null and f.used_at is null and s.bank_account is not null then
        (f.answers->>'payee_name') is distinct from s.payee_name or (f.answers->>'bank_name') is distinct from s.bank_name
        or (f.answers->>'bank_account') is distinct from s.bank_account end)) end);
end $$;
revoke all on function public.supplier_get(uuid) from public, anon;
grant execute on function public.supplier_get(uuid) to authenticated;

create or replace function public.hiring_row(c public.hiring_candidates, p_role text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', c.id, 'name', c.name, 'position', c.position, 'source', c.source, 'stage', c.stage,
    'created_at', c.created_at, 'request_ref', c.request_ref, 'last_step_at', c.last_step_at, 'removed_at', c.removed_at, 'role', p_role,
    'owners', coalesce((select jsonb_agg(t.name order by t.name) from public.hiring_people p
                         join public.team_members t on t.id = p.team_member_id
                        where p.candidate_id = c.id and p.role = 'owner'), '[]'::jsonb))
    || coalesce((select jsonb_build_object('step', s->>'step', 'step_at', s->'at') from public.hiring_step(c.id) s
                  where s is not null), '{}'::jsonb);
$$;
revoke all on function public.hiring_row(public.hiring_candidates, text) from public, anon, authenticated;

create or replace function public.hiring_add(p_values jsonb, p_idem text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v jsonb;
  c public.hiring_candidates;
  v_dup public.hiring_candidates;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_idem, '') !~ '^[A-Za-z0-9-]{8,64}$' then return jsonb_build_object('error', 'bad-request'); end if;
  perform pg_advisory_xact_lock(hashtext('hiring_add:' || p_idem));
  select * into c from public.hiring_candidates where idem = p_idem;
  if c.id is not null then return jsonb_build_object('ok', true, 'id', c.id, 'again', true); end if;
  v := public.hiring_values(p_values || jsonb_build_object(
    'name', coalesce(p_values->>'name', ''), 'email', coalesce(p_values->>'email', ''),
    'position', coalesce(p_values->>'position', ''), 'source', coalesce(p_values->>'source', '')));
  if v ? 'error' then return v; end if;
  select * into v_dup from public.hiring_candidates
   where lower(email) = v->>'email' and removed_at is null and stage not in ('hired', 'closed') limit 1;
  if v_dup.id is not null then
    return jsonb_build_object('error', 'taken', 'id', v_dup.id, 'name', v_dup.name);
  end if;
  insert into public.hiring_candidates (name, email, phone, position, source, cv_url, note, link_key, idem, created_by)
  values (v->>'name', v->>'email', v->>'phone', v->>'position', v->>'source', v->>'cv_url', v->>'note',
          public.new_link_key(), p_idem, me.id)
  returning * into c;
  insert into public.hiring_people (candidate_id, team_member_id, role, added_by) values (c.id, me.id, 'owner', me.id);
  perform public.hiring_log(c.id, 'candidate.added', c.position || ' · ' || initcap(replace(c.source, '_', '-')) || coalesce(' · ' || c.request_ref, ''));
  return jsonb_build_object('ok', true, 'id', c.id);
end $$;
grant execute on function public.hiring_add(jsonb, text) to authenticated;

create or replace function public.careers_read(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_contact text := public.mail_sender('careers')->>'reply_to';
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_state text;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found', 'contact', v_contact); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null;
  if c.id is null then return jsonb_build_object('error', 'not_found', 'contact', v_contact); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() and not (c.stage = 'pool' and c.pool_consent = 'yes') then
    return jsonb_build_object('error', 'expired', 'contact', v_contact);
  end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state <> 'replaced'
   order by invited_at desc limit 1;
  v_state := case when i.id is null then null else public.hiring_interview_state(i) end;
  return jsonb_build_object('ok', true, 'contact', v_contact, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage = 'new' or (c.stage = 'pool' and c.outcome is null) then 'received' else c.stage end, 'received_at', c.created_at,
    'request_ref', c.request_ref,
    'pool_declined', case when c.outcome = 'pool' and c.pool_consent = 'no' then true end,
    'pool', case when c.stage = 'pool' and c.outcome = 'pool' then jsonb_strip_nulls(jsonb_build_object('consent', c.pool_consent,
      'until', c.pool_until, 'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12))) end,
    'interview', case when i.id is null or c.stage in ('pool', 'closed') then null
      /* Cancelled: the state alone, never its time or link (2026-11-20). */
      when i.state = 'cancelled' then case when c.stage in ('new', 'invited', 'interview') and c.outcome is null
        then jsonb_build_object('state', 'cancelled') end
      /* A time chosen, not yet confirmed: the time, its length and online or
         at the office alone, never the note or a link (2026-11-22). */
      when v_state = 'picked' then jsonb_strip_nulls(jsonb_build_object('state', v_state, 'minutes', i.minutes, 'mode', i.mode,
        'at', i.slots[i.picked]))
      else jsonb_strip_nulls(jsonb_build_object(
      'state', v_state, 'slots', case when v_state = 'invited' then to_jsonb(i.slots) end, 'minutes', i.minutes,
      'mode', i.mode, 'note', i.note, 'at', case when i.picked is not null then i.slots[i.picked] end,
      'reply_by', case when v_state = 'invited' then i.reply_by end,
      'link', case when i.state = 'confirmed' and i.held_at is null then i.meeting_link end,
      /* Moved by the team (2026-11-22): the time it held before, while the
         interview is confirmed and not yet held. */
      'was', case when i.state = 'confirmed' and i.held_at is null then i.moved_from end,
      'held', case when i.held_at is not null then true end,
      'decide_by', case when i.held_at is not null and c.outcome is null then c.decide_by end,
      /* Past it with no decision: the careers mailbox to contact (2026-11-20). */
      'contact', case when i.held_at is not null and c.outcome is null and c.decide_by <= now() then v_contact end)) end,
    'docs', case when c.stage in ('offer', 'hired') then coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', d.id, 'kind', d.kind,
        'serial', d.serial, 'state', case when d.state = 'sent' and d.reply_by <= now() then 'expired' else d.state end,
        'sent_at', d.sent_at, 'reply_by', d.reply_by, 'signed_at', d.signed_at)) order by d.sent_at)
      from public.hiring_docs d where d.candidate_id = c.id and d.state in ('sent', 'signed', 'confirmed', 'declined')), '[]'::jsonb) end);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

create or replace function public.id_format_set(p_kind text, p_prefix text, p_width int, p_next bigint, p_pattern text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  f   public.id_formats;
  v_p text := upper(btrim(coalesce(p_prefix, '')));
  v_t text := btrim(coalesce(p_pattern, ''));
  v_top bigint;
  v_moved text[] := '{}';
  v_word text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into f from public.id_formats where kind = p_kind for update;
  if f.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  v_word := case p_kind when 'creator' then 'Creator ID' when 'campaign' then 'Campaign ID' when 'trip' then 'Outstation trip number' when 'request' then 'Request number' when 'revision' then 'Quotation revision' else 'Job reference' end;
  if p_kind = 'job' then
    if length(v_t) > 40 or position('{creator}' in v_t) = 0 or position('{campaign}' in v_t) = 0 then
      return jsonb_build_object('error', 'bad-pattern');
    end if;
    if v_t is distinct from f.pattern then
      update public.id_formats set pattern = v_t, updated_at = now(), updated_by = me.id where kind = p_kind;
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, 'team.changed', 'Creator and campaign IDs', v_word || ': ' || f.pattern || ' → ' || v_t);
    end if;
    return jsonb_build_object('ok', true);
  end if;
  if v_p !~ '^[A-Z]{1,6}$' then return jsonb_build_object('error', 'bad-prefix'); end if;
  if p_width is null or p_width < (case p_kind when 'revision' then 1 when 'request' then 3 else 2 end)
     or p_width > (case p_kind when 'revision' then 3 else 6 end) then return jsonb_build_object('error', 'bad-width'); end if;
  if p_next is null or p_next < 1 then return jsonb_build_object('error', 'bad-next'); end if;
  -- A creator's payment details reference: its Creator ID and a run of n.
  if p_kind = 'creator' and v_t <> '' and (length(v_t) > 40 or position('{creator}' in v_t) = 0 or v_t !~ '\{n{1,6}\}') then
    return jsonb_build_object('error', 'bad-request-pattern');
  end if;
  -- The next number stays above every number in use under that prefix; a
  -- trip's number counts afresh each month, and a request's letters are
  -- drawn at random, so neither keeps a next number.
  if p_kind in ('trip', 'request', 'revision') then
    v_top := null;
  elsif p_kind = 'creator' then
    select max(substring(c.creator_code from length(v_p) + 1)::bigint) into v_top
      from public.creators c where c.creator_code ~ ('^' || v_p || '[0-9]+$');
  else
    select max(substring(m.campaign_code from length(v_p) + 1)::bigint) into v_top
      from public.campaigns m where m.campaign_code ~ ('^' || v_p || '[0-9]+$');
  end if;
  if v_top is not null and p_next <= v_top then
    return jsonb_build_object('error', 'bad-next', 'top', v_top);
  end if;
  v_moved := array_remove(array[
    case when v_p <> f.prefix then 'prefix ' || f.prefix || ' → ' || v_p end,
    case when p_width <> f.width then 'digits ' || f.width || ' → ' || p_width end,
    case when p_kind not in ('trip', 'request', 'revision') and p_next <> f.next_no then 'next ' || f.next_no || ' → ' || p_next end,
    case when p_kind = 'creator' and v_t <> '' and v_t is distinct from f.pattern
         then 'payment details reference ' || coalesce(f.pattern, 'not set') || ' → ' || v_t end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true); end if;
  update public.id_formats set prefix = v_p, width = p_width, next_no = case when p_kind in ('trip', 'request', 'revision') then f.next_no else p_next end,
    pattern = case when p_kind = 'creator' and v_t <> '' then v_t else pattern end,
    updated_at = now(), updated_by = me.id
   where kind = p_kind;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', case when p_kind = 'trip' then 'Outstation trip numbers' when p_kind in ('request', 'revision') then 'Request and quotation numbers' else 'Creator and campaign IDs' end, v_word || ': ' || array_to_string(v_moved, ', '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.id_format_set(text, text, int, bigint, text) from public, anon;
grant execute on function public.id_format_set(text, text, int, bigint, text) to authenticated;

/* Console search by a request's reference or its letters (REQ2611-KMT,
   KMT): a client's details form at Billing, a supplier's form at
   Suppliers, five a kind; a candidate's is matched in `hiring_list`. */
create or replace function public.request_ref_find(p_q text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  v_q   text := upper(regexp_replace(regexp_replace(coalesce(p_q, ''), '^\s*ADP/', '', 'i'), '[^A-Za-z0-9-]', '', 'g'));
  v_out jsonb := '[]'::jsonb;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if length(v_q) < 3 or length(v_q) > 20 then return jsonb_build_object('ok', true, 'rows', v_out); end if;
  if public.allowed('clients.billing', 'view') then
    v_out := v_out || coalesce((select jsonb_agg(jsonb_build_object('kind', 'client', 'ref', x.request_ref, 'id', x.id, 'slug', x.slug,
        'name', x.name, 'code', x.client_code, 'at', x.submitted_at) order by x.submitted_at desc)
      from (select f.request_ref, f.submitted_at, c.id, c.slug, c.name, c.client_code
              from public.client_detail_forms f join public.clients c on c.id = f.client_id
             where f.request_ref like '%' || v_q || '%' and public.client_seen(c.id, 'view')
             order by f.submitted_at desc limit 5) x), '[]'::jsonb);
  end if;
  if public.allowed('suppliers', 'view') then
    v_out := v_out || coalesce((select jsonb_agg(jsonb_build_object('kind', 'supplier', 'ref', x.request_ref, 'id', x.id,
        'name', x.name, 'code', x.code, 'at', x.submitted_at) order by x.submitted_at desc)
      from (select f.request_ref, f.submitted_at, s.id, s.name, s.code
              from public.supplier_forms f join public.suppliers s on s.id = f.supplier_id
             where f.request_ref like '%' || v_q || '%'
             order by f.submitted_at desc limit 5) x), '[]'::jsonb);
  end if;
  return jsonb_build_object('ok', true, 'rows', v_out);
end $$;
revoke all on function public.request_ref_find(text) from public, anon;
grant execute on function public.request_ref_find(text) to authenticated;

-- END OF ONE REQUEST REFERENCE FOR EVERY PUBLIC SUBMISSION -------------------

select public.functions_tidy();
