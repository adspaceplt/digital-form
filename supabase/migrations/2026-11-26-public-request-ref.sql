-- ===========================================================================
-- ONE REQUEST REFERENCE FOR EVERY PUBLIC SUBMISSION (2026-11-26)
-- ===========================================================================
-- WHY: the user, 2026-11-26 ("ok"; then "all outward incoming requests
-- carry one REQ"): every request that reaches ADspace from a public page or
-- the client portal takes one reference, ADP/REQ{YYMM}-{AAA}, as a website
-- quotation request already does, so a code is unique across every kind
-- within a month and the team finds the record by it. Decisions on work
-- ADspace sent (Content Review, Video Scripts, creator selection) take none.
--
-- WHAT IT CHANGES
--   * `client_detail_forms`, `supplier_forms`, `hiring_candidates`,
--     `client_requests` and `feedback_responses` take `request_ref` (unique
--     where set, the reference's shape checked).
--   * `public_request_ref(at)`: the one generator (the `request` row of
--     `id_formats`: three to six consonants from a strong source, a short
--     deny list, drawn again on a clash with any table that holds one,
--     one draw at a time); `quote_request_ref` answers through it, so a
--     website quotation request keeps working unchanged.
--   * A trigger stamps the reference: a details or supplier form when it is
--     submitted; a candidate, a client's request (Change of details,
--     Upgrade, Downgrade, Cancel service; one the team records for the
--     client too) and a feedback answer when added.
--   * `client_details_submit`, `supplier_form_submit`: answer the reference
--     and name it in the Activity record; `client_details_read`,
--     `supplier_form_read`: a form already sent answers its reference.
--   * `client_details_state`, `supplier_get`, `hiring_row`: the record's
--     reference for the team; `careers_read`: the candidate's;
--     `hiring_add`: the candidate's history names it.
--   * `portal_request_once`, `client_request_add`, `feedback_submit`: answer
--     the reference and name it in the Activity record; `get_portal`: each
--     request's, withdrawn ones too; `feedback_read` and `feedback_submit`
--     answered already: the answer's; `feedback_client`: the team's.
--   * `request_ref_find(q)`: console search by the reference or its
--     letters: a details form at Billing, a client's request at Requests, a
--     feedback answer at Clients, each held to the reader's clients; a
--     supplier's at Suppliers (a candidate's is matched in `hiring_list`,
--     through `hiring_row`).
--   * `id_format_set`: the Activity record says Request number, filed under
--     Request and quotation numbers.
--
-- ORDER: this file, then the pages (an open tab reads no reference and
-- draws none). Safe to run twice. No backfill: a submission made before
-- this band keeps no reference. Holds no drop or delete.
-- ROLLBACK: restate each function's last definition before this band
-- (QUOTATIONS CONFIRMED BEFORE THEY GO for `quote_request_ref` and
-- `id_format_set`, INTERVIEW MISSED for `careers_read`; the bands each
-- other function was last restated in);
-- `drop trigger client_detail_forms_request_ref`,
-- `supplier_forms_request_ref`, `hiring_candidates_request_ref`,
-- `client_requests_request_ref`, `feedback_responses_request_ref`; the
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
alter table public.client_requests add column if not exists request_ref text
  check (request_ref is null or request_ref ~ '^ADP/[A-Z]{1,6}[0-9]{4}-[A-Z]{3,6}$');
alter table public.feedback_responses add column if not exists request_ref text
  check (request_ref is null or request_ref ~ '^ADP/[A-Z]{1,6}[0-9]{4}-[A-Z]{3,6}$');
create unique index if not exists hiring_candidates_request_ref_key on public.hiring_candidates (request_ref) where request_ref is not null;
create unique index if not exists client_requests_request_ref_key on public.client_requests (request_ref) where request_ref is not null;
create unique index if not exists feedback_responses_request_ref_key on public.feedback_responses (request_ref) where request_ref is not null;

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
          and not exists (select 1 from public.hiring_candidates h where h.request_ref = v_ref)
          and not exists (select 1 from public.client_requests r where r.request_ref = v_ref)
          and not exists (select 1 from public.feedback_responses b where b.request_ref = v_ref);
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

/* Stamped by the database, never by a page: a form when it is submitted;
   an application, a client's request and a feedback answer when added. */
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
    new.request_ref := public.public_request_ref(now());
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
drop trigger if exists client_requests_request_ref on public.client_requests;
create trigger client_requests_request_ref before insert on public.client_requests
  for each row execute function public.request_ref_on_add();
drop trigger if exists feedback_responses_request_ref on public.feedback_responses;
create trigger feedback_responses_request_ref before insert on public.feedback_responses
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
  m public.hiring_interviews;
  v_state text;
  v_missed jsonb;
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
  /* Interview missed (2026-11-26): its time, while no later interview has
     been confirmed and the candidate is still in the running, or where it
     closed the application. */
  select * into m from public.hiring_interviews where candidate_id = c.id and state = 'missed'
   order by invited_at desc limit 1;
  v_missed := case when m.id is not null
      and not exists (select 1 from public.hiring_interviews j where j.candidate_id = c.id and j.invited_at > m.invited_at and j.state = 'confirmed')
      and ((c.stage in ('new', 'invited', 'interview') and c.outcome is null) or public.hiring_closed_missed(c.id) = m.id)
    then jsonb_strip_nulls(jsonb_build_object('at', m.slots[m.picked], 'closed', case when c.outcome = 'not' then true end)) end;
  return jsonb_strip_nulls(jsonb_build_object('missed', v_missed)) || jsonb_build_object('ok', true, 'contact', v_contact, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage = 'new' or (c.stage = 'pool' and c.outcome is null) then 'received' else c.stage end, 'received_at', c.created_at,
    'request_ref', c.request_ref,
    'pool_declined', case when c.outcome = 'pool' and c.pool_consent = 'no' then true end,
    'pool', case when c.stage = 'pool' and c.outcome = 'pool' then jsonb_strip_nulls(jsonb_build_object('consent', c.pool_consent,
      'until', c.pool_until, 'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12))) end,
    'interview', case when i.id is null or c.stage in ('pool', 'closed') or i.state = 'missed' then null
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

create or replace function public.portal_request_once(
  p_client uuid, p_kind text, p_service uuid, p_note text, p_idem text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  me     public.client_contacts%rowtype;
  sv     public.client_services%rowtype;
  rid    uuid;
  v_ref  text;
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  -- The same request again (a reply lost on the way): the one already filed.
  if v_idem is not null then
    select r.id into rid from public.client_requests r
     where r.client_id = p_client and r.idem = v_idem;
    if rid is not null then return jsonb_build_object('ok', true, 'id', rid, 'again', true); end if;
  end if;
  if p_kind not in ('upgrade', 'downgrade', 'cancel', 'details') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  -- What a client types is held to a length (audit 2026-10-18, item 12).
  if length(coalesce(p_note, '')) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into cl from public.clients where id = p_client;
  select * into me from public.client_contacts
    where client_id = p_client and portal_access and archived_at is null and lower(email) = who
    order by is_primary desc limit 1;
  if p_kind <> 'details' then
    select * into sv from public.client_services
      where id = p_service and client_id = p_client and archived_at is null and state = 'confirmed';
    if sv.id is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if p_kind <> 'cancel' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note-required');
  end if;
  insert into public.client_requests (client_id, contact_id, contact_name, kind, service_id, service_label, note, idem)
  values (p_client, me.id, me.name, p_kind, sv.id, sv.label, nullif(btrim(p_note), ''), v_idem)
  on conflict (client_id, idem) where idem is not null do nothing
  returning id, request_ref into rid, v_ref;
  if rid is null then
    select r.id into rid from public.client_requests r
     where r.client_id = p_client and r.idem = v_idem;
    return jsonb_build_object('ok', true, 'id', rid, 'again', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'request.raised', cl.name, p_kind || coalesce(' · ' || sv.label, '') || coalesce(' · ' || v_ref, ''));
  return jsonb_build_object('ok', true, 'id', rid, 'request_ref', v_ref);
end $$;

create or replace function public.client_request_add(p_client uuid, p_kind text, p_service uuid,
  p_contact uuid, p_note text, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  cl public.clients;
  ct public.client_contacts;
  sv public.client_services;
  rid uuid;
  v_ref text;
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
begin
  if me.id is null or not public.allowed('clients.requests', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into cl from public.clients where id = p_client;
  if cl.id is null or not public.client_scope_ok('client', cl.id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- The same request again (a reply lost on the way): the one already filed.
  if v_idem is not null then
    select r.id into rid from public.client_requests r where r.client_id = cl.id and r.idem = v_idem;
    if rid is not null then return jsonb_build_object('ok', true, 'id', rid, 'again', true); end if;
  end if;
  if p_kind is null or p_kind not in ('upgrade', 'downgrade', 'cancel', 'details') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if length(coalesce(p_note, '')) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  if p_kind <> 'details' then
    select * into sv from public.client_services
     where id = p_service and client_id = cl.id and archived_at is null and state = 'confirmed';
    if sv.id is null then return jsonb_build_object('error', 'no-service'); end if;
  end if;
  if p_kind <> 'cancel' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note-required');
  end if;
  if p_contact is not null then
    select * into ct from public.client_contacts
     where id = p_contact and client_id = cl.id and archived_at is null;
    if ct.id is null then return jsonb_build_object('error', 'bad-contact'); end if;
  end if;
  insert into public.client_requests (client_id, contact_id, contact_name, kind, service_id, service_label,
                                      note, idem, recorded_by)
  values (cl.id, ct.id, ct.name, p_kind, sv.id, sv.label, nullif(btrim(p_note), ''), v_idem, me.name)
  on conflict (client_id, idem) where idem is not null do nothing
  returning id, request_ref into rid, v_ref;
  if rid is null then
    select r.id into rid from public.client_requests r where r.client_id = cl.id and r.idem = v_idem;
    return jsonb_build_object('ok', true, 'id', rid, 'again', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'request.added', cl.name,
          public.client_request_word(p_kind) || coalesce(' · ' || sv.label, '') ||
          coalesce(' · for ' || ct.name, '') || coalesce(' · ' || v_ref, ''));
  return jsonb_build_object('ok', true, 'id', rid, 'request_ref', v_ref);
end $$;
revoke all on function public.client_request_add(uuid, text, uuid, uuid, text, text) from public, anon;
grant execute on function public.client_request_add(uuid, text, uuid, uuid, text, text) to authenticated;

create or replace function public.get_portal(p_client uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  cid uuid;
  cl  public.clients%rowtype;
  me  public.client_contacts%rowtype;
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select p into cid from public.portal_clients() p
    order by (p = p_client) desc nulls last limit 1;
  if cid is null then return jsonb_build_object('error', 'no-access'); end if;
  select * into cl from public.clients where id = cid;
  select * into me from public.client_contacts
    where client_id = cid and portal_access and archived_at is null and lower(email) = who
    order by is_primary desc limit 1;

  return jsonb_build_object(
    'clients', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
      from public.clients c where c.id in (select public.portal_clients())), '[]'::jsonb),
    'client', jsonb_build_object(
      'id', cl.id, 'name', cl.name, 'legal_name', cl.legal_name, 'company_no', cl.company_no,
      'billing_address', cl.billing_address, 'market', coalesce(cl.market, 'MY'),
      'bill_market', public.client_bill_market(cl.market, cl.bill_sgd),
      'sst_applies', coalesce(cl.sst_applies, true), 'stage', cl.stage, 'owner', cl.owner,
      'industry', cl.industry, 'website', cl.website, 'logo_url', cl.logo_url),
    'me', jsonb_build_object('id', me.id, 'name', me.name, 'email', me.email,
      'lang', case when me.lang = 'zh' then 'zh' else 'en' end),
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'role', k.role, 'phone', k.phone,
        'email', k.email, 'is_primary', k.is_primary, 'portal_access', k.portal_access)
        order by k.is_primary desc, k.name)
      from public.client_contacts k where k.client_id = cid and k.archived_at is null), '[]'::jsonb),
    'services', coalesce((
      -- `term_adjust` travels with the line, because the client's page works
      -- the figure out the same way the console and the letter do and must
      -- never print a different one.
      select jsonb_agg(jsonb_build_object('id', s.id, 'label', s.label, 'unit', s.unit, 'qty', s.qty,
        'rate', s.rate, 'tenure', s.tenure, 'start_on', s.start_on, 'state', s.state, 'note', s.note,
        'term_adjust', coalesce(s.term_adjust, false), 'term_pct', s.term_pct)
        order by s.created_at)
      from public.client_services s
      where s.client_id = cid and s.archived_at is null and s.state in ('quoted', 'confirmed')), '[]'::jsonb),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'number', d.number,
        'issued_at', d.issued_at, 'market', d.market, 'subtotal', d.subtotal, 'tax', d.tax,
        'total', d.total, 'bill_to', d.bill_to, 'lines', d.lines, 'issued_by', d.issued_by)
        order by d.created_at desc)
      from public.client_documents d where d.client_id = cid and d.voided_at is null), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'service_label', r.service_label,
        'note', r.note, 'state', r.state, 'fee', r.fee, 'reply', r.reply,
        'created_at', r.created_at, 'withdrawn_at', r.withdrawn_at, 'request_ref', r.request_ref)
        order by r.created_at desc)
      from public.client_requests r where r.client_id = cid), '[]'::jsonb),
    'review', case
      when cl.review_hidden is not true
       and exists (select 1 from public.batches b where b.client_id = cid and b.published)
      then jsonb_build_object('token', cl.access_token) end,
    'campaigns', coalesce((
      -- Where each campaign stands (2026-11-25): its booked creators'
      -- steps, never who they are, and the next shoot ahead.
      select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'title_zh', m.title_zh,
        'state', m.state, 'deadline', m.deadline, 'token', m.access_token,
        'push_format', m.push_format,
        'booked', coalesce((select jsonb_agg(o.state order by o.position, o.added_at)
          from public.campaign_options o where o.campaign_id = m.id
           and o.state in ('confirmed', 'pending_visit', 'pending_draft', 'reviewing',
                           'changes', 'scheduled', 'posted', 'completed')), '[]'::jsonb),
        'next_shoot', (select min(o.visit_date) from public.campaign_options o
          where o.campaign_id = m.id and o.state in ('confirmed', 'pending_visit')
            and o.visit_date >= (now() at time zone 'Asia/Kuala_Lumpur')::date))
        order by m.created_at desc)
      from public.campaigns m where m.client_id = cid and m.state <> 'draft'), '[]'::jsonb),
    'access', coalesce((
      select jsonb_agg(jsonb_build_object('name', k.name, 'email', k.email) order by k.is_primary desc, k.name)
      from public.client_contacts k
      where k.client_id = cid and k.archived_at is null and k.portal_access), '[]'::jsonb)
  );
end $$;
revoke all on function public.get_portal(uuid) from public, anon;
grant execute on function public.get_portal(uuid) to authenticated;

create or replace function public.feedback_read(p_key text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_req  public.feedback_requests;
  v_cl   public.clients;
  v_lang text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{16}$' then
    perform public.feedback_throttle(true);
    return jsonb_build_object('error', 'not_found');
  end if;
  select * into v_req from public.feedback_requests r where r.access_key = p_key;
  if not public.feedback_throttle(v_req.id is null) then return jsonb_build_object('error', 'busy'); end if;
  if v_req.id is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_cl from public.clients c where c.id = v_req.client_id;
  if v_req.closed_reason = 'answered' then
    return jsonb_build_object('error', 'answered', 'answered_at', v_req.answered_at, 'kind', v_req.kind, 'client', v_cl.name,
      'request_ref', (select s.request_ref from public.feedback_responses s where s.request_id = v_req.id));
  end if;
  if v_req.closed_at is not null or v_cl.stage = 'past' then
    return jsonb_build_object('error', 'closed', 'client', v_cl.name);
  end if;
  if v_req.opened_at is null then
    update public.feedback_requests r set opened_at = now() where r.id = v_req.id;
  end if;
  select k.lang into v_lang from public.client_contacts k where k.id = v_req.contact_id;
  return jsonb_build_object('ok', true, 'kind', v_req.kind, 'client', v_cl.name,
    'requested_at', v_req.created_at, 'manager', v_req.manager_name, 'lang', coalesce(v_lang, 'en'),
    'questions', public.feedback_questions_of(v_req.kind, v_req.manager_name));
end $$;
revoke all on function public.feedback_read(text) from public;
grant execute on function public.feedback_read(text) to anon, authenticated;

create or replace function public.feedback_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_req   public.feedback_requests;
  v_cl    public.clients;
  a       jsonb := coalesce(p_answers, '{}'::jsonb);
  q       record;
  v_out   jsonb := '{}'::jsonb;
  v_val   text;
  v_int   int;
  v_lead  int;
  v_band  text;
  v_mgr   int;
  v_ct    public.client_contacts;
  v_resp  uuid;
  v_kword text;
  v_ref   text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{16}$' then
    perform public.feedback_throttle(true);
    return jsonb_build_object('error', 'not_found');
  end if;
  if jsonb_typeof(a) <> 'object' then return jsonb_build_object('error', 'bad-answers'); end if;
  select * into v_req from public.feedback_requests r where r.access_key = p_key for update;
  if not public.feedback_throttle(v_req.id is null) then return jsonb_build_object('error', 'busy'); end if;
  if v_req.id is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_cl from public.clients c where c.id = v_req.client_id;
  if v_req.closed_reason = 'answered' then
    return jsonb_build_object('error', 'answered', 'answered_at', v_req.answered_at,
      'request_ref', (select s.request_ref from public.feedback_responses s where s.request_id = v_req.id));
  end if;
  if v_req.closed_at is not null or v_cl.stage = 'past' then return jsonb_build_object('error', 'closed'); end if;

  -- The lead question first: its band chooses which note is asked.
  for q in select * from public.feedback_questions x
            where x.kind = v_req.kind and x.lead loop
    v_val := a ->> q.key;
    if v_val is null or v_val !~ '^[0-9]{1,2}$' then return jsonb_build_object('error', 'required', 'key', q.key); end if;
    v_lead := v_val::int;
    if v_lead < q.scale_min or v_lead > q.scale_max then return jsonb_build_object('error', 'bad-score', 'key', q.key); end if;
    v_band := case when v_lead <= q.band_low_max then 'low' when v_lead <= q.band_mid_max then 'mid' else 'high' end;
  end loop;
  if v_lead is null then return jsonb_build_object('error', 'bad-kind'); end if;

  for q in select * from public.feedback_questions x
            where x.kind = v_req.kind
              and (not x.about_manager or v_req.manager_name is not null)
              and (x.band is null or x.band = v_band)
            order by x.n loop
    v_val := a ->> q.key;
    if q.type = 'scale' then
      if v_val is null or v_val !~ '^[0-9]{1,2}$' then
        if q.required then return jsonb_build_object('error', 'required', 'key', q.key); end if;
        continue;
      end if;
      v_int := v_val::int;
      if v_int < q.scale_min or v_int > q.scale_max then return jsonb_build_object('error', 'bad-score', 'key', q.key); end if;
      v_out := v_out || jsonb_build_object(q.key, v_int);
      if q.about_manager then v_mgr := v_int; end if;
    else
      v_val := nullif(btrim(coalesce(v_val, '')), '');
      if v_val is null then
        if q.required then return jsonb_build_object('error', 'required', 'key', q.key); end if;
        continue;
      end if;
      if length(v_val) > 2000 then return jsonb_build_object('error', 'too-long', 'key', q.key); end if;
      v_out := v_out || jsonb_build_object(q.key, v_val);
    end if;
  end loop;

  -- A signed-in contact of this client is named; anyone else is the link.
  if public.portal_contact_name(v_req.client_id) is not null then
    select * into v_ct from public.client_contacts k
     where k.client_id = v_req.client_id and k.portal_access and k.archived_at is null
       and lower(k.email) = lower(auth.jwt() ->> 'email')
     order by k.is_primary desc limit 1;
  end if;

  insert into public.feedback_responses (request_id, client_id, kind, answers, score, band,
    manager_id, manager_score, contact_id, contact_name)
  values (v_req.id, v_req.client_id, v_req.kind, v_out, v_lead, v_band,
    v_req.manager_id, v_mgr, v_ct.id, v_ct.name)
  returning id, request_ref into v_resp, v_ref;
  update public.feedback_requests r set answered_at = now(), closed_at = now(), closed_reason = 'answered',
         opened_at = coalesce(r.opened_at, now())
   where r.id = v_req.id;

  v_kword := case v_req.kind when 'quick' then 'Service rating' else 'Performance review' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_ct.name, 'Feedback form'), 'client.edited', v_cl.name,
          v_kword || ' answered: ' || v_lead || ' of ' ||
          (select x.scale_max from public.feedback_questions x where x.kind = v_req.kind and x.lead) ||
          coalesce(' · ' || v_ref, ''));
  -- The account manager told, else whoever sent it; a low score says so.
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.feedback',
         case when v_band = 'low' then 'Low score · ' else 'Feedback received · ' end || v_cl.name,
         v_kword || ': ' || v_lead || ' of ' ||
         (select x.scale_max from public.feedback_questions x where x.kind = v_req.kind and x.lead) ||
         case when v_band = 'low' then '. Open the client''s Feedback to follow up.' else '.' end,
         v_cl.id, 'client.feedback:' || v_resp || ':' || m.id
    from public.team_members m
   where m.active and m.id = coalesce(v_req.manager_id, v_req.sent_by)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true, 'request_ref', v_ref);
end $$;
revoke all on function public.feedback_submit(text, jsonb) from public;
grant execute on function public.feedback_submit(text, jsonb) to anon, authenticated;

create or replace function public.feedback_client(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'requests', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'kind', r.kind, 'created_at', r.created_at, 'sent_by', r.sent_by_name,
             'to_name', r.sent_to_name, 'to_email', r.sent_to_email, 'manager', r.manager_name,
             'opened_at', r.opened_at, 'answered_at', r.answered_at, 'closed_at', r.closed_at,
             'closed_reason', r.closed_reason,
             'response', case when s.id is null then null else jsonb_build_object(
               'id', s.id, 'score', s.score, 'band', s.band, 'submitted_at', s.submitted_at, 'by', s.contact_name, 'request_ref', s.request_ref,
               'max', (select x.scale_max from public.feedback_questions x where x.kind = s.kind and x.lead),
               'manager_score', case when public.feedback_sees_manager(s.manager_id) then s.manager_score end,
               'answers', public.feedback_answers_of(s, r.manager_name, public.feedback_sees_manager(s.manager_id)),
               'task_id', s.followup_task_id,
               'task_done', (select t.completed_at is not null from public.ops_tasks t where t.id = s.followup_task_id)) end)
           order by r.created_at desc)
      from public.feedback_requests r
      left join public.feedback_responses s on s.request_id = r.id
     where r.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.feedback_client(uuid) from public, anon;
grant execute on function public.feedback_client(uuid) to authenticated;

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
   KMT): a details form at Billing, a client's request at Requests, a
   feedback answer at Clients, each held to the reader's clients; a
   supplier's form at Suppliers; five a kind. A candidate's is matched in
   `hiring_list`. */
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
  if public.allowed('clients.requests', 'view') then
    v_out := v_out || coalesce((select jsonb_agg(jsonb_build_object('kind', 'request', 'ref', x.request_ref, 'id', x.id, 'slug', x.slug,
        'name', x.name, 'code', x.client_code, 'at', x.created_at) order by x.created_at desc)
      from (select r.request_ref, r.created_at, c.id, c.slug, c.name, c.client_code
              from public.client_requests r join public.clients c on c.id = r.client_id
             where r.request_ref like '%' || v_q || '%' and public.client_seen(c.id, 'view')
             order by r.created_at desc limit 5) x), '[]'::jsonb);
  end if;
  if public.allowed('clients', 'view') then
    v_out := v_out || coalesce((select jsonb_agg(jsonb_build_object('kind', 'feedback', 'ref', x.request_ref, 'id', x.id, 'slug', x.slug,
        'name', x.name, 'code', x.client_code, 'at', x.submitted_at) order by x.submitted_at desc)
      from (select s.request_ref, s.submitted_at, c.id, c.slug, c.name, c.client_code
              from public.feedback_responses s join public.clients c on c.id = s.client_id
             where s.request_ref like '%' || v_q || '%' and public.client_seen(c.id, 'view')
             order by s.submitted_at desc limit 5) x), '[]'::jsonb);
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
