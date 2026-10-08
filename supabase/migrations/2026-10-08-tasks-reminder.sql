-- ===========================================================================
-- A NOON REMINDER TO ADD TASKS — on a weekday at 12:00 MYT, a colleague with
-- no open task, or who has never added one, is reminded to add their work.
-- 2026-10-08. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-08: "if the account has either totally no tasks under
--   or not created any tasks, sent a reminder daily during weekday at noon to
--   remind to add tasks (admins excluded)".
--   1. `ops_tasks_remind(p_today)` (no caller but pg_cron; revoked from every
--      login): on Monday to Friday (MYT) each active colleague who is not an
--      admin is told once that day (kind `tasks.empty`, `dedupe_key`
--      `tasks.remind.{member}.{day}`), when no open task is assigned to
--      them, or when they have never added a task. Answers how many were
--      told.
--   2. pg_cron `tasks-reminder` runs it at 04:00 UTC (12:00 MYT), Monday to
--      Friday.
--   3. `ops_notifications_push` opens My Work for `tasks.empty` and tags it
--      `tasks-empty`, so a second day's reminder replaces the first.
--
-- ROLLBACK
--   select cron.unschedule('tasks-reminder');
--   drop function public.ops_tasks_remind(date);
--   (ops_notifications_push: re-run the MY HR REMINDERS section.)
-- ===========================================================================

create or replace function public.ops_tasks_remind(p_today date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Kuala_Lumpur')::date);
  m record;
  v_open boolean;
  v_made boolean;
  n integer := 0;
begin
  if extract(isodow from v_today) > 5 then return 0; end if;
  for m in select t.id from public.team_members t
            where t.active and not coalesce(t.is_admin, false) and coalesce(t.role, '') <> 'admin'
            order by t.id loop
    v_open := exists (select 1 from public.ops_task_assignees a
                        join public.ops_tasks k on k.id = a.task_id
                       where a.team_member_id = m.id and a.responsibility = 'owner' and a.ended_at is null
                         and k.completed_at is null and k.cancelled_at is null and k.archived_at is null);
    v_made := exists (select 1 from public.ops_tasks k where k.created_by = m.id);
    if v_open and v_made then continue; end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
    values (m.id, null, 'tasks.empty',
            case when not v_open then 'No open tasks are assigned to you. Add the work you are on in My Work.'
                 else 'Add the tasks you are working on in My Work.' end,
            null, 'tasks.remind.' || m.id || '.' || v_today)
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.ops_tasks_remind(date) from public, anon, authenticated;

create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         when new.kind in ('client_left', 'tasks.empty') then '/admin/?s=work'
         when new.kind = 'hr.letter' then '/admin/?s=mine&view=letters'
         when new.kind = 'perf.disputed' then '/admin/?s=team&tab=performance'
         when new.kind = 'perf.reflect' then '/admin/?s=mine&view=reflection'
         when new.kind = 'perf.initiative' then '/admin/?s=mine&view=initiatives'
         when new.kind like 'health.%' then '/admin/?s=mine&view=health'
         when new.kind like 'perf.%' then '/admin/?s=mine'
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         when new.kind = 'hr.letter' then 'hr-letter'
         when new.kind in ('perf.remind', 'perf.reflect', 'health.remind') then 'my-hr'
         when new.kind = 'tasks.empty' then 'tasks-empty'
         else null end);
  return new;
exception when others then
  return new;
end $$;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: no task reminders go out until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'tasks-reminder';
  perform cron.schedule('tasks-reminder', '0 4 * * 1-5', 'select public.ops_tasks_remind()');
end $$;

-- END OF A NOON REMINDER TO ADD TASKS ----------------------------------------

select public.functions_tidy();
