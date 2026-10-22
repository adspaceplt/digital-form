-- ===========================================================================
-- A MONTH'S LATE WORK READS AS MY WORK READS IT — the client record's
-- Engagements and its month line count overdue tasks by My Work's own rule
-- (2026-10-22)
-- ===========================================================================
-- WHY (audit 2026-10-22, CLI-2; the user: "Fix all"): the record counted a
-- task late once its final date had passed, whatever its stage, from its
-- own read of the reader's tasks; My Work calls it late only while it is
-- short of client review, or past a priority's deadline and short of its
-- review. A task at Client review past its date read "1 overdue" on the
-- client and on time in My Work.
--
-- WHAT IT CHANGES
--   * `ops_task_late(p_task)`: whether a task is late now, by the rule
--     `ops_report`'s WHAT IS LATE states (and `isLate()` in js/ops.js):
--     open, and past its final date (Malaysian days) while short of its
--     workflow's client review, or past its priority's deadline while short
--     of its review (On hold and Blocked still count). Internal: revoked
--     from every caller; functions alone ask it.
--   * `ops_engagement_counts` adds `late`: the month's open tasks late by
--     that rule, over the whole month whoever asks, as its other counts.
--     The page reads it and no longer reads the month's tasks itself.
--
-- ORDER: this file, then the pages. An old page ignores `late` and keeps
-- its own read. Safe to run twice. Mirrored byte for byte in schema.sql.
-- ROLLBACK: run the MONTH COUNTS LEAVE REPORTS OUT section's
-- ops_engagement_counts again, then
--   drop function if exists public.ops_task_late(uuid);
-- ===========================================================================

create or replace function public.ops_task_late(p_task uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select
      (t.current_final_due_at is not null
        and (t.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date
            < (now() at time zone 'Asia/Kuala_Lumpur')::date
        and (f.at is null or s.position < f.at))
      or
      (p.by is not null and p.by < now()
        and (pf.at is null or s.position < pf.at or s.stage_group in ('kiv', 'blocked')))
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.workflow_id = t.workflow_id and s.key = t.stage_key
      cross join lateral (
        select public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as by) p
      cross join lateral (
        select min(w.position) as at from public.ops_workflow_stages w
         where w.workflow_id = t.workflow_id and w.stage_group = 'client_review') f
      cross join lateral (
        select coalesce(min(w.position) filter (where w.stage_group = 'client_review'),
                        min(w.position) filter (where w.stage_group = 'internal_review')) as at
          from public.ops_workflow_stages w where w.workflow_id = t.workflow_id) pf
     where t.id = p_task
       and t.completed_at is null and t.cancelled_at is null and t.archived_at is null
  ), false)
$$;
revoke all on function public.ops_task_late(uuid) from public, anon, authenticated;

/* A month's tasks, counted over the whole month whoever asks: live (not
   cancelled), open (not finished), done (completed), content (live, less
   the report tasks the month makes for itself), and late (open, and late by
   My Work's rule, `ops_task_late`). Only months the caller may see answer. */
create or replace function public.ops_engagement_counts(p_engagements uuid[])
returns jsonb
language sql security definer stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'engagement_id', e.id,
           'live', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null),
           'open', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null and t.completed_at is null),
           'done', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null and t.completed_at is not null),
           'content', (select count(*) from public.ops_tasks t
                        where t.engagement_id = e.id and t.archived_at is null
                          and t.cancelled_at is null
                          and coalesce(t.source_type, '') not in ('report_social', 'report_ads')),
           'late', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null and t.completed_at is null
                       and public.ops_task_late(t.id)))), '[]'::jsonb)
    from public.ops_engagements e
   where e.id = any (coalesce(p_engagements, '{}'::uuid[]))
     and public.ops_may_see_engagement(e.id)
$$;
revoke all on function public.ops_engagement_counts(uuid[]) from public, anon;
grant execute on function public.ops_engagement_counts(uuid[]) to authenticated;

-- END OF A MONTH'S LATE WORK READS AS MY WORK READS IT -----------------------

select public.functions_tidy();
