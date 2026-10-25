-- ===========================================================================
-- ANALYTICS READ WITH AI — an AI analysis of the Analytics figures, kept as
-- versions (2026-10-25)
-- ===========================================================================
-- WHY (the user, 2026-10-25: "i dont see whether this analytics trend is good
-- or bad since all is monochrome … churned clients too much for example";
-- "build part 1 and 2 together")
--
-- WHAT IT CHANGES
--   * `analytics_reads` (RLS on, no policy, no grant): each AI analysis of
--     the Analytics figures as the next version, with the figures it read
--     (`figures`), the period, the model and who ran it.
--   * Write with AI on Analytics is its own count (`ai_drafts.purpose`
--     `analytics`): `analytics` (3) a colleague's a day and
--     `analytics_admin` (10) an admin's, settings in `ai_draft_limits`,
--     claimed by `ai_analytics_claim()` (`team.analytics` at Work) and read
--     by `ai_analytics_left()`; `ai_draft_usage` and `ai_draft_set_limit`
--     know them.
--   * `analytics_read_save(p_press, p_period, p_figures, p_analysis,
--     p_model)` keeps a run as the next version (the press its own, once),
--     filed `team.changed` under Analytics; `analytics_reads_list()` the
--     last twenty, newest first; `analytics_read_delete(p_id)` removes one
--     (asked on the page, no restore), filed.
--
-- ORDER: the page first (it reads Write with AI as "This needs a database
-- update" until this runs), then this file in the SQL Editor (it holds a
-- delete and the purpose check's drop, which the connector holds back),
-- then the edge function `analytics-read`. Safe to run twice.
--
-- ROLLBACK
--   Run CHECKLIST WRITER's ai_draft_usage and ai_draft_set_limit again;
--   drop the six functions and `analytics_reads`; delete the `analytics`
--   rows from ai_drafts and put the purpose check back to its six
--   purposes.
-- ===========================================================================

create table if not exists public.analytics_reads (
  id uuid primary key default gen_random_uuid(),
  version integer not null unique,
  period text not null,
  figures jsonb not null default '{}'::jsonb,
  analysis jsonb not null,
  model text,
  press_id uuid unique references public.ai_drafts (id) on delete set null,
  created_by uuid references public.team_members (id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.analytics_reads enable row level security;
revoke all on public.analytics_reads from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'ai_drafts_purpose' and pg_get_constraintdef(oid) like '%analytics%') then
    alter table public.ai_drafts drop constraint if exists ai_drafts_purpose;
    alter table public.ai_drafts add constraint ai_drafts_purpose
      check (purpose in ('draft', 'check', 'caption', 'script', 'analysis', 'checklist', 'analytics'));
  end if;
end $$;

create or replace function public.ai_analytics_claim()
returns jsonb
language plpgsql security definer set search_path = public as $$
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
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('analytics_admin', 10) else public.ai_draft_limit('analytics', 3) end;
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
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
begin
  if not public.ops_granted('team.analytics', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('analytics_admin', 10) else public.ai_draft_limit('analytics', 3) end;
  return jsonb_build_object('limit', lim, 'next', since + interval '1 day',
    'left', greatest(0, lim - (select count(*) from public.ai_drafts d
      where d.team_member_id = m.id and d.purpose = 'analytics' and d.created_at >= since and d.outcome <> 'failed')::integer));
end $$;

create or replace function public.analytics_read_row(r public.analytics_reads)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', r.id, 'version', r.version, 'period', r.period, 'figures', r.figures,
    'analysis', r.analysis, 'model', r.model, 'created_at', r.created_at,
    'by', (select t.name from public.team_members t where t.id = r.created_by))
$$;
revoke all on function public.analytics_read_row(public.analytics_reads) from public, anon, authenticated;

create or replace function public.analytics_read_save(p_press uuid, p_period text, p_figures jsonb,
                                                      p_analysis jsonb, p_model text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  d public.ai_drafts;
  a public.analytics_reads;
  v_no integer;
begin
  if not public.ops_granted('team.analytics', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.ai_drafts x where x.id = p_press for update;
  if d.id is null or d.team_member_id <> m.id or d.purpose <> 'analytics' or d.outcome <> 'pending'
     or exists (select 1 from public.analytics_reads x where x.press_id = d.id) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if jsonb_typeof(p_analysis) is distinct from 'object' or char_length(p_analysis::text) > 40000
     or jsonb_typeof(p_figures) is distinct from 'object' or char_length(p_figures::text) > 60000
     or char_length(btrim(coalesce(p_period, ''))) not between 1 and 80 then
    return jsonb_build_object('error', 'bad-analysis');
  end if;
  perform pg_advisory_xact_lock(hashtext('analytics_reads'));
  select coalesce(max(x.version), 0) + 1 into v_no from public.analytics_reads x;
  insert into public.analytics_reads (version, period, figures, analysis, model, press_id, created_by)
  values (v_no, btrim(p_period), p_figures, p_analysis, left(nullif(btrim(coalesce(p_model, '')), ''), 80), d.id, m.id)
  returning * into a;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'team.changed', 'Analytics',
          'Analysis version ' || v_no || ' written with AI · ' || btrim(p_period));
  return public.analytics_read_row(a);
end $$;

create or replace function public.analytics_reads_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ops_granted('team.analytics', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('versions', coalesce((select jsonb_agg(public.analytics_read_row(x) order by x.version desc)
    from (select * from public.analytics_reads a order by a.version desc limit 20) x), '[]'::jsonb));
end $$;

create or replace function public.analytics_read_delete(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  a public.analytics_reads;
begin
  if not public.ops_granted('team.analytics', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  delete from public.analytics_reads x where x.id = p_id returning * into a;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'team.changed', 'Analytics',
          'Analysis version ' || a.version || ' deleted · ' || a.period);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ai_draft_usage()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
  -- This calendar month in Malaysia, for what the calls cost.
  v_cal timestamptz := date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'person', public.ai_draft_limit('person', 10),
    'admin', public.ai_draft_limit('admin', 20),
    'report', public.ai_draft_limit('report', 1),
    'report_admin', public.ai_draft_limit('report_admin', 5),
    'check', public.ai_draft_limit('check', 1),
    'check_admin', public.ai_draft_limit('check_admin', 5),
    'caption', public.ai_draft_limit('caption', 20),
    'caption_admin', public.ai_draft_limit('caption_admin', 40),
    'script', public.ai_draft_limit('script', 10),
    'script_admin', public.ai_draft_limit('script_admin', 20),
    'analysis', public.ai_draft_limit('analysis', 3),
    'analysis_admin', public.ai_draft_limit('analysis_admin', 10),
    'checklist', public.ai_draft_limit('checklist', 10),
    'checklist_admin', public.ai_draft_limit('checklist_admin', 20),
    'analytics', public.ai_draft_limit('analytics', 3),
    'analytics_admin', public.ai_draft_limit('analytics_admin', 10),
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
        'day', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose in ('draft', 'check')),
        'captions', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'caption'),
        'caption_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                            then public.ai_draft_limit('caption_admin', 40) else public.ai_draft_limit('caption', 20) end,
        'scripts', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'script'),
        'script_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                           then public.ai_draft_limit('script_admin', 20) else public.ai_draft_limit('script', 10) end,
        'analyses', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'analysis'),
        'analysis_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                             then public.ai_draft_limit('analysis_admin', 10) else public.ai_draft_limit('analysis', 3) end,
        'checklists', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'checklist'),
        'checklist_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                              then public.ai_draft_limit('checklist_admin', 20) else public.ai_draft_limit('checklist', 10) end,
        'analytics', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'analytics'),
        'analytics_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                              then public.ai_draft_limit('analytics_admin', 10) else public.ai_draft_limit('analytics', 3) end,
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed'),
        'limit', (select l.daily from public.ai_draft_limits l where l.scope = t.id::text),
        'cap', public.ai_day_cap(t)) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'review', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'scripts', 'none')) >= public.level_rank('work')
              or exists (select 1 from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month))
    ) s), '[]'::jsonb));
end $$;
revoke all on function public.ai_draft_usage() from public, anon, authenticated;
grant execute on function public.ai_draft_usage() to authenticated;

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
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
  elsif v_scope = 'caption' then
    v_name := 'Captions, each colleague'; v_def := 20;
  elsif v_scope = 'caption_admin' then
    v_name := 'Captions, each admin'; v_def := 40;
  elsif v_scope = 'script' then
    v_name := 'Scripts, each colleague'; v_def := 10;
  elsif v_scope = 'script_admin' then
    v_name := 'Scripts, each admin'; v_def := 20;
  elsif v_scope = 'analysis' then
    v_name := 'Brand analyses, each colleague'; v_def := 3;
  elsif v_scope = 'analysis_admin' then
    v_name := 'Brand analyses, each admin'; v_def := 10;
  elsif v_scope = 'checklist' then
    v_name := 'Checklists, each colleague'; v_def := 10;
  elsif v_scope = 'checklist_admin' then
    v_name := 'Checklists, each admin'; v_def := 20;
  elsif v_scope = 'analytics' then
    v_name := 'Analytics analyses, each colleague'; v_def := 3;
  elsif v_scope = 'analytics_admin' then
    v_name := 'Analytics analyses, each admin'; v_def := 10;
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

revoke all on function public.ai_analytics_claim() from public, anon, authenticated;
revoke all on function public.ai_analytics_left() from public, anon, authenticated;
revoke all on function public.analytics_read_save(uuid, text, jsonb, jsonb, text) from public, anon, authenticated;
revoke all on function public.analytics_reads_list() from public, anon, authenticated;
revoke all on function public.analytics_read_delete(uuid) from public, anon, authenticated;
grant execute on function public.ai_analytics_claim() to authenticated;
grant execute on function public.ai_analytics_left() to authenticated;
grant execute on function public.analytics_read_save(uuid, text, jsonb, jsonb, text) to authenticated;
grant execute on function public.analytics_reads_list() to authenticated;
grant execute on function public.analytics_read_delete(uuid) to authenticated;

-- END OF ANALYTICS READ WITH AI ----------------------------------------------

select public.functions_tidy();
