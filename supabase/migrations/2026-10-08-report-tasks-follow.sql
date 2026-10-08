-- ===========================================================================
-- REPORT TASKS FOLLOW THEIR REPORT — the month's Accounts report and
-- Advertising report tasks move with the report they stand for.
-- 2026-10-08. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-08: "could the tasks for advertising report and
--   accounts report be linked to the stage of the actual report too (report
--   created, it shifts to in progress assigned to the person who created;
--   report in review stage it goes to waiting until it is out to publish
--   stage whereby its marked as sent to client manually for review then move
--   to reviewing stage.) Done to be marked manually by the assigned users".
--   Trigger `sm_reports_task_follow` (after insert, or an update of status
--   or sent_on, on `sm_reports`) finds the report's task as
--   `sm_report_gate` does (the client's month whose span holds the report's
--   last day, its live `report_{kind}` task) and moves it on the everyday
--   workflow, by `sm_report_task_target`:
--     - a draft: In progress (`doing`); a report just made also makes its
--       maker the task's owner;
--     - in review or confirmed, and published but not yet sent: Waiting;
--     - published and marked as sent: Review.
--   Done stays the owner's own press: a finished or cancelled task is never
--   moved, and nothing moves a task to Done. A white-label brand's report
--   (`brand_id`) leaves the month's task alone. Each move is filed on the
--   task (`stage_changed`, `report_id`, note "Report …"). A refusal or fault
--   never fails the report's own write.
--
-- ROLLBACK
--   drop trigger sm_reports_task_follow on public.sm_reports;
--   drop function public.sm_reports_task_follow();
--   drop function public.sm_report_task_target(text, date);
-- ===========================================================================

create or replace function public.sm_report_task_target(p_status text, p_sent date)
returns text
language sql immutable set search_path = public as $$
  select case
    when p_status = 'draft' then 'doing'
    when p_status in ('review', 'confirmed') then 'waiting'
    when p_status = 'published' and p_sent is null then 'waiting'
    when p_status = 'published' then 'review'
  end
$$;

create or replace function public.sm_reports_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  t public.ops_tasks;
  v_to text;
  v_was uuid;
  v_note text;
begin
  if new.brand_id is not null then return null; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.sent_on is not distinct from old.sent_on then
    return null;
  end if;
  v_to := public.sm_report_task_target(new.status, new.sent_on);
  if v_to is null then return null; end if;
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
  if t.id is null or t.completed_at is not null then return null; end if;

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
    end if;
  end if;

  if t.stage_key is distinct from v_to then
    v_note := case
      when tg_op = 'INSERT' then 'Report started'
      when new.status = 'draft' then 'Report back in draft'
      when new.status = 'review' then 'Report submitted for review'
      when new.status = 'confirmed' then 'Report confirmed'
      when new.sent_on is null then 'Report published'
      else 'Report sent to the client' end;
    update public.ops_tasks set stage_key = v_to, version = version + 1, updated_at = now(),
           completed_at = null, blocked_at = null, blocked_category = null
     where id = t.id;
    perform public.ops_log(t.id, 'stage_changed',
      jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', v_to),
      jsonb_build_object('note', v_note, 'report_id', new.id));
  elsif tg_op = 'INSERT' then
    update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_task_follow() from public, anon, authenticated;
revoke all on function public.sm_report_task_target(text, date) from public, anon, authenticated;

create or replace trigger sm_reports_task_follow
  after insert or update of status, sent_on on public.sm_reports
  for each row execute function public.sm_reports_task_follow();

-- END OF REPORT TASKS FOLLOW THEIR REPORT ------------------------------------

select public.functions_tidy();
