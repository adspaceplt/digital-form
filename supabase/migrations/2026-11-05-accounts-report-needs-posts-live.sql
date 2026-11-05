-- ===========================================================================
-- ACCOUNTS REPORT WAITS ON ITS POSTS GOING LIVE (2026-11-05)
-- ===========================================================================
-- WHY: the user, on an Accounts Report reading "0 of 8 planned" at Check and
-- submit: every planned post must be a My Work task at the posted stage
-- (Live, Performance review or Completed) with all its dates in (Draft due,
-- Due date, Post date and the day it went live) before the report goes on
-- ("All four"; who may go past it stays as today: an admin or Reports Full
-- Access, with a reason). Then: a post that dragged past its month is
-- marked delayed from the report, so the count passes and the task carries
-- the delay for attention until it goes live ("mark delay … will affect
-- the tasks"; the report's writer marks it; its dates stay, so On-time
-- posting still reads it late).
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
--   A post marked delayed counts toward the posts planned (`delayed`) and
--   stays in `lacking` with its reason.
--   `ops_tasks.delayed_at`, `delayed_by`, `delayed_reason` (a date move's
--   reason key), `delayed_note` (300) and `delayed_report`, written only by
--   `sm_report_post_delay(p_report, p_task, p_reason, p_note, p_on)`:
--   Reports Work, a draft report, the client in scope at Work, a content
--   task of the report's month short of posted (`not-draft`,
--   `not-in-month`, `posted`, `bad-reason`, `too-long`); filed on the task
--   (`delayed`, `delay_cleared`) and on the report's record, the task's
--   owner told (kind `delayed`). p_on false takes it off again.
--
-- ORDER: the pages, then this file (an old page draws the Content row as
-- before and submits as before; the database refuses it the same way).
-- Safe to run twice. Rollback: sm_report_gate from REPORT CONTENT COUNTS
-- FOR ACCOUNTS REPORTS again; the columns may stay unread.
-- ===========================================================================

-- ACCOUNTS REPORT WAITS ON ITS POSTS GOING LIVE ----------------------------

alter table public.ops_tasks add column if not exists delayed_at timestamptz;
alter table public.ops_tasks add column if not exists delayed_by uuid;
alter table public.ops_tasks add column if not exists delayed_reason text;
alter table public.ops_tasks add column if not exists delayed_note text;
alter table public.ops_tasks add column if not exists delayed_report uuid;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ops_tasks_delayed_shape') then
    alter table public.ops_tasks add constraint ops_tasks_delayed_shape
      check ((delayed_at is null) = (delayed_reason is null) and char_length(coalesce(delayed_note, '')) <= 300);
  end if;
end $$;

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
  v_delayed integer := 0;
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
      /* A post that dragged past its month, marked delayed from the
         report, counts toward the posts planned (2026-11-05). */
      select count(*) into v_delayed from public.ops_tasks x
       where x.engagement_id = e.id and x.cancelled_at is null and x.archived_at is null
         and coalesce(x.source_type, '') not in ('report_social', 'report_ads')
         and x.delayed_at is not null
         and not (x.stage_key in ('live', 'performance_review', 'completed')
                  and x.current_first_draft_due_at is not null and x.current_final_due_at is not null
                  and x.publish_at is not null and x.live_at is not null);
      if v_made < e.planned_count then v_missing := v_missing || 'content'::text; end if;
      if v_posted + v_delayed < e.planned_count then v_missing := v_missing || 'posted'::text; end if;
      if v_posted < e.planned_count then
        select coalesce(jsonb_agg(l.j order by l.n), '[]'::jsonb) into v_lacking from (
          select x.task_no as n, jsonb_build_object('id', x.id, 'task_no', x.task_no, 'code', x.code,
                   'delayed', x.delayed_at is not null, 'delayed_reason', x.delayed_reason, 'delayed_note', x.delayed_note,
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
    'planned', coalesce(e.planned_count, 0), 'made', v_made, 'posted', v_posted, 'delayed', v_delayed, 'lacking', v_lacking,
    'task', case when task.id is null then null else jsonb_build_object(
              'id', task.id, 'task_no', task.task_no, 'stage_key', task.stage_key) end,
    'due', v_due, 'late', now() > v_due,
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'));
end $$;
revoke all on function public.sm_report_gate(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_gate(uuid) to authenticated;

/* Mark delay (2026-11-05): a post of the report's month short of posted,
   marked from the report so the count passes; the task carries the delay
   until it goes live. Its dates are left as planned. */
create or replace function public.sm_report_post_delay(p_report uuid, p_task uuid, p_reason text, p_note text default null, p_on boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  e public.ops_engagements;
  t public.ops_tasks;
  v_owner uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_word text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = r.client_id and x.status <> 'cancelled'
     and r.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null or e.id is null or r.kind <> 'social' or t.engagement_id is distinct from e.id
     or t.cancelled_at is not null or t.archived_at is not null
     or coalesce(t.source_type, '') in ('report_social', 'report_ads') then
    return jsonb_build_object('error', 'not-in-month');
  end if;
  if not coalesce(p_on, true) then
    if t.delayed_at is null then return jsonb_build_object('ok', true, 'id', t.id); end if;
    update public.ops_tasks set delayed_at = null, delayed_by = null, delayed_reason = null, delayed_note = null,
           delayed_report = null, version = version + 1, updated_at = now()
     where id = t.id;
    perform public.ops_log(t.id, 'delay_cleared', jsonb_build_object('reason', t.delayed_reason), '{}'::jsonb,
      jsonb_build_object('report_id', r.id));
    perform public.sm_report_log(r.id, 'report.saved', coalesce(t.code, public.ops_serial(t.task_no)) || ' no longer marked delayed');
    return jsonb_build_object('ok', true, 'id', t.id);
  end if;
  if t.stage_key in ('live', 'performance_review', 'completed')
     and t.current_first_draft_due_at is not null and t.current_final_due_at is not null
     and t.publish_at is not null and t.live_at is not null then
    return jsonb_build_object('error', 'posted');
  end if;
  v_word := case p_reason when 'client_request' then 'Client request' when 'scope_change' then 'Scope change'
    when 'capacity' then 'Internal capacity' when 'pending_assets' then 'Pending assets'
    when 'pending_confirmation' then 'Pending confirmation' end;
  if v_word is null then return jsonb_build_object('error', 'bad-reason'); end if;
  if char_length(coalesce(v_note, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  update public.ops_tasks set delayed_at = now(), delayed_by = me.id, delayed_reason = p_reason, delayed_note = v_note,
         delayed_report = r.id, version = version + 1, updated_at = now()
   where id = t.id;
  perform public.ops_log(t.id, 'delayed', '{}'::jsonb,
    jsonb_build_object('reason', p_reason, 'note', v_note), jsonb_build_object('report_id', r.id));
  perform public.sm_report_log(r.id, 'report.saved',
    coalesce(t.code, public.ops_serial(t.task_no)) || ' marked delayed: ' || v_word || coalesce(' · ' || v_note, ''));
  select a.team_member_id into v_owner from public.ops_task_assignees a
   where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null limit 1;
  if v_owner is not null and v_owner <> me.id then
    perform public.ops_notify(v_owner, t.id, 'delayed', public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
      'Marked delayed in the Accounts Report by ' || coalesce(nullif(me.name, ''), me.email) || ': ' || v_word || '.',
      'delayed:' || t.id::text || ':' || v_owner::text || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI'));
  end if;
  return jsonb_build_object('ok', true, 'id', t.id);
end $$;
revoke all on function public.sm_report_post_delay(uuid, uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.sm_report_post_delay(uuid, uuid, text, text, boolean) to authenticated;

-- END OF ACCOUNTS REPORT WAITS ON ITS POSTS GOING LIVE ---------------------

select public.functions_tidy();
