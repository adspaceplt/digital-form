-- ===========================================================================
-- AI LIMITS A COLLEAGUE A REPORT A DAY — each colleague has one draft and one
-- figures check on a report a day, reset at midnight; an admin five of each.
-- 2026-10-05. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/smsql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-05: "just give per pax per report per use
-- per day ... if they do the report last minute ... they need to be
-- responsible for the late until next day. same goes to the figure check.
-- resets daily")
--   1. A draft is counted by who asks, on that report, today: `report` (1) a
--      colleague's, `report_admin` (5) an admin's. Past it the refusal is
--      `report` with the reset time. A revision of the same period is the
--      same report (`ai_draft_same`).
--   2. A figures check is counted the same way: `check` (1) a colleague's,
--      `check_admin` (5) an admin's, refused `report_check` with the reset
--      time. A revision no longer brings another check the same day.
--   3. `ai_draft_left` and `ai_check_left` read the same counts.
--   4. `ai_draft_set_limit` names the two everyday limits by what they now
--      count. The day's uses (`person` 10, `admin` 20) are unchanged.
--
-- ROLLBACK
--   Run the AI LIMITS BY REPORT AND VERSION section of schema.sql again.
-- ===========================================================================

create or replace function public.ai_draft_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  n_report integer;
  n_member integer;
  lim_member integer;
  lim_report integer;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  -- One count at a time, so two presses together cannot both take the last draft.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  select * into r from public.sm_reports where id = p_report;
  lim_member := public.ai_day_cap(m);
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  lim_report := case when coalesce(m.is_admin, false) then public.ai_draft_limit('report_admin', 5)
                     else public.ai_draft_limit('report', 1) end;
  select count(*) into n_report from public.ai_draft_same(p_report) s
   where s.team_member_id = m.id and s.created_at >= since;
  if n_report >= lim_report then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report', 'limit', lim_report, 'next', since + interval '1 day');
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, version_no)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, r.version_no) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_draft_left(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  is_adm boolean;
  n_member integer;
  l_report integer; l_member integer; l_min integer;
  lim_member integer;
  lim_report integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  is_adm := coalesce(m.is_admin, false);
  lim_member := public.ai_day_cap(m);
  lim_report := case when is_adm then public.ai_draft_limit('report_admin', 5) else public.ai_draft_limit('report', 1) end;
  l_report := greatest(0, lim_report - (select count(*) from public.ai_draft_same(p_report) s
    where s.team_member_id = m.id and s.created_at >= since)::integer);
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  l_member := greatest(0, lim_member - n_member);
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped' when l_min = l_report then 'report' else 'person' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope,
    'limit', case v_scope when 'stopped' then 0 when 'report' then lim_report else lim_member end,
    'report', l_report, 'person', l_member, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope = 'stopped' then null else since + interval '1 day' end);
end $$;

create or replace function public.ai_check_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  n_member integer;
  lim_member integer;
  lim_check integer;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null or not public.client_seen(r.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status not in ('draft', 'review') then return jsonb_build_object('error', 'not-open'); end if;
  -- One count at a time, with the drafts, so the last use is taken once.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim_member := public.ai_day_cap(m);
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  lim_check := case when coalesce(m.is_admin, false) then public.ai_draft_limit('check_admin', 5)
                    else public.ai_draft_limit('check', 1) end;
  if (select count(*) from public.ai_drafts d
       where d.report_id = p_report and d.purpose = 'check' and d.outcome <> 'failed'
         and d.team_member_id = m.id and d.created_at >= since) >= lim_check then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report_check', 'limit', lim_check, 'next', since + interval '1 day');
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, purpose, version_no)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, 'check', r.version_no) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_check_left(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  is_adm boolean;
  n_member integer;
  l_report integer; l_member integer; l_min integer;
  lim_member integer;
  lim_check integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null or not public.client_seen(r.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  is_adm := coalesce(m.is_admin, false);
  lim_member := public.ai_day_cap(m);
  lim_check := case when is_adm then public.ai_draft_limit('check_admin', 5) else public.ai_draft_limit('check', 1) end;
  l_report := greatest(0, lim_check - (select count(*) from public.ai_drafts d
    where d.report_id = p_report and d.purpose = 'check' and d.outcome <> 'failed'
      and d.team_member_id = m.id and d.created_at >= since)::integer);
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  l_member := greatest(0, lim_member - n_member);
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped' when l_min = l_report then 'report_check' else 'person' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope, 'version', r.version_no,
    'limit', case v_scope when 'stopped' then 0 when 'report_check' then lim_check else lim_member end,
    'report', l_report, 'person', l_member, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope = 'stopped' then null else since + interval '1 day' end);
end $$;

revoke all on function public.ai_draft_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_draft_left(uuid) from public, anon, authenticated;
revoke all on function public.ai_check_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_check_left(uuid) from public, anon, authenticated;
grant execute on function public.ai_draft_claim(uuid) to authenticated;
grant execute on function public.ai_draft_left(uuid) to authenticated;
grant execute on function public.ai_check_claim(uuid) to authenticated;
grant execute on function public.ai_check_left(uuid) to authenticated;

-- A colleague's limit a day, or a standard for everyone. Null puts the
-- standard back.
create or replace function public.ai_draft_set_limit(p_scope text, p_daily integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_name text;
  v_was integer;
  v_def integer;
  v_unit text := ' a day';
  v_scope text := btrim(coalesce(p_scope, ''));
  t public.team_members;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  if p_daily is not null and (p_daily < 0 or p_daily > 500) then
    return jsonb_build_object('error', 'bad-limit');
  end if;
  if v_scope = 'person' then
    v_name := 'Each colleague'; v_def := 10;
  elsif v_scope = 'admin' then
    v_name := 'Each admin'; v_def := 20;
  elsif v_scope = 'report' then
    v_name := 'Drafts per report, each colleague'; v_def := 1;
  elsif v_scope = 'report_admin' then
    v_name := 'Drafts per report, each admin'; v_def := 5;
  elsif v_scope = 'check' then
    v_name := 'Figures checks per report, each colleague'; v_def := 1;
  elsif v_scope = 'check_admin' then
    v_name := 'Figures checks per report, each admin'; v_def := 5;
  elsif v_scope = 'team' then
    return jsonb_build_object('error', 'bad-scope');
  else
    select * into t from public.team_members x where x.id::text = v_scope;
    if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
    v_name := t.name;
    v_def := case when coalesce(t.is_admin, false) or t.role = 'admin'
                  then public.ai_draft_limit('admin', 20) else public.ai_draft_limit('person', 10) end;
  end if;
  select l.daily into v_was from public.ai_draft_limits l where l.scope = v_scope;
  if v_was is not distinct from p_daily then return jsonb_build_object('ok', true, 'same', true); end if;
  select coalesce(x.name, x.email) into v_who from public.team_members x
   where lower(x.email) = lower(auth.jwt() ->> 'email') and x.active limit 1;
  insert into public.ai_draft_limits (scope, daily, set_by, set_at)
  values (v_scope, p_daily, v_who, now())
  on conflict (scope) do update set daily = excluded.daily, set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'AI',
          v_name || ': ' ||
          case when v_was is null then 'standard, ' || v_def || v_unit when v_was = 0 then 'stopped' else v_was || v_unit end ||
          ' → ' ||
          case when p_daily is null then 'standard, ' || v_def || v_unit when p_daily = 0 then 'stopped' else p_daily || v_unit end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.ai_draft_set_limit(text, integer) from public, anon, authenticated;
grant execute on function public.ai_draft_set_limit(text, integer) to authenticated;

-- END OF AI LIMITS A COLLEAGUE A REPORT A DAY --------------------------------
