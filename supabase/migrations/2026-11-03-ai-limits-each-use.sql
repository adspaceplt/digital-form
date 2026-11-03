-- AI LIMITS FOR EACH USE ----------------------------------------------------
-- 2026-11-03, the user: "AI usage settings ok approve build". Each use of AI
-- (report drafts, commentary checks, captions, scripts, brand analyses,
-- checklists, analytics) has one standard a person a day, the same for an
-- admin as for anyone; any colleague may be given an own figure for any use
-- (`{colleague id}:{use}`, null is the standard). The day's total of AI uses
-- across drafts and checks, and every `_admin` figure, are no longer read.
-- One draft and one check a report a day stays as a switch (`per_report`,
-- 1 on, 0 off).
--
--   1. The new standards are taken once from the figures in force, so nobody
--      has less room than before: report drafts and commentary checks each
--      take the day's total of AI uses, every other use the larger of the
--      colleague's and the admin's; the report switch is on only where one
--      draft and one check a report were still the figures.
--   2. `ai_cap(p_member, p_use)`: an own figure, else the standard, else the
--      default. Read only by the functions below.
--   3. Every claim and every count of what is left asks it.
--   4. `ai_draft_usage()` answers each person's use today and the limit that
--      applies, for each use; `ai_draft_set_limit` takes the new scopes.
--
-- Rollback: run the AI functions' earlier bands of schema.sql again; the
-- rows of `ai_draft_limits` this adds are ignored by them. `ai_day_cap` and
-- the old rows stay, unread.

do $$
begin
  if not exists (select 1 from public.ai_draft_limits where scope = 'drafts') then
    insert into public.ai_draft_limits (scope, daily, set_by, set_at)
    select k, v, 'portal', now() from (values
      ('drafts', coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'person'), 10)),
      ('checks', coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'person'), 10)),
      ('caption', greatest(coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'caption'), 20),
                           coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'caption_admin'), 40))),
      ('script', greatest(coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'script'), 10),
                          coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'script_admin'), 20))),
      ('analysis', greatest(coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'analysis'), 3),
                            coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'analysis_admin'), 10))),
      ('checklist', greatest(coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'checklist'), 10),
                             coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'checklist_admin'), 20))),
      ('analytics', greatest(coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'analytics'), 3),
                             coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'analytics_admin'), 10))),
      ('per_report', case when coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'report'), 1) <= 1
                           and coalesce((select l.daily from public.ai_draft_limits l where l.scope = 'check'), 1) <= 1
                          then 1 else 0 end)
    ) s(k, v)
    on conflict (scope) do update set daily = excluded.daily, set_by = excluded.set_by, set_at = excluded.set_at;
  end if;
end $$;

-- A use's default, where no standard is set.
create or replace function public.ai_cap_default(p_use text)
returns integer language sql immutable set search_path = public as $$
  select case p_use when 'drafts' then 10 when 'checks' then 10 when 'caption' then 20 when 'script' then 10
                    when 'analysis' then 3 when 'checklist' then 10 when 'analytics' then 3 when 'per_report' then 1 else 0 end
$$;
revoke all on function public.ai_cap_default(text) from public, anon, authenticated;

-- A person's limit for one use: their own, else the standard, else the default.
create or replace function public.ai_cap(p_member uuid, p_use text)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(
    (select l.daily from public.ai_draft_limits l where l.scope = p_member::text || ':' || p_use),
    (select l.daily from public.ai_draft_limits l where l.scope = p_use),
    public.ai_cap_default(p_use))
$$;
revoke all on function public.ai_cap(uuid, text) from public, anon, authenticated;

create or replace function public.ai_draft_claim(p_report uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
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
  lim_member := public.ai_cap(m.id, 'drafts');
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  lim_report := public.ai_cap(m.id, 'per_report');
  if lim_report > 0 then
    select count(*) into n_report from public.ai_draft_same(p_report) s
     where s.team_member_id = m.id and s.created_at >= since;
    if n_report >= lim_report then
      return jsonb_build_object('error', 'ai-limit', 'scope', 'report', 'limit', lim_report, 'next', since + interval '1 day');
    end if;
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose = 'draft';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'drafts', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, version_no)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, r.version_no) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_draft_left(p_report uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_member integer;
  l_report integer; l_member integer; l_min integer;
  lim_member integer;
  lim_report integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim_member := public.ai_cap(m.id, 'drafts');
  lim_report := public.ai_cap(m.id, 'per_report');
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose = 'draft';
  l_member := greatest(0, lim_member - n_member);
  l_report := case when lim_report > 0 then greatest(0, lim_report - (select count(*) from public.ai_draft_same(p_report) s
    where s.team_member_id = m.id and s.created_at >= since)::integer) else l_member end;
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped' when lim_report > 0 and l_report <= l_member then 'report' else 'drafts' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope,
    'limit', case v_scope when 'stopped' then 0 when 'report' then lim_report else lim_member end,
    'report', l_report, 'person', l_member, 'admin', coalesce(m.is_admin, false) or m.role = 'admin',
    'next', case when l_min > 0 or v_scope = 'stopped' then null else since + interval '1 day' end);
end $$;

create or replace function public.ai_check_claim(p_report uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
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
  lim_member := public.ai_cap(m.id, 'checks');
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  lim_check := public.ai_cap(m.id, 'per_report');
  if lim_check > 0 and (select count(*) from public.ai_drafts d
       where d.report_id = p_report and d.purpose = 'check' and d.outcome not in ('failed', 'incomplete')
         and not (d.outcome = 'pending' and d.created_at < now() - interval '10 minutes')
         and d.team_member_id = m.id and d.created_at >= since) >= lim_check then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report_check', 'limit', lim_check, 'next', since + interval '1 day');
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose = 'check';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'checks', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, purpose, version_no)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, 'check', r.version_no) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_check_left(p_report uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
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
  lim_member := public.ai_cap(m.id, 'checks');
  lim_check := public.ai_cap(m.id, 'per_report');
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose = 'check';
  l_member := greatest(0, lim_member - n_member);
  l_report := case when lim_check > 0 then greatest(0, lim_check - (select count(*) from public.ai_drafts d
    where d.report_id = p_report and d.purpose = 'check' and d.outcome not in ('failed', 'incomplete')
      and not (d.outcome = 'pending' and d.created_at < now() - interval '10 minutes')
      and d.team_member_id = m.id and d.created_at >= since)::integer) else l_member end;
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped' when lim_check > 0 and l_report <= l_member then 'report_check' else 'checks' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope, 'version', r.version_no,
    'limit', case v_scope when 'stopped' then 0 when 'report_check' then lim_check else lim_member end,
    'report', l_report, 'person', l_member, 'admin', coalesce(m.is_admin, false) or m.role = 'admin',
    'next', case when l_min > 0 or v_scope = 'stopped' then null else since + interval '1 day' end);
end $$;

create or replace function public.ai_caption_claim(p_batch uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  b public.batches;
  since timestamptz := public.ai_draft_day();
  n_cap integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('review.sets', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into b from public.batches x where x.id = p_batch;
  if b.id is null or not public.client_seen(b.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := public.ai_cap(m.id, 'caption');
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_cap from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'caption' and d.created_at >= since and d.outcome <> 'failed';
  if n_cap >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'caption', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, batch_id, purpose)
  values (m.id, b.client_id, b.id, 'caption') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_cap - 1, 'limit', lim);
end $$;

create or replace function public.ai_caption_left()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('review.sets', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := public.ai_cap(m.id, 'caption');
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'caption' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'caption' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;

create or replace function public.ai_script_claim(p_script uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  v public.video_scripts;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.video_scripts x where x.id = p_script;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(v.client_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  -- One count at a time, with the drafts, so the last script is taken once.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := public.ai_cap(m.id, 'script');
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'script' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'script', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, script_id, purpose)
  values (m.id, v.client_id, v.id, 'script') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;

create or replace function public.ai_script_left()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := public.ai_cap(m.id, 'script');
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'script' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'script' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;

create or replace function public.ai_analysis_claim(p_client uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('clients.brand', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.clients c where c.id = p_client) then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  -- One count at a time, with the drafts, so the last analysis is taken once.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := public.ai_cap(m.id, 'analysis');
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'analysis' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'analysis', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, purpose)
  values (m.id, p_client, 'analysis') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;

create or replace function public.ai_analysis_left()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('clients.brand', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := public.ai_cap(m.id, 'analysis');
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'analysis' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'analysis' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;

create or replace function public.ai_checklist_claim(p_client uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('clients.checklists', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.clients c where c.id = p_client) then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := public.ai_cap(m.id, 'checklist');
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'checklist' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'checklist', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, purpose)
  values (m.id, p_client, 'checklist') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;

create or replace function public.ai_checklist_left()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
begin
  if not public.allowed('clients.checklists', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := public.ai_cap(m.id, 'checklist');
  return jsonb_build_object('limit', lim, 'next', since + interval '1 day',
    'left', greatest(0, lim - (select count(*) from public.ai_drafts d
      where d.team_member_id = m.id and d.purpose = 'checklist' and d.created_at >= since and d.outcome <> 'failed')::integer));
end $$;

create or replace function public.ai_analytics_claim()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.ops_granted('team.analytics', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := public.ai_cap(m.id, 'analytics');
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'analytics' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'analytics', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, purpose)
  values (m.id, 'analytics') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;

create or replace function public.ai_analytics_left()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
begin
  if not public.ops_granted('team.analytics', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := public.ai_cap(m.id, 'analytics');
  return jsonb_build_object('limit', lim, 'next', since + interval '1 day',
    'left', greatest(0, lim - (select count(*) from public.ai_drafts d
      where d.team_member_id = m.id and d.purpose = 'analytics' and d.created_at >= since and d.outcome <> 'failed')::integer));
end $$;

-- A limit set: a use's standard, the report switch, or one colleague's own
-- figure for one use (`{colleague id}:{use}`; null is the standard).
create or replace function public.ai_draft_set_limit(p_scope text, p_daily integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_name text;
  v_was integer;
  v_def integer;
  v_scope text := btrim(coalesce(p_scope, ''));
  v_use text;
  t public.team_members;
  v_words constant jsonb := '{"drafts":"Report drafts","checks":"Commentary checks","caption":"Captions","script":"Scripts",
    "analysis":"Brand analyses","checklist":"Checklists","analytics":"Analytics analyses"}';
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_daily is not null and (p_daily < 0 or p_daily > 500) then
    return jsonb_build_object('error', 'bad-limit');
  end if;
  if v_scope = 'per_report' then
    if p_daily is not null and p_daily > 1 then return jsonb_build_object('error', 'bad-limit'); end if;
    v_name := 'One draft and one check a report a day';
  elsif v_words ? v_scope then
    v_name := v_words ->> v_scope;
    v_def := public.ai_cap_default(v_scope);
  elsif v_scope ~ '^[0-9a-f-]{36}:[a-z]+$' and v_words ? split_part(v_scope, ':', 2) then
    v_use := split_part(v_scope, ':', 2);
    select * into t from public.team_members x where x.id::text = split_part(v_scope, ':', 1);
    if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
    v_name := (v_words ->> v_use) || ', ' || t.name;
    select l.daily into v_def from public.ai_draft_limits l where l.scope = v_use;
    v_def := coalesce(v_def, public.ai_cap(null, v_use));
  else
    return jsonb_build_object('error', 'bad-scope');
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
          case when v_scope = 'per_report' then case when coalesce(v_was, 1) = 0 then 'off' else 'on' end || ' → ' ||
                                                case when coalesce(p_daily, 1) = 0 then 'off' else 'on' end
               else case when v_was is null then 'standard, ' || v_def || ' a day' when v_was = 0 then 'stopped' else v_was || ' a day' end ||
                    ' → ' ||
                    case when p_daily is null then 'standard, ' || v_def || ' a day' when p_daily = 0 then 'stopped' else p_daily || ' a day' end
          end);
  return jsonb_build_object('ok', true);
end $$;

-- Each person's use today and the limit that applies, for each use; the
-- standards; what this month cost.
create or replace function public.ai_draft_usage()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
  -- This calendar month in Malaysia, for what the calls cost.
  v_cal timestamptz := date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_uses constant text[] := array['drafts', 'checks', 'caption', 'script', 'analysis', 'checklist', 'analytics'];
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'limits', (select jsonb_object_agg(u, public.ai_cap(null, u)) from unnest(v_uses || array['per_report']) u),
    'cost', (select jsonb_build_object(
        'since', v_cal,
        'price_in', public.app_setting('ai_price_in', v_today),
        'price_out', public.app_setting('ai_price_out', v_today),
        'price_search', coalesce(public.app_setting('ai_price_search', v_today), 10),
        'uses', count(*),
        'untracked', count(*) filter (where c.input_tokens is null),
        'input', coalesce(sum(c.input_tokens), 0),
        'output', coalesce(sum(c.output_tokens), 0),
        'searches', coalesce(sum(c.web_searches), 0),
        'usd', round(coalesce(sum(c.usd), 0), 2),
        'by', coalesce((select jsonb_object_agg(p.purpose, p.x) from (
            select c2.purpose, jsonb_build_object('uses', count(*), 'input', coalesce(sum(c2.input_tokens), 0),
                     'output', coalesce(sum(c2.output_tokens), 0), 'searches', coalesce(sum(c2.web_searches), 0),
                     'usd', round(coalesce(sum(c2.usd), 0), 2)) as x
              from (select d.purpose, d.input_tokens, d.output_tokens, d.web_searches,
                           (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                          + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                          + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0 as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens, d.web_searches,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                  + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0 as usd
              from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'used', jsonb_build_object('drafts', u.drafts, 'checks', u.checks, 'caption', u.caption, 'script', u.script,
                                   'analysis', u.analysis, 'checklist', u.checklist, 'analytics', u.analytics),
        'cap', (select jsonb_object_agg(k, public.ai_cap(t.id, k)) from unnest(v_uses) k),
        'own', coalesce((select jsonb_object_agg(split_part(l.scope, ':', 2), l.daily) from public.ai_draft_limits l
                          where l.scope like t.id::text || ':%' and l.daily is not null), '{}'::jsonb),
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed')) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
        cross join lateral (
          select count(*) filter (where d.purpose = 'draft') as drafts, count(*) filter (where d.purpose = 'check') as checks,
                 count(*) filter (where d.purpose = 'caption') as caption, count(*) filter (where d.purpose = 'script') as script,
                 count(*) filter (where d.purpose = 'analysis') as analysis, count(*) filter (where d.purpose = 'checklist') as checklist,
                 count(*) filter (where d.purpose = 'analytics') as analytics
            from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed') u
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'review', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'scripts', 'none')) >= public.level_rank('work')
              or exists (select 1 from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month))
    ) s), '[]'::jsonb));
end $$;

-- END OF AI LIMITS FOR EACH USE ---------------------------------------------

select public.functions_tidy();
