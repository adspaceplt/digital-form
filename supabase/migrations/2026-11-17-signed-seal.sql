-- ===========================================================================
-- SIGNED DOCUMENT SEAL (2026-11-17)
-- ===========================================================================
-- WHY: the user, 2026-11-17 (digital-form-tests specs/SEAL-SPEC.md,
-- decisions 1 to 5, approved with specs/signing-record-mockup.html): once a
-- quotation is signed and approved, the PDF is drawn once, stored privately
-- with its SHA-256 and Document ID, and never drawn again; its last page is
-- the Record of this Document, every step to the second. One mechanism the
-- Employment Offer and Contract reuse: the steps table and the device
-- reading are named for a signed document, never a quotation alone.
--
-- WHAT IT CHANGES
--   * `signing_steps` (RLS on, no policy, no grant): the steps a signed
--     document's own columns do not hold, each with the time, the address
--     and country the database saw and the device as the browser reported
--     it: `opened` (the signer's link read) and `code` (a signing code sent,
--     to which email, in Contacts or not). `doc_kind` names the document's
--     family (`quotation` today).
--   * `seal_device(p)`: the browser's own report (browser, system, screen,
--     time zone, language), held to 200 printable characters.
--   * `quote_opened(p_key, p_device)` (anon): the client's link read, kept
--     once in six hours an address and device, a hundred a quotation at
--     most; a colleague's reading and an unsent website quotation keep none.
--   * `quote_sign_code` keeps the device with the code and files the code
--     step; `quote_sign_finish` keeps it in the signing record (`device`).
--     Every refusal of both is kept.
--   * `quotations` holds its seal: `seal_key` (the private file, never
--     granted), `seal_sha` (the whole file's SHA-256), `seal_pages_sha` (the
--     signed pages', printed on the Record page), `sealed_at`, `sealed_by`.
--     `quotation_seal(p_id, p_key, p_sha, p_pages_sha)` (Clients: Quotations
--     Work, the client in scope) keeps it once the quotation is reviewed,
--     once only (`not-reviewed`, `bad-key`, `bad-sha`; a second answers the
--     first, `kept`), filed `client.quotation`.
--   * `quotation_record(p_id)` (Clients: Quotations View, the client in
--     scope): the Document ID, the seal and every step in time order:
--     issued, sent (the link, WhatsApp, email), opened, code sent, signed,
--     submitted, sent back, confirmed, sealed.
--   * `quotation_seal_key(p_id)` (as the caller, for sign-download) and
--     `quote_seal_key(p_key)` (the service role's): the sealed file's key.
--   * `quote_seal_state(p_key)` (anon): the link's Document ID and whether it
--     is sealed, once ADspace has confirmed it.
--
-- ORDER: 2026-10-07-function-hygiene.sql again (`quote_opened` and
-- `quote_seal_state` join `open_to_anon`), this file (connector), then
-- `sign-upload` and `sign-download`, then the pages. A page served before
-- asks none of these and draws the PDF as before. Safe to run twice.
--
-- ROLLBACK: the pages from before; run the AUDIT FIXES, THIRD BATCH band's
-- `quote_sign_code` and the QUOTATION AUDIT FIXES band's `quote_sign_finish`
-- again. The columns, table and functions may stay.
-- ===========================================================================


-- SIGNED DOCUMENT SEAL --------------------------------------------------------

create table if not exists public.signing_steps (
  id          uuid primary key default gen_random_uuid(),
  doc_kind    text not null check (doc_kind ~ '^[a-z_]{2,30}$'),
  doc_id      uuid not null,
  step        text not null check (step ~ '^[a-z_]{2,30}$'),
  at          timestamptz not null default now(),
  email       text,
  in_contacts boolean,
  ip          text,
  country     text,
  device      text
);
create index if not exists signing_steps_doc_idx on public.signing_steps (doc_kind, doc_id, at);
alter table public.signing_steps enable row level security;
revoke all on table public.signing_steps from public, anon, authenticated;

alter table public.quotations add column if not exists seal_key       text;
alter table public.quotations add column if not exists seal_sha       text;
alter table public.quotations add column if not exists seal_pages_sha text;
alter table public.quotations add column if not exists sealed_at      timestamptz;
alter table public.quotations add column if not exists sealed_by      text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'quotations_seal_sha_check') then
    alter table public.quotations add constraint quotations_seal_sha_check
      check ((seal_sha is null or seal_sha ~ '^[0-9a-f]{64}$') and (seal_pages_sha is null or seal_pages_sha ~ '^[0-9a-f]{64}$'));
  end if;
end $$;
grant select (seal_sha, seal_pages_sha, sealed_at, sealed_by) on table public.quotations to authenticated;

/* The device as the browser reported it: printable, 200 at most. A browser
   never gives a MAC address. */
create or replace function public.seal_device(p text)
returns text
language sql immutable set search_path = public as $$
  select nullif(left(btrim(regexp_replace(regexp_replace(coalesce(p, ''), '[[:cntrl:]<>"`\\]', '', 'g'), '\s+', ' ', 'g')), 200), '')
$$;
revoke all on function public.seal_device(text) from public, anon, authenticated;

create or replace function public.quote_opened(p_key text, p_device text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
  v_ip  text := nullif(public.request_ip(), '');
  v_dev text := public.seal_device(p_device);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if public.is_team() then return jsonb_build_object('ok', true, 'kept', false); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if q.id is null or (q.source = 'website' and q.released_at is null) then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  if exists (select 1 from public.signing_steps s
              where s.doc_kind = 'quotation' and s.doc_id = q.id and s.step = 'opened'
                and s.at > now() - interval '6 hours'
                and s.ip is not distinct from v_ip and s.device is not distinct from v_dev)
     or (select count(*) from public.signing_steps s
          where s.doc_kind = 'quotation' and s.doc_id = q.id and s.step = 'opened') >= 100 then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  insert into public.signing_steps (doc_kind, doc_id, step, ip, country, device)
  values ('quotation', q.id, 'opened', v_ip, nullif(public.request_country(), ''), v_dev);
  return jsonb_build_object('ok', true, 'kept', true);
end $$;
revoke all on function public.quote_opened(text, text) from public;
grant execute on function public.quote_opened(text, text) to anon, authenticated;

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
  v_ip text := nullif(public.request_ip(), '');
  v_dev text := public.seal_device(pl->>'device');
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  -- Read again once the row is held: a colleague's Mark signed, Cancel or
  -- revision meanwhile is seen (audit 2026-11-04).
  o := public.quote_sign_open(p_key);
  if o ? 'error' then return o; end if;
  if (o->>'id')::uuid is distinct from q.id then return jsonb_build_object('error', 'not-found'); end if;
  c1 := public.quote_sign_company(pl->'company'); if c1 ? 'error' then return c1; end if;
  c2 := public.quote_sign_contact(pl->'contact'); if c2 ? 'error' then return c2; end if;
  c3 := public.quote_sign_signer(pl->'signer', pl->'signature'); if c3 ? 'error' then return c3; end if;
  if coalesce(pl->>'agree', '') <> 'true' then return jsonb_build_object('error', 'bad-agree'); end if;
  if (select count(*) from public.quote_sign_codes s
       where s.quotation_id = q.id and s.created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('error', 'too-many');
  end if;
  -- And ten an hour from one address, across every quotation (audit
  -- 2026-11-15): the address is kept an hour at most, let go at the next
  -- request after it.
  update public.quote_sign_codes s set caller_ip = null
   where s.caller_ip is not null and s.created_at < now() - interval '1 hour';
  if v_ip is not null and (select count(*) from public.quote_sign_codes s
       where s.caller_ip = v_ip and s.created_at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('error', 'too-many');
  end if;
  v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.quote_sign_codes (quotation_id, code_hash, email, payload, expires_at, caller_ip)
  values (q.id, crypt(v_code, gen_salt('bf', 6)), c2->'contact'->>'email',
          jsonb_build_object('company', c1->'company', 'contact', c2->'contact', 'signer', c3->'signer', 'signature', c3->'signature',
                             'device', v_dev),
          now() + interval '15 minutes', v_ip)
  returning id into v_id;
  /* The code step of the signed document's record (SIGNED DOCUMENT SEAL):
     the email it went to and whether Contacts holds it. */
  insert into public.signing_steps (doc_kind, doc_id, step, email, in_contacts, ip, device)
  values ('quotation', q.id, 'code', c2->'contact'->>'email',
          exists (select 1 from public.client_contacts k
                   where k.client_id = q.client_id and k.archived_at is null
                     and lower(btrim(coalesce(k.email, ''))) = lower(btrim(coalesce(c2->'contact'->>'email', ''))))
          or lower(btrim(coalesce(q.contact->>'email', ''))) = lower(btrim(coalesce(c2->'contact'->>'email', ''))),
          v_ip, v_dev);
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
  -- Read again once the row is held: a colleague's Mark signed, Cancel or
  -- revision meanwhile is seen (audit 2026-11-04).
  o := public.quote_sign_open(p_key);
  if o ? 'error' then return o; end if;
  if (o->>'id')::uuid is distinct from q.id then return jsonb_build_object('error', 'not-found'); end if;
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
         signed = jsonb_build_object('via', 'online') || (s.payload - 'device') || jsonb_build_object('record', jsonb_build_object(
           'at', v_at, 'email', s.email,
           'in_contacts', exists (select 1 from public.client_contacts k
                                   where k.client_id = q.client_id and k.archived_at is null
                                     and lower(btrim(coalesce(k.email, ''))) = lower(btrim(coalesce(s.email, ''))))
                          or lower(btrim(coalesce(q.contact->>'email', ''))) = lower(btrim(coalesce(s.email, ''))),
           'ip', nullif(public.request_ip(), ''), 'country', nullif(public.request_country(), ''),
           'agent', left(coalesce(h ->> 'user-agent', ''), 300),
           -- The device as the signer's browser reported it with the code.
           'device', s.payload->>'device',
           'fingerprint', upper(left(encode(digest(q.ref || q.lines::text || q.totals::text || s.payload::text || v_at::text, 'sha256'), 'hex'), 16)))),
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  select * into c from public.clients where id = q.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation website', 'client.quotation', q.brand,
          q.ref || ' signed on the quotation link by ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name'));
  -- Who prepared it and the person in charge are told; where neither is
  -- here (a website lead nobody has taken), the team who work leads.
  if public.quote_sign_member(q.made_by) is null and public.quote_sign_member(c.owner) is null then
    perform public.quote_tell(q.client_id, 'quote.signed', 'Quotation signed · ' || q.brand,
      q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
      q.id::text || ':' || v_at::text);
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(c.owner)],
      'quote.signed', 'Quotation signed · ' || q.brand,
      q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
      q.client_id, q.id::text || ':' || v_at::text);
  end if;
  return jsonb_build_object('ok', true, 'at', v_at);
end $$;
revoke all on function public.quote_sign_finish(text, text) from public;
grant execute on function public.quote_sign_finish(text, text) to anon, authenticated;

/* The signed document's record: its Document ID, its seal and every step
   in time order, each with who, and for the signer's own steps the email,
   address, country and device. */
create or replace function public.quotation_record(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  s jsonb;
  v_steps jsonb := '[]'::jsonb;
begin
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  s := q.signed;
  v_steps := jsonb_build_array(jsonb_build_object('step', 'issued', 'at', q.issued_at,
    'by', case when q.source = 'website' then null else q.made_by end, 'team', q.source <> 'website',
    'note', 'Rate Card v.' || q.version));
  if q.source = 'website' and q.released_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'sent', 'at', q.released_at, 'by', q.released_by,
      'team', true, 'via', 'link'));
  end if;
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', 'sent', 'at', w.created_at, 'by', coalesce(w.created_by, 'ADspace'), 'team', true,
             'via', 'whatsapp', 'to', w.to_name,
             'state', case when w.read_at is not null then 'read' when w.delivered_at is not null then 'delivered' else w.state end))
      from public.wa_outbox w
     where w.ref_kind = 'quotation' and w.ref_id = q.id and coalesce(w.state, '') <> 'failed'), '[]'::jsonb);
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', 'sent', 'at', e.created_at,
             'by', coalesce((select m.name from public.team_members m where m.id = e.sent_by), 'ADspace'), 'team', true,
             'via', 'email', 'to', e.to_email, 'state', e.status))
      from public.client_emails e
     where e.kind = 'quotation' and e.ref_id = q.id and e.status <> 'failed'), '[]'::jsonb);
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', g.step, 'at', g.at, 'team', false, 'email', g.email,
             'in_contacts', g.in_contacts, 'ip', g.ip, 'country', g.country, 'device', g.device))
      from public.signing_steps g
     where g.doc_kind = 'quotation' and g.doc_id = q.id), '[]'::jsonb);
  if q.signed_at is not null and s is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'signed', 'at', q.signed_at, 'team', false,
      'by', s->'signer'->>'name', 'role', s->'signer'->>'designation', 'via', coalesce(s->>'via', 'online'),
      'company', s->'company'->>'legal_name',
      'email', s->'record'->>'email', 'in_contacts', (s->'record'->>'in_contacts')::boolean,
      'ip', s->'record'->>'ip', 'country', s->'record'->>'country',
      'device', coalesce(s->'record'->>'device', s->'record'->>'agent'),
      'entered_by', case when s->>'via' = 'paper' then s->'record'->>'by' end));
  end if;
  if q.submitted_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'submitted', 'at', q.submitted_at, 'team', true,
      'by', q.submitted_by, 'to', q.reviewer_name));
  end if;
  if q.returned_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'returned', 'at', q.returned_at, 'team', true,
      'by', q.returned_by, 'note', q.return_note));
  end if;
  if q.reviewed_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'confirmed', 'at', q.reviewed_at, 'team', true,
      'by', q.reviewed_by, 'role', q.reviewed_role));
  end if;
  if q.sealed_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'sealed', 'at', q.sealed_at, 'team', true,
      'by', q.sealed_by, 'note', q.seal_sha));
  end if;
  return jsonb_build_object('id', q.id, 'ref', q.ref, 'brand', q.brand, 'company', s->'company'->>'legal_name',
    'signed', q.signed_at is not null, 'confirmed', q.reviewed_at is not null,
    'seal', case when q.seal_key is null then null else jsonb_build_object('sha', q.seal_sha, 'pages_sha', q.seal_pages_sha,
                 'at', q.sealed_at, 'by', q.sealed_by) end,
    'steps', coalesce((select jsonb_agg(x order by (x->>'at')::timestamptz, x->>'step') from jsonb_array_elements(v_steps) x), '[]'::jsonb));
end $$;
revoke all on function public.quotation_record(uuid) from public, anon;
grant execute on function public.quotation_record(uuid) to authenticated;

/* The sealed file, kept once: drawn by the colleague's browser once the
   quotation is reviewed, stored under the client's private folder, never
   replaced. */
create or replace function public.quotation_seal(p_id uuid, p_key text, p_sha text, p_pages_sha text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  if q.seal_key is not null then return jsonb_build_object('ok', true, 'kept', true, 'sha', q.seal_sha); end if;
  if coalesce(p_key, '') !~ ('^private/' || q.client_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$') then
    return jsonb_build_object('error', 'bad-key');
  end if;
  if coalesce(p_sha, '') !~ '^[0-9a-f]{64}$' or coalesce(p_pages_sha, '') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('error', 'bad-sha');
  end if;
  update public.quotations
     set seal_key = p_key, seal_sha = p_sha, seal_pages_sha = p_pages_sha, sealed_at = now(), sealed_by = me.name
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · signed copy sealed · SHA-256 ' || left(p_sha, 4) || '…' || right(p_sha, 4));
  return jsonb_build_object('ok', true, 'sha', p_sha);
end $$;
revoke all on function public.quotation_seal(uuid, text, text, text) from public, anon;
grant execute on function public.quotation_seal(uuid, text, text, text) to authenticated;

-- The sealed file's key, as the caller reads the quotation (sign-download).
create or replace function public.quotation_seal_key(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
begin
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.seal_key is null then return jsonb_build_object('error', 'not-kept'); end if;
  return jsonb_build_object('key', q.seal_key, 'client', q.client_id);
end $$;
revoke all on function public.quotation_seal_key(uuid) from public, anon;
grant execute on function public.quotation_seal_key(uuid) to authenticated;

-- The client's link: the sealed file of the quotation it shows, once confirmed.
create or replace function public.quote_seal_key(p_key text)
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
  if q.id is null or q.reviewed_at is null or q.seal_key is null then return jsonb_build_object('error', 'not-kept'); end if;
  return jsonb_build_object('key', q.seal_key, 'client', q.client_id);
end $$;
revoke all on function public.quote_seal_key(text) from public, anon, authenticated;
grant execute on function public.quote_seal_key(text) to service_role;

-- What the client's link reads of the seal: the Document ID once confirmed.
create or replace function public.quote_seal_state(p_key text)
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
  if q.id is null or q.reviewed_at is null then return jsonb_build_object('confirmed', false); end if;
  return jsonb_build_object('confirmed', true, 'id', q.id, 'confirmed_at', q.reviewed_at, 'sealed', q.seal_key is not null);
end $$;
revoke all on function public.quote_seal_state(text) from public;
grant execute on function public.quote_seal_state(text) to anon, authenticated;

-- END OF SIGNED DOCUMENT SEAL -------------------------------------------------

select public.functions_tidy();
