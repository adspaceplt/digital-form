-- =====================================================================
-- ASSISTANT ACTIONS AND SCHEDULES
-- 2026-11-13, the user: "approve build both" (the mockups "Assistant ·
-- actions with Confirm" and "Assistant · phone"). The Assistant may now
-- book a month's meeting, create a campaign, publish or unpublish a
-- content set and send a WhatsApp template, each only behind its Confirm
-- card, each through the function its screen uses; and it may schedule a
-- reminder, or one of those, for later.
--
-- WHAT IT CHANGES
--   * `agent_schedules` (RLS on, no policy, no grant): one row a thing a
--     colleague confirmed for later: a reminder (`reminder`), a report
--     marked as sent (`mark_sent`), a task created (`add_task`), a set
--     published or unpublished (`publish_set`, `unpublish_set`), a WhatsApp
--     template queued (`whatsapp`); when it runs (Malaysia's clock decides
--     nothing here: a moment), what it is called, what it needs, and an
--     optional condition from a fixed list: `set_undecided` (the set still
--     holds posts the client has not decided), `report_not_sent` (the
--     report is not marked as sent), `task_open` (the task is not finished
--     or cancelled). A Google Meet booking is never scheduled.
--   * `agent_schedule_add(p_kind, p_at, p_title, p_payload, p_condition,
--     p_ref)`: the colleague's own, checked at their access now (`denied`,
--     `bad-kind`, `bad-time` (from a minute ahead to 92 days),
--     `bad-title`, `bad-condition`, `bad-payload`, `not-found`, `too-many`
--     past 50 waiting); filed `assistant.schedule`.
--   * `agent_schedule_cancel(p_id)`: the colleague's own while it waits
--     (`not-found`, `not-waiting`); filed.
--   * `agent_schedule_list()`: the colleague's own, waiting first, then
--     what ran or was cancelled in the last 14 days.
--   * `agent_schedules_run()` (pg_cron `agent-schedules`, every five
--     minutes; nobody's to call): each row due runs as the colleague who
--     confirmed it (`request.jwt.claims`, as `ops_recurring_daily` does),
--     their access asked again at the run; a condition no longer holding
--     marks it skipped; a refusal or a fault marks it failed and tells the
--     colleague (`assistant.failed`, the bell and a push). A reminder is a
--     notice to the colleague (`assistant.reminder`).
--   * `jobs_watch` counts the schedules that failed in its window, for the
--     admins' morning notice.
--
-- ORDER: ASSISTANT ACTIONS, THE SQL EDITOR PART (the Activity record's new
-- tags) in the SQL Editor, then this file, then the edge function
-- `portal-agent`, then the pages. Safe to run twice.
--
-- ROLLBACK: pages first; unschedule `agent-schedules`; restate jobs_watch
-- from JOBS WATCH WHATSAPP; the table and its functions may stay (nothing
-- reads them without the page).
-- =====================================================================
create table if not exists public.agent_schedules (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  kind           text not null,
  run_at         timestamptz not null,
  title          text not null,
  payload        jsonb not null default '{}'::jsonb,
  condition      text,
  condition_ref  uuid,
  state          text not null default 'waiting',
  result         text,
  created_at     timestamptz not null default now(),
  ran_at         timestamptz,
  cancelled_at   timestamptz,
  constraint agent_schedules_kind check (kind in ('reminder', 'mark_sent', 'add_task', 'publish_set', 'unpublish_set', 'whatsapp')),
  constraint agent_schedules_state check (state in ('waiting', 'running', 'done', 'skipped', 'failed', 'cancelled')),
  constraint agent_schedules_condition check (condition is null or condition in ('set_undecided', 'report_not_sent', 'task_open'))
);
alter table public.agent_schedules enable row level security;
revoke all on table public.agent_schedules from anon, authenticated;
create index if not exists agent_schedules_due_idx on public.agent_schedules (run_at) where state = 'waiting';
create index if not exists agent_schedules_member_idx on public.agent_schedules (team_member_id, created_at desc);

/* Whether a schedule's condition still holds, read as the database holds
   it (the run reads it under the colleague's own claims). */
create or replace function public.agent_schedule_holds(p_condition text, p_ref uuid)
returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if p_condition is null then return true; end if;
  if p_condition = 'set_undecided' then
    return exists (
      select 1 from public.posts po
       where po.batch_id = p_ref
         and not exists (
           select 1 from public.reviews r
            where r.post_id = po.id and r.undone_at is null and coalesce(r.round, 1) = coalesce(po.round, 1)
              and (po.review_reset_at is null or r.created_at > po.review_reset_at)));
  end if;
  if p_condition = 'report_not_sent' then
    return exists (select 1 from public.sm_reports r where r.id = p_ref and r.sent_on is null);
  end if;
  if p_condition = 'task_open' then
    return exists (select 1 from public.ops_tasks t where t.id = p_ref and t.completed_at is null and t.cancelled_at is null);
  end if;
  return false;
end $$;
revoke all on function public.agent_schedule_holds(text, uuid) from public, anon, authenticated;

/* What a kind needs, and whether the colleague may do it now; asked at
   the add and again at the run. Answers null, or the refusal. */
create or replace function public.agent_schedule_check(p_kind text, p_payload jsonb)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid;
  b public.batches;
  r public.sm_reports;
  v_prep jsonb;
begin
  if p_kind = 'reminder' then
    if length(btrim(coalesce(p_payload ->> 'message', ''))) not between 2 and 500 then return 'bad-payload'; end if;
    return null;
  end if;
  if p_kind = 'mark_sent' then
    if not public.allowed('reports', 'work') then return 'denied'; end if;
    v_id := nullif(p_payload ->> 'report_id', '')::uuid;
    select * into r from public.sm_reports x where x.id = v_id;
    if r.id is null or not public.client_seen(r.client_id, 'view') then return 'not-found'; end if;
    return null;
  end if;
  if p_kind = 'add_task' then
    if not public.allowed('ops', 'work') then return 'denied'; end if;
    if length(btrim(coalesce(p_payload ->> 'title', ''))) not between 1 and 200 then return 'bad-payload'; end if;
    return null;
  end if;
  if p_kind in ('publish_set', 'unpublish_set') then
    if not public.allowed('review.sets', 'work') then return 'denied'; end if;
    v_id := nullif(p_payload ->> 'set_id', '')::uuid;
    select * into b from public.batches x where x.id = v_id;
    if b.id is null or not public.client_seen(b.client_id, 'view') then return 'not-found'; end if;
    return null;
  end if;
  if p_kind = 'whatsapp' then
    if coalesce(p_payload ->> 'purpose', '') not in ('approval', 'feedback', 'representative') then return 'bad-payload'; end if;
    v_prep := public.wa_compose_prepare('contact', nullif(p_payload ->> 'to_id', '')::uuid, p_payload ->> 'purpose',
                                        nullif(p_payload ->> 'ref', '')::uuid);
    if v_prep ? 'error' then return v_prep ->> 'error'; end if;
    if not exists (select 1 from public.wa_templates t where t.purpose = p_payload ->> 'purpose' and t.active and t.name <> '') then
      return 'wa-off';
    end if;
    return null;
  end if;
  return 'bad-kind';
exception when invalid_text_representation then
  return 'bad-payload';
end $$;
revoke all on function public.agent_schedule_check(text, jsonb) from public, anon, authenticated;

create or replace function public.agent_schedule_add(p_kind text, p_at timestamptz, p_title text, p_payload jsonb,
                                                     p_condition text default null, p_ref uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_title text := btrim(coalesce(p_title, ''));
  v_err text;
  v_id uuid;
begin
  if me.id is null or not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  if p_kind is null or p_kind not in ('reminder', 'mark_sent', 'add_task', 'publish_set', 'unpublish_set', 'whatsapp') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if p_at is null or p_at < now() + interval '1 minute' or p_at > now() + interval '92 days' then
    return jsonb_build_object('error', 'bad-time');
  end if;
  if length(v_title) not between 2 and 200 then return jsonb_build_object('error', 'bad-title'); end if;
  if (p_condition is null) <> (p_ref is null)
     or (p_condition is not null and p_condition not in ('set_undecided', 'report_not_sent', 'task_open')) then
    return jsonb_build_object('error', 'bad-condition');
  end if;
  v_err := public.agent_schedule_check(p_kind, coalesce(p_payload, '{}'::jsonb));
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  perform pg_advisory_xact_lock(hashtext('agent_schedule:' || me.id::text));
  if (select count(*) from public.agent_schedules s where s.team_member_id = me.id and s.state = 'waiting') >= 50 then
    return jsonb_build_object('error', 'too-many');
  end if;
  insert into public.agent_schedules (team_member_id, kind, run_at, title, payload, condition, condition_ref)
  values (me.id, p_kind, p_at, v_title, coalesce(p_payload, '{}'::jsonb), p_condition, p_ref)
  returning id into v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'assistant.schedule', v_title,
          'Scheduled for ' || public.register_day((p_at at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
          lower(to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')) || ' · confirmed through the Assistant');
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.agent_schedule_add(text, timestamptz, text, jsonb, text, uuid) from public, anon;
grant execute on function public.agent_schedule_add(text, timestamptz, text, jsonb, text, uuid) to authenticated;

create or replace function public.agent_schedule_cancel(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s public.agent_schedules;
begin
  if me.id is null or not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.agent_schedules x where x.id = p_id and x.team_member_id = me.id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if s.state <> 'waiting' then return jsonb_build_object('error', 'not-waiting', 'state', s.state); end if;
  update public.agent_schedules x set state = 'cancelled', cancelled_at = now() where x.id = s.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'assistant.schedule', s.title, 'Scheduled run cancelled');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.agent_schedule_cancel(uuid) from public, anon;
grant execute on function public.agent_schedule_cancel(uuid) to authenticated;

create or replace function public.agent_schedule_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null or not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', s.id, 'kind', s.kind, 'title', s.title, 'run_at', s.run_at, 'state', s.state, 'result', s.result,
      'condition', s.condition, 'ran_at', s.ran_at, 'cancelled_at', s.cancelled_at)
      order by (s.state = 'waiting') desc,
               case when s.state = 'waiting' then s.run_at end asc,
               coalesce(s.ran_at, s.cancelled_at, s.created_at) desc)
    from (select * from public.agent_schedules x
           where x.team_member_id = me.id
             and (x.state in ('waiting', 'running') or coalesce(x.ran_at, x.cancelled_at, x.created_at) > now() - interval '14 days')
           order by x.run_at desc limit 60) s), '[]'::jsonb));
end $$;
revoke all on function public.agent_schedule_list() from public, anon;
grant execute on function public.agent_schedule_list() to authenticated;

/* One schedule, run as its colleague: the claims are already set. Answers
   {ok, said} or {error}. */
create or replace function public.agent_schedule_do(s public.agent_schedules, m public.team_members)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p jsonb := s.payload;
  v jsonb;
  b public.batches;
  c public.clients;
  v_on boolean;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_n integer;
  v_what text;
  v_rec jsonb;
begin
  if s.kind = 'reminder' then
    insert into public.ops_notifications (team_member_id, task_id, report_id, client_id, kind, title, body, dedupe_key)
    values (m.id,
            (select t.id from public.ops_tasks t where t.id = nullif(p ->> 'task_id', '')::uuid),
            (select r.id from public.sm_reports r where r.id = nullif(p ->> 'report_id', '')::uuid),
            (select x.id from public.clients x where x.id = nullif(p ->> 'client_id', '')::uuid),
            'assistant.reminder', left(s.title, 200), left(p ->> 'message', 500), 'agent.' || s.id)
    on conflict (dedupe_key) do nothing;
    return jsonb_build_object('ok', true, 'said', 'Reminder sent to you.');
  end if;
  if s.kind = 'mark_sent' then
    v := public.sm_report_sent((p ->> 'report_id')::uuid, coalesce(nullif(p ->> 'sent_on', '')::date, v_today));
    if v ? 'error' then return v; end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.report', s.title, 'Marked as sent ' || public.register_day(v_today) || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Marked as sent.');
  end if;
  if s.kind = 'add_task' then
    v := public.ops_create_task(p, 'agent-schedule-' || s.id::text);
    if v ? 'error' then return v; end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.task', coalesce((select x.name from public.clients x where x.id = nullif(p ->> 'client_id', '')::uuid), 'Internal'),
            'Task added: ' || coalesce(p ->> 'title', '') || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Task added.', 'task_id', v ->> 'id');
  end if;
  if s.kind in ('publish_set', 'unpublish_set') then
    if not public.allowed('review.sets', 'work') then return jsonb_build_object('error', 'denied'); end if;
    select * into b from public.batches x where x.id = (p ->> 'set_id')::uuid for update;
    if b.id is null or not public.client_seen(b.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
    v_on := s.kind = 'publish_set';
    if v_on and not exists (select 1 from public.posts po where po.batch_id = b.id) then
      return jsonb_build_object('error', 'empty');
    end if;
    if b.published = v_on then return jsonb_build_object('ok', true, 'said', case when v_on then 'Already published.' else 'Already unpublished.' end); end if;
    update public.batches x set published = v_on where x.id = b.id;
    select * into c from public.clients x where x.id = b.client_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, case when v_on then 'set.published' else 'set.withdrawn' end, c.name || ' — ' || b.title, null),
           (m.name, 'assistant.set', c.name || ' — ' || b.title,
            case when v_on then 'Published' else 'Unpublished' end || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', case when v_on then 'Published.' else 'Unpublished.' end);
  end if;
  if s.kind = 'whatsapp' then
    v := public.wa_compose_prepare('contact', (p ->> 'to_id')::uuid, p ->> 'purpose', nullif(p ->> 'ref', '')::uuid);
    if v ? 'error' then return v; end if;
    if not exists (select 1 from public.wa_templates t where t.purpose = p ->> 'purpose' and t.active and t.name <> '') then
      return jsonb_build_object('error', 'wa-off');
    end if;
    v_rec := public.wa_sent_recently('contact', (p ->> 'to_id')::uuid, p ->> 'purpose', nullif(p ->> 'ref', '')::uuid, null);
    if coalesce((v_rec ->> 'recent')::boolean, false) then
      return jsonb_build_object('skip', true, 'said', 'Not sent: it was sent on WhatsApp recently.');
    end if;
    /* What waits, as the composer words it: the set's undecided posts, or
       the creator's draft. */
    if p ->> 'purpose' = 'approval' then
      select * into b from public.batches x where x.id = nullif(p ->> 'ref', '')::uuid;
      if b.id is not null then
        select count(*)::int into v_n from public.posts po
         where po.batch_id = b.id
           and not exists (select 1 from public.reviews r where r.post_id = po.id and r.undone_at is null
                              and coalesce(r.round, 1) = coalesce(po.round, 1)
                              and (po.review_reset_at is null or r.created_at > po.review_reset_at));
        v_what := v_n || case when v_n = 1 then ' post' else ' posts' end || ' in ' || b.title;
      else
        v_what := coalesce(nullif(p ->> 'what', ''), 'A draft');
      end if;
    end if;
    perform public.wa_enqueue(p ->> 'purpose', v ->> 'number', v ->> 'name',
      jsonb_build_array(v ->> 'greeting', v ->> 'client',
        case p ->> 'purpose' when 'approval' then v_what when 'representative' then v ->> 'rep' else '' end,
        case when p ->> 'purpose' = 'approval' then 'https://digital.adspace.me/' || coalesce(v ->> 'link', '') else '' end),
      v ->> 'ref_kind', nullif(p ->> 'ref', '')::uuid, (v ->> 'client_id')::uuid,
      case p ->> 'purpose' when 'approval' then v ->> 'link' when 'representative' then v ->> 'code' end);
    /* Sent for a colleague, never Automatic. */
    update public.wa_outbox o set created_by = m.name
     where o.id = (select x.id from public.wa_outbox x where x.created_by = 'system' and x.created_at = now()
                      and x.purpose = p ->> 'purpose' and x.to_number = v ->> 'number' order by x.id limit 1);
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.whatsapp', coalesce(v ->> 'subject', s.title),
            'WhatsApp queued to ' || coalesce(v ->> 'name', '') || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Queued on WhatsApp.');
  end if;
  return jsonb_build_object('error', 'bad-kind');
end $$;
revoke all on function public.agent_schedule_do(public.agent_schedules, public.team_members) from public, anon, authenticated;

/* A refusal in the colleague's words, for the row and the notice. */
create or replace function public.agent_schedule_said(p_code text)
returns text
language sql immutable set search_path = public as $$
  select case p_code
    when 'denied' then 'You no longer have permission to do this.'
    when 'not-found' then 'The record no longer exists or is out of your reach.'
    when 'not-published' then 'The report is not published.'
    when 'bad-date' then 'The date is outside the report''s period.'
    when 'empty' then 'The set holds no posts.'
    when 'wa-off' then 'The WhatsApp template for this message is off.'
    when 'no-number' then 'The contact has no WhatsApp number.'
    when 'username' then 'The contact has a WhatsApp username, which cannot be messaged.'
    when 'not-waiting' then 'Nothing waits on the client any more.'
    when 'not-lead' then 'The client is no longer a lead.'
    when 'no-sales-by' then 'The lead has no Sales by colleague.'
    when 'no-card' then 'The Sales by colleague''s namecard is off.'
    when 'no-contact' then 'The prospect asked not to be contacted.'
    when 'no-month' then 'The client''s content month is not confirmed.'
    when 'month-closed' then 'The client''s content month is closed.'
    when 'month-not-confirmed' then 'The client''s content month is not confirmed.'
    when 'not-team' then 'You are no longer an active colleague.'
    else 'It could not be done (' || coalesce(p_code, 'unknown') || ').'
  end
$$;
revoke all on function public.agent_schedule_said(text) from public, anon, authenticated;

create or replace function public.agent_schedules_run()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.agent_schedules;
  m public.team_members;
  v jsonb;
  v_why text;
  v_done integer := 0;
  v_skip integer := 0;
  v_fail integer := 0;
  was text := current_setting('request.jwt.claims', true);
begin
  for s in
    select * from public.agent_schedules x
     where x.state = 'waiting' and x.run_at <= now()
     order by x.run_at
     limit 50
     for update skip locked
  loop
    v_why := null; v := null;
    select * into m from public.team_members t where t.id = s.team_member_id;
    if m.id is null or not m.active or m.removed_at is not null or m.email is null then
      v_why := 'Its colleague is no longer active.';
    else
      perform set_config('request.jwt.claims', jsonb_build_object('email', m.email, 'role', 'authenticated')::text, true);
      if not public.is_team() then
        v_why := 'You no longer have access to the portal.';
      elsif s.condition is not null and not public.agent_schedule_holds(s.condition, s.condition_ref) then
        update public.agent_schedules x set state = 'skipped', ran_at = now(),
               result = case s.condition when 'set_undecided' then 'Skipped: the client has decided every post.'
                                         when 'report_not_sent' then 'Skipped: the report is already marked as sent.'
                                         else 'Skipped: the task is finished.' end
         where x.id = s.id;
        v_skip := v_skip + 1;
        continue;
      else
        begin
          v := public.agent_schedule_do(s, m);
        exception when others then
          v := jsonb_build_object('error', 'fault');
          raise warning 'agent_schedules_run %: %', s.id, sqlerrm;
        end;
        if v ? 'skip' then
          update public.agent_schedules x set state = 'skipped', ran_at = now(), result = v ->> 'said' where x.id = s.id;
          v_skip := v_skip + 1;
          continue;
        end if;
        if v ? 'error' then v_why := public.agent_schedule_said(v ->> 'error'); end if;
      end if;
    end if;
    if v_why is null then
      update public.agent_schedules x set state = 'done', ran_at = now(), result = coalesce(v ->> 'said', 'Done.') where x.id = s.id;
      v_done := v_done + 1;
    else
      update public.agent_schedules x set state = 'failed', ran_at = now(), result = v_why where x.id = s.id;
      v_fail := v_fail + 1;
      if m.id is not null and m.active then
        insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
        values (m.id, 'assistant.failed', left('Not done: ' || s.title, 200), v_why, 'agent.failed.' || s.id)
        on conflict (dedupe_key) do nothing;
      end if;
    end if;
  end loop;
  perform set_config('request.jwt.claims', coalesce(was, ''), true);
  return jsonb_build_object('done', v_done, 'skipped', v_skip, 'failed', v_fail);
end $$;
revoke all on function public.agent_schedules_run() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: no scheduled Assistant runs until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'agent-schedules';
  perform cron.schedule('agent-schedules', '*/5 * * * *', 'select public.agent_schedules_run()');
end $$;

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

  if v_runs = 0 and v_sweeps = 0 and not v_quiet and v_rules = 0 and v_wa = 0 and v_agent = 0 then
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
    case when v_agent > 0 then v_agent || case when v_agent = 1 then ' run scheduled through the Assistant' else ' runs scheduled through the Assistant' end
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
  return jsonb_build_object('failed', v_runs + v_sweeps + case when v_quiet then 1 else 0 end + v_rules + v_wa + v_agent, 'whatsapp', v_wa,
    'assistant', v_agent, 'jobs', v_jobs, 'self', v_self, 'since', v_since, 'sweeps', v_sweeps, 'sweep_missing', v_quiet,
    'repeats', v_rules, 'told', v_told);
end $$;
revoke all on function public.jobs_watch(timestamptz) from public, anon, authenticated;

-- END OF ASSISTANT ACTIONS AND SCHEDULES -------------------------------------

select public.functions_tidy();
