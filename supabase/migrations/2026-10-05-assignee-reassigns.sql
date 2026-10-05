-- ===========================================================================
-- THE ASSIGNEE REASSIGNS — the person a task is assigned to may give it to
-- someone else, and so may any group above them.
-- 2026-10-05. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two. Runs after the sections that last defined ops_assign_task and
-- ops_hand_over_task (MY WORK AS A DAILY TASK TRACKER for the second).
--
-- WHAT CHANGED
--   Both asked My Work at Manage. The user decided who reassigns: the
--   assignee (My Work at Work, their own task only) and any group above
--   them (Manage, an admin). Helpers and the reviewer stay a manager's.
--   ops_assign_task now also asks ops_may_see_task, as every other task
--   write does, so nobody reassigns a task outside their client scope.
--
-- ROLLBACK
--   Run the two functions from the sections that defined them before.
-- ===========================================================================

create or replace function public.ops_assign_task(
  p_task uuid, p_owner uuid, p_contributors uuid[] default null,
  p_reviewer uuid default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was uuid;
  c   uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  /* The person it is assigned to reassigns it, and so does any group
     above them (My Work at Manage, an admin); helpers and the reviewer
     stay a manager's (the user, 2026-10-05). */
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'manage') then
    if not public.allowed('ops', 'work') or p_contributors is not null or p_reviewer is not null
       or not exists (select 1 from public.ops_task_assignees a
                       where a.task_id = p_task and a.responsibility = 'owner'
                         and a.ended_at is null and a.team_member_id = m.id) then
      return jsonb_build_object('error', 'denied');
    end if;
  end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  select team_member_id into was from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null;

  if p_owner is not null and p_owner is distinct from was then
    /* The former owner stops seeing it as live work and keeps their place in
       its history: the row is ended and kept. */
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (p_task, p_owner, 'owner', m.id);
    perform public.ops_log(p_task, 'assignment_changed',
      jsonb_build_object('owner_id', was), jsonb_build_object('owner_id', p_owner), '{}'::jsonb);
  end if;

  if p_contributors is not null then
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'contributor' and ended_at is null
       and not (team_member_id = any (p_contributors));
    foreach c in array p_contributors loop
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, c, 'contributor', m.id)
      on conflict do nothing;
    end loop;
    perform public.ops_log(p_task, 'contributor_changed', null,
      jsonb_build_object('contributors', to_jsonb(p_contributors)), '{}'::jsonb);
  end if;

  if p_reviewer is not null then
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'reviewer' and ended_at is null
       and team_member_id <> p_reviewer;
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (p_task, p_reviewer, 'reviewer', m.id)
    on conflict do nothing;
    perform public.ops_log(p_task, 'reviewer_changed', null,
      jsonb_build_object('reviewer_id', p_reviewer), '{}'::jsonb);
  end if;

  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_assign_task(uuid, uuid, uuid[], uuid, integer) to authenticated;

create or replace function public.ops_hand_over_task(
  p_task uuid, p_owner uuid, p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  /* The person it is assigned to hands it over, and so does any group
     above them (the user, 2026-10-05). */
  if not public.allowed('ops', 'manage') then
    if not public.allowed('ops', 'work')
       or not exists (select 1 from public.ops_task_assignees a
                       where a.task_id = p_task and a.responsibility = 'owner'
                         and a.ended_at is null and a.team_member_id = m.id) then
      return jsonb_build_object('error', 'denied');
    end if;
  end if;
  if p_owner is null then return jsonb_build_object('error', 'no-such-person'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if not exists (select 1 from public.team_members where id = p_owner and active) then
    return jsonb_build_object('error', 'no-such-person');
  end if;

  select team_member_id into was from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null;
  if p_owner is not distinct from was then return public.ops_task_json(p_task); end if;

  update public.ops_task_assignees set ended_at = now()
   where task_id = p_task and responsibility = 'owner' and ended_at is null;
  insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
  values (p_task, p_owner, 'owner', m.id);
  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'assignment_changed',
    jsonb_build_object('owner_id', was),
    jsonb_build_object('owner_id', p_owner),
    jsonb_build_object('handover', true, 'stage_key', t.stage_key)
      || case when nullif(btrim(coalesce(p_note, '')), '') is null then '{}'::jsonb
              else jsonb_build_object('note', btrim(p_note)) end);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_hand_over_task(uuid, uuid, text, integer) to authenticated;

-- END OF THE ASSIGNEE REASSIGNS ---------------------------------------------
