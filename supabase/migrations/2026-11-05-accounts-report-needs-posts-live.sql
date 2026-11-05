-- ===========================================================================
-- ACCOUNTS REPORT WAITS ON ITS POSTS GOING LIVE (2026-11-05)
-- ===========================================================================
-- WHY: the user, on an Accounts Report reading "0 of 8 planned" at Check and
-- submit: every planned post must be a My Work task at the posted stage
-- (Live, Performance review or Completed) with all its dates in (Draft due,
-- Due date, Post date and the day it went live) before the report goes on
-- ("All four"; who may go past it stays as today: an admin or Reports Full
-- Access, with a reason).
--
-- WHAT IT CHANGES
--   `sm_report_gate` (restated whole from REPORT CONTENT COUNTS FOR
--   ACCOUNTS REPORTS): for an Accounts Report, `posted` counts the month's
--   content tasks at Live, Performance review or Completed holding all four
--   dates, and `posted` is missing while it is under the posts planned;
--   `content` still names a month short of tasks. `lacking` names each task
--   not yet counted (its number, code and what it lacks: stage, draft, due,
--   post, live), twenty at most, while the posts are short. Every other
--   check, the due time and who may go past the gate are unchanged.
--
-- ORDER: the pages, then this file (an old page draws the Content row as
-- before and submits as before; the database refuses it the same way).
-- Safe to run twice. Rollback: sm_report_gate from REPORT CONTENT COUNTS
-- FOR ACCOUNTS REPORTS again.
-- ===========================================================================

-- ACCOUNTS REPORT WAITS ON ITS POSTS GOING LIVE ----------------------------

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
  v_posted integer := 0;
  v_lacking jsonb := '[]'::jsonb;
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
       Report reports the ads, never the posts (2026-11-02). A post counts
       once it has gone live and holds every date (2026-11-05). */
    if r.kind = 'social' then
      select count(*) into v_posted from public.ops_tasks x
       where x.engagement_id = e.id and x.cancelled_at is null and x.archived_at is null
         and coalesce(x.source_type, '') not in ('report_social', 'report_ads')
         and x.stage_key in ('live', 'performance_review', 'completed')
         and x.current_first_draft_due_at is not null and x.current_final_due_at is not null
         and x.publish_at is not null and x.live_at is not null;
      if v_made < e.planned_count then v_missing := v_missing || 'content'::text; end if;
      if v_posted < e.planned_count then
        v_missing := v_missing || 'posted'::text;
        select coalesce(jsonb_agg(l.j order by l.n), '[]'::jsonb) into v_lacking from (
          select x.task_no as n, jsonb_build_object('id', x.id, 'task_no', x.task_no, 'code', x.code,
                   'needs', to_jsonb(array_remove(array[
                     case when x.stage_key not in ('live', 'performance_review', 'completed') then 'stage' end,
                     case when x.current_first_draft_due_at is null then 'draft' end,
                     case when x.current_final_due_at is null then 'due' end,
                     case when x.publish_at is null then 'post' end,
                     case when x.live_at is null then 'live' end], null))) as j
            from public.ops_tasks x
           where x.engagement_id = e.id and x.cancelled_at is null and x.archived_at is null
             and coalesce(x.source_type, '') not in ('report_social', 'report_ads')
             and not (x.stage_key in ('live', 'performance_review', 'completed')
                      and x.current_first_draft_due_at is not null and x.current_final_due_at is not null
                      and x.publish_at is not null and x.live_at is not null)
           order by x.task_no limit 20) l;
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'applies', true, 'ok', cardinality(v_missing) = 0, 'missing', to_jsonb(v_missing),
    'month', case when e.id is null then null else jsonb_build_object(
               'id', e.id, 'period', e.period, 'start_day', e.start_day, 'starts', v_starts, 'ends', v_ends,
               'reports', to_jsonb(e.reports)) end,
    'planned', coalesce(e.planned_count, 0), 'made', v_made, 'posted', v_posted, 'lacking', v_lacking,
    'task', case when task.id is null then null else jsonb_build_object(
              'id', task.id, 'task_no', task.task_no, 'stage_key', task.stage_key) end,
    'due', v_due, 'late', now() > v_due,
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'));
end $$;
revoke all on function public.sm_report_gate(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_gate(uuid) to authenticated;

-- END OF ACCOUNTS REPORT WAITS ON ITS POSTS GOING LIVE ---------------------

select public.functions_tidy();
