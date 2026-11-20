-- ===========================================================================
-- A REPORT'S TASK FOLLOWS IT TO DONE (2026-11-21)
-- ===========================================================================
-- WHY (the user, 2026-11-21: "A. Submit for someone review sent to Review
-- stage; then Sent = move to done. Is it okay", confirmed): the month's
-- report task waited at Waiting while its report was reviewed and stood at
-- Review once the report was sent, so every sent report left a task for its
-- owner to finish by hand, and the task's finished day was the day of that
-- press, not the day the client had the report.
--
-- WHAT CHANGED
--   * `sm_report_task_target` (the one map from a report to its task's
--     stage on the everyday workflow): a draft is In progress (`doing`);
--     submitted for review, confirmed, or published and not yet sent is
--     Review (`review`, was Waiting); published and marked as sent is Done
--     (`complete`, was Review).
--   * `sm_report_task_move` (internal): the one move of a month's report
--     task, used by the three triggers below. Done is stamped finished on the
--     day the report was marked sent (that day's last second in Malaysia, or
--     now where the day is today), so on-time counts that day; its running
--     timers stop and it is filed `completed`, as a press on Done files it.
--     Any other stage clears the finished stamp. Each move is filed on the
--     task (`stage_changed`, note "Report …", `report_id`).
--   * `sm_reports_task_follow`: a finished task moves only when its report
--     moves back: marked as not sent puts it back to Review ("Report marked
--     as not sent"), a report back in draft (sent back from review, or
--     revised after it was published) puts it back In progress. A forward
--     move never touches a finished task, whether the report or its owner
--     finished it. A cancelled task never moves. A white-label brand's
--     report and a report on request leave the month's task alone, as
--     before. A fault never fails the report's write.
--   * `sm_reports_brand_task` and `ops_tasks_report_catch_up`: unchanged
--     but for the move, which is now `sm_report_task_move`, so a report
--     given back to its client, or a task added after its report was sent,
--     reaches Done with its finished day.
--   * Catch-up, once: a month's report task not finished or cancelled whose
--     report is already marked as sent goes to Done, dated the sent day; one
--     at Waiting whose report is in review, confirmed or published unsent
--     goes to Review. Each filed on the task with its report, telling nobody
--     (no colleague pressed anything). A second run finds nothing to move.
--
-- ORDER: this file alone (no page changes). Safe to run twice.
-- ROLLBACK: run `sm_report_task_target`, `sm_reports_task_follow`,
-- `sm_reports_brand_task` and `ops_tasks_report_catch_up` again from their
-- sections before this one in schema.sql (REPORT TASKS FOLLOW THEIR REPORT,
-- AUDIT FIXES OF 11 NOVEMBER, A BRAND TAKES ITS REPORT OFF THE MONTH'S
-- TASK, A REPORT AND ITS MONTH'S TICK KEEP IN STEP), then
-- `drop function public.sm_report_task_move(uuid, text, date, text, uuid, boolean);`
-- in the SQL Editor. The catch-up's moves stay filed on each task; a task it
-- finished is reopened from the task card as any finished task is.
-- ===========================================================================

create or replace function public.sm_report_task_target(p_status text, p_sent date)
returns text
language sql immutable set search_path = public as $$
  select case
    when p_status = 'draft' then 'doing'
    when p_status in ('review', 'confirmed') then 'review'
    when p_status = 'published' and p_sent is null then 'review'
    when p_status = 'published' then 'complete'
  end
$$;
revoke all on function public.sm_report_task_target(text, date) from public, anon, authenticated;

/* The one move of a month's report task: Done finished on the sent day,
   every other stage unfinished, each filed on the task with its report. */
create or replace function public.sm_report_task_move(
  p_task uuid, p_to text, p_sent date, p_note text, p_report uuid, p_quiet boolean default false)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t public.ops_tasks;
  ws public.ops_work_sessions;
  v_done boolean := p_to = 'complete';
  v_at timestamptz;
  v_mins integer;
  v_from jsonb;
  v_to jsonb;
  v_detail jsonb := jsonb_build_object('note', p_note, 'report_id', p_report);
begin
  select * into t from public.ops_tasks x where x.id = p_task for update;
  if t.id is null or p_to is null or t.stage_key is not distinct from p_to then return; end if;
  if v_done then
    v_at := least(now(), ((coalesce(p_sent, (now() at time zone 'Asia/Kuala_Lumpur')::date) + 1)::timestamp
                          at time zone 'Asia/Kuala_Lumpur') - interval '1 second');
  end if;
  update public.ops_tasks set stage_key = p_to, version = version + 1, updated_at = now(),
         completed_at = v_at, blocked_at = null, blocked_category = null
   where id = t.id;
  v_from := jsonb_build_object('stage_key', t.stage_key);
  v_to := jsonb_build_object('stage_key', p_to);
  if p_quiet then
    insert into public.ops_task_events (task_id, event_type, from_value, to_value, detail)
    values (t.id, 'stage_changed', v_from, v_to, v_detail);
  else
    perform public.ops_log(t.id, 'stage_changed', v_from, v_to, v_detail);
  end if;
  if v_done then
    for ws in select * from public.ops_work_sessions x
               where x.task_id = t.id and x.ended_at is null loop
      v_mins := greatest(0, (extract(epoch from (now() - ws.started_at)) / 60)::integer);
      update public.ops_work_sessions set ended_at = now(), minutes = v_mins where id = ws.id;
      insert into public.ops_task_events (task_id, event_type, to_value, detail)
      values (t.id, 'work_stopped', jsonb_build_object('session_id', ws.id, 'minutes', v_mins),
              jsonb_build_object('note', 'Stopped when the task finished'));
    end loop;
    if p_quiet then
      insert into public.ops_task_events (task_id, event_type, detail)
      values (t.id, 'completed', jsonb_build_object('report_id', p_report));
    else
      perform public.ops_log(t.id, 'completed', null, null, jsonb_build_object('report_id', p_report));
    end if;
  end if;
end $$;
revoke all on function public.sm_report_task_move(uuid, text, date, text, uuid, boolean) from public, anon, authenticated;

create or replace function public.sm_reports_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  t public.ops_tasks;
  v_to text;
  v_was uuid;
  v_note text;
  v_back boolean := false;
begin
  if new.brand_id is not null or new.on_request then return null; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.sent_on is not distinct from old.sent_on then
    return null;
  end if;
  v_to := public.sm_report_task_target(new.status, new.sent_on);
  if v_to is null then return null; end if;
  /* The report moved back: into draft, or no longer marked as sent. */
  if tg_op = 'UPDATE' then
    v_back := (new.status = 'draft' and old.status is distinct from 'draft')
           or (new.status = 'published' and old.status = 'published'
               and new.sent_on is null and old.sent_on is not null);
  end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = new.client_id and x.status <> 'cancelled'
     and new.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then return null; end if;
  select * into t from public.ops_tasks x
   where x.engagement_id = e.id and x.source_type = 'report_' || new.kind
     and x.cancelled_at is null and x.archived_at is null
   order by x.created_at desc limit 1
   for update;
  /* A finished task moves only with its report moving back. */
  if t.id is null or (t.completed_at is not null and not v_back) then return null; end if;

  if tg_op = 'INSERT' and new.created_by is not null then
    select team_member_id into v_was from public.ops_task_assignees
     where task_id = t.id and responsibility = 'owner' and ended_at is null;
    if v_was is distinct from new.created_by then
      update public.ops_task_assignees set ended_at = now()
       where task_id = t.id and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (t.id, new.created_by, 'owner', new.created_by);
      perform public.ops_log(t.id, 'assignment_changed',
        jsonb_build_object('owner_id', v_was), jsonb_build_object('owner_id', new.created_by),
        jsonb_build_object('report', true, 'report_id', new.id, 'stage_key', t.stage_key));
      /* The new owner's row may already have caught the task up
         (ops_tasks_report_catch_up): read its stage again, so the move is
         filed once. */
      select x.stage_key into t.stage_key from public.ops_tasks x where x.id = t.id;
    end if;
  end if;

  if t.stage_key is distinct from v_to then
    v_note := case
      when tg_op = 'INSERT' then 'Report started'
      when new.status = 'draft' then 'Report back in draft'
      when new.status = 'review' then 'Report submitted for review'
      when new.status = 'confirmed' then 'Report confirmed'
      when new.sent_on is null and v_back then 'Report marked as not sent'
      when new.sent_on is null then 'Report published'
      else 'Report sent to the client' end;
    perform public.sm_report_task_move(t.id, v_to, new.sent_on, v_note, new.id);
  elsif tg_op = 'INSERT' then
    update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_task_follow() from public, anon, authenticated;

create or replace trigger sm_reports_task_follow
  after insert or update of status, sent_on on public.sm_reports
  for each row execute function public.sm_reports_task_follow();

create or replace function public.sm_reports_brand_task()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  e public.ops_engagements;
  t public.ops_tasks;
  v_starts date;
  v_ends date;
  v_to text;
  v_owner uuid;
  v_was uuid;
  v_note text;
begin
  if new.on_request or new.brand_id is not distinct from old.brand_id then return null; end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = new.client_id and x.status <> 'cancelled'
     and new.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then return null; end if;
  select s.starts, s.ends into v_starts, v_ends from public.ops_month_span(e.period, e.start_day) s;
  select * into t from public.ops_tasks x
   where x.engagement_id = e.id and x.source_type = 'report_' || new.kind
     and x.cancelled_at is null and x.archived_at is null
   order by x.created_at desc limit 1
   for update;
  if t.id is null or t.completed_at is not null then return null; end if;

  if new.brand_id is not null then
    if old.brand_id is not null then return null; end if;
    if exists (select 1 from public.sm_reports r
                where r.id <> new.id and r.client_id = new.client_id and r.kind = new.kind
                  and r.brand_id is null and not coalesce(r.on_request, false)
                  and r.period_end between v_starts and v_ends) then
      return null;
    end if;
    v_to := 'todo';
    v_owner := e.manager_id;
    v_note := 'Report moved to a white-label brand';
  else
    v_to := public.sm_report_task_target(new.status, new.sent_on);
    v_owner := new.created_by;
    v_note := 'Report moved back to the client';
  end if;

  if v_owner is not null then
    select a.team_member_id into v_was from public.ops_task_assignees a
     where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null;
    if v_was is distinct from v_owner then
      update public.ops_task_assignees set ended_at = now()
       where task_id = t.id and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (t.id, v_owner, 'owner', coalesce(me.id, v_owner));
      perform public.ops_log(t.id, 'assignment_changed',
        jsonb_build_object('owner_id', v_was), jsonb_build_object('owner_id', v_owner),
        jsonb_build_object('report', true, 'report_id', new.id, 'note', v_note));
    end if;
  end if;
  if v_to is not null and t.stage_key is distinct from v_to then
    perform public.sm_report_task_move(t.id, v_to, new.sent_on, v_note, new.id);
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_brand_task() from public, anon, authenticated;

create or replace function public.ops_tasks_report_catch_up()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t public.ops_tasks;
  e public.ops_engagements;
  r public.sm_reports;
  v_to text;
  v_first text;
begin
  if new.responsibility <> 'owner' or new.ended_at is not null then return null; end if;
  select * into t from public.ops_tasks x where x.id = new.task_id;
  if t.id is null or t.source_type not in ('report_social', 'report_ads') or t.engagement_id is null
     or t.completed_at is not null or t.cancelled_at is not null then
    return null;
  end if;
  select s.key into v_first from public.ops_workflow_stages s
   where s.workflow_id = t.workflow_id order by s.position limit 1;
  if t.stage_key is distinct from v_first then return null; end if;
  select * into e from public.ops_engagements x where x.id = t.engagement_id;
  if e.id is null then return null; end if;
  select x.* into r from public.sm_reports x
   cross join lateral public.ops_month_span(e.period, e.start_day) s
   where x.client_id = e.client_id and x.brand_id is null and not x.on_request
     and x.kind = substr(t.source_type, 8) and x.period_end between s.starts and s.ends
   order by x.created_at desc limit 1;
  if r.id is null then return null; end if;
  v_to := public.sm_report_task_target(r.status, r.sent_on);
  if v_to is null or v_to = t.stage_key then return null; end if;
  perform public.sm_report_task_move(t.id, v_to, r.sent_on, 'The report was already started in Reports.', r.id);
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.ops_tasks_report_catch_up() from public, anon, authenticated;

/* Catch-up, once: each month's report task to the step its report stands
   at, a sent report's task to Done on the sent day, a reviewed report's
   task from Waiting to Review; filed on the task, telling nobody. */
do $$
declare
  c record;
begin
  for c in
    select t.id as task_id, t.stage_key, r.id as report_id, r.status, r.sent_on,
           public.sm_report_task_target(r.status, r.sent_on) as target
      from public.ops_tasks t
      join public.ops_engagements e on e.id = t.engagement_id
     cross join lateral public.ops_month_span(e.period, e.start_day) s
     cross join lateral (select x.* from public.sm_reports x
                          where x.client_id = e.client_id and x.brand_id is null and not x.on_request
                            and x.kind = substr(t.source_type, 8) and x.period_end between s.starts and s.ends
                          order by x.created_at desc limit 1) r
     where t.source_type in ('report_social', 'report_ads')
       and t.completed_at is null and t.cancelled_at is null and t.archived_at is null
  loop
    if c.target = 'complete' and c.stage_key is distinct from 'complete' then
      perform public.sm_report_task_move(c.task_id, 'complete', c.sent_on, 'Report sent to the client', c.report_id, true);
    elsif c.target = 'review' and c.stage_key = 'waiting' then
      perform public.sm_report_task_move(c.task_id, 'review', null,
        case c.status when 'review' then 'Report submitted for review' when 'confirmed' then 'Report confirmed'
                      else 'Report published' end, c.report_id, true);
    end if;
  end loop;
end $$;

-- END OF A REPORT'S TASK FOLLOWS IT TO DONE ----------------------------------

select public.functions_tidy();
