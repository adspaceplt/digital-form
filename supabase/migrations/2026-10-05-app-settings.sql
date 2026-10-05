-- ===========================================================================
-- APP SETTINGS — the business figures outside Performance that the team may
-- change: how long a lead and a proposal wait before they read overdue, SST,
-- the term adjustments, and when a month's report is due.
-- 2026-10-05. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-05: "what if i need changes the next
-- quarter"; the list chosen the same day)
--   1. `app_settings` (key, from_date, value): a value holds from its day
--      until a later row for the same key. RLS on, no policy, no grant. The
--      first run seeds each key's value as it stood, from 14 Aug 2023 (the
--      company's registration), only where the key has no row:
--      lead_followup_hours 48, proposal_followup_days 21, sst_pct 8,
--      term_1_3 25, term_4_5 15, term_6_11 0, term_12_23 -5, term_24 -10,
--      report_due_days 7.
--   2. `app_setting(key, at)`: the value in force on a day (else the
--      earliest), for the functions alone.
--   3. `app_settings_read()` (anyone: the figures are on every quote):
--      every key's rows, and who set each for the team.
--   4. `app_settings_set(p_from, p_values)` (an admin): from today (MYT) or
--      a later day, never an earlier one (`past`), so an issued letter keeps
--      the SST and terms of its own day; each value in its bounds
--      (`bad-value` with the key); a value already in force is not a
--      change; each change filed `team.changed` under Settings, from and to.
--   5. A month's report task is due once: `report_due_days` after the
--      month's last day at 23:59 MYT (`sm_report_gate` reads the same day),
--      with no separate first draft date
--      (the user, 2026-10-05: "one date, 7 days"). An open report task keeps
--      its first draft date until it is done.
--
-- ROLLBACK
--   Run ops_engagement_sync_reports from A DELETED MONTH TAKES ITS REPORT
--   TASKS and sm_report_gate from REPORT MONTH GATE again; then,
--   in the SQL Editor, drop app_settings_set, app_settings_read,
--   app_setting and the table.
-- ===========================================================================

create table if not exists public.app_settings (
  key        text not null,
  from_date  date not null,
  value      numeric not null,
  set_by     uuid references public.team_members(id) on delete set null,
  set_at     timestamptz not null default now(),
  primary key (key, from_date)
);
alter table public.app_settings enable row level security;
revoke all on table public.app_settings from public, anon, authenticated;

insert into public.app_settings (key, from_date, value)
select k.key, date '2023-08-14', k.value
  from (values ('lead_followup_hours', 48), ('proposal_followup_days', 21), ('sst_pct', 8),
               ('term_1_3', 25), ('term_4_5', 15), ('term_6_11', 0), ('term_12_23', -5), ('term_24', -10),
               ('report_due_days', 7)) k(key, value)
 where not exists (select 1 from public.app_settings s where s.key = k.key);

create or replace function public.app_setting(p_key text, p_at date)
returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select s.value from public.app_settings s where s.key = p_key and s.from_date <= coalesce(p_at, current_date)
      order by s.from_date desc limit 1),
    (select s.value from public.app_settings s where s.key = p_key order by s.from_date limit 1))
$$;
revoke all on function public.app_setting(text, date) from public, anon, authenticated;

create or replace function public.app_settings_read()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_team boolean := public.is_team();
begin
  return jsonb_build_object(
    'today', (now() at time zone 'Asia/Kuala_Lumpur')::date,
    'admin', v_team and public.allowed('admin'),
    'settings', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'from', s.from_date, 'value', s.value,
                   'by', case when v_team then (select t.name from public.team_members t where t.id = s.set_by) end,
                   'at', case when v_team then s.set_at end)
                 order by s.key, s.from_date) from public.app_settings s), '[]'::jsonb));
end $$;

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days'];
  v_moved text[] := '{}';
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, 2) <> v_v
       or (v_k = 'lead_followup_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'proposal_followup_days' and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      insert into public.app_settings (key, from_date, value, set_by, set_at)
      values (v_k, p_from, v_v, v_me.id, now())
      on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_name := case v_k when 'lead_followup_hours' then 'A lead waits' when 'proposal_followup_days' then 'A proposal waits'
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 23 months' when 'term_24' then '24 months and more'
        else 'Report due' end;
      v_unit := case when v_k = 'lead_followup_hours' then ' hours' when v_k in ('proposal_followup_days', 'report_due_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || trim(to_char(v_was, 'FM999999990.99'), '.') || v_unit || ' → ' ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || v_unit || ' · from ' || public.register_day(p_from));
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_read() to anon, authenticated;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

create or replace function public.ops_engagement_sync_reports(p_engagement uuid, p_moved boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  k text;
  v_ends date;
  v_due timestamptz;
  v_draft timestamptz;
  t public.ops_tasks;
  v_first text;
  res jsonb;
  made integer := 0;
  gone integer := 0;
begin
  select * into e from public.ops_engagements where id = p_engagement;
  if e.id is null or e.status in ('completed', 'cancelled') then
    return jsonb_build_object('made', 0, 'cancelled', 0);
  end if;
  select s.ends into v_ends from public.ops_month_span(e.period, e.start_day) s;
  v_due := ((v_ends + public.app_setting('report_due_days', v_ends)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  v_draft := v_due - interval '1 day';
  foreach k in array array['social', 'ads'] loop
    if k = any (e.reports) then
      if not exists (select 1 from public.ops_tasks x
                      where x.engagement_id = e.id and x.source_type = 'report_' || k
                        and x.cancelled_at is null and x.archived_at is null) then
        res := public.ops_create_task(jsonb_build_object(
          'engagement_id', e.id, 'scope', 'client', 'client_id', e.client_id,
          'workflow_key', 'task', 'task_type', 'engagement', 'deliverable_type', 'report',
          'content_desc', case k when 'social' then 'Accounts report' else 'Advertising report' end,
          'code_period', e.period, 'first_draft_due_at', v_draft, 'final_due_at', v_due,
          'source_type', 'report_' || k,
          'owner_id', e.manager_id, 'manager_id', e.manager_id));
        if res ? 'error' then
          raise exception 'report-task: %', res ->> 'error' using errcode = 'P0001';
        end if;
        /* One date: the task is made with a draft date the day before (so
           neither the order check nor the Report template sets one), then
           it is taken off. */
        update public.ops_tasks set original_first_draft_due_at = null, current_first_draft_due_at = null
         where engagement_id = e.id and source_type = 'report_' || k
           and cancelled_at is null and archived_at is null and first_draft_submitted_at is null;
        made := made + 1;
      elsif p_moved then
        for t in select * from public.ops_tasks x
                  where x.engagement_id = e.id and x.source_type = 'report_' || k
                    and x.cancelled_at is null and x.archived_at is null and x.completed_at is null loop
          update public.ops_tasks set current_final_due_at = v_due,
                 updated_at = now(), version = version + 1
           where id = t.id;
          if t.current_final_due_at is distinct from v_due then
            perform public.ops_log(t.id, 'due_changed',
              jsonb_build_object('kind', 'final', 'value', t.current_final_due_at),
              jsonb_build_object('kind', 'final', 'value', v_due),
              jsonb_build_object('reason', 'scope_change', 'note', 'The month''s start day moved.'));
          end if;
        end loop;
      end if;
    else
      for t in select * from public.ops_tasks x
                where x.engagement_id = e.id and x.source_type = 'report_' || k
                  and x.cancelled_at is null and x.archived_at is null and x.completed_at is null loop
        select s.key into v_first from public.ops_workflow_stages s
         where s.workflow_id = t.workflow_id order by s.position limit 1;
        if t.stage_key = v_first then
          update public.ops_tasks set stage_key = 'cancelled', cancelled_at = now(), updated_at = now(),
                 version = version + 1
           where id = t.id;
          perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', t.stage_key),
            jsonb_build_object('stage_key', 'cancelled'),
            jsonb_build_object('note', 'The month no longer asks for this report.'));
          gone := gone + 1;
        end if;
      end loop;
    end if;
  end loop;
  return jsonb_build_object('made', made, 'cancelled', gone);
end $$;
revoke all on function public.ops_engagement_sync_reports(uuid, boolean) from public, anon, authenticated;

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
  if r.period_start < date '2026-10-01' then
    return jsonb_build_object('applies', false, 'ok', true, 'missing', '[]'::jsonb);
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
