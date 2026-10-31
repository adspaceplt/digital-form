-- ===========================================================================
-- QUOTATION SIGNING — the client accepts and signs a quotation on its link;
-- the colleague who prepared it checks the entries and submits them to a
-- reviewer they choose, who approves (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31: one document, the quotation acting as the
-- Letter of Offer; "prepared by should be shown as someone who prepares this
-- quotation … there should be someone to review the entries and submission
-- of this quotation"; "Jane picks the reviewer, approve"; "Ok go ahead all").
--
-- WHAT IT CHANGES
--   * `quotations` keeps the signature (`signed_at`, `signed`: online or on
--     paper, the company and billing contact as entered, the signer, the
--     signature drawn or typed, and for online the record: time, the email
--     the code went to, the address and country the database saw, the
--     device and a fingerprint of what was signed), who submitted it to
--     whom (`submitted_*`, `reviewer_*`), the review (`reviewed_*`), a send
--     back (`returned_*`, `return_note`) and every earlier signature
--     (`sign_history`). Read by the team at Clients: Quotations View.
--   * `quote_sign_codes` (RLS on, no policy, no grant): a six-digit code
--     kept hashed, 15 minutes, five tries, five a quotation an hour.
--   * `quote_sign_code(p_key, p_payload)`, the service role's alone (the
--     `quote-request` function emails the code): checks every field as the
--     details form does and the quotation open to sign (sent, valid, not
--     Cancelled, not signed). `quote_sign_finish(p_key, p_code)` (anon)
--     signs with it, tells the colleague who prepared it and the person in
--     charge (`quote.signed`).
--   * `quotation_link(p_id)` gives a team-built quotation its link.
--     `quotation_reviewers(p_id)`: Clients: Quotations Full Access, or an
--     admin, never the caller. `quotation_submit(p_id, p_reviewer,
--     p_company)` (Quotations Work) submits a signed quotation, a correction
--     kept from and to (`quote.review` to the reviewer). `quotation_review(
--     p_id, p_ok, p_note)` (the reviewer, or an admin in their place)
--     approves: Billing filled where it is empty (held in Bukku left as
--     Bukku holds it), the quotation's lines Confirmed; or sends back with
--     a note. `quotation_paper(p_id, p_payload)` keeps a signature made on
--     paper; `quotation_resign(p_id)` asks for the signature again, the
--     earlier one kept.
--   * `quote_website_read` opens any quotation by its key, answers the
--     stages `accepted` (signed) and `welcome` (reviewed and Active), and
--     `signed`, `prepared`, `reviewed` and `prefill` (while unsigned).
--
-- ORDER: 2026-10-07-function-hygiene.sql again (`quote_sign_finish` joins
-- `open_to_anon`), this file (connector), the `quote-request` function, then
-- the pages. A page served before never asks these; a quotation link read
-- before reads as it did. Safe to run twice.
--
-- ROLLBACK: the pages from before; run QUOTATION REVIEW FIXES'
-- `quote_website_read` again. The columns and functions may stay.
-- ===========================================================================

-- QUOTATION SIGNING ---------------------------------------------------------

alter table public.quotations add column if not exists signed_at     timestamptz;
alter table public.quotations add column if not exists signed        jsonb;
alter table public.quotations add column if not exists submitted_at  timestamptz;
alter table public.quotations add column if not exists submitted_by  text;
alter table public.quotations add column if not exists reviewer_id   uuid references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists reviewer_name text;
alter table public.quotations add column if not exists reviewed_at   timestamptz;
alter table public.quotations add column if not exists reviewed_by   text;
alter table public.quotations add column if not exists reviewed_role text;
alter table public.quotations add column if not exists returned_at   timestamptz;
alter table public.quotations add column if not exists return_note   text;
alter table public.quotations add column if not exists returned_by   text;
alter table public.quotations add column if not exists sign_history  jsonb;
grant select (signed_at, signed, submitted_at, submitted_by, reviewer_id, reviewer_name, reviewed_at,
              reviewed_by, reviewed_role, returned_at, return_note, returned_by, sign_history)
  on table public.quotations to authenticated;

create table if not exists public.quote_sign_codes (
  id           uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  code_hash    text not null,
  email        text not null,
  payload      jsonb not null,
  tries        int not null default 0,
  used_at      timestamptz,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null
);
create index if not exists quote_sign_codes_quotation_idx on public.quote_sign_codes (quotation_id, created_at desc);
alter table public.quote_sign_codes enable row level security;
revoke all on table public.quote_sign_codes from public, anon, authenticated;

/* The company and the billing contact, held as the details form holds
   them; the signer and the signature. Each answers the field it refuses. */
create or replace function public.quote_sign_company(a jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
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
  if v_brn !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-company_no'); end if;
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

create or replace function public.quote_sign_contact(c jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_sal  text := nullif(btrim(coalesce(c->>'salutation', '')), '');
  v_name text := btrim(regexp_replace(coalesce(c->>'name', ''), '\s+', ' ', 'g'));
  v_ph   text := btrim(coalesce(c->>'phone', ''));
  v_mail text := lower(btrim(coalesce(c->>'email', '')));
  v_dig  text := regexp_replace(btrim(coalesce(c->>'phone', '')), '[^0-9]', '', 'g');
begin
  if v_sal is not null and not (v_sal = any (array['Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
       'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik'])) then
    return jsonb_build_object('error', 'bad-contact_salutation');
  end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-contact_name'); end if;
  if length(v_dig) < 8 or length(v_dig) > 15 or length(v_ph) > 30 then return jsonb_build_object('error', 'bad-contact_phone'); end if;
  if v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_mail) > 160 then return jsonb_build_object('error', 'bad-contact_email'); end if;
  return jsonb_build_object('contact', jsonb_build_object('salutation', v_sal, 'name', v_name, 'phone', v_ph, 'email', v_mail));
end $$;
revoke all on function public.quote_sign_contact(jsonb) from public, anon, authenticated;

create or replace function public.quote_sign_signer(sg jsonb, sig jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_name text := btrim(regexp_replace(coalesce(sg->>'name', ''), '\s+', ' ', 'g'));
  v_role text := btrim(regexp_replace(coalesce(sg->>'designation', ''), '\s+', ' ', 'g'));
  v_text text := btrim(coalesce(sig->>'text', ''));
  v_sig  jsonb;
begin
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-signer_name'); end if;
  if length(v_role) < 2 or length(v_role) > 80 then return jsonb_build_object('error', 'bad-signer_designation'); end if;
  if sig->>'type' = 'drawn' and coalesce(sig->>'path', '') ~ '^[MLQCZmlqcz0-9 .,-]{8,30000}$' then
    v_sig := jsonb_build_object('type', 'drawn', 'path', sig->>'path');
  elsif sig->>'type' = 'typed' and length(v_text) between 2 and 80 then
    v_sig := jsonb_build_object('type', 'typed', 'text', v_text);
  else
    return jsonb_build_object('error', 'bad-signature');
  end if;
  return jsonb_build_object('signer', jsonb_build_object('name', v_name, 'designation', v_role), 'signature', v_sig);
end $$;
revoke all on function public.quote_sign_signer(jsonb, jsonb) from public, anon, authenticated;

/* The revision a key shows, if it can be signed now: sent (a website
   quotation released), valid, standing, not Cancelled, not signed. */
create or replace function public.quote_sign_open(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if w.status = 'not_proceeding' or q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unsent'); end if;
  if q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  return jsonb_build_object('id', q.id);
end $$;
revoke all on function public.quote_sign_open(text) from public, anon, authenticated;

/* A colleague, by the name a record holds, while they work here. */
create or replace function public.quote_sign_member(p_name text)
returns uuid
language sql stable security definer set search_path = public as $$
  select m.id from public.team_members m
   where m.active and not coalesce(m.system, false) and m.removed_at is null
     and nullif(btrim(coalesce(p_name, '')), '') is not null and m.name = btrim(p_name)
   limit 1
$$;
revoke all on function public.quote_sign_member(text) from public, anon, authenticated;

create or replace function public.quote_sign_tell(p_ids uuid[], p_kind text, p_title text, p_body text,
                                                  p_client uuid, p_key text)
returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select distinct m, p_kind, p_title, p_body, p_client, p_kind || ':' || p_key || ':' || m
    from unnest(p_ids) m
   where m is not null
  on conflict (dedupe_key) do nothing;
end $$;
revoke all on function public.quote_sign_tell(uuid[], text, text, text, uuid, text) from public, anon, authenticated;

create or replace function public.quote_sign_code(p_key text, p_payload jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  o   jsonb := public.quote_sign_open(p_key);
  q   public.quotations;
  pl  jsonb := coalesce(p_payload, '{}'::jsonb);
  c1  jsonb; c2 jsonb; c3 jsonb;
  v_code text;
  v_id uuid;
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  c1 := public.quote_sign_company(pl->'company'); if c1 ? 'error' then return c1; end if;
  c2 := public.quote_sign_contact(pl->'contact'); if c2 ? 'error' then return c2; end if;
  c3 := public.quote_sign_signer(pl->'signer', pl->'signature'); if c3 ? 'error' then return c3; end if;
  if coalesce(pl->>'agree', '') <> 'true' then return jsonb_build_object('error', 'bad-agree'); end if;
  if (select count(*) from public.quote_sign_codes s
       where s.quotation_id = q.id and s.created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('error', 'too-many');
  end if;
  v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.quote_sign_codes (quotation_id, code_hash, email, payload, expires_at)
  values (q.id, crypt(v_code, gen_salt('bf', 6)), c2->'contact'->>'email',
          jsonb_build_object('company', c1->'company', 'contact', c2->'contact', 'signer', c3->'signer', 'signature', c3->'signature'),
          now() + interval '15 minutes')
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'code', v_code, 'email', c2->'contact'->>'email', 'ref', q.ref,
    'name', btrim(coalesce(c2->'contact'->>'salutation', '') || ' ' || (c2->'contact'->>'name')));
end $$;
revoke all on function public.quote_sign_code(text, jsonb) from public, anon, authenticated;
grant execute on function public.quote_sign_code(text, jsonb) to service_role;

create or replace function public.quote_sign_finish(p_key text, p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  o   jsonb := public.quote_sign_open(p_key);
  q   public.quotations;
  s   public.quote_sign_codes;
  c   public.clients;
  h   json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
  v_at timestamptz := now();
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  select * into s from public.quote_sign_codes x
   where x.quotation_id = q.id and x.used_at is null
   order by x.created_at desc limit 1 for update;
  if s.id is null then return jsonb_build_object('error', 'no-code'); end if;
  if s.expires_at <= now() then return jsonb_build_object('error', 'code-expired'); end if;
  if s.tries >= 5 then return jsonb_build_object('error', 'locked'); end if;
  if regexp_replace(coalesce(p_code, ''), '\s+', '', 'g') !~ '^[0-9]{6}$'
     or crypt(regexp_replace(p_code, '\s+', '', 'g'), s.code_hash) <> s.code_hash then
    update public.quote_sign_codes set tries = tries + 1 where id = s.id;
    return jsonb_build_object('error', 'wrong', 'left', greatest(0, 4 - s.tries));
  end if;
  update public.quote_sign_codes set used_at = v_at where id = s.id;
  update public.quotations
     set signed_at = v_at,
         signed = jsonb_build_object('via', 'online') || s.payload || jsonb_build_object('record', jsonb_build_object(
           'at', v_at, 'email', s.email, 'ip', nullif(public.request_ip(), ''), 'country', nullif(public.request_country(), ''),
           'agent', left(coalesce(h ->> 'user-agent', ''), 300),
           'fingerprint', upper(left(encode(digest(q.ref || q.lines::text || q.totals::text || s.payload::text || v_at::text, 'sha256'), 'hex'), 16)))),
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  select * into c from public.clients where id = q.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation website', 'client.quotation', q.brand,
          q.ref || ' signed on the quotation link by ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name'));
  perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(c.owner)],
    'quote.signed', 'Quotation signed · ' || q.brand,
    q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
    q.client_id, q.id::text || ':' || v_at::text);
  return jsonb_build_object('ok', true, 'at', v_at);
end $$;
revoke all on function public.quote_sign_finish(text, text) from public;
grant execute on function public.quote_sign_finish(text, text) to anon, authenticated;

/* A team quotation's link, made the first time it is asked for. */
create or replace function public.quotation_link(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.access_key is null then
    update public.quotations set access_key = public.new_link_key() where id = q.id returning * into q;
  end if;
  return jsonb_build_object('ok', true, 'key', q.access_key);
end $$;
revoke all on function public.quotation_link(uuid) from public, anon;
grant execute on function public.quotation_link(uuid) to authenticated;

/* Who may review: Clients: Quotations at Full Access, or an admin. */
create or replace function public.quote_sign_may_review(p_member uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.team_members m
                  where m.id = p_member and m.active and not coalesce(m.system, false) and m.removed_at is null
                    and (m.is_admin or m.role = 'admin'
                         or public.level_rank(coalesce(m.access ->> 'clients.quotes', m.access ->> 'clients')) >= 3))
$$;
revoke all on function public.quote_sign_may_review(uuid) from public, anon, authenticated;

create or replace function public.quotation_reviewers(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_last uuid;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_last := coalesce(q.reviewer_id, (select x.reviewer_id from public.quotations x
                                      where x.client_id = q.client_id and x.reviewer_id is not null and x.id <> q.id
                                      order by x.submitted_at desc nulls last limit 1));
  return jsonb_build_object('reviewers', coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'code', m.staff_code, 'designation', m.designation,
                                        'last', m.id = v_last)
                     order by m.staff_code nulls last, m.name)
      from public.team_members m
     where m.id <> me.id and public.quote_sign_may_review(m.id)), '[]'::jsonb));
end $$;
revoke all on function public.quotation_reviewers(uuid) from public, anon;
grant execute on function public.quotation_reviewers(uuid) to authenticated;

create or replace function public.quotation_submit(p_id uuid, p_reviewer uuid, p_company jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  rv public.team_members;
  v_fix jsonb;
  v_moved jsonb := '[]'::jsonb;
  v_k text;
  v_words text := '';
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is not null and q.returned_at is null then return jsonb_build_object('error', 'in-review'); end if;
  select * into rv from public.team_members where id = p_reviewer;
  if rv.id is null or not public.quote_sign_may_review(rv.id) then return jsonb_build_object('error', 'bad-reviewer'); end if;
  if rv.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if p_company is not null and jsonb_typeof(p_company) = 'object' then
    v_fix := public.quote_sign_company((q.signed->'company') || p_company);
    if v_fix ? 'error' then return v_fix; end if;
    for v_k in select jsonb_object_keys(v_fix->'company') loop
      if (v_fix->'company'->>v_k) is distinct from (q.signed->'company'->>v_k) then
        v_moved := v_moved || jsonb_build_array(jsonb_build_object('field', v_k, 'from', q.signed->'company'->v_k,
                     'to', v_fix->'company'->v_k, 'by', me.name, 'at', now()));
        v_words := v_words || '; ' || v_k || ': ' || coalesce(q.signed->'company'->>v_k, 'not set') || ' → ' || coalesce(v_fix->'company'->>v_k, 'not set');
      end if;
    end loop;
    if jsonb_array_length(v_moved) > 0 then
      q.signed := q.signed
        || jsonb_build_object('company_signed', coalesce(q.signed->'company_signed', q.signed->'company'))
        || jsonb_build_object('company', v_fix->'company')
        || jsonb_build_object('corrections', coalesce(q.signed->'corrections', '[]'::jsonb) || v_moved);
    end if;
  end if;
  update public.quotations
     set signed = q.signed, submitted_at = now(), submitted_by = me.name, reviewer_id = rv.id, reviewer_name = rv.name,
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · checked and submitted to ' || rv.name || case when v_words <> '' then ' ·' || substr(v_words, 2) else '' end);
  perform public.quote_sign_tell(array[rv.id], 'quote.review', 'Quotation to review · ' || q.brand,
    q.ref || ' · from ' || me.name, q.client_id, q.id::text || ':' || now()::text);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_submit(uuid, uuid, jsonb) from public, anon;
grant execute on function public.quotation_submit(uuid, uuid, jsonb) to authenticated;

create or replace function public.quotation_review(p_id uuid, p_ok boolean, p_note text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  c  public.clients;
  co jsonb;
  v_note text := btrim(coalesce(p_note, ''));
  v_billing text := 'kept';
  v_lines int := 0;
  v_l jsonb;
  v_admin boolean;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is null or q.returned_at is not null then return jsonb_build_object('error', 'not-submitted'); end if;
  v_admin := coalesce(me.is_admin, false) or me.role = 'admin';
  if q.reviewer_id is distinct from me.id and not v_admin then return jsonb_build_object('error', 'not-reviewer'); end if;

  if not coalesce(p_ok, false) then
    if length(v_note) < 2 or length(v_note) > 1000 then return jsonb_build_object('error', 'note-required'); end if;
    update public.quotations set returned_at = now(), return_note = v_note, returned_by = me.name where id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', q.brand, q.ref || ' · sent back by ' || me.name || ': ' || v_note);
    perform public.quote_sign_tell(array[public.quote_sign_member(q.submitted_by)], 'quote.returned',
      'Quotation sent back · ' || q.brand, q.ref || ' · ' || v_note, q.client_id, q.id::text || ':' || now()::text);
    return jsonb_build_object('ok', true, 'returned', true);
  end if;

  select * into c from public.clients where id = q.client_id for update;
  co := q.signed->'company';
  if exists (select 1 from public.bukku_links b where b.kind = 'client' and b.record_id = c.id and b.held_at is not null) then
    v_billing := 'held';
  elsif coalesce(btrim(c.legal_name), '') = '' and coalesce(btrim(c.company_no), '') = '' and coalesce(btrim(c.billing_address), '') = '' then
    if not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'billing-access'); end if;
    update public.clients
       set legal_name = co->>'legal_name', company_no = co->>'company_no',
           company_no_old = coalesce(co->>'company_no_old', company_no_old), tin = coalesce(co->>'tin', tin),
           sst_no = coalesce(co->>'sst_no', sst_no), billing_address = co->>'billing_address',
           finance_email = coalesce(co->>'finance_email', finance_email)
     where id = c.id;
    v_billing := 'filled';
  end if;

  update public.client_services set state = 'confirmed'
   where quotation_id = q.id and archived_at is null and state <> 'confirmed';
  select count(*) into v_lines from public.client_services where quotation_id = q.id and archived_at is null;
  if v_lines = 0 then
    for v_l in select * from jsonb_array_elements(q.lines) loop
      insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                          tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
      values (q.client_id,
              case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
              v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
              case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'confirmed',
              'Quotation ' || q.ref,
              case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
              v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (q.totals->>'term_pct')::numeric else 0 end,
              nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
              q.id, nullif(v_l->>'tax_code', ''));
      v_lines := v_lines + 1;
    end loop;
  end if;

  update public.quotations set reviewed_at = now(), reviewed_by = me.name, reviewed_role = nullif(btrim(coalesce(me.designation, '')), '')
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · reviewed and approved by ' || me.name ||
          case when q.reviewer_id is distinct from me.id then ' in place of ' || coalesce(q.reviewer_name, 'the reviewer') else '' end ||
          ' · ' || v_lines || ' lines confirmed · Billing ' ||
          case v_billing when 'filled' then 'filled from the signing' when 'held' then 'held in Bukku, left as Bukku holds it' else 'kept as it was' end);
  perform public.quote_sign_tell(array_remove(array[public.quote_sign_member(q.submitted_by), public.quote_sign_member(c.owner)], me.id),
    'quote.reviewed', 'Quotation approved · ' || q.brand, q.ref || ' · by ' || me.name, q.client_id, q.id::text);
  return jsonb_build_object('ok', true, 'billing', v_billing, 'lines', v_lines);
end $$;
revoke all on function public.quotation_review(uuid, boolean, text) from public, anon;
grant execute on function public.quotation_review(uuid, boolean, text) to authenticated;

create or replace function public.quotation_paper(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  pl jsonb := coalesce(p_payload, '{}'::jsonb);
  c1 jsonb; c2 jsonb;
  v_name text := btrim(regexp_replace(coalesce(pl->'signer'->>'name', ''), '\s+', ' ', 'g'));
  v_role text := btrim(regexp_replace(coalesce(pl->'signer'->>'designation', ''), '\s+', ' ', 'g'));
  v_day  text := btrim(coalesce(pl->>'day', ''));
  v_scan text := nullif(btrim(coalesce(pl->>'scan', '')), '');
  v_at timestamptz;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  c1 := public.quote_sign_company(pl->'company'); if c1 ? 'error' then return c1; end if;
  c2 := public.quote_sign_contact(pl->'contact'); if c2 ? 'error' then return c2; end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-signer_name'); end if;
  if length(v_role) < 2 or length(v_role) > 80 then return jsonb_build_object('error', 'bad-signer_designation'); end if;
  if v_day !~ '^\d{4}-\d{2}-\d{2}$' or v_day::date > (now() at time zone 'Asia/Kuala_Lumpur')::date
     or v_day::date < (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'bad-day');
  end if;
  if v_scan is not null and v_scan !~ '^https://[^\s"''<>`\\]+$' then return jsonb_build_object('error', 'bad-scan'); end if;
  -- Noon in Malaysia on the day it was signed.
  v_at := (v_day::date + time '12:00') at time zone 'Asia/Kuala_Lumpur';
  update public.quotations
     set signed_at = v_at,
         signed = jsonb_build_object('via', 'paper', 'company', c1->'company', 'contact', c2->'contact',
           'signer', jsonb_build_object('name', v_name, 'designation', v_role), 'signature', null, 'scan', v_scan,
           'record', jsonb_build_object('at', v_at, 'by', me.name, 'entered_at', now())),
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' signed on paper by ' || v_name || ' for ' || (c1->'company'->>'legal_name') || ' on ' ||
          public.register_day(v_day::date) || ' · entered by ' || me.name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_paper(uuid, jsonb) from public, anon;
grant execute on function public.quotation_paper(uuid, jsonb) to authenticated;

create or replace function public.quotation_resign(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  update public.quotations
     set sign_history = coalesce(sign_history, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'signed_at', q.signed_at, 'signed', q.signed, 'withdrawn_at', now(), 'withdrawn_by', me.name)),
         signed_at = null, signed = null, submitted_at = null, submitted_by = null, reviewer_id = null, reviewer_name = null,
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand, q.ref || ' · signature asked again; the earlier one is kept');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_resign(uuid) from public, anon;
grant execute on function public.quotation_resign(uuid) to authenticated;

create or replace function public.quote_website_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  c  public.clients;
  m  public.team_members;
  pm public.team_members;
  k  public.client_contacts;
  d  public.client_documents;
  f  public.client_detail_forms;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_stage text;
  v_portal boolean := false;
  v_billed boolean;
  v_own boolean;
  v_unsent boolean;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  -- Any quotation with a link: a website quotation, or a team's once
  -- `quotation_link` made one (QUOTATION SIGNING).
  select * into w from public.quotations x
   where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  -- A website quotation the team has not sent holds back its price at every
  -- stage, Not proceeding included (audit 2026-10-30).
  v_unsent := q.source = 'website' and q.released_at is null;
  select * into c from public.clients x where x.id = w.client_id;
  if nullif(btrim(coalesce(c.owner, '')), '') is not null then
    select * into m from public.team_members x
     where x.active and not coalesce(x.system, false) and x.removed_at is null and x.name = c.owner
     limit 1;
  end if;
  -- Prepared by: the colleague who made the revision shown; a website
  -- quotation's, the person in charge.
  select * into pm from public.team_members x where x.id = public.quote_sign_member(q.made_by);
  if pm.id is null and q.source = 'website' then pm := m; end if;
  -- The letter that stands on the quotation's lines, the latest first.
  select dd.* into d from public.client_documents dd
   where dd.kind = 'offer' and dd.voided_at is null and dd.superseded_by is null
     and exists (select 1 from public.client_document_services ds
                   join public.client_services s on s.id = ds.service_id
                  where ds.document_id = dd.id and s.quotation_id = q.id)
   order by dd.created_at desc limit 1;
  -- The client's details form is offered only on the website quotation
  -- that made the lead: a later website quotation that matched an existing
  -- lead's email and number never opens that lead's form (2026-10-26, audit).
  v_own := w.source = 'website' and c.created_at >= w.issued_at - interval '1 minute'
           and not exists (select 1 from public.quotations o
                            where o.client_id = c.id and o.issued_at < w.issued_at and o.id <> w.id);
  v_billed := coalesce(btrim(c.legal_name), '') <> '' and coalesce(btrim(c.company_no), '') <> ''
              and coalesce(btrim(c.billing_address), '') <> '';

  if d.id is not null then
    if d.verified_at is not null and c.stage = 'active' then
      v_stage := 'welcome';
      select exists (select 1 from public.client_contacts k
                      where k.client_id = c.id and k.archived_at is null and k.portal_access
                        and lower(btrim(k.email)) = lower(btrim(coalesce(w.contact->>'email', '')))) into v_portal;
    elsif d.signed_at is not null then v_stage := 'signed';
    else v_stage := 'letter';
    end if;
  elsif w.status = 'not_proceeding' or q.status = 'not_proceeding' then
    v_stage := 'closed';
  elsif q.source = 'website' and q.released_at is null then
    -- Being reviewed: nothing priced leaves the database (2026-10-29).
    v_stage := 'review';
  elsif q.signed_at is not null then
    -- Signed on the link or on paper: accepted, then welcome once reviewed
    -- and Active (QUOTATION SIGNING).
    if q.reviewed_at is not null and c.stage = 'active' then
      v_stage := 'welcome';
      select exists (select 1 from public.client_contacts k
                      where k.client_id = c.id and k.archived_at is null and k.portal_access
                        and lower(btrim(k.email)) = lower(btrim(coalesce(q.signed->'contact'->>'email', w.contact->>'email', '')))) into v_portal;
    else v_stage := 'accepted';
    end if;
  elsif q.valid_until < v_today then
    v_stage := 'expired';
  elsif not v_billed and v_own then
    select * into f from public.client_detail_forms x
     where x.client_id = c.id and x.voided_at is null
     order by x.created_at desc limit 1;
    if f.id is not null and f.submitted_at is not null and f.used_at is null then v_stage := 'billing_sent';
    elsif f.id is not null and f.submitted_at is null and f.expires_at > now() then v_stage := 'billing';
    end if;
  elsif v_billed and w.proceed_at is not null and w.source = 'website' then
    v_stage := 'billing_sent';
  end if;
  if v_stage is null then
    v_stage := case when w.proceed_at is not null then 'ready' else 'quote' end;
  end if;
  if q.signed_at is null then
    select * into k from public.client_contacts x
     where x.client_id = c.id and x.archived_at is null and x.is_primary
     order by x.created_at limit 1;
  end if;

  return jsonb_build_object(
    'ref', q.ref, 'first_ref', w.ref, 'revised', q.id <> w.id,
    'brand', coalesce(w.contact->>'brand', w.brand), 'version', case when q.source <> 'website' or q.released_at is not null then q.version end,
    'issued_at', q.issued_at,
    'valid_until', case when not v_unsent then q.valid_until end,
    'lines', case when not v_unsent then q.lines end,
    'totals', case when not v_unsent then q.totals end,
    'reply_due', case when v_stage = 'review' then q.reply_due end,
    'selection', w.selection, 'attention', coalesce(w.contact->>'name', k.name),
    'stage', v_stage,
    'status', case when d.id is not null then 'offer' else q.status end,
    'details_key', case when v_stage = 'billing' then f.access_key end,
    'portal', v_portal,
    'proceed_at', w.proceed_at, 'proceed_due', w.proceed_due,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today,
    'signed', case when q.signed_at is not null then jsonb_build_object('at', q.signed_at, 'via', q.signed->>'via',
                'signer', q.signed->'signer', 'signature', q.signed->'signature', 'company', q.signed->'company',
                'contact', q.signed->'contact', 'record', case when q.signed->>'via' = 'online' then q.signed->'record' end) end,
    'prepared', case when pm.id is not null then jsonb_build_object('name', pm.name, 'title', nullif(btrim(coalesce(pm.designation, '')), ''))
                     when nullif(btrim(coalesce(q.made_by, '')), '') is not null then jsonb_build_object('name', q.made_by, 'title', null) end,
    'reviewed', case when q.reviewed_at is not null then jsonb_build_object('name', q.reviewed_by, 'title', q.reviewed_role, 'at', q.reviewed_at) end,
    'prefill', case when q.signed_at is null and not v_unsent then jsonb_build_object(
      'company', jsonb_build_object('legal_name', coalesce(c.legal_name, ''), 'company_no', coalesce(c.company_no, ''),
                                    'billing_address', coalesce(c.billing_address, ''), 'sst_no', coalesce(c.sst_no, ''), 'tin', coalesce(c.tin, '')),
      'contact', case when k.id is not null then jsonb_build_object('salutation', coalesce(k.salutation, ''), 'name', coalesce(k.name, ''),
                                                                    'phone', coalesce(k.phone, ''), 'email', coalesce(k.email, ''))
                      else jsonb_build_object('salutation', coalesce(w.contact->>'salutation', ''), 'name', coalesce(w.contact->>'name', ''),
                                              'phone', coalesce(w.contact->>'whatsapp', ''), 'email', coalesce(w.contact->>'email', '')) end) end);
end $$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

-- END OF QUOTATION SIGNING --------------------------------------------------

select public.functions_tidy();
