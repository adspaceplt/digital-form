-- ===========================================================================
-- REPORTS ON REQUEST — a report the client asked for, on any period, held
-- by no month's checks and moving no month's report task.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-09: "Sometimes we need to create report on demand.
--   Like situation like now client requests a report." A report made on
--   request is not the month's report: it covers any period (a week, two
--   weeks, a whole month the month's ticks do not ask for), so nothing tied
--   to the month holds it or follows it.
--   1. `sm_reports.on_request` (false by default), set once at creation.
--   2. `sm_report_create_for(…, p_on_request)` takes it (New report's
--      Requested by the client, or any custom period) and files `On request`
--      on `report.created`. The four-argument `sm_report_create` stays the
--      month's. A changed signature drops the old one first (PostgREST
--      cannot choose between overloads).
--   3. `sm_reports_month_gate` lets it be made for any period.
--   4. `sm_report_gate` does not apply to it: Submit asks no month, content
--      count or late reason.
--   5. `sm_reports_task_follow` and `sm_reports_task_reset` leave the month's
--      report task alone for it.
--   6. `sm_report_months` and `sm_reports_owed` never count it as the
--      month's report.
--   7. A month's report carries on from the month's report before it, never
--      from one asked for; an Advertising Report asked for compares with the
--      same length just before it, typed by the team.
--
-- ROLLBACK
--   Run sm_report_create_for, sm_report_create, sm_reports_month_gate,
--   sm_report_gate, sm_reports_task_follow, sm_reports_task_reset,
--   sm_report_months and sm_reports_owed as their earlier sections define
--   them (dropping sm_report_create_for(uuid, date, date, text, uuid,
--   boolean) first), then drop the column sm_reports.on_request.
-- ===========================================================================

alter table public.sm_reports add column if not exists on_request boolean not null default false;

drop function if exists public.sm_report_create_for(uuid, date, date, text, uuid);
create or replace function public.sm_report_create_for(p_client uuid, p_start date, p_end date, p_kind text, p_brand uuid,
                                                       p_on_request boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rid uuid;
  prev uuid;
  pr public.sm_reports;
  totals jsonb := '{}'::jsonb;
  pgroups jsonb;
  ptk jsonb;
  c public.clients;
  b public.client_brands;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('error', 'bad-period'); end if;
  if coalesce(p_kind, '') not in ('social', 'ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_brand is not null then
    if not public.ops_granted('reports.whitelabel', 'work') then return jsonb_build_object('error', 'denied'); end if;
    select * into b from public.client_brands where id = p_brand;
    if b.id is null or b.client_id <> p_client or not b.active or not c.white_label or c.report_logo is null then
      return jsonb_build_object('error', 'bad-brand');
    end if;
  end if;
  select id into rid from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start = p_start and period_end = p_end
     and brand_id is not distinct from p_brand;
  if rid is not null then return jsonb_build_object('error', 'exists', 'id', rid); end if;
  /* The month's report carries on from the month's before it, never from
     one asked for; one asked for carries its accounts from the latest. */
  select id into prev from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start < p_start and brand_id is not distinct from p_brand
     and (coalesce(p_on_request, false) or not on_request)
   order by period_start desc limit 1;
  perform set_config('adspace.sm_fn', 'on', true);
  begin
    if p_kind = 'ads' then
      /* An Advertising Report asked for compares with the same length just
         before it, typed by the team. */
      if prev is not null and not coalesce(p_on_request, false) then
        select * into pr from public.sm_reports where id = prev;
        select coalesce(jsonb_object_agg(g.objective, jsonb_build_object('results',
                 coalesce(nullif(pr.ads_totals #>> array['groups', g.objective, 'results'], '')::numeric, g.results),
                 'spend', g.spend)), '{}'::jsonb)
          into pgroups
          from (select a.objective, sum(a.results) as results, sum(a.spend) as spend
                  from public.sm_report_ads a where a.report_id = prev and a.platform = 'meta' group by a.objective) g;
        if exists (select 1 from public.sm_report_ads where report_id = prev and platform = 'tiktok')
           or coalesce(pr.ads_totals #>> '{tiktok,reach}', pr.ads_totals #>> '{tiktok,impressions}',
                       pr.ads_totals #>> '{tiktok,spend}') is not null then
          ptk := jsonb_strip_nulls(jsonb_build_object(
            'prev_reach', nullif(pr.ads_totals #>> '{tiktok,reach}', '')::numeric,
            'prev_impressions', coalesce(nullif(pr.ads_totals #>> '{tiktok,impressions}', '')::numeric,
                                         (select sum(impressions) from public.sm_report_ads where report_id = prev and platform = 'tiktok')),
            'prev_spend', coalesce(nullif(pr.ads_totals #>> '{tiktok,spend}', '')::numeric,
                                   (select sum(spend) from public.sm_report_ads where report_id = prev and platform = 'tiktok'))));
        end if;
        totals := jsonb_strip_nulls(jsonb_build_object(
          'prev_start', pr.period_start, 'prev_end', pr.period_end,
          'prev_reach', nullif(pr.ads_totals ->> 'reach', '')::numeric,
          'prev_impressions', coalesce(nullif(pr.ads_totals ->> 'impressions', '')::numeric,
                                       (select sum(impressions) from public.sm_report_ads where report_id = prev and platform = 'meta')),
          'prev_spend', coalesce(nullif(pr.ads_totals ->> 'spend', '')::numeric,
                                 (select sum(spend) from public.sm_report_ads where report_id = prev and platform = 'meta')),
          'prev_groups', pgroups,
          'tiktok', ptk));
      else
        if date_trunc('month', p_start)::date = p_start and (p_start + interval '1 month' - interval '1 day')::date = p_end then
          totals := jsonb_build_object('prev_start', (p_start - interval '1 month')::date, 'prev_end', p_start - 1);
        else
          totals := jsonb_build_object('prev_start', p_start - (p_end - p_start + 1), 'prev_end', p_start - 1);
        end if;
      end if;
      insert into public.sm_reports (client_id, kind, title, period_start, period_end, created_by, first_month, ads_totals,
                                     brand_id, brand_name, label_client, on_request)
      values (p_client, p_kind, 'Social Media Advertising Report', p_start, p_end, me.id, false, totals,
              b.id, b.name, case when b.id is not null then p_client end, coalesce(p_on_request, false))
      returning id into rid;
    else
      insert into public.sm_reports (client_id, kind, period_start, period_end, created_by, brand_id, brand_name, label_client,
                                     on_request)
      values (p_client, p_kind, p_start, p_end, me.id, b.id, b.name, case when b.id is not null then p_client end,
              coalesce(p_on_request, false))
      returning id into rid;
      if prev is not null then
        insert into public.sm_report_platforms (report_id, platform, platform_name, account_name, handle, group_key, group_label,
          position, metrics, followers_start, er_basis, metric_notes)
        select rid, p.platform, p.platform_name, p.account_name, p.handle, p.group_key, p.group_label, p.position, p.metrics,
               coalesce(p.followers_end, case when p.followers_start is not null and p.growth_override is not null
                                              then p.followers_start + p.growth_override end),
               p.er_basis, p.metric_notes
          from public.sm_report_platforms p where p.report_id = prev;
      end if;
    end if;
  exception when unique_violation then
    perform set_config('adspace.sm_fn', 'off', true);
    return jsonb_build_object('error', 'index-pending');
  end;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(rid, 'report.created', nullif(concat_ws(' · ',
    case when b.id is not null then 'White label: ' || b.name end,
    case when p_on_request then 'On request' end), ''));
  return jsonb_build_object('ok', true, 'id', rid, 'carried', prev is not null);
end $$;
revoke all on function public.sm_report_create_for(uuid, date, date, text, uuid, boolean) from public, anon;
grant execute on function public.sm_report_create_for(uuid, date, date, text, uuid, boolean) to authenticated;

create or replace function public.sm_report_create(p_client uuid, p_start date, p_end date, p_kind text default 'social')
returns jsonb
language sql security definer set search_path = public as $$
  select public.sm_report_create_for(p_client, p_start, p_end, p_kind, null, false)
$$;
grant execute on function public.sm_report_create(uuid, date, date, text) to authenticated;

create or replace function public.sm_reports_month_gate()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if new.brand_id is not null or new.on_request or new.period_start < date '2026-10-01' or me.id is null then return new; end if;
  if coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage') then return new; end if;
  if exists (select 1 from public.ops_engagements e
              cross join lateral public.ops_month_span(e.period, e.start_day) s
              where e.client_id = new.client_id and e.status <> 'cancelled'
                and new.period_end between s.starts and s.ends
                and new.kind = any (coalesce(e.reports, '{}'::text[]))) then
    return new;
  end if;
  raise exception 'month-gate' using errcode = 'P0001';
end $$;
revoke all on function public.sm_reports_month_gate() from public, anon, authenticated;

create or replace function public.sm_report_gate(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  e public.ops_engagements;
  task public.ops_tasks;
  v_starts date;
  v_ends date;
  v_due timestamptz;
  v_made integer := 0;
  v_missing text[] := '{}';
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen(c.stage, c.owner, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.period_start < date '2026-10-01' or r.on_request then
    return jsonb_build_object('applies', false, 'ok', true, 'missing', '[]'::jsonb, 'on_request', r.on_request);
  end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = r.client_id and x.status <> 'cancelled'
     and r.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then
    v_missing := v_missing || 'no-month'::text;
    v_due := ((r.period_end + public.app_setting('report_due_days', r.period_end)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  else
    select s.starts, s.ends into v_starts, v_ends from public.ops_month_span(e.period, e.start_day) s;
    v_due := ((v_ends + public.app_setting('report_due_days', v_ends)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
    if not (r.kind = any (e.reports)) then
      v_missing := v_missing || 'not-ticked'::text;
    else
      select * into task from public.ops_tasks x
       where x.engagement_id = e.id and x.source_type = 'report_' || r.kind
         and x.cancelled_at is null and x.archived_at is null
       order by x.created_at desc limit 1;
      if task.id is null then
        v_missing := v_missing || 'no-task'::text;
      else
        v_due := coalesce(task.current_final_due_at, v_due);
      end if;
    end if;
    select count(*) into v_made from public.ops_tasks x
     where x.engagement_id = e.id and x.cancelled_at is null and x.archived_at is null
       and coalesce(x.source_type, '') not in ('report_social', 'report_ads');
    if v_made < e.planned_count then v_missing := v_missing || 'content'::text; end if;
  end if;
  return jsonb_build_object(
    'applies', true, 'ok', cardinality(v_missing) = 0, 'missing', to_jsonb(v_missing),
    'month', case when e.id is null then null else jsonb_build_object(
               'id', e.id, 'period', e.period, 'start_day', e.start_day, 'starts', v_starts, 'ends', v_ends,
               'reports', to_jsonb(e.reports)) end,
    'planned', coalesce(e.planned_count, 0), 'made', v_made,
    'task', case when task.id is null then null else jsonb_build_object(
              'id', task.id, 'task_no', task.task_no, 'stage_key', task.stage_key) end,
    'due', v_due, 'late', now() > v_due,
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'));
end $$;

create or replace function public.sm_reports_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  t public.ops_tasks;
  v_to text;
  v_was uuid;
  v_note text;
begin
  if new.brand_id is not null or new.on_request then return null; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.sent_on is not distinct from old.sent_on then
    return null;
  end if;
  v_to := public.sm_report_task_target(new.status, new.sent_on);
  if v_to is null then return null; end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = new.client_id and x.status <> 'cancelled'
     and new.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then return null; end if;
  select * into t from public.ops_tasks x
   where x.engagement_id = e.id and x.source_type = 'report_' || new.kind
     and x.cancelled_at is null and x.archived_at is null
   order by x.created_at desc limit 1
   for update;
  if t.id is null or t.completed_at is not null then return null; end if;

  if tg_op = 'INSERT' and new.created_by is not null then
    select team_member_id into v_was from public.ops_task_assignees
     where task_id = t.id and responsibility = 'owner' and ended_at is null;
    if v_was is distinct from new.created_by then
      update public.ops_task_assignees set ended_at = now()
       where task_id = t.id and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (t.id, new.created_by, 'owner', new.created_by);
      perform public.ops_log(t.id, 'assignment_changed',
        jsonb_build_object('owner_id', v_was), jsonb_build_object('owner_id', new.created_by),
        jsonb_build_object('report', true, 'report_id', new.id, 'stage_key', t.stage_key));
    end if;
  end if;

  if t.stage_key is distinct from v_to then
    v_note := case
      when tg_op = 'INSERT' then 'Report started'
      when new.status = 'draft' then 'Report back in draft'
      when new.status = 'review' then 'Report submitted for review'
      when new.status = 'confirmed' then 'Report confirmed'
      when new.sent_on is null then 'Report published'
      else 'Report sent to the client' end;
    update public.ops_tasks set stage_key = v_to, version = version + 1, updated_at = now(),
           completed_at = null, blocked_at = null, blocked_category = null
     where id = t.id;
    perform public.ops_log(t.id, 'stage_changed',
      jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', v_to),
      jsonb_build_object('note', v_note, 'report_id', new.id));
  elsif tg_op = 'INSERT' then
    update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_task_follow() from public, anon, authenticated;

create or replace function public.sm_reports_task_reset()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t public.ops_tasks;
begin
  if old.brand_id is not null or old.on_request or old.status <> 'draft' then return null; end if;
  select x.* into t from public.ops_tasks x
    join public.ops_engagements e on e.id = x.engagement_id
   cross join lateral public.ops_month_span(e.period, e.start_day) s
   where e.client_id = old.client_id and e.status <> 'cancelled'
     and old.period_end between s.starts and s.ends
     and x.source_type = 'report_' || old.kind
     and x.cancelled_at is null and x.archived_at is null
   order by e.period desc, x.created_at desc limit 1
   for update of x;
  if t.id is null or t.completed_at is not null or t.stage_key = 'todo' then return null; end if;
  update public.ops_tasks set stage_key = 'todo', version = version + 1, updated_at = now(),
         blocked_at = null, blocked_category = null
   where id = t.id;
  perform public.ops_log(t.id, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', 'todo'),
    jsonb_build_object('note', 'Report deleted', 'report_id', old.id));
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_task_reset() from public, anon, authenticated;

create or replace function public.sm_report_months(p_client uuid, p_kind text default 'social')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.clients;
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_kind, '') not in ('social', 'ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_row_seen(c.stage, c.owner, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'),
    'months', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'period', e.period, 'start_day', e.start_day,
               'starts', s.starts, 'ends', s.ends, 'status', e.status,
               'asks', p_kind = any (coalesce(e.reports, '{}'::text[])),
               'report', (select r.id from public.sm_reports r
                           where r.client_id = e.client_id and r.kind = p_kind and r.brand_id is null
                             and not r.on_request and r.period_end between s.starts and s.ends
                           order by r.period_start desc limit 1))
             order by e.period desc)
        from public.ops_engagements e
       cross join lateral public.ops_month_span(e.period, e.start_day) s
       where e.client_id = p_client and e.status <> 'cancelled'), '[]'::jsonb));
end $$;

create or replace function public.sm_reports_owed(p_period text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_period   text := coalesce(nullif(btrim(p_period), ''),
                       to_char(date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') - interval '1 month', 'YYYY-MM'));
  v_items    jsonb := '[]'::jsonb;
  v_seen     uuid[] := '{}';
  v_task     uuid;
  v_tdue     timestamptz;
  v_assignee text;
  v_due      timestamptz;
  v_found    boolean;
  e          record;
  k          text;
  r          record;
begin
  if not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if v_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then return jsonb_build_object('error', 'bad-period'); end if;

  -- Every report a month of the period asks for, found or not started.
  for e in
    select x.id, x.client_id, x.reports, s.starts, s.ends, c.name as client_name, c.slug as client_slug
      from public.ops_engagements x
      join public.clients c on c.id = x.client_id
     cross join lateral public.ops_month_span(x.period, x.start_day) s
     where x.period = v_period and x.status <> 'cancelled' and cardinality(x.reports) > 0
       and public.client_row_seen(c.stage, c.owner, 'view')
     order by c.name
  loop
    foreach k in array e.reports loop
      v_task := null; v_tdue := null; v_assignee := null;
      select x.id, x.current_final_due_at, m.name into v_task, v_tdue, v_assignee
        from public.ops_tasks x
        left join public.ops_task_assignees a
          on a.task_id = x.id and a.responsibility = 'owner' and a.ended_at is null
        left join public.team_members m on m.id = a.team_member_id
       where x.engagement_id = e.id and x.source_type = 'report_' || k
         and x.cancelled_at is null and x.archived_at is null
       order by x.created_at desc limit 1;
      v_due := coalesce(v_tdue,
        ((e.ends + public.app_setting('report_due_days', e.ends)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur');
      v_found := false;
      for r in
        select y.id, y.status, y.sent_on, b.name as brand_name
          from public.sm_reports y
          left join public.client_brands b on b.id = y.brand_id
         where y.client_id = e.client_id and y.kind = k and not y.on_request
           and y.period_end between e.starts and e.ends
         order by b.name nulls first, y.period_start
      loop
        v_found := true;
        v_seen := v_seen || r.id;
        v_items := v_items || jsonb_build_object(
          'client_id', e.client_id, 'client', e.client_name, 'slug', e.client_slug, 'kind', k,
          'brand', r.brand_name, 'report_id', r.id, 'status', r.status, 'sent_on', r.sent_on,
          'asked', true, 'task_id', v_task, 'assignee', v_assignee, 'due', v_due,
          'late', r.status <> 'published' and now() > v_due);
      end loop;
      if not v_found then
        v_items := v_items || jsonb_build_object(
          'client_id', e.client_id, 'client', e.client_name, 'slug', e.client_slug, 'kind', k,
          'brand', null, 'report_id', null, 'status', 'none', 'sent_on', null,
          'asked', true, 'task_id', v_task, 'assignee', v_assignee, 'due', v_due, 'late', now() > v_due);
      end if;
    end loop;
  end loop;

  -- Every report made for the period that no month's tick asked for: it
  -- belongs to the month whose span holds its last day, else to the
  -- calendar month of that day.
  for r in
    select y.id, y.client_id, y.kind, y.status, y.sent_on, y.period_end,
           c.name as client_name, c.slug as client_slug, b.name as brand_name
      from public.sm_reports y
      join public.clients c on c.id = y.client_id
      left join public.client_brands b on b.id = y.brand_id
     where not (y.id = any (v_seen)) and not y.on_request
       and coalesce((select x.period from public.ops_engagements x
                      cross join lateral public.ops_month_span(x.period, x.start_day) s
                      where x.client_id = y.client_id and x.status <> 'cancelled'
                        and y.period_end between s.starts and s.ends
                      order by x.period desc limit 1),
                    to_char(y.period_end, 'YYYY-MM')) = v_period
       and public.client_row_seen(c.stage, c.owner, 'view')
     order by c.name, y.kind, b.name nulls first
  loop
    v_due := ((r.period_end + public.app_setting('report_due_days', r.period_end)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
    v_items := v_items || jsonb_build_object(
      'client_id', r.client_id, 'client', r.client_name, 'slug', r.client_slug, 'kind', r.kind,
      'brand', r.brand_name, 'report_id', r.id, 'status', r.status, 'sent_on', r.sent_on,
      'asked', false, 'task_id', null, 'assignee', null, 'due', v_due,
      'late', r.status <> 'published' and now() > v_due);
  end loop;

  return jsonb_build_object('period', v_period, 'items', v_items);
end $$;
revoke all on function public.sm_reports_owed(text) from public, anon, authenticated;
grant execute on function public.sm_reports_owed(text) to authenticated;

-- END OF REPORTS ON REQUEST --------------------------------------------------

select public.functions_tidy();
