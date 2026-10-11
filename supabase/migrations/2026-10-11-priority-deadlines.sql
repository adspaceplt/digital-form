-- 2026-10-11 · Priority deadlines: Urgent, High and Medium count down from creation.
-- Safe to run twice. Rollback is in the band's head.

-- ===========================================================================
-- PRIORITY DEADLINES — a priority is a deadline from the moment it is set:
-- Urgent within 24 hours, High within 48, Medium within 72; Normal has none
-- (the user, 2026-10-11).
-- 2026-10-11. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after REACH ALLOWANCE, whose settings it keeps.
--
-- WHAT CHANGED
--   1. Low is retired: on the first run alone, every task at Low (4, or the
--      older 5) becomes Normal (3). Medium then takes 4, which the task
--      functions already accept (1 to 4); Urgent 1, High 2 and Normal 3 keep
--      their keys. The first run is known by the settings below not yet being
--      there, so a second run never turns a Medium task back to Normal.
--   2. `priority_urgent_hours` (24), `priority_high_hours` (48) and
--      `priority_medium_hours` (72) are Business settings, whole hours from 1
--      to 720, from a day on. `app_settings_set` takes them, filed
--      "High deadline: 48 hours → 36 hours · from …".
--   3. `ops_tasks.priority_at` is when the priority was last set, stamped by
--      trigger `ops_tasks_priority_at` (on creation, and on every change of
--      level; a task from before takes its creation). The deadline counts
--      from it (a task made Normal on the 1st, due the 29th, raised to High on
--      the 12th at 9am, is owed by the 14th at 9am) and is never written: the
--      due date is never changed, and the count stops once the task reaches
--      client review (an everyday task's Review). `ops_priority_by(set at,
--      level)` gives the moment it falls.
--   4. A task is late by whichever deadline comes first (the user,
--      2026-10-11): `ops_report` counts a task past its priority's deadline
--      and short of its review as late beside the due date's rule (the late
--      list with `over_minutes`, open work by person), and on time only
--      where it met both (on time delivery, by person).
--
-- ROLLBACK
--   Run app_settings_set from REACH ALLOWANCE and ops_report from its own
--   latest section again; ops_priority_by, the column priority_at and its
--   trigger may stay (nothing else reads them); the three settings rows may
--   stay. A task made Medium reads as Low on a page from before; tasks
--   that were Low stay Normal (none were Low on 2026-10-11).
-- ===========================================================================

alter table public.ops_tasks add column if not exists priority_at timestamptz;
update public.ops_tasks set priority_at = created_at where priority_at is null;

do $$
begin
  if not exists (select 1 from public.app_settings s where s.key = 'priority_medium_hours') then
    update public.ops_tasks set priority_level = 3 where priority_level in (4, 5);
  end if;
end $$;

insert into public.app_settings (key, from_date, value)
select 'priority_urgent_hours', date '2023-08-14', 24
 where not exists (select 1 from public.app_settings s where s.key = 'priority_urgent_hours');
insert into public.app_settings (key, from_date, value)
select 'priority_high_hours', date '2023-08-14', 48
 where not exists (select 1 from public.app_settings s where s.key = 'priority_high_hours');
insert into public.app_settings (key, from_date, value)
select 'priority_medium_hours', date '2023-08-14', 72
 where not exists (select 1 from public.app_settings s where s.key = 'priority_medium_hours');

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours'];
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
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v))) then
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
        when 'priority_medium_hours' then 'Medium deadline' else 'Report due' end;
      v_unit := case when v_k = 'lead_followup_hours' or v_k like 'priority_%_hours' then ' hours' when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days') then ' days'
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


/* When the priority was set: on creation, and again on every change of
   level, by the database's clock. */
create or replace function public.ops_tasks_priority_at()
returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.priority_at := coalesce(new.priority_at, new.created_at, now());
  elsif new.priority_level is distinct from old.priority_level then
    new.priority_at := now();
  end if;
  return new;
end $$;
revoke all on function public.ops_tasks_priority_at() from public, anon, authenticated;

create or replace trigger ops_tasks_priority_at
  before insert or update of priority_level on public.ops_tasks
  for each row execute function public.ops_tasks_priority_at();

/* The moment a priority's deadline falls: when it was set plus the hours
   its level held on that day (Malaysia time); null for Normal. The report's
   late and on time read it; the page works out the same (js/ops.js
   `deadlineOf`). */
create or replace function public.ops_priority_by(p_set timestamptz, p_level smallint)
returns timestamptz
language sql stable security definer set search_path = public as $$
  select p_set + make_interval(hours => coalesce(public.app_setting(
           'priority_' || case p_level when 1 then 'urgent' when 2 then 'high' else 'medium' end || '_hours',
           (p_set at time zone 'Asia/Kuala_Lumpur')::date),
           case p_level when 1 then 24 when 2 then 48 else 72 end)::integer)
   where p_level in (1, 2, 4) and p_set is not null
$$;
revoke all on function public.ops_priority_by(timestamptz, smallint) from public, anon, authenticated;

create or replace function public.ops_report(
  p_from timestamptz default (now() - interval '90 days'),
  p_to   timestamptz default now())
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  out jsonb;
begin
  if not public.ops_granted('ops.reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;

  with
  /* Where client review begins in each workflow. The final due date is the
     day the work is owed AT that stage, so everything below that position is
     "has not reached the client yet". Read from `stage_group` and never from
     a stage key: the two seeded workflows name that stage differently. */
  floors as (
    select workflow_id, min(position) as at
      from public.ops_workflow_stages
     where stage_group = 'client_review'
     group by workflow_id
  ),
  /* Where a priority's deadline is met (2026-10-11): client review, else the
     workflow's first review (an everyday task's Review). */
  pfloors as (
    select workflow_id,
           coalesce(min(position) filter (where stage_group = 'client_review'),
                    min(position) filter (where stage_group = 'internal_review')) as at
      from public.ops_workflow_stages
     group by workflow_id
  ),
  live as (
    select t.*, s.label as stage_label, s.position as stage_position,
           s.stage_group, f.at as review_at,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by, pf.at as prio_at
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.workflow_id = t.workflow_id and s.key = t.stage_key
      left join floors f on f.workflow_id = t.workflow_id
      left join pfloors pf on pf.workflow_id = t.workflow_id
     where t.completed_at is null and t.cancelled_at is null
       and t.archived_at is null
  ),

  /* 1. WHAT IS RUNNING, by the words on the screen. Grouped by the stage's
        own label rather than by its group, because "what is on shooting" is
        the question and Shooting is a label, not a group. */
  running as (
    select jsonb_agg(x order by x ->> 'position', x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key, 'label', stage_label,
               'position', stage_position, 'stage_group', stage_group,
               'count', count(*)) as x
        from live
       group by stage_key, stage_label, stage_position, stage_group
    ) q
  ),

  /* 2. WHAT IS LATE. Past the commitment and still short of client review,
        or past a priority's deadline and short of its review (On hold and
        Blocked still count): whichever comes first (the user, 2026-10-11).
        The same rule the queue row draws, stated once more here because a
        report a page computes for itself is a second definition. */
  late_now as (
    select l.*,
           (l.current_final_due_at is not null and l.current_final_due_at::date < current_date
            and (l.review_at is null or l.stage_position < l.review_at)) as due_late,
           (l.prio_by is not null and l.prio_by < now()
            and (l.prio_at is null or l.stage_position < l.prio_at or l.stage_group in ('kiv', 'blocked'))) as prio_late
      from live l
  ),
  late as (
    select jsonb_agg(x order by x ->> 'due_at') as j from (
      select jsonb_build_object(
               'task_id', l.id, 'task_no', l.task_no, 'title', l.title,
               'client', c.name, 'stage', l.stage_label,
               'due_at', case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                              then l.prio_by else l.current_final_due_at end,
               'days_over', greatest(case when l.due_late then current_date - l.current_final_due_at::date end,
                                     case when l.prio_late then floor(extract(epoch from (now() - l.prio_by)) / 86400)::int end),
               'over_minutes', case when l.prio_late then floor(extract(epoch from (now() - l.prio_by)) / 60)::int end,
               'owner', (select tm.name
                           from public.ops_task_assignees a
                           join public.team_members tm on tm.id = a.team_member_id
                          where a.task_id = l.id and a.responsibility = 'owner'
                            and a.ended_at is null
                          limit 1)) as x
        from late_now l
        left join public.clients c on c.id = l.client_id
       where l.due_late or l.prio_late
    ) q
  ),

  /* 3. HOW LONG EACH STAGE TAKES. A task enters a stage at the event that
        names it and leaves at the next event, or at its own ending, or now.
        Only spans that were ENTERED inside the period are counted, so the
        window means what it says and a task that sat in Editing since March
        does not land in every report for ever. */
  spans as (
    select e.task_id,
           e.to_value ->> 'stage_key' as stage_key,
           e.created_at as from_at,
           coalesce(
             lead(e.created_at) over (partition by e.task_id order by e.created_at),
             t.completed_at, t.cancelled_at, now()) as to_at
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
     where e.event_type in ('task_created', 'stage_changed')
       and e.to_value ->> 'stage_key' is not null
  ),
  /* One row per span and no grouping: an earlier draft grouped by the span's
     own timestamps, which silently collapsed two tasks that entered the same
     stage in the same instant into one measurement. The label is looked up
     once per stage below instead of aggregated here. */
  span_mins as (
    select s.stage_key,
           extract(epoch from (s.to_at - s.from_at)) / 60 as mins
      from spans s
     where s.from_at >= p_from and s.from_at < p_to
       and s.to_at > s.from_at
  ),
  stage_time as (
    select jsonb_agg(x order by x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key,
               'label', coalesce((select w.label from public.ops_workflow_stages w
                                   where w.key = sm.stage_key limit 1), stage_key),
               'n', count(*),
               'median_minutes', round(percentile_cont(0.5) within group (order by mins))::int,
               'p90_minutes', round(percentile_cont(0.9) within group (order by mins))::int) as x
        from span_mins sm
       group by stage_key
    ) q
  ),

  /* 4. WAS IT THERE ON TIME. Of the tasks that reached client review inside
        the period, how many got there on or before the date they were owed.
        Replanning is counted beside it and never folded into it: an extension
        that moves the date would otherwise erase the miss it was granted for,
        and a rate that cannot be missed is not a measurement. */
  reached as (
    select distinct on (e.task_id)
           e.task_id, e.created_at as at, t.current_final_due_at as due,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
           (t.original_final_due_at is distinct from t.current_final_due_at) as replanned
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
      join public.ops_workflow_stages w
        on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
     where e.event_type = 'stage_changed'
       and w.stage_group = 'client_review'
       and e.created_at >= p_from and e.created_at < p_to
     order by e.task_id, e.created_at
  ),
  on_time as (
    select jsonb_build_object(
             'reached', count(*),
             'met', count(*) filter (where (due is null or at::date <= due::date) and (prio_by is null or at <= prio_by)),
             'missed', count(*) filter (where not ((due is null or at::date <= due::date) and (prio_by is null or at <= prio_by))),
             'replanned', count(*) filter (where replanned)) as j
      from reached
  ),

  /* 5. BY PERSON. The foundation of a KPI and not a KPI: what somebody
        finished in the window, how much of it was on time, and how long their
        work took end to end. No ranking and no score — a number a person can
        check is worth more than a league table nobody trusts. */
  done as (
    select t.id, t.created_at, coalesce(t.completed_at, t.delivered_at) as ended,
           t.current_final_due_at as due,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
           /* When a priority's deadline was met: the first move into its
              review or beyond (never On hold, Blocked or Cancelled). */
           (select min(e.created_at)
              from public.ops_task_events e
              join public.ops_workflow_stages w
                on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
              join pfloors pf on pf.workflow_id = t.workflow_id
             where e.task_id = t.id and e.event_type = 'stage_changed'
               and w.position >= pf.at and w.stage_group not in ('kiv', 'blocked', 'cancelled')) as met_at,
           (select a.team_member_id
              from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc
             limit 1) as owner_id
      from public.ops_tasks t
     where t.completed_at is not null
       and t.completed_at >= p_from and t.completed_at < p_to
  ),
  by_person as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', d.owner_id,
               'name', coalesce(tm.name, 'Nobody'),
               'completed', count(*),
               'on_time', count(*) filter (where (d.due is null or d.ended::date <= d.due::date)
                                         and (d.prio_by is null or coalesce(d.met_at, d.ended) <= d.prio_by)),
               'median_cycle_minutes',
                 round(percentile_cont(0.5) within group (
                   order by extract(epoch from (d.ended - d.created_at)) / 60))::int) as x
        from done d
        left join public.team_members tm on tm.id = d.owner_id
       group by d.owner_id, tm.name
    ) q
  ),

  /* 6. WHO IS CARRYING THE OPEN WORK (2026-09-28). One row a Task Owner:
        the open tasks they hold, and how many of those are late by the rule
        in 2 above. The team's whole queue is `ops.all`, so it is answered
        only where that part is granted. */
  open_by_person as (
    select jsonb_agg(x order by (x ->> 'open')::int desc, x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', o.owner_id,
               'name', coalesce(tm.name, 'No task owner'),
               'open', count(*),
               'late', count(*) filter (where o.is_late)) as x
        from (select l.id,
                     (select a.team_member_id
                        from public.ops_task_assignees a
                       where a.task_id = l.id and a.responsibility = 'owner' and a.ended_at is null
                       limit 1) as owner_id,
                     (l.due_late or l.prio_late) as is_late
                from late_now l) o
        left join public.team_members tm on tm.id = o.owner_id
       where public.ops_granted('ops.all', 'view')
       group by o.owner_id, tm.name
    ) q
  )

  select jsonb_build_object(
           'from', p_from, 'to', p_to,
           'running',    coalesce((select j from running), '[]'::jsonb),
           'late',       coalesce((select j from late), '[]'::jsonb),
           'stage_time', coalesce((select j from stage_time), '[]'::jsonb),
           'on_time',    coalesce((select j from on_time), '{}'::jsonb),
           'by_person',  coalesce((select j from by_person), '[]'::jsonb),
           'open_by_person', case when public.ops_granted('ops.all', 'view')
                                  then coalesce((select j from open_by_person), '[]'::jsonb) end)
    into out;

  return out;
end $$;
grant execute on function public.ops_report(timestamptz, timestamptz) to authenticated;

-- END OF PRIORITY DEADLINES -------------------------------------------------

select public.functions_tidy();
