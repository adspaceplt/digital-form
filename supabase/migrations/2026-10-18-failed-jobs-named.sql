-- ===========================================================================
-- FAILED JOBS NAMED — the admins' morning notice names each repeating task
-- that could not be made, counts the rules nobody can make, and reports a
-- failed morning check of its own. 2026-10-18. Safe to run twice. Rollback
-- at the foot. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/ops.js compares the two.
--
-- WHAT CHANGED (review of 2026-10-18, item 15)
--   * ops_recurring_daily passed in only the rules an active colleague
--     could make, so a rule whose creator and task owner had both left was
--     never made and never counted; and ops_generate_recurring skips a rule
--     whose task its colleague can no longer see. Both are now kept as the
--     rule's error (last_error, last_error_at) on the morning run, so the
--     notice counts them. An error from an earlier run that did not recur
--     is cleared once the run has passed it.
--   * jobs_watch names the failing rules (client, else Internal; the rule or
--     task's name; its task number), five at most then a count, and the
--     notice opens the first one's task. It reads back to its own last
--     successful run (at least 24 hours, at most seven days), so a morning
--     whose check failed is reported by the next, which says so. With no
--     active admin, the active colleagues at Team Full Access are told.
--   * The task card's Repeats line shows the rule's error (js/ops.js).
--
-- ROLLBACK
--   Run ops_recurring_daily as PIECES AND REPEATS stated it, and jobs_watch
--   as ONE REPEAT NEVER STOPS THE OTHERS stated it.
-- ===========================================================================

/* The morning run. Each rule is made as the colleague who set it, else its
   task's owner, with that colleague's own access. A rule neither of them can
   make, or whose task its colleague can no longer see, is kept as an error
   on the rule for the morning notice. Nobody calls this but the schedule. */
create or replace function public.ops_recurring_daily()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a   record;
  pp  text;
  out jsonb := '[]'::jsonb;
  was text := current_setting('request.jwt.claims', true);
begin
  update public.ops_recurring_rules r
     set last_error = 'No active colleague can make it: whoever set it and the owner of its task have left.',
         last_error_at = now()
   where r.active
     and not exists (
       select 1 from public.team_members tm
        where tm.active and tm.email is not null
          and tm.id in (r.created_by,
                        (select x.team_member_id from public.ops_task_assignees x
                          where x.task_id = r.source_task_id and x.responsibility = 'owner' and x.ended_at is null
                          limit 1)));
  for a in
    select actor.email, array_agg(r.id order by r.id) as rules
      from public.ops_recurring_rules r
      left join public.ops_tasks s on s.id = r.source_task_id
      cross join lateral (
        select tm.email from public.team_members tm
         where tm.active and tm.email is not null
           and tm.id in (r.created_by,
                         (select x.team_member_id from public.ops_task_assignees x
                           where x.task_id = s.id and x.responsibility = 'owner' and x.ended_at is null
                           limit 1))
         order by (tm.id = r.created_by) desc nulls last
         limit 1) actor
     where r.active
     group by actor.email
  loop
    perform set_config('request.jwt.claims',
      jsonb_build_object('email', a.email, 'role', 'authenticated')::text, true);
    update public.ops_recurring_rules r
       set last_error = 'Its colleague can no longer see the task it copies.', last_error_at = now()
     where r.id = any (a.rules) and r.source_task_id is not null
       and not public.ops_may_see_task(r.source_task_id);
    foreach pp in array public.ops_recurring_periods() loop
      out := out || jsonb_build_object('period', pp, 'rules', to_jsonb(a.rules),
                                       'result', public.ops_generate_recurring(pp, a.rules));
    end loop;
    update public.ops_recurring_rules r
       set last_error = null, last_error_at = null
     where r.id = any (a.rules) and r.last_error_at < now();
  end loop;
  perform set_config('request.jwt.claims', coalesce(was, ''), true);
  return out;
end $$;
revoke all on function public.ops_recurring_daily() from public, anon, authenticated;

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

  if v_runs = 0 and v_sweeps = 0 and not v_quiet and v_rules = 0 then
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
  return jsonb_build_object('failed', v_runs + v_sweeps + case when v_quiet then 1 else 0 end + v_rules,
    'jobs', v_jobs, 'self', v_self, 'since', v_since, 'sweeps', v_sweeps, 'sweep_missing', v_quiet,
    'repeats', v_rules, 'told', v_told);
end $$;
revoke all on function public.jobs_watch(timestamptz) from public, anon, authenticated;

-- END OF FAILED JOBS NAMED ---------------------------------------------------

select public.functions_tidy();
