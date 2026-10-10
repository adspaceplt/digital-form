-- ===========================================================================
-- POST RESULTS — a posted content task records its views and engagements a
-- week after it went live, so the next month is planned from what worked.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js runs it.
--
-- WHAT CHANGED (the user, 2026-10-09: "social media contents doesn't have
-- high views ... content not interesting")
--   1. `ops_tasks.result_views`, `result_engagements` (whole numbers, none
--      below 0), `result_at`, `result_by`: stamped only by the function.
--   2. `ops_set_results(p_task, p_views, p_engagements)`: My Work at Work on
--      a task the colleague may see that has gone live (`not-live`); both
--      figures required (`bad-number`); filed `results_set` from and to.
--      The Months view lists last month's best and weakest posts by views
--      on a month still being planned; nothing is worked out in the
--      database.
--
-- ROLLBACK
--   drop function public.ops_set_results(uuid, integer, integer); the
--   columns may stay. (In the SQL Editor.)
-- ===========================================================================

alter table public.ops_tasks add column if not exists result_views integer;
alter table public.ops_tasks add column if not exists result_engagements integer;
alter table public.ops_tasks add column if not exists result_at timestamptz;
alter table public.ops_tasks add column if not exists result_by uuid references public.team_members(id) on delete set null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ops_tasks_results_whole') then
    alter table public.ops_tasks add constraint ops_tasks_results_whole
      check ((result_views is null or result_views >= 0) and (result_engagements is null or result_engagements >= 0));
  end if;
end $$;

create or replace function public.ops_set_results(p_task uuid, p_views integer, p_engagements integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; t public.ops_tasks;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') or not public.ops_may_see_task(p_task) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.live_at is null then return jsonb_build_object('error', 'not-live'); end if;
  if p_views is null or p_engagements is null or p_views < 0 or p_engagements < 0 then
    return jsonb_build_object('error', 'bad-number');
  end if;
  update public.ops_tasks
     set result_views = p_views, result_engagements = p_engagements,
         result_at = now(), result_by = m.id, version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'results_set',
    jsonb_build_object('views', t.result_views, 'engagements', t.result_engagements),
    jsonb_build_object('views', p_views, 'engagements', p_engagements), '{}'::jsonb);
  return (select to_jsonb(x) from public.ops_tasks x where x.id = p_task);
end $$;
revoke all on function public.ops_set_results(uuid, integer, integer) from public, anon;
grant execute on function public.ops_set_results(uuid, integer, integer) to authenticated;

-- END OF POST RESULTS ---------------------------------------------------------

select public.functions_tidy();
