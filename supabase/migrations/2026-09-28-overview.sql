-- ===========================================================================
-- THE OVERVIEW — the start page for a group that manages a section reads
-- what each section has waiting.
-- 2026-09-28. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `batches.published_at`: when a content set was last published,
--      stamped by a trigger on the move to published and cleared on
--      Unpublish, so "waiting on the client for N days" is a fact and not a
--      guess. Sets already published take the time their last post was
--      added (the nearest thing to a publish date they hold).
--   2. `ops_report` answers `open_by_person` (each Task Owner's open tasks
--      and how many are late) where `ops.all` is granted, so the Report and
--      the Overview count the open work one way. Nothing else in it moves.
--   3. `perf_overview(p_period)`: for a month, each person on the review
--      list and the step their review has reached. Names and steps only,
--      never a score, a grade or a word of a dispute; `team.performance` at
--      View, as the Activity record's Performance tab.
--   Nothing here is money: the Overview shows no revenue, value or fee.
--
-- ROLLBACK
--   drop trigger if exists batches_published_at on public.batches;
--   drop function if exists public.batches_published_at();
--   alter table public.batches drop column if exists published_at;
--   drop function if exists public.perf_overview(date);
--   Re-run ops_report from THE OPERATIONS REPORT.
-- ===========================================================================

alter table public.batches add column if not exists published_at timestamptz;

create or replace function public.batches_published_at()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.published and (tg_op = 'INSERT' or not coalesce(old.published, false)) then
    new.published_at := now();
  elsif not new.published then
    new.published_at := null;
  end if;
  return new;
end $$;
revoke all on function public.batches_published_at() from public, anon, authenticated;
drop trigger if exists batches_published_at on public.batches;
create trigger batches_published_at before insert or update of published on public.batches
  for each row execute function public.batches_published_at();

update public.batches b
   set published_at = coalesce((select max(p.created_at) from public.posts p where p.batch_id = b.id), b.created_at)
 where b.published and b.published_at is null;

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
  live as (
    select t.*, s.label as stage_label, s.position as stage_position,
           s.stage_group, f.at as review_at
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.workflow_id = t.workflow_id and s.key = t.stage_key
      left join floors f on f.workflow_id = t.workflow_id
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

  /* 2. WHAT IS LATE. Past the commitment and still short of client review.
        The same rule the queue row draws, stated once more here because a
        report a page computes for itself is a second definition. */
  late as (
    select jsonb_agg(x order by x ->> 'due_at') as j from (
      select jsonb_build_object(
               'task_id', l.id, 'task_no', l.task_no, 'title', l.title,
               'client', c.name, 'stage', l.stage_label,
               'due_at', l.current_final_due_at,
               'days_over', (current_date - l.current_final_due_at::date),
               'owner', (select tm.name
                           from public.ops_task_assignees a
                           join public.team_members tm on tm.id = a.team_member_id
                          where a.task_id = l.id and a.responsibility = 'owner'
                            and a.ended_at is null
                          limit 1)) as x
        from live l
        left join public.clients c on c.id = l.client_id
       where l.current_final_due_at is not null
         and l.current_final_due_at::date < current_date
         and (l.review_at is null or l.stage_position < l.review_at)
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
             'met', count(*) filter (where due is null or at::date <= due::date),
             'missed', count(*) filter (where due is not null and at::date > due::date),
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
               'on_time', count(*) filter (where d.due is null or d.ended::date <= d.due::date),
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
                     (l.current_final_due_at is not null
                      and l.current_final_due_at::date < current_date
                      and (l.review_at is null or l.stage_position < l.review_at)) as is_late
                from live l) o
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

create or replace function public.perf_overview(p_period date)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare me_row public.team_members; m date;
begin
  me_row := public.ops_me();
  if me_row.id is null or not public.ops_granted('team.performance', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  m := date_trunc('month', coalesce(p_period, current_date))::date;
  return jsonb_build_object('period', m, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('team_member_id', t.id, 'name', t.name,
             'status', coalesce(r.status, 'none')) order by t.name)
      from public.team_members t
      left join public.perf_reviews r on r.team_member_id = t.id and r.period = m
     where t.id is distinct from me_row.id
       and ((t.active and public.perf_reviewed(t.id)) or r.id is not null)), '[]'::jsonb));
end $$;
revoke all on function public.perf_overview(date) from public, anon, authenticated;
grant execute on function public.perf_overview(date) to authenticated;

-- END OF THE OVERVIEW -------------------------------------------------------
