-- ===========================================================================
-- A COLLEAGUE WITHOUT MY WORK TAKES NO TASKS — a colleague whose group holds
-- My Work at No Access is never given a task, a month or a reminder to add
-- tasks (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15: contract staff "focusing on sales or
--   whatsoever, not tasks related" should be "excluded from being
--   assigned"; option A, from the group's My Work level, no new setting)
--   Every active colleague was offered in every My Work picker whatever
--   their access, and the noon reminder told each of them to add tasks.
--
-- WHAT CHANGED
--   * `ops_takes_tasks(p_member)`: active, and an admin or holding My Work
--     (`access.ops`) above No Access. Called by the triggers alone.
--   * Trigger `ops_task_assignees_takes_tasks`: a live assignment (an
--     owner, a helper or a reviewer) to a colleague who takes no tasks is
--     refused (`no-tasks`), whichever function makes it.
--   * Trigger `ops_engagements_takes_tasks`: a month's manager set or
--     changed to such a colleague is refused (`no-tasks`); a month already
--     theirs is left as it is.
--   * `ops_tasks_remind`: the noon reminder skips them.
--
-- ORDER
--   The page first (its pickers leave them out), then this file. An old
--   tab offering them meets the refusal by name.
--
-- Safe to run twice. Rollback: in the SQL Editor, drop the triggers
-- `ops_task_assignees_takes_tasks` on public.ops_task_assignees and
-- `ops_engagements_takes_tasks` on public.ops_engagements, the functions
-- public.ops_task_assignees_takes_tasks(), public.ops_engagements_takes_tasks()
-- and public.ops_takes_tasks(uuid), and run the section A NOON REMINDER TO
-- ADD TASKS again.
-- ===========================================================================
create or replace function public.ops_takes_tasks(p_member uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.team_members t
     where t.id = p_member and t.active
       and (coalesce(t.is_admin, false) or coalesce(t.role, '') = 'admin'
            or public.level_rank(t.access ->> 'ops') > 0));
$$;
revoke all on function public.ops_takes_tasks(uuid) from public, anon, authenticated;

create or replace function public.ops_task_assignees_takes_tasks()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.ended_at is null and new.team_member_id is not null
     and not public.ops_takes_tasks(new.team_member_id) then
    raise exception 'no-tasks';
  end if;
  return new;
end $$;
revoke all on function public.ops_task_assignees_takes_tasks() from public, anon, authenticated;

create or replace trigger ops_task_assignees_takes_tasks
  before insert or update of team_member_id, ended_at on public.ops_task_assignees
  for each row execute function public.ops_task_assignees_takes_tasks();

create or replace function public.ops_engagements_takes_tasks()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.manager_id is not null
     and (tg_op = 'INSERT' or new.manager_id is distinct from old.manager_id)
     and not public.ops_takes_tasks(new.manager_id) then
    raise exception 'no-tasks';
  end if;
  return new;
end $$;
revoke all on function public.ops_engagements_takes_tasks() from public, anon, authenticated;

create or replace trigger ops_engagements_takes_tasks
  before insert or update of manager_id on public.ops_engagements
  for each row execute function public.ops_engagements_takes_tasks();

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
              and public.ops_takes_tasks(t.id)
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

-- END OF A COLLEAGUE WITHOUT MY WORK TAKES NO TASKS ---------------------------
select public.functions_tidy();
