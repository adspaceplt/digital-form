-- ============================================================================
-- A REPORT AND ITS MONTH'S TICK KEEP IN STEP (2026-11-10)
-- ============================================================================
-- The user, 2026-11-10: a report made by hand in Reports for its content
-- month, where the month's Reports tick was not ticked, left the month and
-- its report task out of step. Both ways now meet:
--
--   1. `sm_reports_month_tick` (after insert on `sm_reports`, firing before
--      `sm_reports_task_follow`): a client's monthly report, its own (no
--      brand, not on request), from October 2026, made for a month in My
--      Work that is open and does not ask for its kind, ticks that kind on
--      the month (filed on the month, `edited`, Ticked by the report) and
--      makes its report task (`ops_engagement_sync_reports`), as the
--      report's maker, else (a maker without My Work at Work) as the month's
--      manager, as the morning's repeats are made; the follow trigger then
--      puts the task In progress under the report's maker. A fault never
--      fails the report (the tick and task are left out).
--   2. `ops_tasks_report_catch_up` (after insert on `ops_tasks`): a month's
--      report task made after its report already stands (a tick added in My
--      Work later) takes the report's step at once, the stage
--      `sm_report_task_target` names and the report's maker as its owner,
--      filed on the task.
--
-- Re-runnable. Rollback: drop the two triggers and their functions.

create or replace function public.sm_reports_month_tick()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e   public.ops_engagements;
  was text := current_setting('request.jwt.claims', true);
  v_mgr text;
  v_done boolean := false;
begin
  if new.brand_id is not null or new.on_request or new.period_start < date '2026-10-01' then return null; end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = new.client_id and x.status not in ('completed', 'cancelled')
     and new.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null or new.kind = any (coalesce(e.reports, '{}'::text[])) then return null; end if;
  begin
    update public.ops_engagements
       set reports = array_append(coalesce(reports, '{}'::text[]), new.kind), version = version + 1, updated_at = now()
     where id = e.id;
    perform public.ops_engagement_log(e.id, 'edited', jsonb_build_object(
      'reports', to_jsonb(array_append(coalesce(e.reports, '{}'::text[]), new.kind)),
      'note', case new.kind when 'social' then 'Accounts report' else 'Advertising report' end
              || ' ticked: the report was made in Reports', 'report_id', new.id));
    perform public.ops_engagement_sync_reports(e.id);
    v_done := true;
  exception when others then
    null;
  end;
  if not v_done then
    select m.email into v_mgr from public.team_members m
     where m.id = e.manager_id and m.active and m.email is not null;
    if v_mgr is not null then
      perform set_config('request.jwt.claims', jsonb_build_object('email', v_mgr, 'role', 'authenticated')::text, true);
      begin
        update public.ops_engagements
           set reports = array_append(coalesce(reports, '{}'::text[]), new.kind), version = version + 1, updated_at = now()
         where id = e.id;
        perform public.ops_engagement_log(e.id, 'edited', jsonb_build_object(
          'reports', to_jsonb(array_append(coalesce(e.reports, '{}'::text[]), new.kind)),
          'note', case new.kind when 'social' then 'Accounts report' else 'Advertising report' end
                  || ' ticked: the report was made in Reports', 'report_id', new.id));
        perform public.ops_engagement_sync_reports(e.id);
      exception when others then
        null;
      end;
      perform set_config('request.jwt.claims', coalesce(was, ''), true);
    end if;
  end if;
  return null;
exception when others then
  perform set_config('request.jwt.claims', coalesce(was, ''), true);
  return null;
end $$;
revoke all on function public.sm_reports_month_tick() from public, anon, authenticated;
create or replace trigger sm_reports_month_tick after insert on public.sm_reports
  for each row execute function public.sm_reports_month_tick();

create or replace function public.ops_tasks_report_catch_up()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  r public.sm_reports;
  v_to text;
  v_was uuid;
begin
  if new.source_type not in ('report_social', 'report_ads') or new.engagement_id is null then return null; end if;
  select * into e from public.ops_engagements x where x.id = new.engagement_id;
  if e.id is null then return null; end if;
  select x.* into r from public.sm_reports x
   cross join lateral public.ops_month_span(e.period, e.start_day) s
   where x.client_id = e.client_id and x.brand_id is null and not x.on_request
     and x.kind = substr(new.source_type, 8) and x.period_end between s.starts and s.ends
   order by x.created_at desc limit 1;
  if r.id is null then return null; end if;
  v_to := public.sm_report_task_target(r.status, r.sent_on);
  if v_to is null then return null; end if;
  /* The report's maker owns it where they take tasks; else it stays with
     the month's manager. */
  if r.created_by is not null and exists (select 1 from public.team_members m where m.id = r.created_by and m.active) then
    begin
      select a.team_member_id into v_was from public.ops_task_assignees a
       where a.task_id = new.id and a.responsibility = 'owner' and a.ended_at is null;
      if v_was is distinct from r.created_by then
        update public.ops_task_assignees set ended_at = now()
         where task_id = new.id and responsibility = 'owner' and ended_at is null;
        insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
        values (new.id, r.created_by, 'owner', r.created_by);
        perform public.ops_log(new.id, 'assignment_changed',
          jsonb_build_object('owner_id', v_was), jsonb_build_object('owner_id', r.created_by),
          jsonb_build_object('report', true, 'report_id', r.id));
      end if;
    exception when others then
      null;
    end;
  end if;
  if new.stage_key is distinct from v_to then
    update public.ops_tasks set stage_key = v_to, version = version + 1, updated_at = now()
     where id = new.id;
    perform public.ops_log(new.id, 'stage_changed',
      jsonb_build_object('stage_key', new.stage_key), jsonb_build_object('stage_key', v_to),
      jsonb_build_object('note', 'The report was already made in Reports', 'report_id', r.id));
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.ops_tasks_report_catch_up() from public, anon, authenticated;
create or replace trigger ops_tasks_report_catch_up after insert on public.ops_tasks
  for each row execute function public.ops_tasks_report_catch_up();

select public.functions_tidy();
