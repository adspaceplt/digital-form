-- ===========================================================================
-- OPEN TO TAKE — a Task Owner offers a task to the team, and any colleague
-- who works in My Work takes it and becomes its owner. Pulling work is the
-- initiative; the task keeps an owner throughout.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two. Runs after CLIENT SCOPE.
--
-- WHAT CHANGED (the user, 2026-10-04: pick up work, approved)
--   1. `ops_tasks.open_at`, `open_by`: when and by whom a task was offered.
--      A task that changes hands any way is no longer open (trigger on the
--      new owner's row).
--   2. `ops_set_open(p_task, p_on)`: the Task Owner or an admin, My Work at
--      Work, an open task. Filed `offered` / `offer_withdrawn`.
--   3. `ops_take_task(p_task, p_version)`: My Work at Work, an offered open
--      task the caller may see, not already theirs. The caller becomes the
--      owner (filed `assignment_changed`, `taken`), and the owner before is
--      told.
--   4. `ops_may_see_task`: an offered open task is seen by anyone at My Work
--      Work whose client scope holds its client, so it can be taken.
--
-- ROLLBACK
--   Run the CLIENT SCOPE section's ops_may_see_task again; in the SQL Editor
--   drop the two functions, the trigger and its function. The two columns
--   may stay.
-- ===========================================================================

alter table public.ops_tasks add column if not exists open_at timestamptz;
alter table public.ops_tasks add column if not exists open_by uuid references public.team_members(id) on delete set null;

create or replace function public.ops_may_see_task(p_task uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when not public.allowed('ops', 'view') then false
    when public.ops_granted('ops.all', 'view') and public.client_scope_free('view') then true
    when exists (
      select 1 from public.ops_tasks t
       where t.id = p_task
         and (t.created_by = (select id from public.ops_me())
              or exists (select 1 from public.ops_task_assignees a
                          where a.task_id = t.id and a.ended_at is null
                            and a.team_member_id = (select id from public.ops_me())))) then true
    when public.allowed('ops', 'work') and exists (
      select 1 from public.ops_tasks t
       where t.id = p_task and t.open_at is not null
         and t.completed_at is null and t.cancelled_at is null)
      then public.client_seen((select t.client_id from public.ops_tasks t where t.id = p_task), 'view')
    when public.ops_granted('ops.all', 'view')
      then public.client_seen((select t.client_id from public.ops_tasks t where t.id = p_task), 'view')
    else false
  end
$$;

/* A task that changes hands, any way, is no longer on offer. */
create or replace function public.ops_assignees_close_offer()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.responsibility = 'owner' and new.ended_at is null then
    update public.ops_tasks set open_at = null, open_by = null
     where id = new.task_id and open_at is not null;
  end if;
  return new;
end $$;
revoke all on function public.ops_assignees_close_offer() from public, anon, authenticated;
create or replace trigger ops_assignees_close_offer
  after insert on public.ops_task_assignees
  for each row execute function public.ops_assignees_close_offer();

create or replace function public.ops_set_open(p_task uuid, p_on boolean)
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
  if not public.ops_owner_may_move(p_task) then return jsonb_build_object('error', 'not-owner'); end if;
  if t.completed_at is not null or t.cancelled_at is not null then
    return jsonb_build_object('error', 'finished');
  end if;
  if (t.open_at is not null) = coalesce(p_on, false) then return public.ops_task_json(p_task); end if;
  update public.ops_tasks
     set open_at = case when p_on then now() end, open_by = case when p_on then m.id end,
         version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, case when p_on then 'offered' else 'offer_withdrawn' end,
                         null, null, '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;

create or replace function public.ops_take_task(p_task uuid, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; t public.ops_tasks; was uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') or not public.ops_may_see_task(p_task) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.open_at is null then return jsonb_build_object('error', 'not-open'); end if;
  if t.completed_at is not null or t.cancelled_at is not null then
    return jsonb_build_object('error', 'finished');
  end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  select team_member_id into was from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null;
  if was = m.id then return jsonb_build_object('error', 'already-yours'); end if;
  update public.ops_task_assignees set ended_at = now()
   where task_id = p_task and responsibility = 'owner' and ended_at is null;
  insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
  values (p_task, m.id, 'owner', m.id);
  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'assignment_changed',
    jsonb_build_object('owner_id', was), jsonb_build_object('owner_id', m.id),
    jsonb_build_object('taken', true, 'stage_key', t.stage_key));
  if was is not null then
    perform public.ops_notify(was, p_task, 'taken',
      public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
      'Taken by ' || coalesce(nullif(m.name, ''), m.email) || '.',
      'taken:' || p_task::text || ':' || m.id::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
  end if;
  return public.ops_task_json(p_task);
end $$;

revoke all on function public.ops_set_open(uuid, boolean) from public, anon, authenticated;
revoke all on function public.ops_take_task(uuid, integer) from public, anon, authenticated;
grant execute on function public.ops_set_open(uuid, boolean) to authenticated;
grant execute on function public.ops_take_task(uuid, integer) to authenticated;

-- END OF OPEN TO TAKE -------------------------------------------------------
