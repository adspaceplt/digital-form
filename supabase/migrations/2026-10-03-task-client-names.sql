-- ===========================================================================
-- TASK CLIENT NAMES — a task names its client wherever the colleague may see
-- the task.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   The audit of 2026-10-03: a colleague's own task on a client outside
--   their reach (Own clients only, or a band at No Access) read No client in
--   My Work, because the client's row never arrives to the join. The page
--   asks `ops_task_clients(p_tasks)` for those tasks alone: each task the
--   caller may see (`ops_may_see_task`) with its client's name, and nothing
--   else about the client. At most 500 tasks a call.
--
-- ROLLBACK
--   Remove the function ops_task_clients(uuid[]).
-- ===========================================================================

create or replace function public.ops_task_clients(p_tasks uuid[])
returns table (task_id uuid, client_name text)
language sql security definer stable set search_path = public as $$
  select t.id, c.name
    from public.ops_tasks t
    join public.clients c on c.id = t.client_id
   where t.id = any (p_tasks[1:500])
     and public.ops_may_see_task(t.id)
$$;
revoke all on function public.ops_task_clients(uuid[]) from public, anon;
grant execute on function public.ops_task_clients(uuid[]) to authenticated;

-- END OF TASK CLIENT NAMES ---------------------------------------------------
