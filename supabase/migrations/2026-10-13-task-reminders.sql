-- ===========================================================================
-- TASK REMINDERS — on a weekday from 10:00 to 18:00 MYT each colleague is
-- told what of their own needs them: one notice every few hours, never one
-- a task.
-- 2026-10-13. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-13: "nudge or notification for different
-- assigned person … if its urgent, overdue etc., send periodical
-- notifications"; "for new tasks also not moved to in progress"; "not every
-- single task needs to have a noti but it should have something")
--   1. `ops_tasks_nudge(p_at)` (no caller but pg_cron; revoked from every
--      login) reads each open task's owner (an active colleague, never a
--      system account) and sorts the task into the first of:
--        Overdue: My Work's late rule (the due date passed short of client
--          review, or a priority's deadline passed short of its review);
--        Urgent: Urgent priority, its deadline still running;
--        Due today: the due date, or a priority's deadline, falls today;
--        Not started: still at a starting stage (`intake`, `ready`) with its
--          draft due (else its due date) within `task_start_days`, or with
--          no date, assigned that many days ago.
--      A colleague holding any is sent one notice (kind `tasks.nudge`):
--      one task names it and opens it; several are counted ("5 tasks need
--      attention: 2 overdue, 1 Urgent, 2 not started.") with the first
--      three named, opening My Work. Never more often than every
--      `task_remind_hours`; on a weekday from 10:00 to 18:00 MYT alone.
--      Answers how many were told.
--   2. Business settings (My Work: Task reminders), from a day on:
--      `task_remind_hours` (3; 0 to 24, 0 sends none) and `task_start_days`
--      (2; 0 to 30, 0 leaves out Not started). `app_settings_set` takes them,
--      filed "Task reminders: 3 hours → 4 hours · from …".
--   3. pg_cron `tasks-nudge` runs it at minute 0 of every hour from 02:00 to
--      09:00 UTC (10:00 to 17:00 MYT), Monday to Friday.
--   4. `ops_notifications_push` opens My Work for `tasks.nudge` and tags it
--      `tasks-nudge`, so the next count replaces the last on a phone. It is
--      not sent on WhatsApp (`ops_notifications_wa` names its own kinds).
--
-- ORDER
--   Pages first (the bell opens My Work for the new kind; Settings draws the
--   row), then this file.
--
-- ROLLBACK
--   select cron.unschedule('tasks-nudge');
--   The function and the two settings rows may stay (nothing else reads
--   them); app_settings_set from PRIORITY DEADLINES and
--   ops_notifications_push from VIDEO SCRIPTS run again.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'task_remind_hours', date '2023-08-14', 3
 where not exists (select 1 from public.app_settings s where s.key = 'task_remind_hours');
insert into public.app_settings (key, from_date, value)
select 'task_start_days', date '2023-08-14', 2
 where not exists (select 1 from public.app_settings s where s.key = 'task_start_days');

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days'];
  v_moved text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k = 'meta_checks' and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v))) then
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
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input, a million tokens'
        when 'ai_price_out' then 'AI output, a million tokens' when 'ai_price_search' then 'AI web searches, a thousand' when 'meta_checks' then 'Meta checks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' else 'Report due' end;
      v_unit := case when v_k in ('lead_followup_hours', 'task_remind_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || case when v_k = 'meta_checks' then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k = 'meta_checks' then '' else case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_was, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end || ' → ' ||
              case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end ||
              ' · from ' || public.register_day(p_from) end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;

/* What of a colleague's own needs them, as one notice (see the head). */
create or replace function public.ops_tasks_nudge(p_at timestamptz default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_at    timestamptz := coalesce(p_at, now());
  v_local timestamp := coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur';
  v_today date := (coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur')::date;
  v_every integer;
  v_start integer;
  m record;
  v_title text;
  v_body text;
  v_parts text[];
  n integer := 0;
begin
  v_every := coalesce(public.app_setting('task_remind_hours', v_today), 3)::integer;
  v_start := coalesce(public.app_setting('task_start_days', v_today), 2)::integer;
  if v_every <= 0 or extract(isodow from v_today) > 5
     or extract(hour from v_local) < 10 or extract(hour from v_local) >= 18 then
    return 0;
  end if;
  for m in
    with floors as (
      select workflow_id, min(position) as at
        from public.ops_workflow_stages
       where stage_group = 'client_review'
       group by workflow_id
    ),
    pfloors as (
      select workflow_id,
             coalesce(min(position) filter (where stage_group = 'client_review'),
                      min(position) filter (where stage_group = 'internal_review')) as at
        from public.ops_workflow_stages
       group by workflow_id
    ),
    mine as (
      select a.team_member_id as member, k.id, a.assigned_at, k.priority_level,
             public.ops_serial(k.task_no) || ' · ' || public.ops_title(k) as label,
             coalesce(c.name, 'Internal') as client,
             s.stage_group, s.position, f.at as review_at, pf.at as prio_at,
             public.ops_priority_by(coalesce(k.priority_at, k.created_at), k.priority_level) as prio_by,
             (k.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date as due_day,
             (coalesce(k.current_first_draft_due_at, k.current_final_due_at) at time zone 'Asia/Kuala_Lumpur')::date as first_day
        from public.ops_task_assignees a
        join public.ops_tasks k on k.id = a.task_id
        join public.team_members tm on tm.id = a.team_member_id
        join public.ops_workflow_stages s on s.workflow_id = k.workflow_id and s.key = k.stage_key
        left join public.clients c on c.id = k.client_id
        left join floors f on f.workflow_id = k.workflow_id
        left join pfloors pf on pf.workflow_id = k.workflow_id
       where a.responsibility = 'owner' and a.ended_at is null
         and tm.active and not coalesce(tm.system, false)
         and k.completed_at is null and k.cancelled_at is null and k.archived_at is null
         and coalesce(s.stage_group, '') <> 'cancelled'
    ),
    sorted as (
      select x.*,
             (x.prio_by is not null and (x.prio_at is null or x.position < x.prio_at
                                         or x.stage_group in ('kiv', 'blocked'))) as prio_runs,
             (x.review_at is null or x.position < x.review_at) as short_of_review
        from mine x
    ),
    sized as (
      select y.*, case
        when (y.due_day < v_today and y.short_of_review) or (y.prio_runs and y.prio_by < v_at) then 1
        when y.prio_runs and y.priority_level = 1 then 2
        when (y.due_day = v_today and y.short_of_review)
          or (y.prio_runs and (y.prio_by at time zone 'Asia/Kuala_Lumpur')::date = v_today) then 3
        when v_start > 0 and y.stage_group in ('intake', 'ready')
          and ((y.first_day is not null and y.first_day <= v_today + v_start)
            or (y.first_day is null and y.assigned_at <= v_at - make_interval(days => v_start))) then 4
      end as bucket
        from sorted y
    )
    select z.member,
           count(*) as total,
           count(*) filter (where z.bucket = 1) as late,
           count(*) filter (where z.bucket = 2) as urgent,
           count(*) filter (where z.bucket = 3) as today,
           count(*) filter (where z.bucket = 4) as idle,
           (array_agg(z.id order by z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_id,
           (array_agg(z.bucket order by z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_bucket,
           (array_agg(z.client order by z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_client,
           (array_agg(z.prio_by order by z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_by,
           (array_agg(z.label order by z.bucket, coalesce(z.due_day, z.first_day), z.label))[1:3] as labels
      from sized z
     where z.bucket is not null
     group by z.member
     order by z.member
  loop
    if exists (select 1 from public.ops_notifications o
                where o.team_member_id = m.member and o.kind = 'tasks.nudge'
                  and o.created_at > v_at - make_interval(mins => v_every * 60 - 10)) then
      continue;
    end if;
    if m.total = 1 then
      v_title := m.labels[1] || case m.first_bucket when 1 then ' is overdue.' when 2 then ' is Urgent.'
                                                  when 3 then ' is due today.' else ' has not started.' end;
      v_body := m.first_client || case when m.first_bucket = 2 and m.first_by is not null then
        ' · deliver by ' || to_char(m.first_by at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam') || ', ' ||
        public.register_day((m.first_by at time zone 'Asia/Kuala_Lumpur')::date) || '.' else '' end;
    else
      v_parts := array_remove(array[
        case when m.late > 0 then m.late || ' overdue' end,
        case when m.urgent > 0 then m.urgent || ' Urgent' end,
        case when m.today > 0 then m.today || ' due today' end,
        case when m.idle > 0 then m.idle || ' not started' end], null);
      v_title := m.total || ' tasks need attention: ' || array_to_string(v_parts, ', ') || '.';
      v_body := array_to_string(m.labels, '; ') ||
                case when m.total > 3 then '; and ' || (m.total - 3) || ' more.' else '.' end;
    end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, created_at, dedupe_key)
    values (m.member, case when m.total = 1 then m.first_id end, 'tasks.nudge', v_title, v_body, v_at,
            'tasks.nudge.' || m.member || '.' || to_char(v_local, 'YYYY-MM-DD-HH24'))
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.ops_tasks_nudge(timestamptz) from public, anon, authenticated;

-- A count of what needs a colleague opens My Work.
create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.link is not null then new.link
         when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         when new.script_id is not null then '/admin/?s=scripts&script=' || new.script_id::text
         when new.kind in ('client_left', 'tasks.empty', 'tasks.nudge') then '/admin/?s=work'
         when new.kind = 'hr.letter' then '/admin/?s=mine&view=letters'
         when new.kind = 'perf.disputed' then '/admin/?s=team&tab=performance'
         when new.kind = 'perf.reflect' then '/admin/?s=mine&view=reflection'
         when new.kind = 'perf.initiative' then '/admin/?s=mine&view=initiatives'
         when new.kind like 'health.%' then '/admin/?s=mine&view=health'
         when new.kind like 'perf.%' then '/admin/?s=mine'
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         when new.script_id is not null then 'script-' || new.script_id::text
         when new.kind = 'hr.letter' then 'hr-letter'
         when new.kind in ('perf.remind', 'perf.reflect', 'health.remind') then 'my-hr'
         when new.kind = 'tasks.empty' then 'tasks-empty'
         when new.kind = 'tasks.nudge' then 'tasks-nudge'
         when new.kind = 'outstation' then 'outstation'
         else null end);
  return new;
exception when others then
  return new;
end $$;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: no task reminders go out until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'tasks-nudge';
  perform cron.schedule('tasks-nudge', '0 2-9 * * 1-5', 'select public.ops_tasks_nudge()');
end $$;

-- END OF TASK REMINDERS ------------------------------------------------------

select public.functions_tidy();
