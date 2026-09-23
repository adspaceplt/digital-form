-- ===========================================================================
-- MY WORK AS A DAILY TASK TRACKER — everyday tasks, quick creation, comments,
-- checklist items, templates, and the next-step rules the task page shows.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   A task is one finishable action. Most of them do not need the content
--   workflow's nine stages and its gates, so there is a second, small
--   workflow for them: `task` — To do, In progress, Waiting, Review, Done —
--   where any stage may follow any other and nothing is gated. A content
--   deliverable stays on the content workflow with every gate it had.
--
--   1. The `task` workflow, seeded once, into a database that has none.
--
--   2. `ops_create_task` names an everyday task by what it is (no content
--      code), takes the client and the month from a linked engagement, and
--      takes a template's default title, owner and due offset in calendar
--      days from a base date.
--
--   3. `ops_transition_task`: skipping a step is a manual override and needs
--      ops Manage (every move the workflow lists stays at ops Work); and a
--      move into a terminal stage closes every running timer on the task.
--
--   4. `ops_hand_over_task` (ops Manage, the note kept on the event),
--      `ops_set_publish_date` (ops Work), `ops_add_checklist_item` and
--      `ops_add_comment` (ops Work), `ops_save_template` (the granted part
--      ops.workflows, Work).
--
--   5. Three columns on `ops_task_templates` (default_title,
--      default_owner_id, due_offset_days) and one index for cancelled work.
--
--   No existing task is rewritten, moved or renamed. No policy changes.
--
-- Rollback: re-run sections 9.8 and 9.10 of 2026-09-23-operations-phase4.sql
-- (the previous ops_create_task and ops_transition_task), then
--   drop function if exists public.ops_hand_over_task(uuid, uuid, text, integer);
--   drop function if exists public.ops_set_publish_date(uuid, timestamptz, integer);
--   drop function if exists public.ops_add_checklist_item(uuid, text);
--   drop function if exists public.ops_add_comment(uuid, text);
--   drop function if exists public.ops_save_template(uuid, jsonb);
--   drop index if exists public.ops_tasks_cancelled_idx;
-- The `task` workflow and the three template columns may stay: nothing reads
-- them once the functions are rolled back. Remove them only where no task was
-- created on the workflow:
--   delete from public.ops_workflow_stages where workflow_id in
--     (select id from public.ops_workflows where key = 'task');
--   delete from public.ops_workflows where key = 'task';
-- ===========================================================================

-- 1. The everyday workflow ------------------------------------------------------
do $$
declare w uuid;
begin
  if exists (select 1 from public.ops_workflows where key = 'task') then return; end if;
  insert into public.ops_workflows (key, name, description)
  values ('task', 'Everyday task', 'To do, in progress, waiting, review and done.')
  returning id into w;
  insert into public.ops_workflow_stages
    (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
     is_review, is_terminal, wip_guidance, next_stage_keys) values
    (w, 'todo',      'To do',       1, 'intake',          false, false, false, false, null, array['doing','waiting','review','complete','cancelled']),
    (w, 'doing',     'In progress', 2, 'active',          true,  false, false, false, null, array['todo','waiting','review','complete','cancelled']),
    (w, 'waiting',   'Waiting',     3, 'waiting',         false, true,  false, false, null, array['todo','doing','review','complete','cancelled']),
    (w, 'review',    'Review',      4, 'internal_review', false, true,  true,  false, null, array['todo','doing','waiting','complete','cancelled']),
    (w, 'complete',  'Done',        5, 'done',            false, false, false, true,  null, array['todo','doing']),
    (w, 'cancelled', 'Cancelled',   6, 'cancelled',       false, false, false, true,  null, array['todo']);
end $$;

alter table public.ops_task_templates add column if not exists default_title    text;
alter table public.ops_task_templates add column if not exists default_owner_id uuid references public.team_members(id);
alter table public.ops_task_templates add column if not exists due_offset_days  integer;
create index if not exists ops_tasks_cancelled_idx on public.ops_tasks(cancelled_at desc)
  where cancelled_at is not null;

-- 2. Making a task --------------------------------------------------------------
create or replace function public.ops_create_task(p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  tpl   public.ops_task_templates;
  wf    uuid;
  tid   uuid;
  owner uuid;
  publish timestamptz;
  fd    timestamptz;
  fin   timestamptz;
  item  jsonb;
  i     integer := 0;
  scope text;
  ttype text;
  cid   uuid;
  bad   text;
  descr text;
  period text;
  week  integer;
  seq   integer;
  code  text;
  title text;
  first_stage text;
  wkey  text;
  base  timestamptz;
  eng   public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  scope := coalesce(p_payload ->> 'scope', 'client');
  cid := (p_payload ->> 'client_id')::uuid;
  /* A task linked to a month's engagement takes the client from it: the
     person names the month once and the client comes with it. */
  if (p_payload ->> 'engagement_id') is not null then
    select * into eng from public.ops_engagements where id = (p_payload ->> 'engagement_id')::uuid;
    if eng.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if cid is null then cid := eng.client_id; scope := 'client'; end if;
  end if;
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;

  ttype := coalesce(p_payload ->> 'task_type', 'adhoc');
  if ttype not in ('engagement', 'adhoc', 'goodwill', 'special') then
    return jsonb_build_object('error', 'bad-task-type');
  end if;

  /* The description is the team's to edit and may start blank on a task that
     carries a code; a task with no code is named by its description alone, so
     there it is required. `title` is accepted from older callers as the
     description. */
  descr := nullif(btrim(coalesce(p_payload ->> 'content_desc', p_payload ->> 'title', '')), '');

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
    descr := coalesce(descr, nullif(btrim(coalesce(tpl.default_title, tpl.name, '')), ''));
  end if;
  /* New work goes on the content workflow. A caller may still name another
     (a template's own, or one somebody adds), and a task already on a retired
     workflow is never moved. */
  wf := coalesce((p_payload ->> 'workflow_id')::uuid,
                 (select id from public.ops_workflows where key = p_payload ->> 'workflow_key' and active),
                 tpl.workflow_id,
                 (select id from public.ops_workflows where key = 'content' and active),
                 (select id from public.ops_workflows where active order by created_at limit 1));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  select key into first_stage from public.ops_workflow_stages
   where workflow_id = wf order by position limit 1;
  select key into wkey from public.ops_workflows where id = wf;

  publish := (p_payload ->> 'publish_at')::timestamptz;
  fd := coalesce((p_payload ->> 'first_draft_due_at')::timestamptz,
        case when publish is not null and tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.first_draft_offset_business_days)
             when tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.first_draft_offset_business_days)
        end);
  /* A template's due date is a number of calendar days from the day the
     work is made for (the base date the caller names, else today). */
  base := coalesce((p_payload ->> 'base_date')::timestamptz, now());
  fin := coalesce((p_payload ->> 'final_due_at')::timestamptz,
        case when tpl.due_offset_days is not null
             then date_trunc('day', base) + make_interval(days => tpl.due_offset_days)
             when publish is not null and tpl.final_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.final_offset_business_days)
             when tpl.final_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.final_offset_business_days)
        end);
  if fd is not null and fin is not null and not public.ops_due_order_ok(fd, fin) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  /* The name. The month is the content month (the scheduled publish date's,
     else the one the caller names, else this one); the week is the planned
     publishing week, chosen by the caller and prefilled by the page from the
     date; the running number is the client's for the month. Generated once,
     under the lock, and never rewritten: a publish date that moves later
     leaves the name as it was, because the name is a label and not a fact
     about the date. */
  if wkey = 'task' then
    /* An everyday task is named by what it is. It carries no content code,
       because the code numbers a client's deliverables for the month and a
       task is not one; the content month is kept where it is known, so the
       task can be grouped with the month it belongs to. */
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
    period := coalesce(nullif(p_payload ->> 'code_period', ''), eng.period);
  elsif scope <> 'internal' then
    period := coalesce(nullif(p_payload ->> 'code_period', ''),
                       case when publish is not null then to_char(publish, 'YYYY-MM') end,
                       to_char(now(), 'YYYY-MM'));
    if period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
    week := coalesce((p_payload ->> 'code_week')::integer,
                     case when publish is not null
                          then least(5, ((extract(day from publish)::integer - 1) / 7) + 1) end,
                     1);
    if week < 1 or week > 5 then return jsonb_build_object('error', 'bad-week'); end if;
    seq := public.ops_next_seq(cid, period);
    code := public.ops_code_of(period, week, seq);
    title := btrim(code || ' ' || coalesce(descr, ''));
  else
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
  end if;

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality,
    task_type, code, code_period, code_week, code_seq, content_desc,
    engagement_id, manager_id, parent_task_id)
  values (
    scope, cid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, coalesce(first_stage, 'intake'),
    title, p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'other'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'),
    ttype, code, period, week, seq, descr,
    coalesce((p_payload ->> 'engagement_id')::uuid, eng.id),
    coalesce((p_payload ->> 'manager_id')::uuid, m.id),
    (p_payload ->> 'parent_task_id')::uuid)
  returning id into tid;

  owner := coalesce((p_payload ->> 'owner_id')::uuid, tpl.default_owner_id);
  if owner is not null then
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (tid, owner, 'owner', m.id);
    perform public.ops_log(tid, 'assignment_changed', null,
      jsonb_build_object('owner_id', owner), '{}'::jsonb);
  end if;
  if (p_payload ->> 'reviewer_id') is not null then
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (tid, (p_payload ->> 'reviewer_id')::uuid, 'reviewer', m.id);
  end if;

  -- The template's checklist, or the one the caller hands over (a duplicate
  -- carries its source's labels, unticked), in the order stated.
  for item in select * from jsonb_array_elements(
      coalesce(p_payload -> 'checklist', tpl.checklist, '[]'::jsonb)) loop
    i := i + 1;
    insert into public.ops_task_checklist_items (task_id, label, position)
    values (tid, item #>> '{}', i);
  end loop;

  if (p_payload -> 'video') is not null then
    insert into public.ops_video_details (
      task_id, output_duration_seconds, footage_duration_seconds,
      subtitle_required, motion_graphics_required, aspect_ratios,
      script_ready, footage_ready, shoot_required, shoot_at, variant_count)
    values (tid,
      ((p_payload -> 'video') ->> 'output_duration_seconds')::integer,
      ((p_payload -> 'video') ->> 'footage_duration_seconds')::integer,
      coalesce(((p_payload -> 'video') ->> 'subtitle_required')::boolean, false),
      coalesce(((p_payload -> 'video') ->> 'motion_graphics_required')::boolean, false),
      coalesce((select array_agg(x) from jsonb_array_elements_text(
                 coalesce((p_payload -> 'video') -> 'aspect_ratios', '[]'::jsonb)) x), '{}'),
      ((p_payload -> 'video') ->> 'script_ready')::boolean,
      ((p_payload -> 'video') ->> 'footage_ready')::boolean,
      coalesce(((p_payload -> 'video') ->> 'shoot_required')::boolean, false),
      ((p_payload -> 'video') ->> 'shoot_at')::timestamptz,
      coalesce(((p_payload -> 'video') ->> 'variant_count')::integer, 1));
  end if;

  perform public.ops_log(tid, 'task_created', null,
    jsonb_build_object('title', title, 'code', code,
                       'first_draft_due_at', fd, 'final_due_at', fin),
    case when (p_payload ->> 'duplicated_from') is null then '{}'::jsonb
         else jsonb_build_object('duplicated_from', p_payload ->> 'duplicated_from') end);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

-- 3. Moving a task --------------------------------------------------------------
/* The phase 4 move, with two rules added: a skip is an override, and a
   finished task stops its timers. */
create or replace function public.ops_transition_task(
  p_task uuid, p_next text, p_version integer default null, p_note text default null,
  p_assignee uuid default null, p_skip_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cur public.ops_workflow_stages;
  nxt public.ops_workflow_stages;
  sk  public.ops_workflow_stages;
  eng public.ops_engagements;
  has_owner boolean;
  has_draft boolean;
  has_final boolean;
  was_owner uuid;
  side text[] := array['blocked', 'waiting', 'kiv', 'cancelled'];
  skipping boolean := false;
  ws  public.ops_work_sessions;
  wmins integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if t.stage_key = p_next then return public.ops_task_json(p_task); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  if not (p_next = any (cur.next_stage_keys)) then
    /* A step the deliverable does not need is skipped, forward along the
       line, with a reason on the record: who skipped it and why is written
       against every stage that was passed over. Nothing beside the line can
       be skipped into or out of, and nothing is skipped backwards. */
    if not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.position > cur.position then
      /* Passing over a step is a manual override of the workflow, so it is
         the section's Manage level. A hidden control is not the gate. */
      if not public.allowed('ops', 'manage') then
        return jsonb_build_object('error', 'override-denied');
      end if;
      if nullif(btrim(coalesce(p_skip_reason, '')), '') is null then
        return jsonb_build_object('error', 'skip-reason-required');
      end if;
      skipping := true;
    else
      return jsonb_build_object('error', 'bad-transition',
        'allowed', to_jsonb(cur.next_stage_keys));
    end if;
  end if;

  -- What each gate needs before it opens.
  has_owner := exists (select 1 from public.ops_task_assignees
                        where task_id = p_task and responsibility = 'owner' and ended_at is null)
               or p_assignee is not null;
  has_draft := exists (select 1 from public.ops_task_links
                        where task_id = p_task and archived_at is null
                          and kind in ('draft', 'review'));
  has_final := exists (select 1 from public.ops_task_links
                        where task_id = p_task and archived_at is null and kind = 'final');

  if p_next = 'ready' and (not has_owner or t.current_final_due_at is null) then
    return jsonb_build_object('error', 'ready-needs-owner-and-due');
  end if;
  if p_next = 'editing' and exists (
       select 1 from public.ops_video_details v
        where v.task_id = p_task and v.footage_ready is false) then
    return jsonb_build_object('error', 'footage-not-ready');
  end if;
  /* Production waits on the engagement: planning marked complete, and the
     content meeting held or marked not applicable. A task with no engagement
     (ad hoc, internal) has nothing to wait on. */
  if p_next = 'in_production' and t.engagement_id is not null then
    select * into eng from public.ops_engagements where id = t.engagement_id;
    if eng.status = 'planning' then return jsonb_build_object('error', 'planning-incomplete'); end if;
    if not (eng.meeting_na or (eng.meeting_at is not null and eng.meeting_at <= now())) then
      return jsonb_build_object('error', 'meeting-required');
    end if;
  end if;
  if p_next = 'client_review' and not has_draft then
    return jsonb_build_object('error', 'needs-draft');
  end if;
  if p_next = 'delivered' and not has_final then
    return jsonb_build_object('error', 'needs-final-link');
  end if;
  if p_next = 'done' and t.delivered_at is null
     and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-delivery-or-reason');
  end if;
  if p_next = 'published' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;

  /* The hand to the next person, recorded on the move: the previous owner
     ends, the new one begins, and the event names both with the stage it
     happened at. Work level, because handing the work on is part of doing
     it; reassigning a task without moving it stays Manage. */
  if p_assignee is not null then
    select team_member_id into was_owner from public.ops_task_assignees
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    if p_assignee is distinct from was_owner then
      if not exists (select 1 from public.team_members where id = p_assignee and active) then
        return jsonb_build_object('error', 'no-such-person');
      end if;
      update public.ops_task_assignees set ended_at = now()
       where task_id = p_task and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, p_assignee, 'owner', m.id);
      perform public.ops_log(p_task, 'assignment_changed',
        jsonb_build_object('owner_id', was_owner),
        jsonb_build_object('owner_id', p_assignee),
        jsonb_build_object('handover', true, 'stage_key', p_next, 'from_stage_key', t.stage_key));
    end if;
  end if;

  if skipping then
    for sk in select * from public.ops_workflow_stages
               where workflow_id = t.workflow_id
                 and position > cur.position and position < nxt.position
                 and not (stage_group = any (side))
               order by position loop
      perform public.ops_log(p_task, 'stage_skipped',
        jsonb_build_object('stage_key', sk.key), jsonb_build_object('stage_key', p_next),
        jsonb_build_object('reason', btrim(p_skip_reason)));
    end loop;
  end if;

  update public.ops_tasks set
    stage_key = p_next,
    version = version + 1,
    updated_at = now(),
    first_draft_submitted_at = case
      when first_draft_submitted_at is null and nxt.is_review then now()
      else first_draft_submitted_at end,
    delivered_at = case when p_next = 'delivered' then coalesce(delivered_at, now())
                        else delivered_at end,
    completed_at = case when nxt.is_terminal and p_next <> 'cancelled' then coalesce(completed_at, now())
                        when not nxt.is_terminal then null
                        else completed_at end,
    cancelled_at = case when p_next = 'cancelled' then coalesce(cancelled_at, now())
                        else cancelled_at end,
    blocked_at = case when p_next = 'blocked' then blocked_at else null end,
    blocked_category = case when p_next = 'blocked' then blocked_category else null end
  where id = p_task;

  /* A finished task is not being worked on, so every timer running on it
     stops with it, each filed as the stop it is. */
  if nxt.is_terminal then
    for ws in select * from public.ops_work_sessions
               where task_id = p_task and ended_at is null loop
      wmins := greatest(0, (extract(epoch from (now() - ws.started_at)) / 60)::integer);
      update public.ops_work_sessions set ended_at = now(), minutes = wmins where id = ws.id;
      perform public.ops_log(p_task, 'work_stopped', null,
        jsonb_build_object('session_id', ws.id, 'minutes', wmins),
        jsonb_build_object('note', 'Stopped when the task finished'));
    end loop;
  end if;

  perform public.ops_log(p_task, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', p_next),
    (case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end)
    || (case when skipping then jsonb_build_object('skip_reason', btrim(p_skip_reason)) else '{}'::jsonb end));
  if p_next = 'delivered' then
    perform public.ops_log(p_task, 'delivered', null, null, '{}'::jsonb);
  end if;
  if nxt.is_terminal and p_next <> 'cancelled' then
    perform public.ops_log(p_task, 'completed', null, null, '{}'::jsonb);
  end if;
  if p_next = 'cancelled' then
    perform public.ops_log(p_task, 'cancelled', null, null,
      jsonb_build_object('reason', p_note));
  end if;
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_transition_task(uuid, text, integer, text, uuid, text) to authenticated;

/* Changing responsibility without changing the stage. The note is for the
   person taking it on, so it is kept on the event and not in a column. */
create or replace function public.ops_hand_over_task(
  p_task uuid, p_owner uuid, p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if p_owner is null then return jsonb_build_object('error', 'no-such-person'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if not exists (select 1 from public.team_members where id = p_owner and active) then
    return jsonb_build_object('error', 'no-such-person');
  end if;

  select team_member_id into was from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null;
  if p_owner is not distinct from was then return public.ops_task_json(p_task); end if;

  update public.ops_task_assignees set ended_at = now()
   where task_id = p_task and responsibility = 'owner' and ended_at is null;
  insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
  values (p_task, p_owner, 'owner', m.id);
  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'assignment_changed',
    jsonb_build_object('owner_id', was),
    jsonb_build_object('owner_id', p_owner),
    jsonb_build_object('handover', true, 'stage_key', t.stage_key)
      || case when nullif(btrim(coalesce(p_note, '')), '') is null then '{}'::jsonb
              else jsonb_build_object('note', btrim(p_note)) end);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_hand_over_task(uuid, uuid, text, integer) to authenticated;

/* The scheduled publish date: tentative until the content meeting, never
   a commitment, so it moves on the press and gates nothing. */
create or replace function public.ops_set_publish_date(
  p_task uuid, p_at timestamptz, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if t.publish_at is not distinct from p_at then return public.ops_task_json(p_task); end if;

  update public.ops_tasks set publish_at = p_at, version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'publish_changed',
    jsonb_build_object('value', t.publish_at), jsonb_build_object('value', p_at), '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_set_publish_date(uuid, timestamptz, integer) to authenticated;

-- 4. Adding to a task -----------------------------------------------------------
/* One more thing to tick, at the foot of the list. */
create or replace function public.ops_add_checklist_item(p_task uuid, p_label text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  lbl text;
  pos integer;
  iid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  lbl := nullif(btrim(coalesce(p_label, '')), '');
  if lbl is null then return jsonb_build_object('error', 'label-required'); end if;
  if length(lbl) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  select coalesce(max(position), 0) + 1 into pos from public.ops_task_checklist_items where task_id = p_task;
  insert into public.ops_task_checklist_items (task_id, label, position)
  values (p_task, lbl, pos) returning id into iid;
  perform public.ops_log(p_task, 'checklist_changed', null,
    jsonb_build_object('label', lbl, 'added', true), '{}'::jsonb);
  return (select to_jsonb(c) from public.ops_task_checklist_items c where c.id = iid);
end $$;
grant execute on function public.ops_add_checklist_item(uuid, text) to authenticated;

/* A comment is an event: it is read in the task's own history, in order,
   with who wrote it, and it cannot be edited or removed afterwards. */
create or replace function public.ops_add_comment(p_task uuid, p_body text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  body text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  body := nullif(btrim(coalesce(p_body, '')), '');
  if body is null then return jsonb_build_object('error', 'comment-required'); end if;
  if length(body) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  perform public.ops_log(p_task, 'commented', null, null, jsonb_build_object('note', body));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_add_comment(uuid, text) to authenticated;

-- 5. Templates ------------------------------------------------------------------
/* A template is the task somebody makes every month: its title, its owner,
   when it is due relative to the day it is made for, its checklist and its
   estimate. Kept by whoever holds the granted part ops.workflows. */
create or replace function public.ops_save_template(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  nm   text;
  wf   uuid;
  tid  uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('ops.workflows', 'work') then return jsonb_build_object('error', 'denied'); end if;
  nm := nullif(btrim(coalesce(p_payload ->> 'name', '')), '');
  if nm is null then return jsonb_build_object('error', 'name-required'); end if;
  if exists (select 1 from public.ops_task_templates
              where lower(name) = lower(nm) and id is distinct from p_id) then
    return jsonb_build_object('error', 'name-taken');
  end if;
  wf := coalesce((select id from public.ops_workflows where key = coalesce(p_payload ->> 'workflow_key', 'task')),
                 (select id from public.ops_workflows where key = 'task'));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  if p_id is null then
    insert into public.ops_task_templates (name, deliverable_type, workflow_id, default_title,
      default_owner_id, due_offset_days, default_estimate_minutes, checklist, active)
    values (nm, coalesce(nullif(p_payload ->> 'deliverable_type', ''), 'other'), wf,
      nullif(btrim(coalesce(p_payload ->> 'default_title', '')), ''),
      (p_payload ->> 'default_owner_id')::uuid,
      (p_payload ->> 'due_offset_days')::integer,
      (p_payload ->> 'default_estimate_minutes')::integer,
      coalesce(p_payload -> 'checklist', '[]'::jsonb),
      coalesce((p_payload ->> 'active')::boolean, true))
    returning id into tid;
  else
    update public.ops_task_templates set
      name = nm,
      deliverable_type = coalesce(nullif(p_payload ->> 'deliverable_type', ''), deliverable_type),
      workflow_id = wf,
      default_title = nullif(btrim(coalesce(p_payload ->> 'default_title', '')), ''),
      default_owner_id = (p_payload ->> 'default_owner_id')::uuid,
      due_offset_days = (p_payload ->> 'due_offset_days')::integer,
      default_estimate_minutes = (p_payload ->> 'default_estimate_minutes')::integer,
      checklist = coalesce(p_payload -> 'checklist', '[]'::jsonb),
      active = coalesce((p_payload ->> 'active')::boolean, active),
      updated_at = now()
    where id = p_id
    returning id into tid;
    if tid is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  return (select to_jsonb(x) from public.ops_task_templates x where x.id = tid);
end $$;
grant execute on function public.ops_save_template(uuid, jsonb) to authenticated;

-- END OF MY WORK AS A DAILY TASK TRACKER -----------------------------------
