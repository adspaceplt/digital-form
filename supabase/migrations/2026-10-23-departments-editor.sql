-- ===========================================================================
-- DEPARTMENTS, THE SQL EDITOR PART — the checks that named Creative and
-- Marketing give way to the list, and a department nobody names can be
-- taken off it (2026-10-23)
-- ===========================================================================
-- WHY: 2026-10-23-departments.sql makes the department a reference to
-- `departments`. The three checks that named the two departments stand
-- until they are taken away, and the connector holds any statement naming
-- them, so this part runs in the SQL Editor, after that file.
--
-- WHAT IT CHANGES
--   * The checks `team_members_department_check`,
--     `perf_people_department_check` and
--     `perf_dept_scores_department_check` go; each column keeps its
--     reference to `departments(key)`.
--   * `department_delete(p_key)` (Business settings): takes a department
--     off the list where no colleague, review profile or prize score names
--     it (`in-use` with the colleagues counted), else `not-found`; filed
--     `team.changed` under Departments.
--
-- ORDER: after 2026-10-23-departments.sql. Safe to run twice. Rollback:
-- revoke execute on public.department_delete(text) from authenticated; the
-- checks are not put back (they would refuse every department added since).
-- ===========================================================================

alter table public.team_members drop constraint if exists team_members_department_check;
alter table public.perf_people drop constraint if exists perf_people_department_check;
alter table public.perf_dept_scores drop constraint if exists perf_dept_scores_department_check;

/* Take a department nobody names off the list. */
create or replace function public.department_delete(p_key text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.team_members; v_old public.departments; v_n int;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  select * into v_old from public.departments d where d.key = p_key for update;
  if v_old.key is null then return jsonb_build_object('error', 'not-found'); end if;
  select count(*)::int into v_n from public.team_members t where t.department = p_key;
  if v_n > 0 or exists (select 1 from public.perf_people p where p.department = p_key)
     or exists (select 1 from public.perf_dept_scores s where s.department = p_key) then
    return jsonb_build_object('error', 'in-use', 'members', v_n);
  end if;
  delete from public.departments d where d.key = p_key;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Departments', 'Removed: ' || v_old.name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.department_delete(text) from public, anon;
grant execute on function public.department_delete(text) to authenticated;

-- END OF DEPARTMENTS, THE SQL EDITOR PART ----------------------------------

select public.functions_tidy();
