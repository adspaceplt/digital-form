-- ===========================================================================
-- SCRIPT WRITER — Write script in Video Scripts: a video's script drafted by
-- AI from the colleague's notes, counted apart from the reports' and the
-- captions' AI uses.
-- 2026-10-09. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/smsql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-09: "go ahead and write script")
--   1. `ai_drafts.purpose` takes `script`; a script's row names its video
--      (`script_id`) and client.
--   2. `ai_script_claim(p_script)`: Video Scripts at Work, a video on a client
--      the colleague works on. Counted by the colleague a day, from midnight
--      MYT: `script` (10) a colleague's, `script_admin` (20) an admin's, both
--      settings in `ai_draft_limits`; 0 stops it. `ai_script_left()` reads
--      what is left without writing.
--   3. The reports' limits count report drafts and commentary checks alone
--      (`purpose in ('draft', 'check')`), so neither a caption nor a script
--      takes from them.
--   4. `ai_draft_usage()` adds the script limits and each colleague's scripts
--      today, and lists a colleague at Video Scripts Work;
--      `ai_draft_set_limit` names `script` and `script_admin`.
--
-- ROLLBACK
--   Run the CAPTION WRITER AND AI COST section again; then, in the SQL
--   Editor, drop ai_script_claim(uuid) and ai_script_left(), delete the
--   script rows from ai_drafts and put the purpose check back to
--   ('draft', 'check', 'caption'). The column may stay.
-- ===========================================================================

alter table public.ai_drafts add column if not exists script_id uuid;
alter table public.ai_drafts drop constraint if exists ai_drafts_purpose;
alter table public.ai_drafts add constraint ai_drafts_purpose check (purpose in ('draft', 'check', 'caption', 'script'));

-- A script: the colleague's own count a day, apart from the reports' and the
-- captions'.
create or replace function public.ai_script_claim(p_script uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
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
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('script_admin', 20) else public.ai_draft_limit('script', 10) end;
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

-- What Write script has left today, read without writing.
create or replace function public.ai_script_left()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('script_admin', 20) else public.ai_draft_limit('script', 10) end;
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'script' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'script' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;

revoke all on function public.ai_script_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_script_left() from public, anon, authenticated;
grant execute on function public.ai_script_claim(uuid) to authenticated;
grant execute on function public.ai_script_left() to authenticated;

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
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose in ('draft', 'check');
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
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose in ('draft', 'check');
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
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose in ('draft', 'check');
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
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose in ('draft', 'check');
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
    'cost', (select jsonb_build_object(
        'since', v_cal,
        'price_in', public.app_setting('ai_price_in', v_today),
        'price_out', public.app_setting('ai_price_out', v_today),
        'uses', count(*),
        'untracked', count(*) filter (where c.input_tokens is null),
        'input', coalesce(sum(c.input_tokens), 0),
        'output', coalesce(sum(c.output_tokens), 0),
        'usd', round(coalesce(sum(c.usd), 0), 2),
        'by', coalesce((select jsonb_object_agg(p.purpose, p.x) from (
            select c2.purpose, jsonb_build_object('uses', count(*), 'input', coalesce(sum(c2.input_tokens), 0),
                     'output', coalesce(sum(c2.output_tokens), 0), 'usd', round(coalesce(sum(c2.usd), 0), 2)) as x
              from (select d.purpose, d.input_tokens, d.output_tokens,
                           (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                          + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0 as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0 as usd
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

-- END OF SCRIPT WRITER --------------------------------------------------------

select public.functions_tidy();
