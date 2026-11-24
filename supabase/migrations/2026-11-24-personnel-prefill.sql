-- ===========================================================================
-- PERSONNEL PREFILLED FROM THE OVERVIEW (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: the employee record asked again for what a
-- colleague's Overview already holds. Its Email and Mobile or WhatsApp now
-- start filled in from the colleague's sign-in email and namecard mobile;
-- the person may change either, and a value saved in the record wins.
-- Full Name as per NRIC is never prefilled from the portal name.
--
-- WHAT IT CHANGES
--   * `personnel_json` answers `prefill`: the record's own colleague's
--     `team_members.email` and `team_members.mobile`, nothing else, each
--     left out where it is not held. `personnel_get` (the team, behind
--     `team.personnel`) and `personnel_mine` (the colleague's own, behind
--     the fresh proof) read it as before; every refusal of theirs stands.
--     Nothing is written: the record's data is unchanged until a save.
--
-- ORDER: this file after the page's deploy or before it alike: the page
-- reads `prefill` only where it is answered, and an old page ignores it.
-- Safe to run twice.
-- ROLLBACK: run PERSONNEL RECORDS' `personnel_json` again.
-- ===========================================================================

-- PERSONNEL PREFILLED FROM THE OVERVIEW -------------------------------------

/* One record as the reader may read it: never a salary, never a file's key;
   with what the colleague's Overview already holds for the form to start
   from (prefilled, never saved by this read). */
create or replace function public.personnel_json(p_member uuid, p_team boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.personnel_records; t public.team_members; s public.personnel_salaries;
begin
  select * into t from public.team_members where id = p_member;
  select * into r from public.personnel_records where team_member_id = p_member;
  select * into s from public.personnel_salaries where team_member_id = p_member;
  return jsonb_build_object('ok', true, 'member', p_member, 'name', t.name,
    'data', coalesce(r.data, '{}'::jsonb),
    'prefill', jsonb_strip_nulls(jsonb_build_object(
      'email', nullif(btrim(coalesce(t.email, '')), ''),
      'mobile', nullif(btrim(coalesce(t.mobile, '')), ''))),
    'files', coalesce((select jsonb_object_agg(k, jsonb_build_object('at', v ->> 'at', 'type', v ->> 'type'))
                         from jsonb_each(coalesce(r.files, '{}'::jsonb)) x(k, v)), '{}'::jsonb),
    'consent_at', r.consent_at, 'declared_name', r.declared_name, 'declared_at', r.declared_at,
    'requested_at', r.requested_at, 'updated_at', r.updated_at,
    'updated_by', (select u.name from public.team_members u where u.id = r.updated_by),
    'join_date', r.join_date, 'employee_status', r.employee_status, 'employee_type', r.employee_type,
    'probation_months', r.probation_months, 'contract_end', r.contract_end,
    'confirm_date', public.personnel_confirm_date(r.join_date, r.probation_months),
    'superior_id', case when p_team then r.superior_id end,
    'salary_set', case when p_team then (s.probation is not null or s.confirmed is not null) end,
    'missing', to_jsonb(public.personnel_missing(coalesce(r.data, '{}'::jsonb))));
end $$;
revoke all on function public.personnel_json(uuid, boolean) from public, anon, authenticated;

-- END OF PERSONNEL PREFILLED FROM THE OVERVIEW ------------------------------

select public.functions_tidy();
