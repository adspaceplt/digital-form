-- ===========================================================================
-- VERIFY LOOKUPS COUNTED — /verify/ answers a connection outside the team
-- thirty references an hour (2026-10-19)
-- ===========================================================================
-- WHY (audit 2026-10-18/19, item 2): `verify_serial` (anon) answers any
-- reference with its kind, date and Valid or Void, and an HR reference is
-- guessable (`ADHR/{Employee ID}/{type code}{YYMM}`, `.../PR{YYMM}`), so a
-- stranger could sweep the months and codes and learn which letters a
-- colleague was given.
--
-- WHAT IT CHANGES
--   * Each lookup by anyone the team does not hold is counted against the
--     caller's address (`request_ip()`: the address Cloudflare saw) in
--     `verify_tries` (RLS on, no policy, no grant). Past 30 in an hour the
--     answer is `locked` with the minutes left, before any reference is
--     read; the page says so in its words. A colleague is never counted,
--     nor a session with no request (the SQL Editor, a suite).
--   * What a found reference shows is unchanged.
--   * `privacy_retention` (the 2nd of each month) removes an address's row
--     once its hour began over 30 days ago (`verify_tries_removed`);
--     everything else it does is PASSCODE TRIES ARE KEPT FOR A TIME's.
--
-- ORDER: the pages first (verify.js reads `locked`), then this file in the
-- SQL Editor as one run (the connector holds a statement holding `delete`).
-- Safe to run twice. An old open tab reads a lock as Unable to check.
-- Rollback: run verify_serial from A PERFORMANCE RECORD CAN BE DELETED and
-- privacy_retention from PASSCODE TRIES ARE KEPT FOR A TIME again, then
-- drop table if exists public.verify_tries;
-- ===========================================================================

create table if not exists public.verify_tries (
  ip    text primary key,
  n     integer not null default 0,
  since timestamptz not null default now()
);
alter table public.verify_tries enable row level security;
revoke all on public.verify_tries from public, anon, authenticated;

create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  rv public.perf_reviews%rowtype;
  dl public.perf_deleted%rowtype;
  v_ip text := public.request_ip();
  v_n integer;
  v_since timestamptz;
begin
  if v_ip <> '' then
    if not public.is_team() then
      insert into public.verify_tries as v (ip, n, since) values (v_ip, 1, now())
      on conflict (ip) do update
        set n = case when v.since < now() - interval '1 hour' then 1 else v.n + 1 end,
            since = case when v.since < now() - interval '1 hour' then now() else v.since end
      returning v.n, v.since into v_n, v_since;
      if v_n > 30 then
        return jsonb_build_object('found', false, 'locked', true,
          'minutes', greatest(1, ceil(extract(epoch from (v_since + interval '1 hour' - now())) / 60)::integer));
      end if;
    end if;
  end if;
  if length(s) < 3 or length(s) > 40 then return jsonb_build_object('found', false); end if;
  sd := replace(s, '/', '-');
  select * into d from public.documents
   where upper(serial) = s or replace(upper(serial), '/', '-') = sd
   order by (upper(serial) = s) desc, (voided_at is null) desc, created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('found', true, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued_at', d.issued_at,
      'state', case when d.voided_at is null then 'valid' else 'voided' end);
  end if;
  select * into l from public.client_documents
   where upper(number) = s or replace(upper(number), '/', '-') = sd
   order by (upper(number) = s) desc limit 1;
  if l.id is not null then
    return jsonb_build_object('found', true, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued_at', l.issued_at,
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end);
  end if;
  select * into rv from public.perf_reviews pr
   where (upper(pr.serial) = s or replace(upper(pr.serial), '/', '-') = sd)
     and exists (select 1 from public.perf_events pe where pe.review_id = pr.id and pe.kind = 'printed')
   limit 1;
  if rv.id is not null then
    return jsonb_build_object('found', true, 'serial', rv.serial, 'kind', 'HR Letter',
      'issued_at', rv.released_at,
      'state', case when rv.status = 'draft' then 'replaced' else 'valid' end);
  end if;
  select * into dl from public.perf_deleted pd
   where pd.printed and (upper(pd.serial) = s or replace(upper(pd.serial), '/', '-') = sd)
   order by pd.deleted_at desc limit 1;
  if dl.id is not null then
    return jsonb_build_object('found', true, 'serial', dl.serial, 'kind', 'HR Letter',
      'issued_at', dl.released_at, 'state', 'voided');
  end if;
  return jsonb_build_object('found', false);
end $$;
revoke all on function public.verify_serial(text) from public;
grant execute on function public.verify_serial(text) to anon, authenticated;

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0; v_vt integer := 0;
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
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt, 'verify_tries_removed', v_vt);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;
-- END OF VERIFY LOOKUPS COUNTED ---------------------------------------------
select public.functions_tidy();
