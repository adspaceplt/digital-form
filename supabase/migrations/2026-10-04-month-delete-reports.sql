-- ===========================================================================
-- A DELETED MONTH TAKES ITS REPORT TASKS — the report tasks a month made for
-- itself and nobody has started are cancelled when the month is deleted.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two. Runs after MONTH REPORTS.
--
-- WHAT CHANGED
--   1. `ops_engagement_cancel_reports(month, kinds, note)`: each of the
--      month's open report tasks of those kinds still at its workflow's first
--      stage is cancelled, filed with the note; one already started is kept.
--      One copy, used by the two below.
--   2. `ops_engagement_sync_reports` cancels a report unticked through it.
--   3. `ops_delete_engagement` cancels both kinds through it before the month
--      goes ("The month was deleted."), so a month keyed for the wrong client
--      or period leaves no report owed behind. Every other task leaves the
--      month as before, and the record counts the reports cancelled.
--
-- ROLLBACK
--   Run the MONTH REPORTS section's ops_engagement_sync_reports and THE
--   MONTH IN TWO TICKS section's ops_delete_engagement again, then remove
--   the function ops_engagement_cancel_reports(uuid, text[], text).
-- ===========================================================================

-- A month's report tasks nobody has started, cancelled with a note.
create or replace function public.ops_engagement_cancel_reports(p_engagement uuid, p_kinds text[], p_note text)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  t public.ops_tasks;
  v_first text;
  gone integer := 0;
begin
  for t in select * from public.ops_tasks x
            where x.engagement_id = p_engagement
              and x.source_type in (select 'report_' || k from unnest(coalesce(p_kinds, '{}'::text[])) k)
              and x.cancelled_at is null and x.archived_at is null and x.completed_at is null loop
    select s.key into v_first from public.ops_workflow_stages s
     where s.workflow_id = t.workflow_id order by s.position limit 1;
    if t.stage_key = v_first then
      update public.ops_tasks set stage_key = 'cancelled', cancelled_at = now(), updated_at = now(),
             version = version + 1
       where id = t.id;
      perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', t.stage_key),
        jsonb_build_object('stage_key', 'cancelled'), jsonb_build_object('note', p_note));
      gone := gone + 1;
    end if;
  end loop;
  return gone;
end $$;
revoke all on function public.ops_engagement_cancel_reports(uuid, text[], text) from public, anon, authenticated;

-- One live task a report the month asks for; a report no longer asked for
-- cancels its task while it is still To do; a start day moved moves the
-- dates of one still open.
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
  res jsonb;
  made integer := 0;
  gone integer := 0;
begin
  select * into e from public.ops_engagements where id = p_engagement;
  if e.id is null or e.status in ('completed', 'cancelled') then
    return jsonb_build_object('made', 0, 'cancelled', 0);
  end if;
  select s.ends into v_ends from public.ops_month_span(e.period, e.start_day) s;
  v_due := ((v_ends + 7)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  v_draft := ((v_ends + 5)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  foreach k in array array['social', 'ads'] loop
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
        made := made + 1;
      elsif p_moved then
        for t in select * from public.ops_tasks x
                  where x.engagement_id = e.id and x.source_type = 'report_' || k
                    and x.cancelled_at is null and x.archived_at is null and x.completed_at is null loop
          update public.ops_tasks set current_final_due_at = v_due,
                 current_first_draft_due_at = case when first_draft_submitted_at is null then v_draft
                                                   else current_first_draft_due_at end,
                 updated_at = now(), version = version + 1
           where id = t.id;
          if t.current_final_due_at is distinct from v_due then
            perform public.ops_log(t.id, 'due_changed',
              jsonb_build_object('kind', 'final', 'value', t.current_final_due_at),
              jsonb_build_object('kind', 'final', 'value', v_due),
              jsonb_build_object('reason', 'scope_change', 'note', 'The month''s start day moved.'));
          end if;
          if t.first_draft_submitted_at is null and t.current_first_draft_due_at is distinct from v_draft then
            perform public.ops_log(t.id, 'due_changed',
              jsonb_build_object('kind', 'first_draft', 'value', t.current_first_draft_due_at),
              jsonb_build_object('kind', 'first_draft', 'value', v_draft),
              jsonb_build_object('reason', 'scope_change', 'note', 'The month''s start day moved.'));
          end if;
        end loop;
      end if;
    else
      gone := gone + public.ops_engagement_cancel_reports(e.id, array[k], 'The month no longer asks for this report.');
    end if;
  end loop;
  return jsonb_build_object('made', made, 'cancelled', gone);
end $$;
revoke all on function public.ops_engagement_sync_reports(uuid, boolean) from public, anon, authenticated;

/* A month keyed in for the wrong client or the wrong period has to be able
   to go. ops Manage, a reason, and a row in the activity record, because the
   month's own history goes with it. Its tasks are not deleted: they stay, with
   their codes, and simply leave the month; the report tasks it made and
   nobody has started are cancelled first. */
create or replace function public.ops_delete_engagement(p_engagement uuid, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m  public.team_members;
  e  public.ops_engagements;
  cl text;
  n  integer;
  v_gone integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return jsonb_build_object('error', 'reason-required');
  end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select c.name into cl from public.clients c where c.id = e.client_id;
  v_gone := public.ops_engagement_cancel_reports(e.id, array['social', 'ads'], 'The month was deleted.');
  select count(*) into n from public.ops_tasks t where t.engagement_id = e.id;

  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.month_deleted', coalesce(cl, 'Client'),
          to_char(to_date(e.period || '-01', 'YYYY-MM-DD'), 'Mon YYYY') ||
          case when n = 1 then ' · 1 task left the month'
               when n > 1 then ' · ' || n || ' tasks left the month' else '' end ||
          case when v_gone = 1 then ' · 1 report task cancelled'
               when v_gone > 1 then ' · ' || v_gone || ' report tasks cancelled' else '' end ||
          ' · ' || btrim(p_reason));

  delete from public.ops_engagements where id = e.id;
  return jsonb_build_object('deleted', true, 'period', e.period, 'tasks', n, 'cancelled', v_gone);
end $$;
grant execute on function public.ops_delete_engagement(uuid, text) to authenticated;

-- END OF A DELETED MONTH TAKES ITS REPORT TASKS -------------------------------
