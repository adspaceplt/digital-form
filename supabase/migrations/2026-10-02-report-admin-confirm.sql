-- ===========================================================================
-- REPORT ADMIN CONFIRM — an admin may confirm a report they submitted.
-- 2026-10-02. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   `sm_report_confirm(p_id)`: a manager still never confirms their own
--   report (`self-confirm`), but an admin (`team_members.is_admin`, or the
--   older `role = 'admin'`) may: the team's hierarchy ends with them, and a
--   report waiting on nobody else is otherwise stuck (the user, 2026-10-02).
--   The page asks first and the activity record files it under their name.
--
-- ROLLBACK
--   Re-run sm_report_confirm from 2026-09-25-report-builder.sql.
-- ===========================================================================

create or replace function public.sm_report_confirm(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'review' then return jsonb_build_object('error', 'not-in-review', 'status', r.status); end if;
  if r.submitted_by = me.id and not (coalesce(me.is_admin, false) or me.role = 'admin') then
    return jsonb_build_object('error', 'self-confirm');
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'confirmed', confirmed_by = me.id, confirmed_at = now() where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.confirmed');
  return jsonb_build_object('ok', true, 'status', 'confirmed');
end $$;
grant execute on function public.sm_report_confirm(uuid) to authenticated;

-- END OF REPORT ADMIN CONFIRM -------------------------------------------------
