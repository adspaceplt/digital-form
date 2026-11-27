-- ===========================================================================
-- FEEDBACK SATISFACTION RATE (2026-11-27)
-- ===========================================================================
-- WHY: the linked sections (the user, 27 Nov: "the link could proceed on",
-- flow 3 as recommended): Performance's Client satisfaction rate was typed
-- by hand each month while the clients' own answers sat in Client feedback.
-- The review sheet now offers the month's rate from those answers, as it
-- offers My Work's two figures; management presses it or types its own.
--
-- WHAT CHANGES
--   * `perf_ops_rate(member, month)` (restated whole from THE REVIEW'S MY
--     WORK FIGURES) answers `satisfaction: {answers, rate}` beside
--     `posting` and `timeline`: the account manager question alone (the
--     lead score rates the agency, not the person), each answer as a
--     percentage of its own scale's maximum (Service rating 1 to 5,
--     Performance review 1 to 10), averaged over the answers submitted in
--     the month (MYT) naming this colleague as manager. No answer: no key,
--     never 0. Withheld where `feedback_sees_manager` withholds the score.
--     Read only through `perf_json`'s full view (management), as before.
--
-- ORDER: this file (connector), then the pages. An old page reads no
-- `satisfaction` and draws nothing for it. Safe to run twice.
-- ROLLBACK: run perf_ops_rate from THE REVIEW'S MY WORK FIGURES again.
-- ===========================================================================

-- FEEDBACK SATISFACTION RATE -------------------------------------------------

create or replace function public.perf_ops_rate(p_member uuid, p_period date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m_from timestamptz := (date_trunc('month', p_period)::date)::timestamp at time zone 'Asia/Kuala_Lumpur';
  m_to   timestamptz := ((date_trunc('month', p_period) + interval '1 month')::date)::timestamp at time zone 'Asia/Kuala_Lumpur';
  today  date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  p_due integer; p_ok integer; t_reached integer; t_met integer; s_n integer := 0; s_rate numeric;
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

  /* Client satisfaction (FEEDBACK SATISFACTION RATE): the account manager
     question of each answer submitted in the month (MYT) naming this
     colleague, each as a percentage of its own scale's maximum, then
     averaged; a month with no answer has no rate, never 0. Withheld where
     the reader may not see the manager's score. */
  if public.feedback_sees_manager(p_member) then
    select count(*), round(avg(r.manager_score::numeric * 100 / q.scale_max), 1)
      into s_n, s_rate
      from public.feedback_responses r
      join public.feedback_questions q on q.kind = r.kind and q.about_manager and q.type = 'scale' and q.scale_max > 0
     where r.manager_id = p_member and r.manager_score is not null
       and r.submitted_at >= m_from and r.submitted_at < m_to;
  end if;

  return jsonb_build_object(
    'posting',  jsonb_build_object('due', p_due, 'on_time', p_ok),
    'timeline', jsonb_build_object('reached', t_reached, 'met', t_met))
    || case when s_n > 0 then jsonb_build_object('satisfaction', jsonb_build_object('answers', s_n, 'rate', s_rate)) else '{}'::jsonb end;
end $$;
revoke all on function public.perf_ops_rate(uuid, date) from public, anon, authenticated;

-- END OF FEEDBACK SATISFACTION RATE ------------------------------------------

select public.functions_tidy();
