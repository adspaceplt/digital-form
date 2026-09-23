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
--   3. `ops_transition_task`: skipping a step keeps the published rule (ops
--      Work, with a reason) and can never land on a revision stage; a task
--      reaches Client review only after AQC review; a revision takes a note;
--      every review and revision records its round; and a move into a
--      terminal stage closes every running timer on the task.
--
--   4. `ops_hand_over_task` (ops Manage, the note kept on the event),
--      `ops_set_publish_date` (ops Work), `ops_add_checklist_item` and
--      `ops_add_comment` (ops Work), `ops_save_template` (the granted part
--      ops.workflows, Work).
--
--   5. Three columns on `ops_task_templates` (default_title,
--      default_owner_id, due_offset_days) and one index for cancelled work.
--
--   6. The task number reads #WT00001 (`ops_serial`), in the notifications,
--      the activity record and the delete check alike; `ops_next_task_no` and
--      `ops_set_next_task_no` let an admin read and set the next number.
--
--   7. The content workflow's words and its two revision loops: In progress,
--      Ready to start and AQC review are relabelled where they still read as
--      seeded, and Revision (Internal) (from AQC review) and Revision
--      (Client) (from Client review) are added. Changes requested stays for
--      any task already in it and is no longer offered as a next step.
--
--   8. `ops_delete_tasks`: several tasks deleted in one act, ops Manage, the
--      count typed back and a reason, each one filed as its own deletion.
--
--   No existing task is rewritten, moved or renamed. No policy changes. The
--   test tasks are cleared by a separate file, 2026-09-24-clear-test-tasks.sql,
--   which is run once and on purpose.
--
-- Rollback: re-run sections 9.8 and 9.10 of 2026-09-23-operations-phase4.sql
-- (the previous ops_create_task, ops_transition_task, ops_log and
-- ops_delete_task), then
--   drop function if exists public.ops_delete_tasks(uuid[], text, text);
--   drop function if exists public.ops_set_next_task_no(bigint);
--   drop function if exists public.ops_next_task_no();
--   drop function if exists public.ops_serial(bigint);
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
  v_round integer;
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
    /* A revision is where work is sent back from a review, so it is never
       a step somebody skips forward into. */
    if not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.stage_group <> 'revision'
       and nxt.position > cur.position then
      if nullif(btrim(coalesce(p_skip_reason, '')), '') is null then
        return jsonb_build_object('error', 'skip-reason-required');
      end if;
      skipping := true;
    else
      return jsonb_build_object('error', 'bad-transition',
        'allowed', to_jsonb(cur.next_stage_keys));
    end if;
  end if;

  /* A performance review goes back to whoever created the task unless the
     move names somebody else. */
  if p_next = 'performance_review' and p_assignee is null and exists (
       select 1 from public.team_members where id = t.created_by and active) then
    p_assignee := t.created_by;
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
  /* AQC review comes first: the client sees the work only once it has been
     through AQC review at least once. */
  if p_next = 'client_review'
     and exists (select 1 from public.ops_workflow_stages s
                  where s.workflow_id = t.workflow_id and s.key = 'internal_review')
     and not exists (select 1 from public.ops_task_events e
                      where e.task_id = p_task and e.event_type = 'stage_changed'
                        and e.to_value ->> 'stage_key' = 'internal_review') then
    return jsonb_build_object('error', 'needs-aqc');
  end if;
  if p_next = 'client_review' and not has_draft then
    return jsonb_build_object('error', 'needs-draft');
  end if;
  /* A revision says what has to change, and so does taking a post down. */
  if ((nxt.stage_group = 'revision' and p_next <> 'changes_requested') or p_next = 'taken_down')
     and nullif(btrim(coalesce(p_note, '')), '') is null then
    return jsonb_build_object('error', 'note-required');
  end if;
  /* After approval: a schedule needs its date, going live is confirmed with
     its own date through ops_mark_live and needs the post's link or a note,
     and a task is completed only once its performance checklist is done. */
  if p_next = 'scheduled' and t.publish_at is null then
    return jsonb_build_object('error', 'needs-schedule');
  end if;
  if p_next = 'live' and t.live_at is null then
    return jsonb_build_object('error', 'needs-live-date');
  end if;
  if p_next = 'live' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;
  if p_next = 'completed' and exists (
       select 1 from public.ops_task_checklist_items c
        where c.task_id = p_task and c.required and c.completed_at is null) then
    return jsonb_build_object('error', 'checklist-incomplete');
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

  /* The round: how many times this task has now entered this review or
     this revision, counted off its own history, so nothing is stored that
     a reverted move could leave wrong. */
  if nxt.is_review or nxt.stage_group = 'revision' then
    select count(*) + 1 into v_round from public.ops_task_events e
     where e.task_id = p_task and e.event_type = 'stage_changed'
       and e.to_value ->> 'stage_key' = p_next;
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

  /* The performance review brings its own checklist, the same five checks
     for a brand post and a KOC post, added once however often the task
     comes back to the stage. */
  if p_next = 'performance_review' then
    insert into public.ops_task_checklist_items (task_id, label, position, required)
    select p_task, x.label,
           coalesce((select max(c.position) from public.ops_task_checklist_items c
                      where c.task_id = p_task), 0) + x.n,
           true
      from (values (1, 'Reach and views checked'),
                   (2, 'Engagement checked (likes, comments, shares, saves)'),
                   (3, 'Comments checked for brand safety'),
                   (4, 'Leads or sales checked, where tracked'),
                   (5, 'Keep live or take down decided')) as x(n, label)
     where not exists (select 1 from public.ops_task_checklist_items c
                        where c.task_id = p_task and c.label = x.label);
  end if;

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
    || (case when skipping then jsonb_build_object('skip_reason', btrim(p_skip_reason)) else '{}'::jsonb end)
    || (case when v_round is not null then jsonb_build_object('round', v_round) else '{}'::jsonb end));
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

-- 10. The task number reads #WT00001 ---------------------------------------------
/* One running number for every task, written with a fixed prefix and five
   digits. The number is the same column it always was; how it is written
   lives here and nowhere else in the database. */
create or replace function public.ops_serial(p_no bigint)
returns text
language sql immutable set search_path = public as $$
  select '#WT' || lpad(p_no::text, 5, '0')
$$;
grant execute on function public.ops_serial(bigint) to authenticated;

/* ops_log as phase 4 left it, with the number written by ops_serial and the
   round named when work comes back for a review or a revision. */
create or replace function public.ops_log(
  p_task uuid, p_type text, p_from jsonb, p_to jsonb, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  t      public.ops_tasks;
  owner  uuid;
  who    text;
  body   text;
  st     public.ops_workflow_stages;
begin
  m := public.ops_me();
  insert into public.ops_task_events (task_id, event_type, actor_id, actor_email,
                                      from_value, to_value, detail)
  values (p_task, p_type, m.id, m.email, p_from, p_to, coalesce(p_detail, '{}'::jsonb));

  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return; end if;
  who := coalesce(nullif(m.name, ''), m.email, 'Somebody');

  if p_type = 'assignment_changed' then
    owner := (p_to ->> 'owner_id')::uuid;
    if owner is not null and owner is distinct from m.id then
      perform public.ops_notify(owner, p_task, 'assigned',
        public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
        case when coalesce((p_detail ->> 'handover')::boolean, false)
             then 'Handed to you by ' || who || ' at ' ||
                  coalesce((public.ops_stage(t.workflow_id, p_detail ->> 'stage_key')).label, p_detail ->> 'stage_key') || '.'
             else 'Assigned to you by ' || who || '.' end,
        'assigned:' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
    end if;
    return;
  end if;

  select team_member_id into owner from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null
   limit 1;
  if owner is null or owner = m.id then return; end if;

  if p_type = 'stage_changed' then
    st := public.ops_stage(t.workflow_id, p_to ->> 'stage_key');
    body := 'Moved to ' || coalesce(st.label, p_to ->> 'stage_key')
      || coalesce(', round ' || (p_detail ->> 'round'), '') || ' by ' || who || '.';
  elsif p_type = 'due_changed' then
    body := 'The ' || case when p_to ->> 'kind' = 'final' then 'final' else 'first draft' end
      || ' date moved to ' || to_char((p_to ->> 'value')::timestamptz, 'DD Mon YYYY')
      || ' by ' || who || '.';
  elsif p_type = 'blocked' then
    body := 'Marked blocked by ' || who || ': '
      || coalesce(p_detail ->> 'category', 'reason not given') || '.';
  elsif p_type = 'unblocked' then
    body := 'Unblocked by ' || who || '.';
  elsif p_type = 'revision_requested' then
    body := 'A revision was requested by ' || who || '.';
  elsif p_type = 'approval_recorded' then
    body := 'A review decision was recorded by ' || who || '.';
  elsif p_type = 'reopened' then
    body := 'Reopened by ' || who || '.';
  elsif p_type = 'cancelled' then
    body := 'Cancelled by ' || who || '.';
  else
    return;
  end if;

  perform public.ops_notify(owner, p_task, p_type,
    public.ops_serial(t.task_no) || ' · ' || public.ops_title(t), body,
    p_type || ':' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
end $$;

/* The deletion names the task the way every screen does, and the number is
   typed back with or without the # and in any case. */
create or replace function public.ops_delete_task(
  p_task uuid, p_confirm text, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cl  text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if upper(regexp_replace(coalesce(p_confirm, ''), '[^A-Za-z0-9]', '', 'g'))
     <> upper(regexp_replace(public.ops_serial(t.task_no), '[^A-Za-z0-9]', '', 'g')) then
    return jsonb_build_object('error', 'confirm-required');
  end if;

  select c.name into cl from public.clients c where c.id = t.client_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.deleted',
          public.ops_serial(t.task_no),
          public.ops_title(t) ||
          coalesce(' · ' || cl, case when t.scope = 'internal' then ' · Internal' else '' end) ||
          coalesce(' · ' || nullif(btrim(p_reason), ''), ''));

  delete from public.ops_tasks where id = p_task;
  return jsonb_build_object('deleted', true, 'task_no', t.task_no);
end $$;
grant execute on function public.ops_delete_task(uuid, text, text) to authenticated;

-- 11. The content workflow: its words, AQC review, and what follows approval ----
/* In progress, Ready to start and AQC review are the team's words, applied
   only where a stage still reads as seeded, so a label somebody changed is
   left alone. Two revision loops replace the one: Revision (Internal) is
   reached from AQC review only and Revision (Client) from Client review
   only, each back to the review it came from. After approval the work is
   Scheduled, goes Live on a confirmed date, has its Performance review, and
   ends Completed or Taken down. Changes requested and Published stay for any
   task already in them and are no longer offered as next steps. Positions
   are appended after the last one, so nothing already placed moves. */
do $$
declare
  w uuid;
  p integer;
begin
  select id into w from public.ops_workflows where key = 'content';
  if w is null then return; end if;

  update public.ops_workflow_stages set label = 'In progress'
   where workflow_id = w and key = 'in_production' and label = 'In production';
  update public.ops_workflow_stages set label = 'Ready to start'
   where workflow_id = w and key = 'ready' and label = 'Ready for production';
  update public.ops_workflow_stages set label = 'AQC review'
   where workflow_id = w and key = 'internal_review' and label = 'Internal quality review';

  if not exists (select 1 from public.ops_workflow_stages
                  where workflow_id = w and key = 'revision_internal') then
    select coalesce(max(position), 0) into p from public.ops_workflow_stages where workflow_id = w;
    insert into public.ops_workflow_stages
      (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
       is_review, is_terminal, wip_guidance, next_stage_keys) values
      (w, 'revision_internal',  'Revision (Internal)', p + 1, 'revision',    true,  false, false, false, null,
          array['internal_review', 'blocked', 'on_hold']),
      (w, 'revision_client',    'Revision (Client)',   p + 2, 'revision',    true,  false, false, false, null,
          array['client_review', 'internal_review', 'blocked', 'on_hold']),
      (w, 'scheduled',          'Scheduled',           p + 3, 'scheduled',   false, true,  false, false, null,
          array['live', 'revision_client', 'on_hold', 'cancelled']),
      (w, 'live',               'Live',                p + 4, 'live',        false, true,  false, false, null,
          array['performance_review', 'taken_down']),
      (w, 'performance_review', 'Performance review',  p + 5, 'performance', false, false, true,  false, null,
          array['completed', 'taken_down', 'live']),
      (w, 'taken_down',         'Taken down',          p + 6, 'taken_down',  false, false, false, true,  null,
          array['live']),
      (w, 'completed',          'Completed',           p + 7, 'done',        false, false, false, true,  null,
          array['performance_review']);

    update public.ops_workflow_stages set next_stage_keys =
      array['client_review', 'revision_internal', 'in_production', 'blocked']
     where workflow_id = w and key = 'internal_review';
    update public.ops_workflow_stages set next_stage_keys =
      array['approved', 'revision_client', 'blocked', 'on_hold']
     where workflow_id = w and key = 'client_review';
    update public.ops_workflow_stages set next_stage_keys =
      array['scheduled', 'live', 'revision_client']
     where workflow_id = w and key = 'approved';
    update public.ops_workflow_stages set next_stage_keys =
      array['ready', 'in_production', 'internal_review', 'revision_internal', 'client_review',
            'revision_client', 'scheduled', 'cancelled']
     where workflow_id = w and key = 'blocked';
    update public.ops_workflow_stages set next_stage_keys =
      array['planning', 'ready', 'in_production', 'internal_review', 'revision_internal',
            'client_review', 'revision_client', 'scheduled', 'cancelled']
     where workflow_id = w and key = 'on_hold';
  end if;
end $$;

-- 12. The live date and the rating -------------------------------------------------
/* When the work actually went live, and what the team made of the task once
   it was finished. A column each, added, never a rewrite. */
alter table public.ops_tasks add column if not exists live_at     timestamptz;
alter table public.ops_tasks add column if not exists rating      smallint;
alter table public.ops_tasks add column if not exists rating_note text;
alter table public.ops_tasks add column if not exists rated_by    uuid references public.team_members(id);
alter table public.ops_tasks add column if not exists rated_at    timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ops_tasks_rating_range') then
    alter table public.ops_tasks add constraint ops_tasks_rating_range
      check (rating is null or rating between 1 and 5);
  end if;
end $$;

/* Going live. The date is today unless somebody says otherwise; a date that
   differs from the scheduled one says why, and both dates and the reason are
   on the record. The move itself is ops_transition_task, with every gate it
   has, and the date is put back if the move is refused. */
create or replace function public.ops_mark_live(
  p_task uuid, p_live_at timestamptz, p_reason text default null,
  p_version integer default null, p_assignee uuid default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  t    public.ops_tasks;
  res  jsonb;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if p_live_at is null then return jsonb_build_object('error', 'no-date'); end if;
  if (p_live_at at time zone 'Asia/Kuala_Lumpur')::date
     > (now() at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'live-in-future');
  end if;
  if t.publish_at is not null
     and (p_live_at at time zone 'Asia/Kuala_Lumpur')::date
         <> (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date
     and nullif(btrim(coalesce(p_reason, '')), '') is null then
    return jsonb_build_object('error', 'live-reason-required');
  end if;

  update public.ops_tasks set live_at = p_live_at where id = p_task;
  res := public.ops_transition_task(p_task, 'live', p_version, p_note, p_assignee, null);
  if res ? 'error' then
    update public.ops_tasks set live_at = t.live_at where id = p_task;
    return res;
  end if;
  perform public.ops_log(p_task, 'live_confirmed',
    jsonb_build_object('scheduled', t.publish_at),
    jsonb_build_object('live_at', p_live_at),
    case when nullif(btrim(coalesce(p_reason, '')), '') is null then '{}'::jsonb
         else jsonb_build_object('reason', btrim(p_reason)) end);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_mark_live(uuid, timestamptz, text, integer, uuid, text) to authenticated;

/* A finished task is rated one to five, with a line if there is one to say.
   Changing the rating is a second event, never an overwrite of the first. */
create or replace function public.ops_rate_task(p_task uuid, p_rating integer, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.completed_at is null then return jsonb_build_object('error', 'not-finished'); end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    return jsonb_build_object('error', 'bad-rating');
  end if;
  update public.ops_tasks set
    rating = p_rating,
    rating_note = nullif(btrim(coalesce(p_note, '')), ''),
    rated_by = m.id,
    rated_at = now()
  where id = p_task;
  perform public.ops_log(p_task, 'rated',
    case when t.rating is null then null else jsonb_build_object('rating', t.rating) end,
    jsonb_build_object('rating', p_rating),
    case when nullif(btrim(coalesce(p_note, '')), '') is null then '{}'::jsonb
         else jsonb_build_object('note', btrim(p_note)) end);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_rate_task(uuid, integer, text) to authenticated;

-- 13. Several tasks deleted at once --------------------------------------------------
/* The same act as ops_delete_task, for a selection: ops Manage, every task in
   it one the person may see or none is deleted, the count typed back, a
   reason, and a row in the activity record for each task, because the task's
   own history goes with it. At most 500 in one act. */
create or replace function public.ops_delete_tasks(p_tasks uuid[], p_confirm text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  t     public.ops_tasks;
  want  integer := coalesce(array_length(p_tasks, 1), 0);
  n     integer := 0;
  cl    text;
  why   text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if want = 0 then return jsonb_build_object('error', 'none-selected'); end if;
  if want > 500 then return jsonb_build_object('error', 'too-many'); end if;
  if btrim(coalesce(p_confirm, '')) <> want::text then
    return jsonb_build_object('error', 'confirm-required');
  end if;
  if why is null then return jsonb_build_object('error', 'reason-required'); end if;
  if exists (select 1 from unnest(p_tasks) x where not public.ops_may_see_task(x)) then
    return jsonb_build_object('error', 'denied');
  end if;

  for t in select * from public.ops_tasks where id = any (p_tasks) order by task_no for update loop
    select c.name into cl from public.clients c where c.id = t.client_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(m.name, m.email), 'ops.deleted', public.ops_serial(t.task_no),
            public.ops_title(t) ||
            coalesce(' · ' || cl, case when t.scope = 'internal' then ' · Internal' else '' end) ||
            ' · ' || why);
    delete from public.ops_tasks where id = t.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('deleted', n);
end $$;
grant execute on function public.ops_delete_tasks(uuid[], text, text) to authenticated;

-- 14. The next number, for an admin -------------------------------------------------
/* What the next task will be numbered, and the place to set it: an admin
   only, never below or on a number a task already holds, and filed in the
   activity record. */
create or replace function public.ops_next_task_no()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  lv   bigint;
  ic   boolean;
  nxt  bigint;
  top  bigint;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  select last_value, is_called into lv, ic from public.ops_task_no_seq;
  nxt := case when ic then lv + 1 else lv end;
  select max(task_no) into top from public.ops_tasks;
  return jsonb_build_object('next', nxt, 'serial', public.ops_serial(nxt),
    'highest', top, 'highest_serial', case when top is null then null else public.ops_serial(top) end);
end $$;
grant execute on function public.ops_next_task_no() to authenticated;

create or replace function public.ops_set_next_task_no(p_next bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  top  bigint;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  if p_next is null or p_next < 1 or p_next > 9999999 then
    return jsonb_build_object('error', 'bad-number');
  end if;
  select max(task_no) into top from public.ops_tasks;
  if top is not null and p_next <= top then
    return jsonb_build_object('error', 'number-taken', 'highest', public.ops_serial(top));
  end if;
  perform setval('public.ops_task_no_seq', p_next, false);
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.numbering', 'My Work',
          'Next task number set to ' || public.ops_serial(p_next));
  return public.ops_next_task_no();
end $$;
grant execute on function public.ops_set_next_task_no(bigint) to authenticated;

-- END OF MY WORK AS A DAILY TASK TRACKER -----------------------------------


-- The record files a change to the next task number under My Work.
-- Identical to activity_section in supabase/schema.sql.
create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.withdrawn', 'creator.added',
                    'creator.off', 'creator.on', 'creator.removed', 'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.stage', 'client.touch',
                    'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored', 'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'set.created', 'set.deleted', 'set.published', 'set.renamed',
                    'set.withdrawn') then 'review'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;
