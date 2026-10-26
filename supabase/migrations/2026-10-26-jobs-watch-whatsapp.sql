-- ===========================================================================
-- JOBS WATCH WHATSAPP — the admins' morning notice counts the automatic
-- WhatsApp messages that failed (2026-10-26)
-- ===========================================================================
-- WHY (the whole-repo audit of 2026-10-26, finding 10): the reminders and a
-- creator's booking go out on WhatsApp by themselves. When the token
-- expires, or Meta refuses a template, every one fails and is filed Failed
-- in the WhatsApp section, which nobody reads every day; the morning notice
-- of failed jobs said nothing.
--
-- WHAT IT CHANGES
--   `jobs_watch` (restated whole from FAILED JOBS NAMED) also counts the
--   messages queued by the portal itself (`created_by` 'system') that
--   failed since its last good run, by Meta's word (`failed_at`) or by the
--   send (`state` failed), and names them in the one notice.
--
-- ORDER: this file (connector). No page reads it.
--
-- ROLLBACK: run jobs_watch from FAILED JOBS NAMED again.
-- ===========================================================================

create or replace function public.jobs_watch(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_jobs jsonb := '[]'::jsonb;
  v_runs integer := 0;
  v_self integer := 0;
  v_sweeps integer := 0;
  v_quiet boolean := false;
  v_words text;
  v_day text := to_char(p_now at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM-DD');
  v_told integer := 0;
  v_rules integer := 0;
  v_wa integer := 0;
  v_names text;
  v_task uuid;
  v_since timestamptz := p_now - interval '24 hours';
  v_last timestamptz;
begin
  if to_regclass('cron.job_run_details') is not null then
    /* Back to this check's own last successful run, so a morning whose
       check failed is reported by the next: at least 24 hours, at most
       seven days. */
    select max(d.start_time) into v_last
      from cron.job_run_details d join cron.job j on j.jobid = d.jobid
     where j.jobname = 'jobs-watch' and d.status = 'succeeded' and d.start_time < p_now - interval '1 minute';
    v_since := greatest(p_now - interval '7 days', least(p_now - interval '24 hours', coalesce(v_last, p_now - interval '24 hours')));
    select coalesce(jsonb_agg(jsonb_build_object('job', x.name, 'failed', x.n) order by x.n desc, x.name), '[]'::jsonb),
           coalesce(sum(x.n), 0)::int
      into v_jobs, v_runs
      from (select coalesce(j.jobname, 'job ' || d.jobid) as name, count(*)::int as n
              from cron.job_run_details d
              left join cron.job j on j.jobid = d.jobid
             where d.status = 'failed' and d.start_time >= v_since and d.start_time < p_now
             group by 1) x;
    select coalesce(sum((e ->> 'failed')::int), 0)::int into v_self
      from jsonb_array_elements(v_jobs) e where e ->> 'job' = 'jobs-watch';
    /* The S3 report's job posts to its edge function and succeeds either
       way: a report that never arrived is a failure too. */
    v_quiet := exists (select 1 from cron.job j where j.jobname = 's3-sweep-daily' and j.active)
           and not exists (select 1 from public.s3_sweeps s where s.ran_at >= p_now - interval '26 hours' and s.ran_at < p_now);
  end if;
  select count(*)::int into v_sweeps from public.s3_sweeps s
   where s.mode = 'failed' and s.ran_at >= v_since and s.ran_at < p_now;
  /* The WhatsApp messages the portal sends by itself (a reminder, a
     booking): one Meta refused, or that could not be sent at all. An
     expired token fails every one, and nobody sees it otherwise. */
  select count(*)::int into v_wa
    from (select coalesce(o.failed_at, case when o.state = 'failed' then coalesce(o.sent_at, o.claimed_at, o.created_at) end) as at
            from public.wa_outbox o where o.created_by = 'system') w
   where w.at >= v_since and w.at < p_now;

  /* Each repeat rule that could not make its task, named: its client (else
     Internal), the rule or its task, and the task number. */
  select count(*)::int,
         string_agg(w.label, '; ' order by w.at) filter (where w.n <= 5),
         (array_agg(w.task order by w.at) filter (where w.task is not null))[1]
    into v_rules, v_names, v_task
    from (select coalesce(c.name, 'Internal') || ': ' || coalesce(nullif(btrim(x.name), ''), public.ops_title(t), 'Repeating task')
                 || coalesce(' (' || public.ops_serial(t.task_no) || ')', '') as label,
                 x.last_error_at as at, t.id as task,
                 row_number() over (order by x.last_error_at) as n
            from public.ops_recurring_rules x
            left join public.ops_tasks t on t.id = x.source_task_id
            left join public.clients c on c.id = coalesce(case when t.id is not null then case when t.scope = 'client' then t.client_id end
                                                              else x.client_id end, x.client_id)
           where x.active and x.last_error_at >= v_since and x.last_error_at < p_now) w;

  if v_runs = 0 and v_sweeps = 0 and not v_quiet and v_rules = 0 and v_wa = 0 then
    return jsonb_build_object('failed', 0, 'told', 0);
  end if;
  v_words := concat_ws('; ',
    case when v_self > 0 then 'the morning check of scheduled jobs failed ' || v_self ||
                              case when v_self = 1 then ' time' else ' times' end end,
    nullif((select string_agg((e ->> 'job') || ' failed ' || (e ->> 'failed') ||
                              case when (e ->> 'failed')::int = 1 then ' time' else ' times' end, '; ')
              from jsonb_array_elements(v_jobs) e where e ->> 'job' <> 'jobs-watch'), ''),
    case when v_sweeps > 0 then 'the S3 report was filed as failed' end,
    case when v_quiet then 'the S3 report did not arrive' end,
    case when v_wa > 0 then v_wa || case when v_wa = 1 then ' automatic WhatsApp message' else ' automatic WhatsApp messages' end
                            || ' failed to send' end,
    case when v_rules > 0 then v_rules || case when v_rules = 1 then ' repeating task could' else ' repeating tasks could' end
                               || ' not be made: ' || v_names
                               || case when v_rules > 5 then ' and ' || (v_rules - 5) || ' more' else '' end end) || '.';
  insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
  select t.id, v_task, 'jobs.failed',
         case when v_since < p_now - interval '25 hours' then 'Scheduled jobs failed since the last check'
              else 'Scheduled jobs failed in the last 24 hours' end,
         v_words, 'jobs.failed.' || v_day || '.' || t.id
    from public.team_members t
   where t.active
     and (t.is_admin
          or (not exists (select 1 from public.team_members o where o.active and o.is_admin)
              and public.level_rank(t.access ->> 'team') >= 3))
  on conflict (dedupe_key) do nothing;
  get diagnostics v_told = row_count;
  return jsonb_build_object('failed', v_runs + v_sweeps + case when v_quiet then 1 else 0 end + v_rules + v_wa, 'whatsapp', v_wa,
    'jobs', v_jobs, 'self', v_self, 'since', v_since, 'sweeps', v_sweeps, 'sweep_missing', v_quiet,
    'repeats', v_rules, 'told', v_told);
end $$;
revoke all on function public.jobs_watch(timestamptz) from public, anon, authenticated;

-- END OF JOBS WATCH WHATSAPP --------------------------------------------------

select public.functions_tidy();
