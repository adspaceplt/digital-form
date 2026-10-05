-- ===========================================================================
-- AI LIMITS BY REPORT AND VERSION — one draft a report, one figures check a
-- version, ten AI uses a day a colleague, an admin five drafts and five
-- checks a report a day within twenty.
-- 2026-10-05. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-05: the figures check allowed up to twenty
-- a day on one report; a report is drafted once, its revisions inside that
-- one draft, and checked once a version)
--   1. `ai_drafts.version_no`: the report's version a check was run on.
--   2. `ai_day_cap(m)`: a colleague's AI uses a day, drafts and checks
--      together: their own limit, else `admin` (20) for an admin, else
--      `person` (10). Every count and the usage page read it.
--   3. `ai_check_claim`: a colleague's check is refused once the report's
--      current version has one (`recheck`, setting `check`, 1); an admin's
--      past it up to `check_admin` (5) a report a day (`report_check`).
--   4. `ai_check_left(p_report)`: what is left for the Check button, read
--      without writing, as `ai_draft_left` is for drafts.
--   5. `ai_draft_usage` and `ai_draft_set_limit` carry `admin`, `check` and
--      `check_admin` beside `person`, `report` and `report_admin`; the
--      standard a colleague is 10.
--   Drafts are unchanged: one a report from colleagues (`report`, by
--   subject, so a revision of the same period shares it), an admin's five
--   a report a day (`report_admin`).
--
-- ROLLBACK
--   Run the DRAFT WITH AI RESETS AT MIDNIGHT section's ai_draft_claim,
--   ai_draft_left, ai_draft_usage and ai_draft_set_limit, and the AI CHECKS
--   A REPORT AGAINST ITS FIGURES section's ai_check_claim, again; then, in
--   the SQL Editor, drop ai_check_left and ai_day_cap. The column may stay.
-- ===========================================================================

alter table public.ai_drafts add column if not exists version_no integer;

-- A colleague's AI uses a day: their own, else an admin's or the standard.
create or replace function public.ai_day_cap(m public.team_members)
returns integer
language sql stable security definer set search_path = public as $$
  select public.ai_draft_limit(m.id::text,
    case when coalesce(m.is_admin, false) or m.role = 'admin'
         then public.ai_draft_limit('admin', 20)
         else public.ai_draft_limit('person', 10) end)
$$;
revoke all on function public.ai_day_cap(public.team_members) from public, anon, authenticated;

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
  lim_report integer := public.ai_draft_limit('report', 1);
  lim_admin integer := public.ai_draft_limit('report_admin', 5);
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
  -- A report's drafts from a colleague; past them, the rest are an admin's.
  if not coalesce(m.is_admin, false) and (select count(*) from public.ai_draft_same(p_report)) >= lim_report then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'redraft', 'limit', lim_report);
  end if;
  select count(*) into n_report from public.ai_draft_same(p_report) s where s.created_at >= since;
  if coalesce(m.is_admin, false) and n_report >= lim_admin then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report', 'limit', lim_admin, 'next', since + interval '1 day');
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
  n_report integer; n_member integer;
  l_report integer; l_member integer; l_min integer;
  lim_member integer;
  lim_report integer := public.ai_draft_limit('report', 1);
  lim_admin integer := public.ai_draft_limit('report_admin', 5);
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  is_adm := coalesce(m.is_admin, false);
  lim_member := public.ai_day_cap(m);
  select count(*) into n_report from public.ai_draft_same(p_report) s where s.created_at >= since;
  if is_adm then
    l_report := greatest(0, lim_admin - n_report);
  else
    l_report := greatest(0, lim_report - (select count(*) from public.ai_draft_same(p_report))::integer);
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  l_member := greatest(0, lim_member - n_member);
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped'
                  when l_min = l_report then case when is_adm then 'report' else 'redraft' end
                  else 'person' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope,
    'limit', case v_scope when 'stopped' then 0 when 'redraft' then lim_report when 'report' then lim_admin else lim_member end,
    'report', l_report, 'person', l_member, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope in ('redraft', 'stopped') then null else since + interval '1 day' end);
end $$;

-- A figures check: one a version of the report from colleagues; an admin's
-- past it, up to `check_admin` a report a day; all within the day's uses.
create or replace function public.ai_check_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  n_member integer;
  lim_member integer;
  lim_check integer := public.ai_draft_limit('check', 1);
  lim_admin integer := public.ai_draft_limit('check_admin', 5);
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
  if not coalesce(m.is_admin, false) then
    if (select count(*) from public.ai_drafts d
         where d.report_id = p_report and d.purpose = 'check' and d.outcome <> 'failed'
           and d.version_no is not distinct from r.version_no) >= lim_check then
      return jsonb_build_object('error', 'ai-limit', 'scope', 'recheck', 'limit', lim_check, 'version', r.version_no);
    end if;
  elsif (select count(*) from public.ai_drafts d
          where d.report_id = p_report and d.purpose = 'check' and d.outcome <> 'failed'
            and d.created_at >= since) >= lim_admin then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report_check', 'limit', lim_admin, 'next', since + interval '1 day');
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

-- What the Check button has left, read without writing.
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
  lim_check integer := public.ai_draft_limit('check', 1);
  lim_admin integer := public.ai_draft_limit('check_admin', 5);
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
  if is_adm then
    l_report := greatest(0, lim_admin - (select count(*) from public.ai_drafts d
      where d.report_id = p_report and d.purpose = 'check' and d.outcome <> 'failed' and d.created_at >= since)::integer);
  else
    l_report := greatest(0, lim_check - (select count(*) from public.ai_drafts d
      where d.report_id = p_report and d.purpose = 'check' and d.outcome <> 'failed'
        and d.version_no is not distinct from r.version_no)::integer);
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  l_member := greatest(0, lim_member - n_member);
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped'
                  when l_min = l_report then case when is_adm then 'report_check' else 'recheck' end
                  else 'person' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope, 'version', r.version_no,
    'limit', case v_scope when 'stopped' then 0 when 'recheck' then lim_check when 'report_check' then lim_admin else lim_member end,
    'report', l_report, 'person', l_member, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope in ('recheck', 'stopped') then null else since + interval '1 day' end);
end $$;

revoke all on function public.ai_draft_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_draft_left(uuid) from public, anon, authenticated;
revoke all on function public.ai_check_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_check_left(uuid) from public, anon, authenticated;
grant execute on function public.ai_draft_claim(uuid) to authenticated;
grant execute on function public.ai_draft_left(uuid) to authenticated;
grant execute on function public.ai_check_claim(uuid) to authenticated;
grant execute on function public.ai_check_left(uuid) to authenticated;

-- Every colleague's use today against their limit, for an admin.
create or replace function public.ai_draft_usage()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'person', public.ai_draft_limit('person', 10),
    'admin', public.ai_draft_limit('admin', 20),
    'report', public.ai_draft_limit('report', 1),
    'report_admin', public.ai_draft_limit('report_admin', 5),
    'check', public.ai_draft_limit('check', 1),
    'check_admin', public.ai_draft_limit('check_admin', 5),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'day', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed'),
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed'),
        'limit', (select l.daily from public.ai_draft_limits l where l.scope = t.id::text),
        'cap', public.ai_day_cap(t)) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or exists (select 1 from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month))
    ) s), '[]'::jsonb));
end $$;
revoke all on function public.ai_draft_usage() from public, anon, authenticated;
grant execute on function public.ai_draft_usage() to authenticated;

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
    v_name := 'Drafts per report'; v_def := 1; v_unit := '';
  elsif v_scope = 'report_admin' then
    v_name := 'Admin drafts per report'; v_def := 5;
  elsif v_scope = 'check' then
    v_name := 'Figures checks per version'; v_def := 1; v_unit := '';
  elsif v_scope = 'check_admin' then
    v_name := 'Admin figures checks per report'; v_def := 5;
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

-- END OF AI LIMITS BY REPORT AND VERSION ------------------------------------
