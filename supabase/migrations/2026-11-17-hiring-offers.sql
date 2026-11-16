-- ===========================================================================
-- HIRING OFFERS AND CONTRACTS — the Employment Offer and the Employment
-- Contract, signed on the candidate's page, by a scan or on paper, then
-- confirmed and sealed (2026-11-17, release H2 step D)
-- ===========================================================================
-- WHY (HR-SPEC.md decisions 4, 5, 10, 14, 15): once a candidate is to
-- proceed, the part or the Owner drafts the offer; the part sets the salary
-- behind the master code; the candidate reads it on their page behind a
-- six-digit code emailed to them and a caution step, then accepts or
-- declines it; the contract follows an offer confirmed and is signed in the
-- page (typed name, drawn signature, the code's email kept), or by a scan,
-- or on paper; the part confirms (countersigns), a stamp certificate
-- number optional, and the confirmed copy is sealed once, never drawn again.
--
-- The salary (decision 10) lives in `hiring_doc_pay` alone, read and written
-- only by `hiring_doc_pay_get` / `hiring_doc_pay_set` (the part and a live
-- unlock of the master code) and by the candidate's own view
-- (`careers_doc_open` / `careers_doc_read`, behind the emailed code). Never in
-- a list, a notice, an email, the Activity record or the record's history.
--
-- WHAT IT CHANGES
--   * `hiring_docs` (a document a row: its Document ID, kind, state,
--     reference, terms, signing, confirmation, stamp and seal),
--     `hiring_doc_pay` (the salary), `hiring_doc_codes` (the candidate's
--     codes, hashed, and the view they open): RLS on, no policy, no grant.
--   * `hiring_unlock(p_code)` (the part's master-code unlock, the same token
--     Performance and Personnel take), `hiring_docs_of`, `hiring_doc_save`,
--     `hiring_doc_pay_set`, `hiring_doc_pay_get`, `hiring_doc_send`,
--     `hiring_doc_withdraw`, `hiring_doc_mark`, `hiring_doc_send_back`,
--     `hiring_doc_confirm`, `hiring_doc_signed`, `hiring_doc_seal`, `hiring_doc_void`,
--     `hiring_doc_replace`, `hiring_doc_delete`, `hiring_doc_record`,
--     `hiring_doc_mail_prepare`, `hiring_doc_mail_done`;
--     `hiring_doc_code` (the service role's: hiring-mail emails the code);
--     anon `careers_doc_open`, `careers_doc_read`, `careers_doc_answer`;
--     `careers_read` restated with the candidate's documents.
--   * A document's files (a scan, the stamp, the sealed copy) live in the
--     private `hiring` bucket under the candidate's folder and are queued
--     for the console to take out of Storage when the document goes
--     (trigger `hiring_docs_files_gone`).
--
-- ORDER: this file (connector; the parts holding `delete` in the SQL
-- Editor), then hiring-mail deployed, then the pages. Safe to run twice.
-- ROLLBACK: drop the three tables and the new functions; careers_read as
-- HIRING OUTCOMES left it.
-- ===========================================================================

-- HIRING OFFERS AND CONTRACTS ---------------------------------------------------

create table if not exists public.hiring_docs (
  id            uuid primary key default gen_random_uuid(),
  candidate_id  uuid not null references public.hiring_candidates(id) on delete cascade,
  kind          text not null check (kind in ('offer', 'contract')),
  state         text not null default 'draft'
                check (state in ('draft', 'sent', 'withdrawn', 'declined', 'signed', 'confirmed', 'void')),
  serial        text check (serial is null or serial ~ '^ADHR/(OFR|EMP)[0-9]{7}$'),
  terms         jsonb not null default '{}'::jsonb,
  replaces      uuid,
  made_by       uuid references public.team_members(id) on delete set null,
  made_at       timestamptz not null default now(),
  sent_by       uuid references public.team_members(id) on delete set null,
  sent_at       timestamptz,
  reply_by      timestamptz,
  answered_at   timestamptz,
  decline_note  text check (decline_note is null or char_length(decline_note) <= 500),
  signed        jsonb,
  signed_at     timestamptz,
  history       jsonb not null default '[]'::jsonb,
  returned_at   timestamptz,
  returned_by   text,
  returned_note text check (returned_note is null or char_length(returned_note) <= 500),
  confirmed_by  uuid references public.team_members(id) on delete set null,
  confirmed_at  timestamptz,
  stamp_no      text check (stamp_no is null or stamp_no ~ '^[A-Za-z0-9/\-]{4,40}$'),
  stamp_path    text check (stamp_path is null or char_length(stamp_path) <= 300),
  seal_path     text check (seal_path is null or char_length(seal_path) <= 300),
  seal_sha      text check (seal_sha is null or seal_sha ~ '^[0-9a-f]{64}$'),
  seal_pages_sha text check (seal_pages_sha is null or seal_pages_sha ~ '^[0-9a-f]{64}$'),
  sealed_at     timestamptz,
  sealed_by     text,
  void_note     text check (void_note is null or char_length(void_note) <= 500),
  voided_at     timestamptz,
  voided_by     text,
  mail          text,
  mail_at       timestamptz,
  updated_at    timestamptz not null default now()
);
create index if not exists hiring_docs_candidate_idx on public.hiring_docs (candidate_id, made_at desc);
create unique index if not exists hiring_docs_serial_idx on public.hiring_docs (serial) where serial is not null and state <> 'void';
alter table public.hiring_docs enable row level security;
revoke all on table public.hiring_docs from public, anon, authenticated;

create table if not exists public.hiring_doc_pay (
  doc_id     uuid primary key references public.hiring_docs(id) on delete cascade,
  basic      numeric(12, 2) not null check (basic > 0 and basic < 1000000),
  probation  numeric(12, 2) check (probation is null or (probation > 0 and probation < 1000000)),
  set_by     uuid references public.team_members(id) on delete set null,
  set_at     timestamptz not null default now()
);
alter table public.hiring_doc_pay enable row level security;
revoke all on table public.hiring_doc_pay from public, anon, authenticated;

create table if not exists public.hiring_doc_codes (
  id         uuid primary key default gen_random_uuid(),
  doc_id     uuid not null references public.hiring_docs(id) on delete cascade,
  code_hash  text not null,
  email      text not null,
  tries      int not null default 0,
  expires_at timestamptz not null,
  used_at    timestamptz,
  view_hash  text,
  view_until timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists hiring_doc_codes_doc_idx on public.hiring_doc_codes (doc_id, created_at desc);
alter table public.hiring_doc_codes enable row level security;
revoke all on table public.hiring_doc_codes from public, anon, authenticated;

/* The part's master-code unlock: the same token Performance and Personnel
   take, counted and locked as they count it. */
create or replace function public.hiring_unlock(p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  m public.team_members; h text; a public.perf_attempts; tok text; f integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select value into h from public.app_secrets where key = 'perf_code';
  if coalesce(h, '') = '' then return jsonb_build_object('error', 'no-code'); end if;
  insert into public.perf_attempts (team_member_id, failures) values (m.id, 0)
  on conflict (team_member_id) do nothing;
  select * into a from public.perf_attempts where team_member_id = m.id for update;
  if a.locked_until > now() then
    return jsonb_build_object('error', 'locked', 'until', a.locked_until);
  end if;
  if crypt(coalesce(p_code, ''), h) <> h then
    f := case when a.locked_until is not null then 1 else coalesce(a.failures, 0) + 1 end;
    update public.perf_attempts set failures = f,
           locked_until = case when f >= 5 then now() + interval '15 minutes' end
     where team_member_id = m.id;
    perform public.perf_log(null, null, 'unlock_failed', jsonb_build_object('failures', f));
    if f >= 5 then
      return jsonb_build_object('error', 'locked', 'until', now() + interval '15 minutes');
    end if;
    return jsonb_build_object('error', 'wrong-code', 'left', 5 - f);
  end if;
  update public.perf_attempts set failures = 0, locked_until = null where team_member_id = m.id;
  tok := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.perf_unlocks (token_hash, team_member_id, expires_at)
  values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), m.id, now() + interval '15 minutes');
  perform public.perf_log(null, null, 'unlocked', '{}'::jsonb);
  return jsonb_build_object('token', tok, 'expires_at', now() + interval '15 minutes');
end $$;
revoke all on function public.hiring_unlock(text) from public, anon;
grant execute on function public.hiring_unlock(text) to authenticated;

/* A live unlock for the part, kept alive by use; null when it stands. */
create or replace function public.hiring_pay_check(p_token text)
returns text
language plpgsql security definer set search_path = public as $$
declare m public.team_members; n integer;
begin
  m := public.ops_me();
  if m.id is null then return 'not-team'; end if;
  if not public.ops_granted('team.hiring', 'work') then return 'denied'; end if;
  if not public.perf_code_set() then return 'no-code'; end if;
  update public.perf_unlocks set expires_at = now() + interval '15 minutes'
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and team_member_id = m.id and expires_at > now();
  get diagnostics n = row_count;
  if n = 0 then return 'code-needed'; end if;
  return null;
end $$;
revoke all on function public.hiring_pay_check(text) from public, anon, authenticated;

/* The terms a document holds, checked: never a salary (that is
   `hiring_doc_pay`'s). */
create or replace function public.hiring_doc_terms(p_kind text, p jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  t jsonb := coalesce(p, '{}'::jsonb);
  v_type text := coalesce(t->>'type', '');
  v_prob int; v_reply int; v_start date; v_end date;
  v_txt text;
begin
  if char_length(btrim(coalesce(t->>'position', ''))) not between 2 and 80 then return jsonb_build_object('error', 'bad-position'); end if;
  if v_type not in ('permanent', 'contract', 'intern', 'part_time') then return jsonb_build_object('error', 'bad-type'); end if;
  begin
    v_prob := coalesce(nullif(t->>'probation_months', ''), '0')::int;
    v_reply := coalesce(nullif(t->>'reply_days', ''), case when p_kind = 'offer' then '3' else '7' end)::int;
    v_start := nullif(t->>'start', '')::date;
    v_end := nullif(t->>'end', '')::date;
  exception when others then return jsonb_build_object('error', 'bad-request');
  end;
  if v_prob < 0 or v_prob > 12 then return jsonb_build_object('error', 'bad-probation'); end if;
  if v_reply < 1 or v_reply > 14 then return jsonb_build_object('error', 'bad-reply'); end if;
  if v_start is null or v_start < date '2023-08-14' or v_start > date '2099-12-31' then return jsonb_build_object('error', 'bad-start'); end if;
  if v_type in ('contract', 'intern') and (v_end is null or v_end <= v_start) then return jsonb_build_object('error', 'bad-end'); end if;
  if v_type not in ('contract', 'intern') then v_end := null; end if;
  foreach v_txt in array array['scope', 'duties', 'place'] loop
    if char_length(coalesce(t->>v_txt, '')) > (case v_txt when 'duties' then 2000 else 300 end) then
      return jsonb_build_object('error', 'too-long', 'field', v_txt);
    end if;
  end loop;
  if p_kind = 'offer' and char_length(btrim(coalesce(t->>'scope', ''))) < 2 then return jsonb_build_object('error', 'bad-scope'); end if;
  if p_kind = 'contract' and char_length(btrim(coalesce(t->>'duties', ''))) < 2 then return jsonb_build_object('error', 'bad-duties'); end if;
  return jsonb_build_object('ok', true, 'terms', jsonb_strip_nulls(jsonb_build_object(
    'position', btrim(t->>'position'), 'type', v_type, 'probation_months', v_prob, 'reply_days', v_reply,
    'start', v_start, 'end', v_end,
    'scope', nullif(btrim(coalesce(t->>'scope', '')), ''), 'duties', nullif(btrim(coalesce(t->>'duties', '')), ''),
    'place', nullif(btrim(coalesce(t->>'place', '')), ''))));
end $$;
revoke all on function public.hiring_doc_terms(text, jsonb) from public, anon, authenticated;

/* A document as the console reads it: never the salary, only whether one
   is set. */
create or replace function public.hiring_doc_row(d public.hiring_docs)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', d.id, 'kind', d.kind, 'state', d.state, 'serial', d.serial, 'terms', d.terms, 'replaces', d.replaces,
    'made_by', (select t.name from public.team_members t where t.id = d.made_by), 'made_at', d.made_at,
    'sent_by', (select t.name from public.team_members t where t.id = d.sent_by),
    'sent_role', (select t.designation from public.team_members t where t.id = d.sent_by), 'sent_at', d.sent_at,
    'reply_by', d.reply_by, 'expired', d.state = 'sent' and d.reply_by <= now(),
    'answered_at', d.answered_at, 'decline_note', d.decline_note,
    'signed', case when d.signed is not null then jsonb_strip_nulls(jsonb_build_object('via', d.signed->>'via',
      'name', d.signed->>'name', 'on', d.signed->>'on', 'has_scan', d.signed ? 'path', 'path', d.signed->>'path',
      'email', d.signed->'record'->>'email')) end,
    'signed_at', d.signed_at, 'returned_at', d.returned_at, 'returned_by', d.returned_by, 'returned_note', d.returned_note,
    'confirmed_by', (select t.name from public.team_members t where t.id = d.confirmed_by), 'confirmed_at', d.confirmed_at,
    'stamp_no', d.stamp_no, 'stamp_path', d.stamp_path, 'seal_path', d.seal_path, 'seal_sha', d.seal_sha,
    'sealed_at', d.sealed_at, 'void_note', d.void_note, 'voided_at', d.voided_at, 'mail', d.mail, 'mail_at', d.mail_at,
    'pay_set', exists (select 1 from public.hiring_doc_pay p where p.doc_id = d.id), 'updated_at', d.updated_at))
$$;
revoke all on function public.hiring_doc_row(public.hiring_docs) from public, anon, authenticated;

create or replace function public.hiring_docs_of(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_role text := public.hiring_role(p_id);
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(public.hiring_doc_row(d) order by d.made_at desc)
    from public.hiring_docs d where d.candidate_id = p_id), '[]'::jsonb));
end $$;
grant execute on function public.hiring_docs_of(uuid) to authenticated;

/* A draft made or edited: the offer once the candidate is to proceed, the
   contract once an offer is confirmed; one live document of each kind. */
create or replace function public.hiring_doc_save(p_candidate uuid, p_doc uuid, p_kind text, p_terms jsonb, p_expected timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_candidate);
  c public.hiring_candidates;
  d public.hiring_docs;
  t jsonb;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_candidate for update;
  if c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if p_doc is not null then
    select * into d from public.hiring_docs where id = p_doc and candidate_id = p_candidate for update;
    if d.id is null then return jsonb_build_object('error', 'gone'); end if;
    if d.state <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
    if p_expected is not null and d.updated_at <> p_expected then
      return jsonb_build_object('error', 'stale', 'row', public.hiring_doc_row(d));
    end if;
    t := public.hiring_doc_terms(d.kind, p_terms);
    if t ? 'error' then return t; end if;
    update public.hiring_docs set terms = t->'terms', updated_at = now() where id = d.id returning * into d;
    perform public.hiring_log(c.id, 'candidate.document', (case d.kind when 'offer' then 'Employment Offer' else 'Employment Contract' end) || ' draft edited');
    return jsonb_build_object('ok', true, 'row', public.hiring_doc_row(d));
  end if;
  if coalesce(p_kind, '') not in ('offer', 'contract') then return jsonb_build_object('error', 'bad-request'); end if;
  if c.stage <> 'offer' then return jsonb_build_object('error', 'not-offer'); end if;
  if p_kind = 'contract' and not exists (select 1 from public.hiring_docs x where x.candidate_id = c.id and x.kind = 'offer' and x.state = 'confirmed') then
    return jsonb_build_object('error', 'offer-first');
  end if;
  if exists (select 1 from public.hiring_docs x where x.candidate_id = c.id and x.kind = p_kind
              and x.state in ('draft', 'sent', 'signed', 'confirmed') and x.replaces is null
              and not exists (select 1 from public.hiring_docs y where y.replaces = x.id)) then
    return jsonb_build_object('error', 'exists');
  end if;
  t := public.hiring_doc_terms(p_kind, p_terms);
  if t ? 'error' then return t; end if;
  insert into public.hiring_docs (candidate_id, kind, terms, made_by) values (c.id, p_kind, t->'terms', me.id) returning * into d;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.document', (case p_kind when 'offer' then 'Employment Offer' else 'Employment Contract' end) || ' drafted');
  return jsonb_build_object('ok', true, 'row', public.hiring_doc_row(d));
end $$;
grant execute on function public.hiring_doc_save(uuid, uuid, text, jsonb, timestamptz) to authenticated;

/* The salary: the part's alone, behind the master code; a draft's only. */
create or replace function public.hiring_doc_pay_set(p_doc uuid, p_basic numeric, p_probation numeric, p_token text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  d public.hiring_docs;
  v_err text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null or public.hiring_role(d.candidate_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  v_err := public.hiring_pay_check(p_token);
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  if d.state <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  if p_basic is null or p_basic <= 0 or p_basic >= 1000000 or p_basic <> round(p_basic, 2) then return jsonb_build_object('error', 'bad-basic'); end if;
  if p_probation is not null and (p_probation <= 0 or p_probation >= 1000000 or p_probation <> round(p_probation, 2)) then
    return jsonb_build_object('error', 'bad-probation-pay');
  end if;
  insert into public.hiring_doc_pay (doc_id, basic, probation, set_by, set_at)
  values (d.id, p_basic, p_probation, me.id, now())
  on conflict (doc_id) do update set basic = excluded.basic, probation = excluded.probation, set_by = excluded.set_by, set_at = now();
  update public.hiring_docs set updated_at = now() where id = d.id;
  perform public.hiring_log(d.candidate_id, 'candidate.document', 'Salary changed');
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_pay_set(uuid, numeric, numeric, text) to authenticated;

create or replace function public.hiring_doc_pay_get(p_doc uuid, p_token text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  d public.hiring_docs;
  p public.hiring_doc_pay;
  v_err text;
begin
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null or public.hiring_role(d.candidate_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  v_err := public.hiring_pay_check(p_token);
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  select * into p from public.hiring_doc_pay where doc_id = d.id;
  return jsonb_build_object('ok', true, 'basic', p.basic, 'probation', p.probation);
end $$;
grant execute on function public.hiring_doc_pay_get(uuid, text) to authenticated;

/* The next reference of a kind and month: ADHR/OFR{YYMM}{NNN} for an
   offer, ADHR/EMP{YYMM}{NNN} for a contract, under the kind's lock. */
create or replace function public.hiring_doc_serial(p_kind text)
returns text language plpgsql volatile security definer set search_path = public as $$
declare
  v_pre text := 'ADHR/' || case p_kind when 'offer' then 'OFR' else 'EMP' end || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYMM');
  v_n int;
begin
  perform pg_advisory_xact_lock(hashtext('hiring_doc_serial:' || p_kind));
  select coalesce(max(right(d.serial, 3)::int), 0) + 1 into v_n
    from public.hiring_docs d where d.serial like v_pre || '___';
  if v_n > 999 then raise exception 'no-serial'; end if;
  return v_pre || lpad(v_n::text, 3, '0');
end $$;
revoke all on function public.hiring_doc_serial(text) from public, anon, authenticated;

/* Send: the draft goes to the candidate's page with its reference and the
   days to answer; a replacement takes the reference of the one it
   replaces, which is voided. */
create or replace function public.hiring_doc_send(p_doc uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  d public.hiring_docs;
  o public.hiring_docs;
  c public.hiring_candidates;
  v_role text;
  v_serial text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  if not exists (select 1 from public.hiring_doc_pay p where p.doc_id = d.id) then return jsonb_build_object('error', 'no-pay'); end if;
  select * into c from public.hiring_candidates where id = d.candidate_id for update;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage <> 'offer' then return jsonb_build_object('error', 'not-offer'); end if;
  if d.replaces is not null then
    select * into o from public.hiring_docs where id = d.replaces for update;
    if o.id is null or o.state not in ('sent', 'withdrawn', 'declined', 'signed') then return jsonb_build_object('error', 'replaced'); end if;
    v_serial := o.serial;
    update public.hiring_docs set state = 'void', void_note = 'Replaced', voided_at = now(), voided_by = me.name, updated_at = now()
     where id = o.id;
  else
    v_serial := public.hiring_doc_serial(d.kind);
  end if;
  update public.hiring_docs set state = 'sent', serial = v_serial, sent_by = me.id, sent_at = now(),
    reply_by = now() + make_interval(days => coalesce((d.terms->>'reply_days')::int, 3)), mail = null, mail_at = null, updated_at = now()
   where id = d.id returning * into d;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.document', (case d.kind when 'offer' then 'Employment Offer ' else 'Employment Contract ' end) || v_serial || ' sent');
  return jsonb_build_object('ok', true, 'row', public.hiring_doc_row(d));
end $$;
grant execute on function public.hiring_doc_send(uuid) to authenticated;

/* Withdraw a sent document from the candidate's page, or Restore it while
   its days to answer run. */
create or replace function public.hiring_doc_withdraw(p_doc uuid, p_restore boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_restore, false) then
    if d.state <> 'withdrawn' then return jsonb_build_object('ok', true, 'same', true); end if;
    if d.reply_by <= now() then return jsonb_build_object('error', 'expired'); end if;
    update public.hiring_docs set state = 'sent', updated_at = now() where id = d.id;
    perform public.hiring_log(d.candidate_id, 'candidate.document', d.serial || ' restored');
  else
    if d.state <> 'sent' then return jsonb_build_object('error', 'not-sent'); end if;
    update public.hiring_docs set state = 'withdrawn', updated_at = now() where id = d.id;
    perform public.hiring_log(d.candidate_id, 'candidate.document', d.serial || ' withdrawn');
  end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_withdraw(uuid, boolean) to authenticated;

/* Signed outside the page: a scan the candidate signed by hand, or a copy
   handed in on paper and scanned by the team, with the day it was signed. */
create or replace function public.hiring_doc_mark(p_doc uuid, p_route text, p_on date, p_path text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  d public.hiring_docs; v_role text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state not in ('sent', 'withdrawn') then return jsonb_build_object('error', 'not-sent'); end if;
  if coalesce(p_route, '') not in ('scan', 'paper') then return jsonb_build_object('error', 'bad-request'); end if;
  if p_on is null or p_on > v_today or p_on < (d.sent_at at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'bad-date'); end if;
  if coalesce(p_path, '') !~ ('^' || d.candidate_id::text || '/[0-9]{10,16}-[A-Za-z0-9._ -]{1,120}\.pdf$') then
    return jsonb_build_object('error', 'bad-file');
  end if;
  update public.hiring_docs set state = 'signed', signed_at = now(), answered_at = now(),
    signed = jsonb_build_object('via', p_route, 'on', p_on, 'path', p_path, 'record', jsonb_build_object('by', me.name, 'at', now())),
    updated_at = now()
   where id = d.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
  perform public.hiring_log(d.candidate_id, 'candidate.document', d.serial || case p_route when 'scan' then ' signed by scan' else ' signed on paper' end ||
    ' on ' || public.register_day(p_on));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_mark(uuid, text, date, text) to authenticated;

/* Send back a signed document with a reason: the signing is kept in its
   history and the candidate answers again. */
create or replace function public.hiring_doc_send_back(p_doc uuid, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'signed' then return jsonb_build_object('error', 'not-signed'); end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 2 and 500 then return jsonb_build_object('error', 'bad-note'); end if;
  update public.hiring_docs set state = 'sent', history = history || jsonb_build_array(jsonb_build_object('signed', signed, 'at', signed_at,
      'returned_at', now(), 'returned_by', me.name, 'note', btrim(p_note))),
    signed = null, signed_at = null, answered_at = null, returned_at = now(), returned_by = me.name, returned_note = btrim(p_note),
    reply_by = now() + make_interval(days => coalesce((d.terms->>'reply_days')::int, 3)), updated_at = now()
   where id = d.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
  perform public.hiring_log(d.candidate_id, 'candidate.document', d.serial || ' sent back: ' || btrim(p_note));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_send_back(uuid, text) to authenticated;

/* Confirm (countersign): the part's alone, with a stamp certificate number
   and file where the document was stamped. */
create or replace function public.hiring_doc_confirm(p_doc uuid, p_stamp_no text, p_stamp_path text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  if public.hiring_role(d.candidate_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'signed' then return jsonb_build_object('error', 'not-signed'); end if;
  if nullif(btrim(coalesce(p_stamp_no, '')), '') is not null and btrim(p_stamp_no) !~ '^[A-Za-z0-9/\-]{4,40}$' then
    return jsonb_build_object('error', 'bad-stamp');
  end if;
  if nullif(p_stamp_path, '') is not null and p_stamp_path !~ ('^' || d.candidate_id::text || '/[0-9]{10,16}-[A-Za-z0-9._ -]{1,120}\.pdf$') then
    return jsonb_build_object('error', 'bad-file');
  end if;
  update public.hiring_docs set state = 'confirmed', confirmed_by = me.id, confirmed_at = now(),
    stamp_no = nullif(btrim(coalesce(p_stamp_no, '')), ''), stamp_path = nullif(p_stamp_path, ''), updated_at = now()
   where id = d.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
  perform public.hiring_log(d.candidate_id, 'candidate.document', d.serial || ' confirmed' ||
    case when nullif(btrim(coalesce(p_stamp_no, '')), '') is not null then ' · stamped' else '' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_confirm(uuid, text, text) to authenticated;

/* The sealed copy, kept once: drawn by the colleague's browser once the
   document is confirmed, stored in the candidate's private folder. */
create or replace function public.hiring_doc_seal(p_doc uuid, p_path text, p_sha text, p_pages_sha text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed'); end if;
  if d.seal_path is not null then return jsonb_build_object('ok', true, 'kept', true, 'path', d.seal_path); end if;
  if coalesce(p_path, '') !~ ('^' || d.candidate_id::text || '/sealed-[0-9a-f-]{36}\.pdf$') then return jsonb_build_object('error', 'bad-file'); end if;
  if coalesce(p_sha, '') !~ '^[0-9a-f]{64}$' or coalesce(p_pages_sha, '') !~ '^[0-9a-f]{64}$' then return jsonb_build_object('error', 'bad-sha'); end if;
  update public.hiring_docs set seal_path = p_path, seal_sha = p_sha, seal_pages_sha = p_pages_sha, sealed_at = now(), sealed_by = me.name,
    updated_at = now() where id = d.id;
  perform public.hiring_log(d.candidate_id, 'candidate.document', d.serial || ' sealed');
  return jsonb_build_object('ok', true, 'path', p_path);
end $$;
grant execute on function public.hiring_doc_seal(uuid, text, text, text) to authenticated;

/* The candidate's signing as the sealed copy prints it (the signature drawn
   and the NRIC or passport number): the part's, behind the master code. */
create or replace function public.hiring_doc_signed(p_doc uuid, p_token text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.hiring_docs; v_err text;
begin
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null or public.hiring_role(d.candidate_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  v_err := public.hiring_pay_check(p_token);
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  return jsonb_build_object('ok', true, 'signed', d.signed);
end $$;
grant execute on function public.hiring_doc_signed(uuid, text) to authenticated;

/* Void, with a reason: the part's alone; a signed or confirmed copy is
   kept. A candidate who did not join reads Withdrawn after signing. */
create or replace function public.hiring_doc_void(p_doc uuid, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  if public.hiring_role(d.candidate_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if d.state in ('draft', 'void') then return jsonb_build_object('error', 'bad-state'); end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 2 and 500 then return jsonb_build_object('error', 'bad-note'); end if;
  update public.hiring_docs set state = 'void', void_note = btrim(p_note), voided_at = now(), voided_by = me.name, updated_at = now()
   where id = d.id;
  perform public.hiring_log(d.candidate_id, 'candidate.document', d.serial || ' voided: ' || btrim(p_note));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_void(uuid, text) to authenticated;

/* Replace: a new draft of a sent, withdrawn, declined or signed document,
   its terms copied (the salary is set again behind the master code); on
   Send it takes the reference and the earlier one is voided. */
create or replace function public.hiring_doc_replace(p_doc uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; n public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state not in ('sent', 'withdrawn', 'declined', 'signed') then return jsonb_build_object('error', 'bad-state'); end if;
  if exists (select 1 from public.hiring_docs x where x.replaces = d.id and x.state = 'draft') then return jsonb_build_object('error', 'exists'); end if;
  insert into public.hiring_docs (candidate_id, kind, terms, replaces, made_by)
  values (d.candidate_id, d.kind, d.terms, d.id, me.id) returning * into n;
  perform public.hiring_log(d.candidate_id, 'candidate.document', 'Replacement for ' || d.serial || ' drafted');
  return jsonb_build_object('ok', true, 'row', public.hiring_doc_row(n));
end $$;
grant execute on function public.hiring_doc_replace(uuid) to authenticated;

/* Delete a draft, or a void document with its reference typed back (the
   part's). A document's files wait for the console to take them out of
   Storage. */
create or replace function public.hiring_doc_delete(p_doc uuid, p_serial text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('ok', true, 'same', true); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.state = 'draft' then
    if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  elsif d.state = 'void' then
    if not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
    if btrim(coalesce(p_serial, '')) <> d.serial then return jsonb_build_object('error', 'bad-serial'); end if;
  else
    return jsonb_build_object('error', 'bad-state');
  end if;
  delete from public.hiring_docs where id = d.id;
  perform public.hiring_log(d.candidate_id, 'candidate.document', coalesce(d.serial, case d.kind when 'offer' then 'Employment Offer draft' else 'Employment Contract draft' end) || ' deleted');
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_delete(uuid, text) to authenticated;

create or replace function public.hiring_docs_files_gone()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.hiring_files_gone (path)
  select x from unnest(array[old.signed->>'path', old.stamp_path, old.seal_path]) x where x is not null
  on conflict (path) do nothing;
  return old;
end $$;
revoke all on function public.hiring_docs_files_gone() from public, anon, authenticated;
drop trigger if exists hiring_docs_files_gone on public.hiring_docs;
create trigger hiring_docs_files_gone before delete on public.hiring_docs
  for each row execute function public.hiring_docs_files_gone();

/* The Record of this Document: every step with who, when, where and the
   device, as the seal prints it and the console reads it. */
create or replace function public.hiring_doc_record(p_doc uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d public.hiring_docs; c public.hiring_candidates; v_role text; v_steps jsonb;
  h jsonb;
begin
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = d.candidate_id;
  v_steps := jsonb_build_array(jsonb_build_object('step', 'issued', 'at', d.made_at, 'team', true,
    'by', (select t.name from public.team_members t where t.id = d.made_by)));
  if d.sent_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'sent', 'at', d.sent_at, 'team', true, 'via', 'page',
      'by', (select t.name from public.team_members t where t.id = d.sent_by)));
  end if;
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', g.step, 'at', g.at, 'team', false, 'party', 'Candidate', 'email', g.email,
             'ip', g.ip, 'country', g.country, 'device', g.device) order by g.at)
      from public.signing_steps g where g.doc_kind = 'hiring_doc' and g.doc_id = d.id), '[]'::jsonb);
  for h in select x from jsonb_array_elements(d.history) x loop
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'signed', 'at', h->>'at', 'team', false, 'party', 'Candidate',
        'by', h->'signed'->>'name', 'via', coalesce(h->'signed'->>'via', 'online'), 'email', h->'signed'->'record'->>'email',
        'ip', h->'signed'->'record'->>'ip', 'country', h->'signed'->'record'->>'country', 'device', h->'signed'->'record'->>'device',
        'entered_by', case when h->'signed'->>'via' <> 'online' then h->'signed'->'record'->>'by' end),
      jsonb_build_object('step', 'returned', 'at', h->>'returned_at', 'team', true, 'by', h->>'returned_by', 'note', h->>'note'));
  end loop;
  if d.signed is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'signed', 'at', d.signed_at, 'team', false, 'party', 'Candidate',
      'by', coalesce(d.signed->>'name', c.name), 'via', case when d.signed->>'via' = 'online' then 'online' else 'paper' end,
      'email', d.signed->'record'->>'email', 'ip', d.signed->'record'->>'ip', 'country', d.signed->'record'->>'country',
      'device', d.signed->'record'->>'device',
      'entered_by', case when d.signed->>'via' <> 'online' then d.signed->'record'->>'by' end));
  end if;
  if d.state = 'declined' then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'declined', 'at', d.answered_at, 'team', false,
      'party', 'Candidate', 'note', d.decline_note));
  end if;
  if d.confirmed_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'confirmed', 'at', d.confirmed_at, 'team', true,
      'by', (select t.name from public.team_members t where t.id = d.confirmed_by),
      'role', (select t.designation from public.team_members t where t.id = d.confirmed_by)));
    if d.stamp_no is not null then
      v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'stamped', 'at', d.confirmed_at, 'team', true,
        'by', (select t.name from public.team_members t where t.id = d.confirmed_by), 'note', d.stamp_no));
    end if;
  end if;
  if d.sealed_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'sealed', 'at', d.sealed_at, 'team', true, 'by', d.sealed_by, 'note', d.seal_sha));
  end if;
  if d.state = 'void' then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'withdrawn', 'at', d.voided_at, 'team', true, 'by', d.voided_by, 'note', d.void_note));
  end if;
  return jsonb_build_object('ok', true, 'id', d.id, 'ref', d.serial, 'steps', v_steps, 'signed', d.signed is not null,
    'confirmed', d.confirmed_at is not null, 'withdrawn', d.state = 'void',
    'seal', case when d.seal_sha is not null then jsonb_build_object('sha', d.seal_sha, 'pages_sha', d.seal_pages_sha, 'at', d.sealed_at) end);
end $$;
grant execute on function public.hiring_doc_record(uuid) to authenticated;

/* hiring-mail's, asked as the caller: the email that tells the candidate a
   document waits on their page. Never the salary. */
create or replace function public.hiring_doc_mail_prepare(p_doc uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; c public.hiring_candidates; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'sent' then return jsonb_build_object('error', 'not-sent'); end if;
  select * into c from public.hiring_candidates where id = d.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('id', d.id, 'kind', 'doc', 'doc', d.kind, 'ref', d.serial, 'to', c.email, 'name', c.name,
    'position', d.terms->>'position', 'key', c.link_key, 'reply_by', public.register_day((d.reply_by at time zone 'Asia/Kuala_Lumpur')::date),
    'returned', d.returned_note is not null, 'sent_key', extract(epoch from coalesce(d.returned_at, d.sent_at))::bigint,
    'sender', me.name, 'reply_to', me.email);
end $$;
grant execute on function public.hiring_doc_mail_prepare(uuid) to authenticated;

create or replace function public.hiring_doc_mail_done(p_doc uuid, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-request'); end if;
  update public.hiring_docs set mail = p_status, mail_at = now() where id = d.id;
  perform public.hiring_log(d.candidate_id, 'candidate.email', d.serial || case p_status when 'sent' then ' emailed'
    when 'unknown' then ' emailed, not confirmed' else ' not emailed' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_mail_done(uuid, text, text) to authenticated;

/* The candidate's own document by their link; null where it is not theirs
   or not on their page. */
create or replace function public.careers_doc_of(p_key text, p_doc uuid)
returns public.hiring_docs language plpgsql stable security definer set search_path = public as $$
declare c public.hiring_candidates; d public.hiring_docs;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' or p_doc is null then return null; end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null;
  if c.id is null or c.last_step_at + make_interval(days => v_days) <= now() then return null; end if;
  select * into d from public.hiring_docs where id = p_doc and candidate_id = c.id and state in ('sent', 'signed', 'confirmed', 'declined');
  return d;
end $$;
revoke all on function public.careers_doc_of(text, uuid) from public, anon, authenticated;

/* The service role's (hiring-mail, at the candidate's press): a six-digit
   code to read the document, kept hashed for 15 minutes, five an hour a
   document, the code step filed with the address the function saw. */
create or replace function public.hiring_doc_code(p_key text, p_doc uuid, p_device text, p_ip text)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
  c public.hiring_candidates;
  v_code text;
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  perform 1 from public.hiring_docs where id = d.id for update;
  select * into c from public.hiring_candidates where id = d.candidate_id;
  if (select count(*) from public.hiring_doc_codes s where s.doc_id = d.id and s.created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('error', 'too-many');
  end if;
  v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.hiring_doc_codes (doc_id, code_hash, email, expires_at)
  values (d.id, crypt(v_code, gen_salt('bf', 6)), c.email, now() + interval '15 minutes');
  insert into public.signing_steps (doc_kind, doc_id, step, email, ip, country, device)
  values ('hiring_doc', d.id, 'code', c.email, nullif(left(coalesce(p_ip, ''), 64), ''), nullif(public.request_country(), ''), public.seal_device(p_device));
  return jsonb_build_object('ok', true, 'code', v_code, 'email', c.email, 'name', c.name, 'ref', d.serial,
    'doc', d.kind);
end $$;
revoke all on function public.hiring_doc_code(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.hiring_doc_code(text, uuid, text, text) to service_role;

/* The document as the candidate reads it, the salary with it. */
create or replace function public.careers_doc_json(d public.hiring_docs)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object('ok', true, 'id', d.id, 'kind', d.kind, 'serial', d.serial,
    'state', case when d.state = 'sent' and d.reply_by <= now() then 'expired' else d.state end,
    'sent_at', d.sent_at, 'reply_by', d.reply_by, 'terms', d.terms, 'returned_note', case when d.state = 'sent' then d.returned_note end,
    'name', c.name, 'signed_at', d.signed_at, 'signed_name', d.signed->>'name',
    'signatory', jsonb_build_object('name', t.name, 'designation', t.designation),
    'pay', jsonb_build_object('basic', p.basic, 'probation', p.probation)))
    from public.hiring_candidates c
    left join public.hiring_doc_pay p on p.doc_id = d.id
    left join public.team_members t on t.id = d.sent_by
   where c.id = d.candidate_id
$$;
revoke all on function public.careers_doc_json(public.hiring_docs) from public, anon, authenticated;

/* The code typed: the document opens for 30 minutes on this device (a view
   token, kept hashed), filed as opened. */
create or replace function public.careers_doc_open(p_key text, p_doc uuid, p_code text, p_device text)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
  s public.hiring_doc_codes;
  v_tok text;
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into s from public.hiring_doc_codes x where x.doc_id = d.id and x.used_at is null
   order by x.created_at desc limit 1 for update;
  if s.id is null then return jsonb_build_object('error', 'no-code'); end if;
  if s.expires_at <= now() then return jsonb_build_object('error', 'code-expired'); end if;
  if s.tries >= 5 then return jsonb_build_object('error', 'locked'); end if;
  if regexp_replace(coalesce(p_code, ''), '\s+', '', 'g') !~ '^[0-9]{6}$'
     or crypt(regexp_replace(p_code, '\s+', '', 'g'), s.code_hash) <> s.code_hash then
    update public.hiring_doc_codes set tries = tries + 1 where id = s.id;
    return jsonb_build_object('error', 'wrong', 'left', greatest(0, 4 - s.tries));
  end if;
  v_tok := encode(gen_random_bytes(24), 'hex');
  update public.hiring_doc_codes set used_at = now(), view_hash = encode(digest(v_tok, 'sha256'), 'hex'),
    view_until = now() + interval '30 minutes' where id = s.id;
  insert into public.signing_steps (doc_kind, doc_id, step, email, ip, country, device)
  values ('hiring_doc', d.id, 'opened', s.email, nullif(public.request_ip(), ''), nullif(public.request_country(), ''), public.seal_device(p_device));
  return public.careers_doc_json(d) || jsonb_build_object('view', v_tok);
end $$;
revoke all on function public.careers_doc_open(text, uuid, text, text) from public;
grant execute on function public.careers_doc_open(text, uuid, text, text) to anon, authenticated;

/* The view a code opened, while its 30 minutes run. */
create or replace function public.careers_doc_view(p_doc uuid, p_view text)
returns public.hiring_doc_codes language sql stable security definer set search_path = public, extensions as $$
  select s.* from public.hiring_doc_codes s
   where s.doc_id = p_doc and s.view_hash = encode(digest(coalesce(p_view, ''), 'sha256'), 'hex') and s.view_until > now()
   order by s.used_at desc limit 1
$$;
revoke all on function public.careers_doc_view(uuid, text) from public, anon, authenticated;

create or replace function public.careers_doc_read(p_key text, p_doc uuid, p_view text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if (public.careers_doc_view(d.id, p_view)).id is null then return jsonb_build_object('error', 'code-needed'); end if;
  return public.careers_doc_json(d);
end $$;
revoke all on function public.careers_doc_read(text, uuid, text) from public;
grant execute on function public.careers_doc_read(text, uuid, text) to anon, authenticated;

/* The candidate's answer inside the view: an offer accepted (their name
   typed and the confirmation ticked) or declined (a reason optional); a
   contract signed (name, NRIC or passport number, a drawn signature, the
   confirmation; the signature a path drawn in a 300 by 100 box, as a
   quotation's). The code's email, the address, country and device, and
   the document's fingerprint are kept with the signing. */
create or replace function public.careers_doc_answer(p_key text, p_doc uuid, p_view text, p_answer text, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
  s public.hiring_doc_codes;
  p public.hiring_doc_pay;
  pl jsonb := coalesce(p_payload, '{}'::jsonb);
  v_name text := btrim(coalesce(pl->>'name', ''));
  v_id text := upper(btrim(coalesce(pl->>'id_no', '')));
  v_sig text := coalesce(pl->>'signature', '');
  v_at timestamptz := now();
  v_title text;
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  s := public.careers_doc_view(d.id, p_view);
  if s.id is null then return jsonb_build_object('error', 'code-needed'); end if;
  select * into d from public.hiring_docs where id = d.id for update;
  if d.state <> 'sent' then return jsonb_build_object('error', 'answered'); end if;
  if d.reply_by <= now() then return jsonb_build_object('error', 'expired'); end if;
  v_title := case d.kind when 'offer' then 'Employment Offer' else 'Employment Contract' end;
  if p_answer = 'decline' then
    if d.kind <> 'offer' then return jsonb_build_object('error', 'bad-request'); end if;
    if char_length(coalesce(pl->>'note', '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
    update public.hiring_docs set state = 'declined', answered_at = v_at, decline_note = nullif(btrim(coalesce(pl->>'note', '')), ''),
      updated_at = now() where id = d.id;
    update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
    insert into public.hiring_events (candidate_id, actor, action, detail)
    values (d.candidate_id, 'Candidate page', 'candidate.document', d.serial || ' declined');
    perform public.hiring_tell(d.candidate_id, 'hiring.declined', 'A candidate declined an offer', d.serial || '.');
    return jsonb_build_object('ok', true);
  end if;
  if coalesce(p_answer, '') not in ('accept', 'sign') or (p_answer = 'accept') <> (d.kind = 'offer') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if char_length(v_name) not between 2 and 120 then return jsonb_build_object('error', 'bad-name'); end if;
  if coalesce(pl->>'agree', '') <> 'true' then return jsonb_build_object('error', 'bad-agree'); end if;
  if d.kind = 'contract' then
    if v_id !~ '^([0-9]{6}-[0-9]{2}-[0-9]{4}|[A-Z0-9]{6,20})$' then return jsonb_build_object('error', 'bad-id'); end if;
    if v_sig !~ '^[MLQCZmlqcz0-9 .,-]+$' or char_length(v_sig) not between 8 and 30000 then return jsonb_build_object('error', 'bad-signature'); end if;
  end if;
  select * into p from public.hiring_doc_pay where doc_id = d.id;
  update public.hiring_docs set state = 'signed', signed_at = v_at, answered_at = v_at,
    signed = jsonb_strip_nulls(jsonb_build_object('via', 'online', 'name', v_name,
      'id_no', case when d.kind = 'contract' then v_id end, 'signature', case when d.kind = 'contract' then v_sig end,
      'record', jsonb_build_object('at', v_at, 'email', s.email, 'ip', nullif(public.request_ip(), ''),
        'country', nullif(public.request_country(), ''), 'device', public.seal_device(pl->>'device'),
        'fingerprint', upper(left(encode(digest(d.serial || d.terms::text || coalesce(p.basic::text, '') || coalesce(p.probation::text, '') ||
          v_name || v_at::text, 'sha256'), 'hex'), 16))))),
    updated_at = now()
   where id = d.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (d.candidate_id, 'Candidate page', 'candidate.document', d.serial || case d.kind when 'offer' then ' accepted' else ' signed' end || ' on the candidate page');
  perform public.hiring_tell(d.candidate_id, 'hiring.signed', case d.kind when 'offer' then 'A candidate accepted an offer' else 'A candidate signed a contract' end,
    d.serial || '. Confirm it on the candidate''s record.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_doc_answer(text, uuid, text, text, jsonb) from public;
grant execute on function public.careers_doc_answer(text, uuid, text, text, jsonb) to anon, authenticated;

/* The candidate's page, with their documents (never the terms or the
   salary: those open behind the code). Restated from HIRING OUTCOMES. */
create or replace function public.careers_read(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() and not (c.stage = 'pool' and c.pool_consent = 'yes') then
    return jsonb_build_object('error', 'expired');
  end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state <> 'replaced'
   order by invited_at desc limit 1;
  return jsonb_build_object('ok', true, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage = 'new' or (c.stage = 'pool' and c.outcome is null) then 'received' else c.stage end, 'received_at', c.created_at,
    'pool', case when c.stage = 'pool' and c.outcome = 'pool' then jsonb_strip_nulls(jsonb_build_object('consent', c.pool_consent,
      'until', c.pool_until, 'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12))) end,
    'interview', case when i.id is null or i.state = 'cancelled' or c.stage in ('pool', 'closed') then null else jsonb_strip_nulls(jsonb_build_object(
      'state', i.state, 'slots', case when i.state = 'invited' then to_jsonb(i.slots) end, 'minutes', i.minutes,
      'mode', i.mode, 'note', i.note, 'at', case when i.picked is not null then i.slots[i.picked] end,
      'link', case when i.state = 'confirmed' then i.meeting_link end)) end,
    'docs', case when c.stage in ('offer', 'hired') then coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', d.id, 'kind', d.kind,
        'serial', d.serial, 'state', case when d.state = 'sent' and d.reply_by <= now() then 'expired' else d.state end,
        'sent_at', d.sent_at, 'reply_by', d.reply_by, 'signed_at', d.signed_at)) order by d.sent_at)
      from public.hiring_docs d where d.candidate_id = c.id and d.state in ('sent', 'signed', 'confirmed', 'declined')), '[]'::jsonb) end);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

-- END OF HIRING OFFERS AND CONTRACTS -------------------------------------------

select public.functions_tidy();
