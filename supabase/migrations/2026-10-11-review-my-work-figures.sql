-- 2026-10-11 · The review's My Work figures: on-time posting and timeline adherence.
-- Safe to run twice. Rollback is in the band's head.

-- ===========================================================================
-- THE REVIEW'S MY WORK FIGURES — what My Work already knows, beside the two
-- delivery rates a reviewer types (the user, 2026-10-11: "add timeline
-- adherence next").
-- 2026-10-11. Safe to run twice. Rollback below. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two. Runs after PRIORITY DEADLINES, whose `ops_priority_by` it reads.
--
-- WHAT CHANGED
--   `perf_ops_rate(member, month)` answers two figures, each a hint beside
--   its rate and never a score:
--   1. posting (On-time posting): the content tasks the colleague owns whose
--      post date fell in the month, MYT, and has passed (or that went live),
--      and how many went live by their post date's day; a cancelled task is
--      left out. Before, this rate's hint counted tasks finished by their due
--      date, which is the timeline's question.
--   2. timeline (Timeline adherence): the tasks the colleague owns that
--      reached their review in the month, MYT, and how many got there by
--      their deadline, whichever came first (the rule My Work's late reads):
--      the due date's day at client review (an everyday task's at its
--      finish) and a priority's deadline at its review.
--   It answers `{posting: {due, on_time}, timeline: {reached, met}}` in
--   place of `{done, on_time}`: a page from before finds no `done` and draws
--   no hint, and this page finds no `posting` on a database from before and
--   draws none.
--
-- ROLLBACK
--   Run perf_ops_rate from PRIORITY DEADLINES again.
-- ===========================================================================

/* The review's My Work figures (2026-10-11). Who owns a task is its owner of
   record (the open assignment, else the last), as the hint read before. */
create or replace function public.perf_ops_rate(p_member uuid, p_period date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m_from timestamptz := (date_trunc('month', p_period)::date)::timestamp at time zone 'Asia/Kuala_Lumpur';
  m_to   timestamptz := ((date_trunc('month', p_period) + interval '1 month')::date)::timestamp at time zone 'Asia/Kuala_Lumpur';
  today  date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  p_due integer; p_ok integer; t_reached integer; t_met integer;
begin
  if to_regclass('public.ops_tasks') is null then return null; end if;

  select count(*),
         count(*) filter (where t.live_at is not null
                            and (t.live_at at time zone 'Asia/Kuala_Lumpur')::date
                                <= (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date)
    into p_due, p_ok
    from public.ops_tasks t
   where t.publish_at >= m_from and t.publish_at < m_to
     and t.cancelled_at is null
     and (t.live_at is not null or (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date < today)
     and exists (select 1 from public.ops_workflow_stages s
                  where s.workflow_id = t.workflow_id and s.stage_group = 'live')
     and (select a.team_member_id from public.ops_task_assignees a
           where a.task_id = t.id and a.responsibility = 'owner'
           order by a.ended_at nulls first, a.assigned_at desc limit 1) = p_member;

  with owned as (
    select t.id, t.workflow_id, t.current_final_due_at as due,
           coalesce(t.completed_at, t.delivered_at) as ended,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
           (select min(s.position) from public.ops_workflow_stages s
             where s.workflow_id = t.workflow_id and s.stage_group = 'client_review') as review_at,
           (select min(s.position) from public.ops_workflow_stages s
             where s.workflow_id = t.workflow_id and s.stage_group = 'internal_review') as first_review_at
      from public.ops_tasks t
     where t.cancelled_at is null
       and (t.current_final_due_at is not null or t.priority_level in (1, 2, 4))
       and (select a.team_member_id from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc limit 1) = p_member
  ),
  /* When each deadline was met: the first move to its stage or beyond, never
     into On hold, Blocked or Cancelled. The due date's is client review, else
     the finish; a priority's is client review, else the first review. */
  marks as (
    select o.*,
           case when o.review_at is null then o.ended
                else coalesce((select min(e.created_at)
                                 from public.ops_task_events e
                                 join public.ops_workflow_stages w
                                   on w.workflow_id = o.workflow_id and w.key = e.to_value ->> 'stage_key'
                                where e.task_id = o.id and e.event_type = 'stage_changed'
                                  and w.position >= o.review_at
                                  and w.stage_group not in ('kiv', 'blocked', 'cancelled')), o.ended) end as due_met,
           coalesce((select min(e.created_at)
                       from public.ops_task_events e
                       join public.ops_workflow_stages w
                         on w.workflow_id = o.workflow_id and w.key = e.to_value ->> 'stage_key'
                      where e.task_id = o.id and e.event_type = 'stage_changed'
                        and w.position >= coalesce(o.review_at, o.first_review_at)
                        and w.stage_group not in ('kiv', 'blocked', 'cancelled')), o.ended) as prio_met
      from owned o
  ),
  /* A task is counted in the month it met the last of its deadlines. */
  settled as (
    select m.*,
           case when (m.due is null or m.due_met is not null)
                 and (m.prio_by is null or m.prio_met is not null)
                then greatest(case when m.due is not null then m.due_met end,
                              case when m.prio_by is not null then m.prio_met end) end as at
      from marks m
  )
  select count(*),
         count(*) filter (where (s.due is null
                                 or (s.due_met at time zone 'Asia/Kuala_Lumpur')::date
                                    <= (s.due at time zone 'Asia/Kuala_Lumpur')::date)
                            and (s.prio_by is null or s.prio_met <= s.prio_by))
    into t_reached, t_met
    from settled s
   where s.at >= m_from and s.at < m_to;

  return jsonb_build_object(
    'posting',  jsonb_build_object('due', p_due, 'on_time', p_ok),
    'timeline', jsonb_build_object('reached', t_reached, 'met', t_met));
end $$;
revoke all on function public.perf_ops_rate(uuid, date) from public, anon, authenticated;

-- END OF THE REVIEW'S MY WORK FIGURES ---------------------------------------

select public.functions_tidy();
