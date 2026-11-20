-- ===========================================================================
-- VERIFY CHECKS COUNTED (2026-11-21)
-- ===========================================================================
-- WHY: the user, 2026-11-21: "is it possible to show how many time this
-- verify has been checked? Eg. Verified N times one very small wordings",
-- "not shown in pdf but on the verify portal itself … Go", and "is it
-- redundant to show since when cos it would always since from the date of
-- issue" (so no "since").
--
-- WHAT IT CHANGES
--   * `verify_checks` (kind, doc_id, day, addr_hash; RLS on, no policy, no
--     grant): a lookup on /verify/ that finds a document is kept once a
--     caller's address a Malaysian day a document. The address is never
--     kept: `addr_hash` is the SHA-256 of a salt held in `app_secrets`
--     (`verify_check_salt`, made at the first check), the day and the
--     address `request_ip()` reads (an IPv6 caller by its /64).
--   * `verify_check_totals` (kind, doc_id, n; RLS on, no policy, no grant):
--     each document's count, raised by one when a new row joins
--     `verify_checks`, so the total never drops when the rows go.
--   * `verify_check_note(f)` (no caller's): the one writer. A miss, a
--     repeat the same day from the same address, a colleague and a session
--     with no request (the SQL Editor, a suite) are never counted.
--   * `verify_serial` (restated whole from VERIFY DETAILS) notes a lookup
--     that finds a document; its answer is unchanged (no count in it).
--   * `verify_details` (restated whole from VERIFY DETAILS) answers
--     `checks`, the document's count, one at least, beside the Document ID.
--     Every refusal, the ten an hour and the one answer for a miss are kept.
--   * `verify_checks_of(p_kind, p_id)` (the team's): a document's count for
--     its record in the console (kind document, letter, quotation, hiring or
--     perf), read once a record is opened; never a list's.
--   * `privacy_retention` (restated whole from VERIFY DETAILS) lets go of
--     the address hashes 30 days after their day, as it does /verify/'s
--     counts; the totals stay.
--   Counted from the day this file runs: nothing before it was kept.
--
-- ORDER: this file, then the pages. An old page meets a `checks` it never
-- reads; a new page meeting the old database reads no `checks` and draws no
-- line, and the console's record reads no count (the function is missing)
-- and leaves the fact out. Safe to run twice.
--
-- ROLLBACK: run `verify_serial`, `verify_details` and `privacy_retention`
-- from VERIFY DETAILS again; drop `verify_checks_of`, `verify_check_note`,
-- `verify_check_count`, `verify_checks` and `verify_check_totals`; delete
-- the `verify_check_salt` row of `app_secrets`.
-- ===========================================================================

create table if not exists public.verify_checks (
  kind      text not null,
  doc_id    uuid not null,
  day       date not null,
  addr_hash text not null,
  primary key (kind, doc_id, day, addr_hash)
);
alter table public.verify_checks enable row level security;
revoke all on public.verify_checks from public, anon, authenticated;

create table if not exists public.verify_check_totals (
  kind   text not null,
  doc_id uuid not null,
  n      integer not null default 0,
  primary key (kind, doc_id)
);
alter table public.verify_check_totals enable row level security;
revoke all on public.verify_check_totals from public, anon, authenticated;

/* A lookup that found a document, kept once an address a Malaysian day a
   document; the address only as a salted hash. */
create or replace function public.verify_check_note(f jsonb)
returns void
language plpgsql volatile set search_path = public as $$
declare
  v_ip   text := public.request_ip();
  v_day  date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_salt text;
  v_id   uuid;
  v_new  integer := 0;
begin
  if f is null or coalesce(f ->> 'src', '') = '' or coalesce(f ->> 'id', '') = '' or v_ip = '' or public.is_team() then return; end if;
  begin
    v_id := (f ->> 'id')::uuid;
  exception when others then return;
  end;
  select s.value into v_salt from public.app_secrets s where s.key = 'verify_check_salt';
  if v_salt is null then
    insert into public.app_secrets (key, value)
    values ('verify_check_salt', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
    on conflict (key) do nothing;
    select s.value into v_salt from public.app_secrets s where s.key = 'verify_check_salt';
  end if;
  insert into public.verify_checks (kind, doc_id, day, addr_hash)
  values (f ->> 'src', v_id, v_day, encode(sha256(convert_to(v_salt || '|' || v_day::text || '|' || v_ip, 'UTF8')), 'hex'))
  on conflict do nothing;
  get diagnostics v_new = row_count;
  if v_new > 0 then
    insert into public.verify_check_totals as t (kind, doc_id, n) values (f ->> 'src', v_id, 1)
    on conflict (kind, doc_id) do update set n = t.n + 1;
  end if;
end $$;
revoke all on function public.verify_check_note(jsonb) from public, anon, authenticated;

/* A document's count. */
create or replace function public.verify_check_count(p_kind text, p_id uuid)
returns integer
language sql stable set search_path = public as $$
  select coalesce((select t.n from public.verify_check_totals t where t.kind = p_kind and t.doc_id = p_id), 0);
$$;
revoke all on function public.verify_check_count(text, uuid) from public, anon, authenticated;

/* The first answer: that ADSPACE PLT issued a document with this reference,
   its kind, its standing and its month. Its days and steps wait for the
   Document ID (`verify_details`). A lookup that finds one is counted. */
create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  f jsonb;
  v_wait integer := public.verify_count();
begin
  if v_wait > 0 then
    return jsonb_build_object('found', false, 'locked', true, 'minutes', v_wait);
  end if;
  f := public.verify_find(p_serial);
  if f is null then return jsonb_build_object('found', false); end if;
  perform public.verify_check_note(f);
  return jsonb_build_object('found', true, 'serial', f ->> 'serial', 'kind', f ->> 'kind', 'state', f ->> 'state',
    'issued_month', to_char((f ->> 'issued')::date, 'YYYY-MM'), 'sealed', coalesce((f ->> 'sealed')::boolean, false),
    'more', true, 'by_day', public.verify_by_day(f));
end $$;
revoke all on function public.verify_serial(text) from public;
grant execute on function public.verify_serial(text) to anon, authenticated;

/* The full answer for somebody holding the copy: the Document ID printed on
   it, or the day of issue where that may stand for it, and how many times
   the document has been checked. One answer for a wrong code, a wrong day
   and an unknown reference. */
create or replace function public.verify_details(p_serial text, p_code text, p_day date)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f jsonb;
  c text := upper(regexp_replace(left(coalesce(p_code, ''), 80), '[^0-9A-Za-z]', '', 'g'));
  v_contact text := (select b.address from public.mail_boxes b where b.key = 'legal');
  v_wait integer := public.verify_detail_count();
  v_ok boolean := false;
begin
  if v_wait > 0 then
    return jsonb_build_object('locked', true, 'minutes', v_wait, 'contact', v_contact);
  end if;
  f := public.verify_find(p_serial);
  if f is not null then
    if c <> '' and f ->> 'code' is not null and c = f ->> 'code' then
      v_ok := true;
    elsif c ~ '^[0-9A-F]{32}$' and (f ->> 'sealed')::boolean and f ->> 'src' in ('quotation', 'hiring')
          and c = upper(replace(f ->> 'id', '-', '')) then
      v_ok := true;
    elsif c = '' and p_day is not null and public.verify_by_day(f) and p_day = (f ->> 'issued')::date then
      v_ok := true;
    end if;
  end if;
  if not v_ok then return jsonb_build_object('no_match', true, 'contact', v_contact); end if;
  return jsonb_build_object('ok', true, 'serial', f ->> 'serial', 'kind', f ->> 'kind', 'state', f ->> 'state',
    'issued_on', f ->> 'issued',
    'document_id', case when f ->> 'code' is not null then substr(f ->> 'code', 1, 4) || '-' || substr(f ->> 'code', 5, 4) end,
    'sealed', coalesce((f ->> 'sealed')::boolean, false),
    'checks', greatest(1, public.verify_check_count(f ->> 'src', (f ->> 'id')::uuid)),
    'history', f -> 'steps', 'contact', v_contact);
end $$;
revoke all on function public.verify_details(text, text, date) from public;
grant execute on function public.verify_details(text, text, date) to anon, authenticated;

/* A document's count for its record in the console: the team's alone. */
create or replace function public.verify_checks_of(p_kind text, p_id uuid)
returns integer
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_team() then return null; end if;
  if p_id is null or p_kind not in ('document', 'letter', 'quotation', 'hiring', 'perf') then return 0; end if;
  return public.verify_check_count(p_kind, p_id);
end $$;
revoke all on function public.verify_checks_of(text, uuid) from public, anon;
grant execute on function public.verify_checks_of(text, uuid) to authenticated;

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0; v_vt integer := 0; v_vd integer := 0; v_vc integer := 0;
  v_today date := (p_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_keep integer := coalesce(public.app_setting('health_keep_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 24)::integer;
  v_left integer := coalesce(public.app_setting('health_leaver_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 6)::integer;
  v_gone uuid[];
begin
  update public.wa_outbox o
     set to_number = '', to_name = null, params = '[]'::jsonb, button = null
   where o.created_at < p_now - interval '12 months'
     and o.state not in ('queued', 'sending')
     and (o.to_number <> '' or o.to_name is not null or o.params <> '[]'::jsonb or o.button is not null);
  get diagnostics v_wa = row_count;
  delete from public.activity_log a where a.created_at < p_now - interval '3 years';
  get diagnostics v_act = row_count;
  delete from public.health_checkins k where k.half < v_today - make_interval(months => v_keep);
  get diagnostics v_hc = row_count;
  select coalesce(array_agg(m.id), '{}') into v_gone from public.team_members m
   where not m.active and coalesce(m.removed_at, m.expired_at) < p_now - make_interval(months => v_left);
  if array_length(v_gone, 1) > 0 then
    delete from public.health_checkins k where k.team_member_id = any(v_gone);
    get diagnostics v_hl = row_count;
    delete from public.health_talks t where t.team_member_id = any(v_gone) or t.with_id = any(v_gone);
    delete from public.health_log l where l.team_member_id = any(v_gone);
    delete from public.health_consents c where c.team_member_id = any(v_gone);
  end if;
  -- A caller's address against a link's passcode, once it has had nothing
  -- to say for 30 days and holds no lock (audit 2026-10-18, item 14).
  delete from public.link_tries t
   where greatest(t.last_at, coalesce(t.ok_at, t.last_at)) < p_now - interval '30 days'
     and coalesce(t.locked_until, t.last_at) < p_now;
  get diagnostics v_lt = row_count;
  -- A caller's address against /verify/, once its hour began 30 days ago.
  delete from public.verify_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vt = row_count;
  -- And against /verify/'s details (VERIFY DETAILS, 2026-11-20).
  delete from public.verify_detail_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vd = row_count;
  -- And a check's address hash, 30 days after its day; the document's
  -- total stays (VERIFY CHECKS COUNTED, 2026-11-21).
  delete from public.verify_checks v where v.day < v_today - 30;
  get diagnostics v_vc = row_count;
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt, 'verify_tries_removed', v_vt, 'verify_detail_tries_removed', v_vd,
    'verify_checks_removed', v_vc);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;

-- END OF VERIFY CHECKS COUNTED -----------------------------------------------

select public.functions_tidy();
