-- ===========================================================================
-- DEPARTMENTS IN RECORDS — the list says which department records still
-- name, so Delete is offered only where it would go through (2026-10-24)
-- ===========================================================================
-- WHY (the Team audit of 2026-10-24, TEAM2-15)
--   Settings' Departments offered Delete wherever no active colleague was in
--   the department, and `department_delete` then refused it (`in-use`)
--   where a colleague no longer active, a review profile or a prize score
--   still named it: an act offered only to be refused.
--
-- WHAT CHANGED
--   * `departments_list()` also answers `in_records` for each department:
--     true while any colleague (active or not), a performance review
--     profile or a department prize score names it, exactly what
--     `department_delete` refuses. The page draws Delete only where neither
--     `members` nor `in_records` holds; the function still refuses.
--
-- ORDER
--   This file, then the page. An open page before reads the extra key and
--   ignores it; the new page on a database without it reads no
--   `in_records` and offers Delete as before.
--
-- Safe to run twice. Rollback: run DEPARTMENTS' departments_list again.
-- ===========================================================================

create or replace function public.departments_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'key', d.key, 'name', d.name, 'active', d.active, 'in_prize', d.in_prize,
      'criteria', coalesce(d.criteria, '[]'::jsonb),
      'members', (select count(*)::int from public.team_members t where t.department = d.key and t.active),
      'in_records', exists (select 1 from public.team_members t where t.department = d.key)
                    or exists (select 1 from public.perf_people p where p.department = d.key)
                    or exists (select 1 from public.perf_dept_scores s where s.department = d.key))
      order by d.position, lower(d.name))
    from public.departments d), '[]'::jsonb);
end $$;
revoke all on function public.departments_list() from public, anon;
grant execute on function public.departments_list() to authenticated;

-- END OF DEPARTMENTS IN RECORDS ----------------------------------------------

select public.functions_tidy();
