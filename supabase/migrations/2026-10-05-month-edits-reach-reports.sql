-- ===========================================================================
-- A MONTH'S EDITS REACH ITS REPORTS — cancelling a month cancels its report
-- tasks nobody started, reopening it asks for them again, and a new manager
-- takes the ones nobody started.
-- 2026-10-05. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two. Runs after MONTH STAGES FOLLOW THE WORK (ops_engagement_set_status)
-- and APP SETTINGS (ops_engagement_sync_reports).
--
-- WHAT CHANGED
--   Audit round 7, continued. A cancelled month kept its report tasks live
--   in My Work, though deleting the month cancelled them; a reopened month
--   never asked for them again; and a month whose manager changed left its
--   report tasks with the manager before. Each is the rule deleting and
--   unticking already keep: only a task still at its first stage moves.
--
-- ROLLBACK
--   Run the two functions from the sections named above again.
-- ===========================================================================

create or replace function public.ops_engagement_set_status(
  p_engagement uuid, p_status text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements; v_open integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_status in ('ready', 'in_production') then
    return jsonb_build_object('error', 'derived-state');
  end if;
  if p_status not in ('planning', 'completed', 'cancelled') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> e.version then
    return jsonb_build_object('error', 'stale', 'engagement', public.ops_engagement_json(p_engagement));
  end if;
  if p_status = 'completed' then
    select count(*) into v_open from public.ops_tasks t
     where t.engagement_id = p_engagement and t.archived_at is null
       and t.completed_at is null and t.cancelled_at is null;
    if v_open > 0 then
      return jsonb_build_object('error', 'tasks-open', 'open', v_open);
    end if;
  end if;
  if e.status = p_status then return public.ops_engagement_json(p_engagement); end if;
  update public.ops_engagements set status = p_status, updated_at = now(), version = version + 1
   where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'status_changed',
    jsonb_build_object('from', e.status, 'to', p_status));
  /* A month cancelled cancels the report tasks nobody started (as deleting
     it does), keeping a started one; reopened, it asks for its reports
     again. */
  if p_status = 'cancelled' then
    perform public.ops_engagement_cancel_reports(p_engagement, array['social', 'ads'], 'The month was cancelled.');
  elsif e.status = 'cancelled' and p_status = 'planning' then
    perform public.ops_engagement_sync_reports(p_engagement);
  end if;
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_status(uuid, text, integer) to authenticated;

create or replace function public.ops_engagement_sync_reports(p_engagement uuid, p_moved boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  k text;
  v_ends date;
  v_due timestamptz;
  v_draft timestamptz;
  t public.ops_tasks;
  v_first text;
  res jsonb;
  made integer := 0;
  gone integer := 0;
begin
  select * into e from public.ops_engagements where id = p_engagement;
  if e.id is null or e.status in ('completed', 'cancelled') then
    return jsonb_build_object('made', 0, 'cancelled', 0);
  end if;
  select s.ends into v_ends from public.ops_month_span(e.period, e.start_day) s;
  v_due := ((v_ends + public.app_setting('report_due_days', v_ends)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  v_draft := v_due - interval '1 day';
  foreach k in array array['social', 'ads'] loop
    /* A report task nobody has started follows the month's manager. */
    if k = any (e.reports) and e.manager_id is not null then
      for t in select * from public.ops_tasks x
                where x.engagement_id = e.id and x.source_type = 'report_' || k
                  and x.cancelled_at is null and x.archived_at is null and x.completed_at is null
                  and x.stage_key = (select s.key from public.ops_workflow_stages s
                                      where s.workflow_id = x.workflow_id order by s.position limit 1)
                  and exists (select 1 from public.ops_task_assignees a
                               where a.task_id = x.id and a.responsibility = 'owner' and a.ended_at is null
                                 and a.team_member_id <> e.manager_id) loop
        update public.ops_task_assignees set ended_at = now()
         where task_id = t.id and responsibility = 'owner' and ended_at is null;
        insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
        values (t.id, e.manager_id, 'owner', e.manager_id);
        update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
        perform public.ops_log(t.id, 'assignment_changed', null,
          jsonb_build_object('owner_id', e.manager_id),
          jsonb_build_object('note', 'The month''s manager changed.'));
      end loop;
    end if;
    if k = any (e.reports) then
      if not exists (select 1 from public.ops_tasks x
                      where x.engagement_id = e.id and x.source_type = 'report_' || k
                        and x.cancelled_at is null and x.archived_at is null) then
        res := public.ops_create_task(jsonb_build_object(
          'engagement_id', e.id, 'scope', 'client', 'client_id', e.client_id,
          'workflow_key', 'task', 'task_type', 'engagement', 'deliverable_type', 'report',
          'content_desc', case k when 'social' then 'Accounts report' else 'Advertising report' end,
          'code_period', e.period, 'first_draft_due_at', v_draft, 'final_due_at', v_due,
          'source_type', 'report_' || k,
          'owner_id', e.manager_id, 'manager_id', e.manager_id));
        if res ? 'error' then
          raise exception 'report-task: %', res ->> 'error' using errcode = 'P0001';
        end if;
        /* One date: the task is made with a draft date the day before (so
           neither the order check nor the Report template sets one), then
           it is taken off. */
        update public.ops_tasks set original_first_draft_due_at = null, current_first_draft_due_at = null
         where engagement_id = e.id and source_type = 'report_' || k
           and cancelled_at is null and archived_at is null and first_draft_submitted_at is null;
        made := made + 1;
      elsif p_moved then
        for t in select * from public.ops_tasks x
                  where x.engagement_id = e.id and x.source_type = 'report_' || k
                    and x.cancelled_at is null and x.archived_at is null and x.completed_at is null loop
          update public.ops_tasks set current_final_due_at = v_due,
                 updated_at = now(), version = version + 1
           where id = t.id;
          if t.current_final_due_at is distinct from v_due then
            perform public.ops_log(t.id, 'due_changed',
              jsonb_build_object('kind', 'final', 'value', t.current_final_due_at),
              jsonb_build_object('kind', 'final', 'value', v_due),
              jsonb_build_object('reason', 'scope_change', 'note', 'The month''s start day moved.'));
          end if;
        end loop;
      end if;
    else
      for t in select * from public.ops_tasks x
                where x.engagement_id = e.id and x.source_type = 'report_' || k
                  and x.cancelled_at is null and x.archived_at is null and x.completed_at is null loop
        select s.key into v_first from public.ops_workflow_stages s
         where s.workflow_id = t.workflow_id order by s.position limit 1;
        if t.stage_key = v_first then
          update public.ops_tasks set stage_key = 'cancelled', cancelled_at = now(), updated_at = now(),
                 version = version + 1
           where id = t.id;
          perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', t.stage_key),
            jsonb_build_object('stage_key', 'cancelled'),
            jsonb_build_object('note', 'The month no longer asks for this report.'));
          gone := gone + 1;
        end if;
      end loop;
    end if;
  end loop;
  return jsonb_build_object('made', made, 'cancelled', gone);
end $$;
revoke all on function public.ops_engagement_sync_reports(uuid, boolean) from public, anon, authenticated;

-- END OF A MONTH'S EDITS REACH ITS REPORTS ---------------------------------
