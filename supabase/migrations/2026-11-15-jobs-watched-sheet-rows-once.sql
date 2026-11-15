-- ===========================================================================
-- JOBS WATCHED, SHEET ROWS ADDED ONCE (2026-11-15)
-- ===========================================================================
-- WHY: the whole-portal audit of 2026-11-15 (items 12 and 13).
--
-- WHAT IT CHANGES
--   * `job_beats` (RLS on, no policy, no grant): a background run that only
--     wakes an edge function writes when it ends, through `job_beat` (the
--     service role's). bukku-sync's nightly read writes `bukku-nightly`.
--   * `jobs_watch` tells the admins of a nightly Bukku read that did not
--     arrive in 26 hours or that failed, and of creator emails that failed
--     or were not confirmed.
--   * The creator payments sheet: a row Google may have taken (an append
--     that timed out or met a 5xx, or a row left at Sending) is marked not
--     confirmed and never tried again by itself, nor queued afresh when the
--     sheet's setting is saved, so the bank details are never added twice.
--
-- ORDER: this file, then the functions (bukku-sync, creator-mail). A function
-- served before this file writes no beat: the morning notice then reads "the
-- nightly Bukku read did not arrive" until the function is deployed.
-- Safe to run twice.
--
-- ROLLBACK: restate `mail_sweep`, `creator_sheet_done`, `creator_sheet_set`
-- and `jobs_watch` from their bands before this one, then
-- drop function public.job_beat(text, boolean, text); drop table public.job_beats;
-- ===========================================================================

-- JOBS WATCHED, SHEET ROWS ADDED ONCE ------------------------------------------

create table if not exists public.job_beats (
  job    text primary key,
  ran_at timestamptz not null default now(),
  ok     boolean not null default true,
  detail text
);
alter table public.job_beats enable row level security;
revoke all on public.job_beats from public, anon, authenticated;

create or replace function public.job_beat(p_job text, p_ok boolean, p_detail text)
returns void
language sql volatile security definer set search_path = public as $$
  insert into public.job_beats (job, ran_at, ok, detail)
  values (left(p_job, 60), now(), coalesce(p_ok, false), left(nullif(p_detail, ''), 300))
  on conflict (job) do update set ran_at = excluded.ran_at, ok = excluded.ok, detail = excluded.detail;
$$;
revoke all on function public.job_beat(text, boolean, text) from public, anon, authenticated;
grant execute on function public.job_beat(text, boolean, text) to service_role;

create or replace function public.mail_sweep()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  n integer := 0;
  k integer;
begin
  update public.invoice_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.supplier_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.client_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.team_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.creator_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.claimed_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  -- A row left at Sending may stand in the sheet: never tried again by itself
  -- (audit 2026-11-15), so the bank details are never added twice.
  update public.creator_sheet_rows x set status = 'failed', tries = 5,
         error = 'Not confirmed. Check the sheet before adding the row again.'
   where x.status = 'sending' and x.claimed_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_sweep() from public, anon, authenticated;

create or replace function public.creator_sheet_done(p_id uuid, p_ok boolean, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
begin
  update public.creator_sheet_rows x set status = case when p_ok then 'added' else 'failed' end,
    error = case when p_ok then null else left(nullif(p_error, ''), 480) end,
    -- one Google may have taken (a timeout, a 5xx) is never tried again by itself
    tries = case when not p_ok and p_error like 'Not confirmed%' then 5 else x.tries end,
    added_at = case when p_ok then now() end
   where x.id = p_id and x.status = 'sending';
  return jsonb_build_object('ok', found);
end $$;
revoke all on function public.creator_sheet_done(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.creator_sheet_done(uuid, boolean, text) to service_role;

create or replace function public.creator_sheet_set(p_on boolean, p_sheet text, p_tab text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s  public.creator_sheet_settings;
  v_id text := nullif(btrim(coalesce(p_sheet, '')), '');
  v_tab text := nullif(btrim(coalesce(p_tab, '')), '');
  v_moved text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_id ~ '/spreadsheets/d/' then v_id := substring(v_id from '/spreadsheets/d/([A-Za-z0-9_-]+)'); end if;
  if v_id is not null and v_id !~ '^[A-Za-z0-9_-]{20,100}$' then return jsonb_build_object('error', 'bad-sheet'); end if;
  if coalesce(p_on, false) and v_id is null then return jsonb_build_object('error', 'bad-sheet'); end if;
  if v_tab is not null and length(v_tab) > 100 then return jsonb_build_object('error', 'bad-tab'); end if;
  select * into s from public.creator_sheet_settings where id = 1 for update;
  if s.on_send is distinct from coalesce(p_on, false) then
    v_moved := v_moved || ('Add rows: ' || case when s.on_send then 'On → Off' else 'Off → On' end);
  end if;
  if s.spreadsheet_id is distinct from v_id then v_moved := v_moved || 'Google Sheets link changed'::text; end if;
  if s.tab is distinct from v_tab then
    v_moved := v_moved || ('Tab: ' || coalesce(s.tab, 'First tab') || ' → ' || coalesce(v_tab, 'First tab'));
  end if;
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true); end if;
  update public.creator_sheet_settings set on_send = coalesce(p_on, false), spreadsheet_id = v_id, tab = v_tab,
    updated_at = now(), updated_by = me.id where id = 1;
  -- The sheet corrected: every row it refused is tried afresh, never one
  -- Google may have taken (audit 2026-11-15).
  update public.creator_sheet_rows x set status = 'queued', tries = 0, error = null
   where x.status = 'failed' and coalesce(x.error, '') not like 'Not confirmed%';
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Creator payments sheet', array_to_string(v_moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_sheet_set(boolean, text, text) from public, anon;
grant execute on function public.creator_sheet_set(boolean, text, text) to authenticated;

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
  v_agent integer := 0;
  v_mail integer := 0;
  v_bukku text;
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
  /* What colleagues scheduled through the Assistant that could not be done
     (each colleague is told of their own at the run). */
  select count(*)::int into v_agent from public.agent_schedules s
   where s.state = 'failed' and s.ran_at >= v_since and s.ran_at < p_now;

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

  /* The creator emails the portal sends by itself that failed or were not
     confirmed, and the nightly Bukku read: its job only wakes an edge
     function and succeeds either way, so the run writes a beat when it ends
     (`job_beats`), and none in 26 hours, or one that failed, is told
     (audit 2026-11-15). */
  select count(*)::int into v_mail from public.creator_emails e
   where e.status in ('failed', 'unknown', 'bounced') and e.created_at >= v_since and e.created_at < p_now;
  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job j where j.jobname = 'bukku-read-nightly' and j.active) then
    select case when b.job is null or b.ran_at < p_now - interval '26 hours' then 'the nightly read from Bukku did not run'
                when not b.ok then 'the nightly read from Bukku failed: ' || coalesce(b.detail, 'no reason given') end
      into v_bukku
      from (select 1) one left join public.job_beats b on b.job = 'bukku-nightly';
    end if;
  end if;
  if v_runs = 0 and v_sweeps = 0 and not v_quiet and v_rules = 0 and v_wa = 0 and v_agent = 0 and v_mail = 0 and v_bukku is null then
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
    v_bukku,
    case when v_mail > 0 then v_mail || case when v_mail = 1 then ' creator email was not sent or not confirmed'
                                            else ' creator emails were not sent or not confirmed' end end,
    case when v_agent > 0 then v_agent || case when v_agent = 1 then ' scheduled Assistant action' else ' scheduled Assistant actions' end
                               || ' could not be done' end,
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
  return jsonb_build_object('failed', v_runs + v_sweeps + case when v_quiet then 1 else 0 end + v_rules + v_wa + v_agent + v_mail
      + case when v_bukku is null then 0 else 1 end, 'whatsapp', v_wa, 'creator_mail', v_mail, 'bukku', v_bukku,
    'assistant', v_agent, 'jobs', v_jobs, 'self', v_self, 'since', v_since, 'sweeps', v_sweeps, 'sweep_missing', v_quiet,
    'repeats', v_rules, 'told', v_told);
end $$;
revoke all on function public.jobs_watch(timestamptz) from public, anon, authenticated;

-- END OF JOBS WATCHED, SHEET ROWS ADDED ONCE -----------------------------------

select public.functions_tidy();
