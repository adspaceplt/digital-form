-- ===========================================================================
-- TASK CODE EDITABLE — a task's code is corrected in place.
-- 2026-10-08. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-08: "the 2610WN make it editable". The code was made
--   once and never rewritten; the #WT serial stays the task's identity, so
--   the code may now be corrected. `ops_set_code(p_task, p_code, p_version)`:
--   the owner or an admin (`ops_owner_may_move`, `not-owner`), My Work at
--   Work, a task that already carries a code (`no-code`); the code keeps its
--   shape YYMMW{week}{NN}, the month 01 to 12 and the week 1 to 5
--   (`bad-code`), and is the client's own for that month (`code-taken`,
--   naming the task that holds it). It writes code, code_period, code_week,
--   code_seq and the title, and files `code_changed` from and to.
--
-- ROLLBACK
--   Remove the function ops_set_code(uuid, text, integer).
-- ===========================================================================

create or replace function public.ops_set_code(
  p_task uuid, p_code text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
  v_code text;
  v_parts text[];
  v_period text;
  v_week integer;
  v_seq integer;
  v_other bigint;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_owner_may_move(p_task) then return jsonb_build_object('error', 'not-owner'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if coalesce(t.code, '') = '' or t.code_seq is null then
    return jsonb_build_object('error', 'no-code');
  end if;
  v_code := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  v_parts := regexp_match(v_code, '^([0-9]{2})([0-9]{2})W([1-5])([0-9]{2,3})$');
  if v_parts is null or v_parts[2]::integer not between 1 and 12 or v_parts[4]::integer < 1 then
    return jsonb_build_object('error', 'bad-code');
  end if;
  v_period := '20' || v_parts[1] || '-' || v_parts[2];
  v_week := v_parts[3]::integer;
  v_seq := v_parts[4]::integer;
  v_code := v_parts[1] || v_parts[2] || 'W' || v_week::text || lpad(v_seq::text, 2, '0');
  if v_code = t.code then return public.ops_task_json(p_task); end if;
  select o.task_no into v_other from public.ops_tasks o
   where o.id <> p_task
     and coalesce(o.client_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(t.client_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and o.code_period = v_period and o.code_seq = v_seq
   limit 1;
  if found then
    return jsonb_build_object('error', 'code-taken', 'task_no', v_other);
  end if;
  update public.ops_tasks
     set code = v_code, code_period = v_period, code_week = v_week, code_seq = v_seq,
         title = btrim(v_code || ' ' || coalesce(content_desc, '')),
         version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'code_changed',
    jsonb_build_object('code', t.code), jsonb_build_object('code', v_code), '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
revoke all on function public.ops_set_code(uuid, text, integer) from public, anon;
grant execute on function public.ops_set_code(uuid, text, integer) to authenticated;

-- END OF TASK CODE EDITABLE -------------------------------------------------

select public.functions_tidy();
