-- ===========================================================================
-- REPORT CONTENT COUNTS FOR ACCOUNTS REPORTS — a month's planned content
-- holds its Accounts Report alone (2026-11-02)
-- ===========================================================================
-- WHY: the user, on an Advertising Report held at Check and submit by
-- "Content 0 of 6 planned": an Advertising Report reports the ads, never the
-- posts, so the month's content tasks are not its to wait on ("Yes", to
-- holding the content check to Accounts Reports).
--
-- WHAT IT CHANGES
--   `sm_report_gate` (restated whole from SALES BY): `content` is missing
--   only for an Accounts Report (`kind` social). Every other check, the
--   due time and who may go past the gate are unchanged; `planned` and
--   `made` are still answered.
--
-- ORDER: this file, then the pages (an old page draws a Content row the
-- function no longer holds against an Advertising Report, and submits).
-- Safe to run twice. Rollback: sm_report_gate from SALES BY again.
-- ===========================================================================

-- REPORT CONTENT COUNTS FOR ACCOUNTS REPORTS -------------------------------

create or replace function public.sm_report_gate(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  e public.ops_engagements;
  task public.ops_tasks;
  v_starts date;
  v_ends date;
  v_due timestamptz;
  v_made integer := 0;
  v_missing text[] := '{}';
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.period_start < date '2026-10-01' or r.on_request then
    return jsonb_build_object('applies', false, 'ok', true, 'missing', '[]'::jsonb, 'on_request', r.on_request);
  end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = r.client_id and x.status <> 'cancelled'
     and r.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then
    v_missing := v_missing || 'no-month'::text;
    v_due := ((r.period_end + public.app_setting('report_due_days', r.period_end)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  else
    select s.starts, s.ends into v_starts, v_ends from public.ops_month_span(e.period, e.start_day) s;
    v_due := ((v_ends + public.app_setting('report_due_days', v_ends)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
    if not (r.kind = any (e.reports)) then
      v_missing := v_missing || 'not-ticked'::text;
    else
      select * into task from public.ops_tasks x
       where x.engagement_id = e.id and x.source_type = 'report_' || r.kind
         and x.cancelled_at is null and x.archived_at is null
       order by x.created_at desc limit 1;
      if task.id is null then
        v_missing := v_missing || 'no-task'::text;
      else
        v_due := coalesce(task.current_final_due_at, v_due);
      end if;
    end if;
    select count(*) into v_made from public.ops_tasks x
     where x.engagement_id = e.id and x.cancelled_at is null and x.archived_at is null
       and coalesce(x.source_type, '') not in ('report_social', 'report_ads');
    /* Planned content holds an Accounts Report alone: an Advertising
       Report reports the ads, never the posts (2026-11-02). */
    if r.kind = 'social' and v_made < e.planned_count then v_missing := v_missing || 'content'::text; end if;
  end if;
  return jsonb_build_object(
    'applies', true, 'ok', cardinality(v_missing) = 0, 'missing', to_jsonb(v_missing),
    'month', case when e.id is null then null else jsonb_build_object(
               'id', e.id, 'period', e.period, 'start_day', e.start_day, 'starts', v_starts, 'ends', v_ends,
               'reports', to_jsonb(e.reports)) end,
    'planned', coalesce(e.planned_count, 0), 'made', v_made,
    'task', case when task.id is null then null else jsonb_build_object(
              'id', task.id, 'task_no', task.task_no, 'stage_key', task.stage_key) end,
    'due', v_due, 'late', now() > v_due,
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'));
end $$;
revoke all on function public.sm_report_gate(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_gate(uuid) to authenticated;

-- END OF REPORT CONTENT COUNTS FOR ACCOUNTS REPORTS ------------------------

select public.functions_tidy();
