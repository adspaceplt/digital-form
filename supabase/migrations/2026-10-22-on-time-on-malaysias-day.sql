-- ===========================================================================
-- ON TIME ON MALAYSIA'S DAY — the Dashboard's on-time figures read the day a
-- task reached client review in Malaysia, per person too, and the six
-- months' line reads only what it draws. 2026-10-22. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/ops.js compares the two.
--
-- WHAT CHANGED (the review of 2026-10-22, OVW-1, OVW-2, OVW-11)
--   * On time: a task reaching client review is on time where the Malaysian
--     day it got there is not after its due date's Malaysian day. The casts
--     read UTC's day: a task reaching review at 07:00 the morning after its
--     due date counted as on time while the queue called it late (OVW-1).
--   * On time by person: a finished task is on time where it reached client
--     review by its due date (else its review, else its finish), as the ring
--     above it reads the same work; it had compared the day the task was
--     finished, a week after it went live, so nearly every content task read
--     late (OVW-2). A priority's deadline reads as before.
--   * ops_report's body is ops_report_of(p_from, p_to, p_light); ops_report
--     answers it whole, and ops_reports answers the third span on (the six
--     months' line) light: on_time, posted and by_person, with what is
--     running, late, each stage's time and the open work left empty, so the
--     whole open queue is read for the two spans that show it (OVW-11).
--
-- ORDER: this file, then the pages (an old page reads the same answers).
--
-- ROLLBACK
--   Run ops_report from POSTED ON TIME and ops_reports from OPS REPORTS AT
--   ONCE again; ops_report_of is then unused and may stay.
-- ===========================================================================

create or replace function public.ops_report_of(
  p_from  timestamptz,
  p_to    timestamptz,
  p_light boolean)
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
       /* Client scope: a colleague on Own clients only reads the work of
          the clients they hold, and their own tasks always (2026-10-18). */
       and public.ops_task_in_scope(t.id)
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
       where not p_light
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
           (l.current_final_due_at is not null and (l.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date
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
               'days_over', greatest(case when l.due_late then (now() at time zone 'Asia/Kuala_Lumpur')::date - (l.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date end,
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
       where (l.due_late or l.prio_late) and not p_light
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
       and public.ops_task_in_scope(t.id)
       /* Only a span entered in the period is counted, and its end is the
          task's next event, never an earlier one: what came before the
          period is not read (2026-10-18). */
       and e.created_at >= p_from
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
       where not p_light
       group by stage_key
    ) q
  ),

  /* 4. WAS IT THERE ON TIME. Of the tasks that reached client review inside
        the period, how many got there on or before the date they were owed;
        the work still late is counted beside them (`late_open`).
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
       and public.ops_task_in_scope(t.id)
       and e.created_at >= p_from and e.created_at < p_to
     order by e.task_id, e.created_at
  ),
  /* Work still short of its review and past its deadline is a miss too
     (2026-10-19, the user: "there are late tasks yet showing 100% on time
     delivery"): counted in the period its first missed deadline fell in,
     and in any period that runs to now (its end within ten minutes of now:
     the page names the moment it asks), where it is still late. A task
     counted as reached in the period is not counted again. */
  late_open as (
    select l.id
      from late_now l
     where (l.due_late or l.prio_late)
       and not exists (select 1 from reached r where r.task_id = l.id)
       and (case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                 then l.prio_by else l.current_final_due_at end) < p_to
       and ((case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                  then l.prio_by else l.current_final_due_at end) >= p_from
            or p_to >= now() - interval '10 minutes')
  ),
  on_time as (
    select jsonb_build_object(
             'reached', count(*),
             'met', count(*) filter (where (due is null or (at at time zone 'Asia/Kuala_Lumpur')::date <= (due at time zone 'Asia/Kuala_Lumpur')::date)
                                       and (prio_by is null or at <= prio_by)),
             'missed', count(*) filter (where not ((due is null or (at at time zone 'Asia/Kuala_Lumpur')::date <= (due at time zone 'Asia/Kuala_Lumpur')::date)
                                                 and (prio_by is null or at <= prio_by))),
             'late_open', (select count(*) from late_open),
             'replanned', count(*) filter (where replanned)) as j
      from reached
  ),
  /* 4b. POSTED ON TIME (2026-10-19). Of the content whose post date fell in
         the period and has passed (Malaysia's day), or which went live, how
         much went live by its post date. Client approval counts here, as it
         does for the client; on-time delivery above is the team's own. */
  posted as (
    select jsonb_build_object(
             'due', count(*),
             'met', count(*) filter (where t.live_at is not null
                                       and (t.live_at at time zone 'Asia/Kuala_Lumpur')::date
                                           <= (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date)) as j
      from public.ops_tasks t
     where t.publish_at >= p_from and t.publish_at < p_to
       and t.cancelled_at is null and t.archived_at is null
       and (t.live_at is not null
            or (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date)
       and exists (select 1 from public.ops_workflow_stages s
                    where s.workflow_id = t.workflow_id and s.stage_group = 'live')
       and public.ops_task_in_scope(t.id)
  ),

  /* 5. BY PERSON. The foundation of a KPI and not a KPI: what somebody
        finished in the window, how much of it was on time, and how long their
        work took end to end. No ranking and no score — a number a person can
        check is worth more than a league table nobody trusts. */
  done as (
    select t.id, t.created_at, t.completed_at as ended,
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
           /* When it reached client review (2026-10-22, OVW-2): the day the
              due date is owed at, as the on-time ring reads it. */
           (select min(e.created_at)
              from public.ops_task_events e
              join public.ops_workflow_stages w
                on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
             where e.task_id = t.id and e.event_type = 'stage_changed'
               and w.stage_group = 'client_review') as review_at,
           (select a.team_member_id
              from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc
             limit 1) as owner_id
      from public.ops_tasks t
     where t.completed_at is not null
       and t.completed_at >= p_from and t.completed_at < p_to
       and public.ops_task_in_scope(t.id)
  ),
  by_person as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', d.owner_id,
               'name', coalesce(tm.name, 'Nobody'),
               'completed', count(*),
               'on_time', count(*) filter (where (d.due is null
                                                 or (coalesce(d.review_at, d.met_at, d.ended) at time zone 'Asia/Kuala_Lumpur')::date
                                                    <= (d.due at time zone 'Asia/Kuala_Lumpur')::date)
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
       where public.ops_granted('ops.all', 'view') and not p_light
       group by o.owner_id, tm.name
    ) q
  )

  select jsonb_build_object(
           'from', p_from, 'to', p_to,
           'running',    coalesce((select j from running), '[]'::jsonb),
           'late',       coalesce((select j from late), '[]'::jsonb),
           'stage_time', coalesce((select j from stage_time), '[]'::jsonb),
           'on_time',    coalesce((select j from on_time), '{}'::jsonb),
           'posted',     coalesce((select j from posted), '{}'::jsonb),
           'by_person',  coalesce((select j from by_person), '[]'::jsonb),
           'open_by_person', case when public.ops_granted('ops.all', 'view')
                                  then coalesce((select j from open_by_person), '[]'::jsonb) end)
    into out;

  return out;
end $$;

revoke all on function public.ops_report_of(timestamptz, timestamptz, boolean) from public, anon;
grant execute on function public.ops_report_of(timestamptz, timestamptz, boolean) to authenticated;

create or replace function public.ops_report(
  p_from timestamptz default (now() - interval '90 days'),
  p_to   timestamptz default now())
returns jsonb
language sql stable security invoker set search_path = public as $$
  select public.ops_report_of(p_from, p_to, false)
$$;
grant execute on function public.ops_report(timestamptz, timestamptz) to authenticated;

/* The period and the one before it whole; each span after them (the six
   months' line) light. */
create or replace function public.ops_reports(p_ranges jsonb)
returns jsonb
language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(public.ops_report_of((x.r ->> 'from')::timestamptz, (x.r ->> 'to')::timestamptz, x.n > 2) order by x.n), '[]'::jsonb)
    from jsonb_array_elements(case when jsonb_typeof(p_ranges) = 'array' then p_ranges else '[]'::jsonb end)
         with ordinality x(r, n)
   where x.n <= 12
$$;
revoke all on function public.ops_reports(jsonb) from public, anon;
grant execute on function public.ops_reports(jsonb) to authenticated;

-- END OF ON TIME ON MALAYSIA'S DAY -------------------------------------------
select public.functions_tidy();
