-- ===========================================================================
-- DEPARTMENT SCORES ARE AN ADMIN'S — the quarter's department scores are
-- entered by an admin alone. 2026-10-18. Safe to run twice. Rollback at the
-- foot. Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/perf.js compares the two.
--
-- WHAT CHANGED (review item 6)
--   NOBODY SCORES THEIR OWN DEPARTMENT kept a member from scoring their own
--   department, but the prize goes whole to the higher of two: a member of
--   Creative holding team.performance could still mark Marketing down and
--   win it. perf_dept_save now refuses `admin-only` unless the caller holds
--   Team: Performance admin (perf_is_admin(), team.perfadmin, an admin's
--   by itself). The own-department refusal stays for an admin who holds a
--   department. The page offers Department scores to that part alone.
--
-- ROLLBACK
--   Run the perf_dept_save definition of the NOBODY SCORES THEIR OWN
--   DEPARTMENT section of supabase/schema.sql again.
-- ===========================================================================

create or replace function public.perf_dept_save(p_token text, p_quarter date, p_department text, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err text; v_me public.team_members; v_q date; v_c jsonb; v_i integer; v_v jsonb; v_n numeric[] := '{}';
  v_max constant numeric[] := array[25, 25, 20, 15, 15]; v_was public.perf_dept_scores; v_crit boolean;
  v_changed jsonb := '[]'::jsonb; v_old numeric[];
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  /* The department prize is decided by an admin alone: with two
     departments, a member scoring the other one could swing it. */
  if not public.perf_is_admin() then return jsonb_build_object('error', 'admin-only'); end if;
  v_me := public.ops_me();
  v_q := date_trunc('quarter', p_quarter)::date;
  if v_q is null or v_q < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if p_department is null or p_department not in ('creative', 'marketing') then
    return jsonb_build_object('error', 'bad-department');
  end if;
  /* Nobody scores their own department: its members share its prize. */
  if v_me.department is not distinct from p_department then
    return jsonb_build_object('error', 'own-department');
  end if;
  if exists (select 1 from public.perf_rewards where kind = 'quarter' and period = v_q) then
    return jsonb_build_object('error', 'confirmed');
  end if;
  v_c := p_payload -> 'criteria';
  if v_c is null or jsonb_typeof(v_c) <> 'array' then return jsonb_build_object('error', 'bad-payload'); end if;
  if jsonb_array_length(v_c) <> 5 then return jsonb_build_object('error', 'bad-payload'); end if;
  for v_i in 1..5 loop
    v_v := v_c -> (v_i - 1);
    if jsonb_typeof(v_v) <> 'number' then
      return jsonb_build_object('error', 'bad-score', 'index', v_i, 'max', v_max[v_i]);
    end if;
    if (v_v #>> '{}')::numeric not between 0 and v_max[v_i]
       or round((v_v #>> '{}')::numeric, 1) <> (v_v #>> '{}')::numeric then
      return jsonb_build_object('error', 'bad-score', 'index', v_i, 'max', v_max[v_i]);
    end if;
    v_n := v_n || (v_v #>> '{}')::numeric;
  end loop;
  v_crit := coalesce((p_payload ->> 'critical')::boolean, false);
  select * into v_was from public.perf_dept_scores where quarter = v_q and department = p_department for update;
  insert into public.perf_dept_scores (quarter, department, c1, c2, c3, c4, c5, critical, entered_by, updated_at)
  values (v_q, p_department, v_n[1], v_n[2], v_n[3], v_n[4], v_n[5], v_crit, v_me.id, now())
  on conflict (quarter, department) do update set
    c1 = excluded.c1, c2 = excluded.c2, c3 = excluded.c3, c4 = excluded.c4, c5 = excluded.c5,
    critical = excluded.critical, entered_by = excluded.entered_by, updated_at = now();
  v_old := array[v_was.c1, v_was.c2, v_was.c3, v_was.c4, v_was.c5];
  for v_i in 1..5 loop
    if v_old[v_i] is distinct from v_n[v_i] then
      v_changed := v_changed || jsonb_build_array(jsonb_build_object('key', 'c' || v_i, 'from', v_old[v_i], 'to', v_n[v_i]));
    end if;
  end loop;
  if v_was.critical is distinct from v_crit then
    v_changed := v_changed || jsonb_build_array(jsonb_build_object('key', 'critical', 'from', v_was.critical, 'to', v_crit));
  end if;
  if jsonb_array_length(v_changed) > 0 then
    perform public.perf_log(null, null, 'dept_scored',
      jsonb_build_object('key', v_q::text, 'department', p_department, 'changed', v_changed));
  end if;
  return public.perf_quarter(p_token, v_q);
end $$;

revoke all on function public.perf_dept_save(text, date, text, jsonb) from public, anon, authenticated;
grant execute on function public.perf_dept_save(text, date, text, jsonb) to authenticated;

-- END OF DEPARTMENT SCORES ARE AN ADMIN'S ----------------------------------

select public.functions_tidy();
