-- ===========================================================================
-- REPORT MONTH GATE — a report is submitted for review only once its month
-- is in order, and on time or with the reason it is late.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after MONTH REPORTS.
--
-- WHAT CHANGED
--   1. `sm_report_gate(p_id)` (Reports View): for a report whose period starts
--      on or after 1 Oct 2026, the client's month whose span holds the
--      report's last day, and what it lacks: `no-month` (no such month),
--      `not-ticked` (the month does not ask for this report), `no-task` (its
--      report task is not there), `content` (fewer content tasks than
--      planned; report tasks and cancelled tasks are not counted). It answers
--      the due time (the report task's, else 23:59 MYT seven days after the
--      month's last day, else after the report's), `late`, and
--      `may_override` (an admin or Reports Full Access). An earlier report is
--      not gated. A report the caller may not see answers `denied`.
--   2. `sm_report_submit(p_id, p_reviewer, p_reason)`: after the report's own
--      contents, a report that fails the gate is refused `month-gate` with
--      what it lacks, unless an admin or Reports Full Access gives a reason;
--      a late report is refused `late-reason` until a reason is given. The
--      reason is kept on the report (`late_reason`, `gate_note`) and filed
--      with the submission.
--   3. `sm_report_guard` keeps both columns to the functions.
--
-- ROLLBACK
--   Run the REPORT REVIEWER section's sm_report_guard and sm_report_submit
--   again, remove the function sm_report_gate(uuid), then
--   alter table public.sm_reports drop column if exists late_reason,
--     drop column if exists gate_note;
-- ===========================================================================

alter table public.sm_reports add column if not exists late_reason text;
alter table public.sm_reports add column if not exists gate_note text;

create or replace function public.sm_report_guard()
returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('adspace.sm_fn', true), '') = 'on' then
    new.updated_at := now();
    return new;
  end if;
  if new.status is distinct from old.status or new.version_no is distinct from old.version_no
     or new.submitted_by is distinct from old.submitted_by or new.submitted_at is distinct from old.submitted_at
     or new.confirmed_by is distinct from old.confirmed_by or new.confirmed_at is distinct from old.confirmed_at
     or new.return_note is distinct from old.return_note or new.client_id is distinct from old.client_id
     or new.kind is distinct from old.kind or new.reviewer_id is distinct from old.reviewer_id
     or new.late_reason is distinct from old.late_reason or new.gate_note is distinct from old.gate_note
     or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'sm-status-by-function' using errcode = 'P0001';
  end if;
  if old.status <> 'draft' then
    raise exception 'sm-not-draft' using errcode = 'P0001';
  end if;
  new.updated_at := now();
  return new;
end $$;
revoke all on function public.sm_report_guard() from public, anon, authenticated;

-- What a report's month lacks, and when the report is due.
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
  if not public.client_row_seen(c.stage, c.owner, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.period_start < date '2026-10-01' then
    return jsonb_build_object('applies', false, 'ok', true, 'missing', '[]'::jsonb);
  end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = r.client_id and x.status <> 'cancelled'
     and r.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then
    v_missing := v_missing || 'no-month'::text;
    v_due := ((r.period_end + 7)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  else
    select s.starts, s.ends into v_starts, v_ends from public.ops_month_span(e.period, e.start_day) s;
    v_due := ((v_ends + 7)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
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
    if v_made < e.planned_count then v_missing := v_missing || 'content'::text; end if;
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

/* `p_reason` is the reason a late submit, or one past the month's gate,
   gives; it is read from MONTH REPORTS (2026-10-04) on. */
create or replace function public.sm_report_submit(p_id uuid, p_reviewer uuid default null, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  cname text;
  g jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_gate text;
  v_late text;
  v_extra text := '';
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if r.kind = 'ads' then
    if not exists (select 1 from public.sm_report_ads where report_id = p_id) then
      return jsonb_build_object('error', 'no-ads');
    end if;
  else
    if not exists (select 1 from public.sm_report_platforms where report_id = p_id) then
      return jsonb_build_object('error', 'no-platforms');
    end if;
    if not exists (select 1 from public.sm_report_posts where report_id = p_id) then
      return jsonb_build_object('error', 'no-posts');
    end if;
  end if;
  g := public.sm_report_gate(p_id);
  if coalesce((g ->> 'applies')::boolean, false) then
    if not (g ->> 'ok')::boolean then
      if not (g ->> 'may_override')::boolean or v_reason is null then
        return jsonb_build_object('error', 'month-gate', 'missing', g -> 'missing', 'planned', g -> 'planned',
                                  'made', g -> 'made', 'may_override', g -> 'may_override');
      end if;
      v_gate := left(v_reason, 500);
    end if;
    if (g ->> 'late')::boolean then
      if v_reason is null then
        return jsonb_build_object('error', 'late-reason', 'due', g -> 'due');
      end if;
      v_late := left(v_reason, 500);
    end if;
  end if;
  if p_reviewer is null then return jsonb_build_object('error', 'no-reviewer'); end if;
  if p_reviewer = me.id then return jsonb_build_object('error', 'self-review'); end if;
  if not public.sm_report_may_review(p_reviewer) then return jsonb_build_object('error', 'bad-reviewer'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'review', submitted_by = me.id, submitted_at = now(),
    reviewer_id = p_reviewer, return_note = null, confirmed_by = null, confirmed_at = null,
    late_reason = v_late, gate_note = v_gate where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  if v_gate is not null then v_extra := v_extra || ' · Past the month''s gate: ' || v_gate; end if;
  if v_late is not null and v_gate is distinct from v_late then v_extra := v_extra || ' · Late: ' || v_late;
  elsif v_late is not null then v_extra := v_extra || ' · Late'; end if;
  perform public.sm_report_log(p_id, 'report.submitted',
    'Reviewer: ' || (select name from public.team_members where id = p_reviewer) || v_extra);
  select c.name into cname from public.clients c where c.id = r.client_id;
  perform public.sm_report_notify(p_reviewer, p_id, 'report.review', 'Report to review',
    cname || ' · ' || public.sm_period_word(r.period_start, r.period_end));
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
revoke all on function public.sm_report_submit(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.sm_report_submit(uuid, uuid, text) to authenticated;

-- END OF REPORT MONTH GATE ---------------------------------------------------
