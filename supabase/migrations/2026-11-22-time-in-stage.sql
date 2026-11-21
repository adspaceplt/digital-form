-- ===========================================================================
-- TIME IN STAGE (2026-11-22)
-- ===========================================================================
-- WHY: the user approved the team view of the stage timeline proposal on
-- 2026-11-22, shown at once from the moves already held (since mid-October),
-- as a view of Analytics' Where work waits card (Median time · Time in
-- stage). The card's own view reads `ops_report`'s stage spans, which count
-- a stage left within minutes (a colleague catching the card up: 36% of live
-- visits) and the stage a task stands on now; this one reads closed stays
-- only and leaves those out, as the task card's timeline does.
--
-- WHAT IT CHANGES
--   * `ops_stage_times(p_from, p_to)` (security definer, stable; My Work:
--     Reports at View, `ops_granted('ops.reports', 'view')`, else
--     `denied`): every stay in a stage that ended in the period, from the
--     move into it (the task's making for its first stage) to the move out,
--     5 minutes or more, a task the caller's client scope reaches
--     (`ops_task_in_scope`). Credited to whoever held the task as the stay
--     began. Answers `stages` (each workflow's stage with its label,
--     position, stage group, stays, tasks and median minutes), `people`
--     (each colleague's stays and median a `workflow|stage`, and their tasks) and
--     `tasks` (how many tasks in all). Calendar time. Nothing is stored.
--
-- ORDER: this file, then the pages. A page served before it never asks; a
-- new page meeting a database without it reads the view's refusal and draws
-- its Try again on that view alone. Safe to run twice.
--
-- ROLLBACK: drop function public.ops_stage_times(timestamptz, timestamptz);
-- ===========================================================================

create or replace function public.ops_stage_times(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  out jsonb;
begin
  if not public.ops_granted('ops.reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;

  with moves as (
    select e.task_id, e.created_at,
           e.from_value ->> 'stage_key' as from_key,
           e.to_value ->> 'stage_key' as to_key,
           row_number() over (partition by e.task_id order by e.created_at, e.id) as rn
      from public.ops_task_events e
     where e.event_type = 'stage_changed'
       and e.to_value ->> 'stage_key' is not null
  ),
  stays as (
    /* A move opens a stay in the stage it led into; the next move closes it. */
    select m.task_id, m.to_key as stage_key, m.created_at as from_at,
           lead(m.created_at) over (partition by m.task_id order by m.created_at, m.rn) as to_at
      from moves m
    union all
    /* The first stage, from the task's making to its first move. */
    select m.task_id, m.from_key, t.created_at, m.created_at
      from moves m
      join public.ops_tasks t on t.id = m.task_id
     where m.rn = 1 and m.from_key is not null and m.created_at > t.created_at
  ),
  kept as (
    select s.task_id, s.stage_key, s.from_at,
           extract(epoch from (s.to_at - s.from_at)) / 60 as mins,
           t.workflow_id, wf.key as wf_key,
           coalesce(
             (select a.team_member_id from public.ops_task_assignees a
               where a.task_id = s.task_id and a.responsibility = 'owner'
                 and a.assigned_at <= s.from_at and (a.ended_at is null or a.ended_at > s.from_at)
               order by a.assigned_at desc limit 1),
             (select a.team_member_id from public.ops_task_assignees a
               where a.task_id = s.task_id and a.responsibility = 'owner'
               order by a.assigned_at limit 1)) as owner_id
      from stays s
      join public.ops_tasks t on t.id = s.task_id
      join public.ops_workflows wf on wf.id = t.workflow_id
     where s.to_at is not null
       and s.to_at >= p_from and s.to_at < p_to
       and s.to_at - s.from_at >= interval '5 minutes'
       and public.ops_task_in_scope(s.task_id)
  ),
  stages as (
    select jsonb_agg(x order by x ->> 'workflow', (x ->> 'position')::int) as j from (
      select jsonb_build_object(
               'workflow', k.wf_key,
               'stage_key', k.stage_key,
               'label', coalesce(min(w.label), k.stage_key),
               'position', coalesce(min(w.position), 999),
               'stage_group', min(w.stage_group),
               'n', count(*),
               'tasks', count(distinct k.task_id),
               'median_minutes', round(percentile_cont(0.5) within group (order by k.mins))::int) as x
        from kept k
        left join public.ops_workflow_stages w on w.workflow_id = k.workflow_id and w.key = k.stage_key
       group by k.wf_key, k.stage_key
    ) q
  ),
  people as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'id', k.owner_id,
               'name', coalesce(tm.name, ''),
               'tasks', (select count(distinct k2.task_id) from kept k2 where k2.owner_id is not distinct from k.owner_id),
               'stages', jsonb_object_agg(k.wf_key || '|' || k.stage_key, jsonb_build_object(
                  'n', k.n, 'median_minutes', k.med))) as x
        from (select owner_id, wf_key, stage_key, count(*) as n,
                     round(percentile_cont(0.5) within group (order by mins))::int as med
                from kept group by owner_id, wf_key, stage_key) k
        left join public.team_members tm on tm.id = k.owner_id
       group by k.owner_id, tm.name
    ) q
  )
  select jsonb_build_object(
           'stages', coalesce((select j from stages), '[]'::jsonb),
           'people', coalesce((select j from people), '[]'::jsonb),
           'tasks', (select count(distinct task_id) from kept))
    into out;
  return out;
end $$;
revoke all on function public.ops_stage_times(timestamptz, timestamptz) from public, anon;
grant execute on function public.ops_stage_times(timestamptz, timestamptz) to authenticated;

-- END OF TIME IN STAGE -----------------------------------------------------

select public.functions_tidy();
