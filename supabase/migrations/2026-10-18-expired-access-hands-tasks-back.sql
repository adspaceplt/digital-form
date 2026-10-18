-- ===========================================================================
-- EXPIRED ACCESS HANDS TASKS BACK — when a colleague's access expires, each
-- open task they hold goes back to whoever created it, else is left open to
-- take. 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte
-- for byte in supabase/schema.sql under the same banner; tests/ops.js
-- compares the two.
--
-- WHAT CHANGED (review of 2026-10-18, item 19)
--   team_expire_access stood a colleague down and left their open tasks
--   with them: hidden from most of the team and movable only by an admin.
--   It now calls team_expiry_hand_back for each colleague it stands down.
--   Each open task (not finished, cancelled or archived) they hold as owner:
--     * goes back to its creator where the creator is another active
--       colleague who takes tasks (ops_takes_tasks), who is told (kind
--       assigned, "Handed back to you: … access ended.");
--     * else is left with no owner and open to take (open_at; the Take
--       flow of OPEN TO TAKE), and each active colleague at My Work Manage
--       or admin who takes tasks is told (kind tasks.unassigned).
--   Each move is filed on the task (assignment_changed, detail expired and
--   a note), so its history says why. Helpers and reviewers are left as
--   they are (trigger team_members_leaving ends them on a removal).
--
-- ROLLBACK
--   Run team_expire_access as TEAM ACCESS TIME stated it (the
--   previous last definition in schema.sql); team_expiry_hand_back may stay.
-- ===========================================================================

create or replace function public.team_expiry_hand_back(p_member uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_who public.team_members;
  t public.ops_tasks;
  v_to uuid;
  v_title text;
  n int := 0;
begin
  select * into v_who from public.team_members where id = p_member;
  if v_who.id is null then return 0; end if;
  for t in select k.* from public.ops_tasks k
             join public.ops_task_assignees a on a.task_id = k.id
            where a.team_member_id = p_member and a.responsibility = 'owner' and a.ended_at is null
              and k.completed_at is null and k.cancelled_at is null and k.archived_at is null
            order by k.task_no loop
    v_to := case when t.created_by is not null and t.created_by <> p_member
                       and public.ops_takes_tasks(t.created_by) then t.created_by end;
    v_title := public.ops_serial(t.task_no) || ' · ' || public.ops_title(t);
    update public.ops_task_assignees set ended_at = now()
     where task_id = t.id and responsibility = 'owner' and ended_at is null;
    if v_to is not null then
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (t.id, v_to, 'owner', null);
      update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
      perform public.ops_notify(v_to, t.id, 'assigned', v_title,
        'Handed back to you: ' || v_who.name || '''s access ended.',
        'returned:' || t.id::text || ':' || v_to::text || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI'));
    else
      update public.ops_tasks set open_at = now(), open_by = null, version = version + 1, updated_at = now()
       where id = t.id;
      perform public.ops_notify(x.id, t.id, 'tasks.unassigned', v_title,
        v_who.name || '''s access ended. The task is open to take.',
        'unassigned:' || t.id::text || ':' || x.id::text || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI'))
        from public.team_members x
       where x.active and x.id <> p_member and not coalesce(x.system, false)
         and (coalesce(x.is_admin, false) or coalesce(x.role, '') = 'admin' or public.level_rank(x.access ->> 'ops') >= 3)
         and public.ops_takes_tasks(x.id);
    end if;
    insert into public.ops_task_events (task_id, event_type, actor_id, actor_email, from_value, to_value, detail)
    values (t.id, 'assignment_changed', null, null,
            jsonb_build_object('owner_id', p_member), jsonb_build_object('owner_id', v_to),
            jsonb_build_object('expired', true, 'note',
              case when v_to is not null then 'Access ended; handed back to whoever created it.'
                   else 'Access ended; open to take.' end));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.team_expiry_hand_back(uuid) from public, anon, authenticated;

create or replace function public.team_expire_access()
returns int language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  n int := 0;
begin
  for m in select * from public.team_members t
            where t.active and t.access_until is not null
              and public.team_access_ends(t.access_until, t.access_until_time) <= now()
            order by t.access_until, t.access_until_time nulls last, t.name loop
    if (m.is_admin or m.role = 'admin') and not exists (
         select 1 from public.team_members o
          where o.id <> m.id and o.active and (o.is_admin or o.role = 'admin')
            and (o.access_until is null
                 or public.team_access_ends(o.access_until, o.access_until_time) > now())) then
      continue;
    end if;
    update public.team_members set active = false, expired_at = now() where id = m.id;
    perform public.team_expiry_hand_back(m.id);
    insert into public.activity_log (actor, action, subject, detail)
    values ('system', 'team.changed', m.name,
            case when m.access_until_time is null
                 then 'Access expired after ' || public.team_access_word(m.access_until, null)
                 else 'Access expired at ' || public.team_access_word(m.access_until, m.access_until_time) end);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.team_expire_access() from public, anon, authenticated;

-- END OF EXPIRED ACCESS HANDS TASKS BACK ------------------------------------

select public.functions_tidy();
