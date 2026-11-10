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
--   2. `ops_tasks_report_catch_up` (after insert on `ops_task_assignees`,
--      once the task holds its owner): a month's report task still at its
--      first stage whose report already stands (a tick added in My Work
--      later) takes the report's step at once, the stage
--      `sm_report_task_target` names, filed on the task; its owner stays
--      the month's manager.
--
-- Re-runnable. Rollback: drop the two triggers (on `sm_reports` and
-- `ops_task_assignees`) and their functions.

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
      'note', case new.kind when 'social' then 'Accounts Report' else 'Advertising Report' end
              || ' added to the month. The report was started in Reports.', 'report_id', new.id));
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
          'note', case new.kind when 'social' then 'Accounts Report' else 'Advertising Report' end
                  || ' added to the month. The report was started in Reports.', 'report_id', new.id));
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
  update public.ops_tasks set stage_key = v_to, version = version + 1, updated_at = now()
   where id = t.id;
  perform public.ops_log(t.id, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', v_to),
    jsonb_build_object('note', 'The report was already started in Reports.', 'report_id', r.id));
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.ops_tasks_report_catch_up() from public, anon, authenticated;
create or replace trigger ops_tasks_report_catch_up after insert on public.ops_task_assignees
  for each row execute function public.ops_tasks_report_catch_up();

select public.functions_tidy();
