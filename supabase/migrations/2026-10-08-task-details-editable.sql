-- ===========================================================================
-- TASK DETAILS EDITABLE — a task's format, type, complexity and estimate are
-- changed where the record shows them.
-- 2026-10-08. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-08: "allow changes straight from these too … a lot of
--   it are hardcoded". `ops_update_task(p_task, p_payload, p_version)` takes,
--   beside the brief and the priority, `deliverable_type` (a format key, or
--   null; `bad-format`), `task_type` (`bad-type`), `complexity`
--   (`bad-complexity`) and `estimate_minutes` (0 to 10,000, or null;
--   `bad-estimate`), each only where sent, and files `details_changed` from
--   and to for what moved.
--
-- ROLLBACK
--   Run the earlier ops_update_task again (supabase/schema.sql, the section
--   "What was added can be put right": the brief and the priority only).
-- ===========================================================================

create or replace function public.ops_update_task(
  p_task uuid, p_payload jsonb, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  t     public.ops_tasks;
  d     text;
  pr    integer;
  fm    text;
  ty    text;
  cx    text;
  es    integer;
  was   jsonb := '{}'::jsonb;
  now_  jsonb := '{}'::jsonb;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  d := t.description; pr := t.priority_level; fm := t.deliverable_type;
  ty := t.task_type; cx := t.complexity; es := t.estimate_minutes;
  if p_payload ? 'description' then
    d := nullif(btrim(coalesce(p_payload ->> 'description', '')), '');
    if length(coalesce(d, '')) > 4000 then return jsonb_build_object('error', 'too-long'); end if;
  end if;
  if p_payload ? 'priority_level' then
    pr := (p_payload ->> 'priority_level')::integer;
    if pr is null or pr < 1 or pr > 4 then return jsonb_build_object('error', 'bad-priority'); end if;
  end if;
  if p_payload ? 'deliverable_type' then
    fm := nullif(btrim(coalesce(p_payload ->> 'deliverable_type', '')), '');
    if fm is not null and fm !~ '^[a-z0-9_]{1,40}$' then return jsonb_build_object('error', 'bad-format'); end if;
  end if;
  if p_payload ? 'task_type' then
    ty := p_payload ->> 'task_type';
    if ty is null or ty not in ('engagement', 'adhoc', 'goodwill', 'special') then
      return jsonb_build_object('error', 'bad-type');
    end if;
  end if;
  if p_payload ? 'complexity' then
    cx := p_payload ->> 'complexity';
    if cx is null or cx not in ('simple', 'standard', 'complex') then
      return jsonb_build_object('error', 'bad-complexity');
    end if;
  end if;
  if p_payload ? 'estimate_minutes' then
    if jsonb_typeof(p_payload -> 'estimate_minutes') = 'null' then es := null;
    else
      es := (p_payload ->> 'estimate_minutes')::integer;
      if es < 0 or es > 10000 then return jsonb_build_object('error', 'bad-estimate'); end if;
    end if;
  end if;
  if d is distinct from t.description then
    was := was || jsonb_build_object('description', t.description); now_ := now_ || jsonb_build_object('description', d);
  end if;
  if pr is distinct from t.priority_level then
    was := was || jsonb_build_object('priority_level', t.priority_level); now_ := now_ || jsonb_build_object('priority_level', pr);
  end if;
  if fm is distinct from t.deliverable_type then
    was := was || jsonb_build_object('deliverable_type', t.deliverable_type); now_ := now_ || jsonb_build_object('deliverable_type', fm);
  end if;
  if ty is distinct from t.task_type then
    was := was || jsonb_build_object('task_type', t.task_type); now_ := now_ || jsonb_build_object('task_type', ty);
  end if;
  if cx is distinct from t.complexity then
    was := was || jsonb_build_object('complexity', t.complexity); now_ := now_ || jsonb_build_object('complexity', cx);
  end if;
  if es is distinct from t.estimate_minutes then
    was := was || jsonb_build_object('estimate_minutes', t.estimate_minutes); now_ := now_ || jsonb_build_object('estimate_minutes', es);
  end if;
  if now_ = '{}'::jsonb then return public.ops_task_json(p_task); end if;
  update public.ops_tasks set description = d, priority_level = pr, deliverable_type = fm,
         task_type = ty, complexity = cx, estimate_minutes = es,
         version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'details_changed', was, now_, '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_update_task(uuid, jsonb, integer) to authenticated;

-- END OF TASK DETAILS EDITABLE ----------------------------------------------

select public.functions_tidy();
