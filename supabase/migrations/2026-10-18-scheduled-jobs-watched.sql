-- ===========================================================================
-- SCHEDULED JOBS WATCHED — a scheduled job that fails is told to the admins
-- the next morning, and the job history and old read notices are pruned.
-- 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED (second audit, item 4)
--   Nothing read cron.job_run_details, and the kicks and notification
--   fan-outs swallow their own errors by design (a notice never fails the
--   write that caused it), so a reminder, a repeat or the S3 report that
--   stopped working stopped silently.
--   * jobs_watch(p_now) (pg_cron `jobs-watch`, 08:20 MYT daily) counts the
--     scheduled runs that failed in the 24 hours before p_now, by job, and
--     the S3 reports filed as failed (s3_sweeps mode `failed`), and names an
--     S3 report that did not arrive at all in 26 hours while its job is on
--     (the job posts to the edge function, so its run succeeds whether or
--     not the function answers). Where anything failed, each active admin
--     is told once that day (kind `jobs.failed`, the bell and a push; never
--     WhatsApp), the jobs and their counts in the words.
--   * jobs_prune(p_now) (pg_cron `jobs-prune`, 03:40 MYT daily) removes job
--     history older than 14 days and notices read more than 90 days ago,
--     never a colleague's notice (Notices count its copies as Read by).
--   Neither is any page's to call. On a database without pg_cron both
--   functions leave the job history alone and no job is scheduled.
--
-- ROLLBACK
--   select cron.unschedule(jobid) from cron.job where jobname in ('jobs-watch', 'jobs-prune');
--   drop function if exists public.jobs_watch(timestamptz);
--   drop function if exists public.jobs_prune(timestamptz);
-- ===========================================================================

create or replace function public.jobs_watch(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_jobs jsonb := '[]'::jsonb;
  v_runs integer := 0;
  v_sweeps integer := 0;
  v_quiet boolean := false;
  v_words text;
  v_day text := to_char(p_now at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM-DD');
  v_told integer := 0;
begin
  if to_regclass('cron.job_run_details') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('job', x.name, 'failed', x.n) order by x.n desc, x.name), '[]'::jsonb),
           coalesce(sum(x.n), 0)::int
      into v_jobs, v_runs
      from (select coalesce(j.jobname, 'job ' || d.jobid) as name, count(*)::int as n
              from cron.job_run_details d
              left join cron.job j on j.jobid = d.jobid
             where d.status = 'failed' and d.start_time >= p_now - interval '24 hours' and d.start_time < p_now
             group by 1) x;
    /* The S3 report's job posts to its edge function and succeeds either
       way: a report that never arrived is a failure too. */
    v_quiet := exists (select 1 from cron.job j where j.jobname = 's3-sweep-daily' and j.active)
           and not exists (select 1 from public.s3_sweeps s where s.ran_at >= p_now - interval '26 hours' and s.ran_at < p_now);
  end if;
  select count(*)::int into v_sweeps from public.s3_sweeps s
   where s.mode = 'failed' and s.ran_at >= p_now - interval '24 hours' and s.ran_at < p_now;

  if v_runs = 0 and v_sweeps = 0 and not v_quiet then
    return jsonb_build_object('failed', 0, 'told', 0);
  end if;
  v_words := concat_ws('; ',
    nullif((select string_agg((e ->> 'job') || ' failed ' || (e ->> 'failed') ||
                              case when (e ->> 'failed')::int = 1 then ' time' else ' times' end, '; ')
              from jsonb_array_elements(v_jobs) e), ''),
    case when v_sweeps > 0 then 'the S3 report was filed as failed' end,
    case when v_quiet then 'the S3 report did not arrive' end) || '.';
  insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
  select t.id, 'jobs.failed', 'Scheduled jobs failed in the last 24 hours',
         v_words, 'jobs.failed.' || v_day || '.' || t.id
    from public.team_members t
   where t.active and t.is_admin
  on conflict (dedupe_key) do nothing;
  get diagnostics v_told = row_count;
  return jsonb_build_object('failed', v_runs + v_sweeps + case when v_quiet then 1 else 0 end,
    'jobs', v_jobs, 'sweeps', v_sweeps, 'sweep_missing', v_quiet, 'told', v_told);
end $$;
revoke all on function public.jobs_watch(timestamptz) from public, anon, authenticated;

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
   where n.read_at is not null and n.created_at < p_now - interval '90 days' and n.notice_id is null;
  get diagnostics v_notes = row_count;
  return jsonb_build_object('job_runs', v_runs, 'notices', v_notes);
end $$;
revoke all on function public.jobs_prune(timestamptz) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: scheduled jobs are not watched until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname in ('jobs-watch', 'jobs-prune');
  perform cron.schedule('jobs-watch', '20 0 * * *', 'select public.jobs_watch()');
  perform cron.schedule('jobs-prune', '40 19 * * *', 'select public.jobs_prune()');
end $$;

-- END OF SCHEDULED JOBS WATCHED ---------------------------------------------

select public.functions_tidy();
