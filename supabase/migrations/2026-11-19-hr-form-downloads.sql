-- ===========================================================================
-- HR FORM DOWNLOADS (2026-11-19)
-- ===========================================================================
-- WHY: the user, 2026-11-19: the Employee Record Form, Interview Sheet,
-- Entry and Exit checklist and Welcome Kit, once recorded in the portal,
-- downloaded as PDFs; "admins and requires verification code to download".
--
-- WHAT IT CHANGES
--   * `hr_form_pass(p_kind, p_name)`: asked before a form is drawn in the
--     browser. An admin alone (`denied`, `not-team`), a known kind
--     (`bad-kind`: record, sheet, onboarding, kit), a session that proved an
--     emailed code within fifteen minutes (`perf_code_fresh`, else
--     `code-needed` with the sign-in address the page sends the code to).
--     Each download filed `team.changed` under whom it is about.
--   * Nothing is stored: the form is drawn from what the admin already reads.
--
-- ROLLBACK: drop function public.hr_form_pass(text, text);
-- Safe to run twice.
-- ===========================================================================

create or replace function public.hr_form_pass(p_kind text, p_name text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); v_form text;
begin
  if me.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not coalesce(me.is_admin, false) then return jsonb_build_object('error', 'denied'); end if;
  v_form := case p_kind when 'record' then 'Employee Record Form' when 'sheet' then 'Interview Sheet'
    when 'onboarding' then 'Onboarding Checklist' when 'kit' then 'Welcome Kit' end;
  if v_form is null then return jsonb_build_object('error', 'bad-kind'); end if;
  if not public.perf_code_fresh() then return jsonb_build_object('error', 'code-needed', 'email', me.email); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', left(coalesce(nullif(btrim(p_name), ''), v_form), 120), 'Downloaded as PDF: ' || v_form);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hr_form_pass(text, text) from public, anon;
grant execute on function public.hr_form_pass(text, text) to authenticated;

-- END OF HR FORM DOWNLOADS ---------------------------------------------------

select public.functions_tidy();
