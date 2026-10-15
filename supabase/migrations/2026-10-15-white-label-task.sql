-- ===========================================================================
-- A BRAND TAKES ITS REPORT OFF THE MONTH'S TASK — a report given to a
-- white-label brand after it was made lets go of the month's report task,
-- and one given back to its client takes it again (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15: "apply white label settings" after creating)
--   A report made for the client itself takes the month's report task: In
--   progress, under whoever made it. Given a brand afterwards (the report
--   head's White label), it is no longer the month's report, but the task
--   stayed In progress under its maker and never followed the report again,
--   since a brand's report leaves the month's task alone.
--
-- WHAT CHANGED
--   * Trigger `sm_reports_brand_task` (after the brand of a report moves):
--     a report given a brand puts the month's report task back to To do
--     under the month's manager, unless another of the client's own reports
--     in the month still holds it; a report given back to its client takes
--     the task as a report made does, under its maker, at the stage its
--     state asks. A finished or cancelled task never moves, a report on
--     request never touches it, each move is filed on the task with the
--     report, and a fault never fails the report's write.
--
-- ORDER
--   The page ships first (it lists each brand under its client in New
--   report); this file may run before or after it.
--
-- Safe to run twice. Rollback: drop the trigger `sm_reports_brand_task` on
-- public.sm_reports and the function public.sm_reports_brand_task() in the
-- SQL Editor.
-- ===========================================================================
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
    update public.ops_tasks set stage_key = v_to, version = version + 1, updated_at = now(),
           blocked_at = null, blocked_category = null
     where id = t.id;
    perform public.ops_log(t.id, 'stage_changed',
      jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', v_to),
      jsonb_build_object('note', v_note, 'report_id', new.id));
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_brand_task() from public, anon, authenticated;

create or replace trigger sm_reports_brand_task
  after update of brand_id on public.sm_reports
  for each row execute function public.sm_reports_brand_task();

-- END OF A BRAND TAKES ITS REPORT OFF THE MONTH'S TASK -------------------------
select public.functions_tidy();
