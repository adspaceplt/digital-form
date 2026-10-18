-- ===========================================================================
-- ONE REPEAT NEVER STOPS THE OTHERS — a repeating task that cannot be made
-- is kept as an error on its rule, and every other rule is made as usual.
-- 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/ops.js compares
-- the two.
--
-- WHAT CHANGED (second audit, item 15)
--   ops_generate_recurring returned at the first refusal, and a raised
--   error ended the whole call, so one rule that could no longer make its
--   task (a month gone, an owner who left) stopped every rule after it for
--   that colleague every night, and nobody was told.
--   * Each make runs in its own block: a refusal or an error undoes that
--     attempt alone, is kept on the rule (ops_recurring_rules.last_error,
--     last_error_at; cleared by the next task the rule makes), leaves that
--     rule's other dates for the next run, and the run goes on to the next
--     rule. The answer adds `failed` and `errors` (rule, date, words).
--   * jobs_watch counts the active rules that failed in the last 24 hours
--     in the admins' morning notice ("2 repeating tasks could not be made").
--
-- ROLLBACK
--   Run the ops_generate_recurring definition of the DAYS ON MALAYSIA'S
--   CALENDAR section and the jobs_watch definition of SCHEDULED JOBS
--   WATCHED in supabase/schema.sql again; the two columns may stay.
-- ===========================================================================

alter table public.ops_recurring_rules add column if not exists last_error text;
alter table public.ops_recurring_rules add column if not exists last_error_at timestamptz;

create or replace function public.ops_generate_recurring(
  p_period text, p_rules uuid[] default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  r     public.ops_recurring_rules;
  src   public.ops_tasks;
  made  integer := 0;
  skip  integer := 0;
  key   text;
  first_day date;
  last_day date;
  anchor date;
  d     date;
  stepd integer;
  one   jsonb;
  wk    integer;
  held  integer := 0;
  ccl   uuid;
  mon   public.ops_engagements;
  errs  jsonb := '[]'::jsonb;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  first_day := (p_period || '-01')::date;
  last_day := (first_day + interval '1 month' - interval '1 day')::date;

  for r in select * from public.ops_recurring_rules
            where active and (p_rules is null or id = any (p_rules))
              and (source_task_id is null or public.ops_may_see_task(source_task_id)) loop
    if r.source_task_id is not null then
      select * into src from public.ops_tasks where id = r.source_task_id;
    else
      src := null;
    end if;

    /* A client's repeats wait for the client's month: one that exists, is
       open and has its content meeting set or marked not applicable. Until
       then the rule is held and counted, and a later run makes them. */
    ccl := case when src.id is not null then case when src.scope = 'client' then src.client_id end
                else r.client_id end;
    mon := null;
    if ccl is not null then
      select * into mon from public.ops_engagements x where x.client_id = ccl and x.period = p_period;
      if mon.id is null or mon.status in ('completed', 'cancelled')
         or (mon.meeting_at is null and not mon.meeting_na) then
        held := held + 1;
        continue;
      end if;
    end if;

    /* The dates this rule falls on inside the month. */
    if r.frequency = 'monthly' then
      d := first_day + (least(coalesce(r.day_of_month,
              case when src.publish_at is not null then extract(day from src.publish_at)::integer else 1 end),
              extract(day from last_day)::integer) - 1);
      stepd := null;
    else
      stepd := case when r.frequency = 'weekly' then 7 else greatest(1, coalesce(r.interval_days, 7)) end;
      anchor := coalesce(src.publish_at::date, (r.created_at at time zone 'Asia/Kuala_Lumpur')::date, first_day);
      if anchor > first_day then d := anchor;
      else d := anchor + ((((first_day - anchor) + stepd - 1) / stepd) * stepd); end if;
    end if;

    while d is not null and d <= last_day loop
      if d >= first_day
         /* The task a rule copies is its first occurrence: nothing on or
            before its day is made again. */
         and (src.id is null or d > coalesce(src.publish_at::date, (r.created_at at time zone 'Asia/Kuala_Lumpur')::date))
         and (r.ends_on is null or d <= r.ends_on)
         and (r.max_count is null or r.generated_count < r.max_count) then
        key := 'recur:' || r.id::text || ':' || to_char(d, 'YYYY-MM-DD');
        /* Made once is made: a copy since deleted stays deleted, and a rule
           set again on the same task makes none of its dates twice. */
        if exists (select 1 from public.ops_tasks where idem_key = key)
           or exists (select 1 from public.ops_recurring_made x
                       where x.on_date = d
                         and (x.rule_id = r.id
                              or (r.source_task_id is not null and x.source_task_id = r.source_task_id))) then
          skip := skip + 1;
        else
          wk := coalesce(r.code_week, least(5, ((extract(day from d)::integer - 1) / 7) + 1));
          /* One rule that cannot make its task never stops the others: the
             attempt is undone, its error kept on the rule and answered, and
             the run goes on to the next rule. */
          one := null;
          begin
            if src.id is not null then
              one := public.ops_duplicate_task(src.id, jsonb_build_object(
                'keep_desc', true, 'copy_dates', false, 'copy_assignees', true,
                'publish_at', d::timestamptz, 'code_period', p_period, 'code_week', wk,
                'engagement_id', mon.id), key);
            else
              one := public.ops_create_task(jsonb_build_object(
                'scope', case when r.client_id is null then 'internal' else 'client' end,
                'client_id', r.client_id, 'template_id', r.template_id,
                'title', r.name || ' — ' || p_period, 'content_desc', r.name,
                'owner_id', r.owner_id, 'publish_at', d::timestamptz,
                'code_period', p_period, 'code_week', wk, 'engagement_id', mon.id), key);
            end if;
            if one ? 'error' then raise exception using message = 'repeat-refused'; end if;
          exception when others then
            if one is null or not (one ? 'error') then one := jsonb_build_object('error', sqlerrm); end if;
          end;
          if one ? 'error' then
            errs := errs || jsonb_build_array(jsonb_build_object('rule', r.id, 'on', d, 'error', one ->> 'error'));
            update public.ops_recurring_rules
               set last_error = left(one ->> 'error', 500), last_error_at = now()
             where id = r.id;
            exit;
          end if;
          made := made + 1;
          insert into public.ops_recurring_made (rule_id, source_task_id, on_date)
          values (r.id, r.source_task_id, d) on conflict do nothing;
          update public.ops_recurring_rules
             set generated_count = generated_count + 1, last_generated_period = p_period, updated_at = now(),
                 last_error = null, last_error_at = null
           where id = r.id;
          r.generated_count := r.generated_count + 1;
        end if;
      end if;
      exit when stepd is null;
      d := d + stepd;
    end loop;
  end loop;
  return jsonb_build_object('created', made, 'skipped', skip, 'held', held, 'period', p_period,
    'failed', jsonb_array_length(errs), 'errors', errs);
end $$;

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
  v_rules integer := 0;
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

  /* A repeat rule that could not make its task (ops_generate_recurring
     keeps the error on the rule and goes on to the next). */
  select count(*)::int into v_rules from public.ops_recurring_rules x
   where x.active and x.last_error_at >= p_now - interval '24 hours' and x.last_error_at < p_now;

  if v_runs = 0 and v_sweeps = 0 and not v_quiet and v_rules = 0 then
    return jsonb_build_object('failed', 0, 'told', 0);
  end if;
  v_words := concat_ws('; ',
    nullif((select string_agg((e ->> 'job') || ' failed ' || (e ->> 'failed') ||
                              case when (e ->> 'failed')::int = 1 then ' time' else ' times' end, '; ')
              from jsonb_array_elements(v_jobs) e), ''),
    case when v_sweeps > 0 then 'the S3 report was filed as failed' end,
    case when v_quiet then 'the S3 report did not arrive' end,
    case when v_rules > 0 then v_rules || case when v_rules = 1 then ' repeating task could' else ' repeating tasks could' end
                               || ' not be made' end) || '.';
  insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
  select t.id, 'jobs.failed', 'Scheduled jobs failed in the last 24 hours',
         v_words, 'jobs.failed.' || v_day || '.' || t.id
    from public.team_members t
   where t.active and t.is_admin
  on conflict (dedupe_key) do nothing;
  get diagnostics v_told = row_count;
  return jsonb_build_object('failed', v_runs + v_sweeps + case when v_quiet then 1 else 0 end + v_rules,
    'jobs', v_jobs, 'sweeps', v_sweeps, 'sweep_missing', v_quiet, 'repeats', v_rules, 'told', v_told);
end $$;

grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;
revoke all on function public.jobs_watch(timestamptz) from public, anon, authenticated;

-- END OF ONE REPEAT NEVER STOPS THE OTHERS ----------------------------------

select public.functions_tidy();
