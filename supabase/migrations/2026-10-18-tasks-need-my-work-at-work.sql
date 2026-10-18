-- ===========================================================================
-- TASKS NEED MY WORK AT WORK — a task, a month or a reminder to add tasks
-- goes only to a colleague whose group holds My Work at Work or above.
-- 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED (review of 2026-10-18, item 12)
--   ops_takes_tasks let in any level above No Access, so a colleague at My
--   Work View could be given a task they cannot move, take or hand on (every
--   task write asks My Work at Work). It now asks Work or above (an admin
--   always). The triggers that call it (ops_task_assignees_takes_tasks,
--   ops_engagements_takes_tasks) and the noon reminder follow. Work already
--   held is left as it is: nobody at View held a live task on 2026-10-18.
--
-- ROLLBACK
--   Run ops_takes_tasks as A COLLEAGUE WITHOUT MY WORK TAKES NO TASKS stated
--   it (level_rank(...) > 0).
-- ===========================================================================

create or replace function public.ops_takes_tasks(p_member uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.team_members t
     where t.id = p_member and t.active
       and (coalesce(t.is_admin, false) or coalesce(t.role, '') = 'admin'
            or public.level_rank(t.access ->> 'ops') >= 2));
$$;
revoke all on function public.ops_takes_tasks(uuid) from public, anon, authenticated;

-- END OF TASKS NEED MY WORK AT WORK ------------------------------------------

select public.functions_tidy();
