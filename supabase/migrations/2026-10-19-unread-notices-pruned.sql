-- ===========================================================================
-- UNREAD NOTICES PRUNED — jobs_prune also removes a notice left unread for
-- 180 days (2026-10-19)
-- ===========================================================================
-- WHY (audit 2026-10-18/19, item 4): `jobs_prune` removed only notices read
-- over 90 days ago, so one never opened was kept for good.
--
-- WHAT IT CHANGES
--   * It also removes a notice unread for over 180 days. A colleague's
--     notice (`notice_id`) still stays, read or not: Notices reads its
--     copies. Job history is pruned as before.
--
-- ORDER: this file in the SQL Editor as one run (the connector holds a
-- statement holding `delete`). Safe to run twice. Rollback: run jobs_prune
-- from SCHEDULED JOBS WATCHED again.
-- ===========================================================================

create or replace function public.jobs_prune(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_runs integer := 0; v_notes integer := 0;
begin
  if to_regclass('cron.job_run_details') is not null then
    delete from cron.job_run_details d where d.end_time < p_now - interval '14 days';
    get diagnostics v_runs = row_count;
  end if;
  /* A colleague's notice (notice_id) stays: Notices read its copies. */
  delete from public.ops_notifications n
   where n.notice_id is null
     and ((n.read_at is not null and n.created_at < p_now - interval '90 days')
       or (n.read_at is null and n.created_at < p_now - interval '180 days'));
  get diagnostics v_notes = row_count;
  return jsonb_build_object('job_runs', v_runs, 'notices', v_notes);
end $$;
revoke all on function public.jobs_prune(timestamptz) from public, anon, authenticated;
-- END OF UNREAD NOTICES PRUNED ----------------------------------------------
select public.functions_tidy();
