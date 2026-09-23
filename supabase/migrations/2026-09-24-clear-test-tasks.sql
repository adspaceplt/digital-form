-- 2026-09-24 · Clear the test tasks and start task numbers at #WT00001
--
-- RUN ONCE, ON PURPOSE, after 2026-09-24-my-work-daily-tasks.sql.
--
-- Every task in My Work today was made while testing (confirmed by the user
-- on 2026-09-24), so this deletes every task, and with it each task's own
-- history, checklist, links, time entries and notifications, and restarts
-- the running number so the next task is #WT00001. Engagements, clients and
-- the activity record are not touched; one activity row records the clear.
--
-- Safe to run twice: the first run leaves a marker, and a second run finds
-- it and deletes nothing. The marker is what stops this file from ever
-- emptying real work by accident later.
--
-- Preview first (reads only):
--   select count(*) as tasks, min(task_no) as first, max(task_no) as last
--     from public.ops_tasks;
--
-- There is no rollback: deleted tasks are gone. Take a backup first if in
-- any doubt.

create table if not exists public.ops_settings (
  key        text primary key,
  value      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.ops_settings enable row level security;

do $$
declare
  n integer;
begin
  if exists (select 1 from public.ops_settings where key = 'test_tasks_cleared') then
    raise notice 'The test tasks were already cleared. Nothing was deleted.';
    return;
  end if;
  select count(*) into n from public.ops_tasks;
  insert into public.activity_log (actor, action, subject, detail)
  values ('System', 'ops.deleted', 'My Work',
          n || ' test tasks cleared. Task numbers restart at #WT00001.');
  delete from public.ops_tasks;
  perform setval('public.ops_task_no_seq', 1, false);
  insert into public.ops_settings (key, value)
  values ('test_tasks_cleared', jsonb_build_object('at', now(), 'tasks', n));
end $$;
