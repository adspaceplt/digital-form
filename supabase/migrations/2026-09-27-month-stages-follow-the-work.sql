-- ===========================================================================
-- MONTH STAGES FOLLOW THE WORK — a content month's stage is worked out from
-- its facts; Completed, Cancelled and a reopen are the team's decisions.
-- 2026-09-27. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT CHANGED, the user's decision of 2026-09-27 ("Can the status on content
-- month being set automatically triggered by each stages?"):
--  1. Planning, Ready and In production are no longer set by hand. The page
--     works them out on every load: Planning until the readiness ticks are
--     answered and the meeting is set (or marked not applicable), Ready once
--     they are, In production once the meeting has passed and the month
--     holds a task. `ops_engagement_set_status` refuses them
--     (`derived-state`).
--  2. What a person decides is stored: Completed, refused while any of the
--     month's tasks is open (`tasks-open`, with the count); Cancelled; and
--     Planning, which reopens either.
--  3. A task's move into production reads the same facts (the readiness
--     ticks and the meeting) instead of the stored status, which now stays
--     Planning for an open month; otherwise no content task could start.
--  4. `ops_engagement_counts` counts each month's live, open and done tasks
--     over every task in it: a colleague who reads only their own tasks
--     would otherwise see a month nearly done that is not. Counts only; no
--     task is named. A stored Ready or In production from before is left as
--     it is and read as open.
--
-- ROLLBACK
--   Re-run ops_engagement_set_status from 2026-09-23-operations-phase4.sql
--   and ops_transition_task from 2026-09-26-my-work-stages-in-order.sql;
--   drop function if exists public.ops_engagement_counts(uuid[]);
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
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_status(uuid, text, integer) to authenticated;

/* A month's tasks, counted over the whole month whoever asks: live (not
   cancelled), open (not finished) and done (completed). Only months the
   caller may see answer. */
create or replace function public.ops_engagement_counts(p_engagements uuid[])
returns jsonb
language sql security definer stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'engagement_id', e.id,
           'live', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null),
           'open', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null and t.completed_at is null),
           'done', (select count(*) from public.ops_tasks t
                     where t.engagement_id = e.id and t.archived_at is null
                       and t.cancelled_at is null and t.completed_at is not null))), '[]'::jsonb)
    from public.ops_engagements e
   where e.id = any (coalesce(p_engagements, '{}'::uuid[]))
     and public.ops_may_see_engagement(e.id)
$$;
revoke all on function public.ops_engagement_counts(uuid[]) from public, anon;
grant execute on function public.ops_engagement_counts(uuid[]) to authenticated;

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
  going_back boolean := false;
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
  /* The stage is the owner's to move. Once a task is handed to somebody,
     whoever created it or held it before reads it and no longer moves it; an
     admin still may. */
  if not public.ops_owner_may_move(p_task) then return jsonb_build_object('error', 'not-owner'); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  /* A retired stage keeps the tasks already standing on it and takes no new
     ones: Planning and the content meeting are the month's, not a task's. */
  if nxt.retired then return jsonb_build_object('error', 'retired-stage'); end if;
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
    /* Going back is picking an earlier stage on the line, and says why; the
       reason goes on the record with the move. A revision is entered only
       from the review that sends work to it. */
    elsif not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.stage_group <> 'revision'
       and nxt.position < cur.position then
      if nullif(btrim(coalesce(p_note, '')), '') is null then
        return jsonb_build_object('error', 'back-reason-required');
      end if;
      going_back := true;
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
  /* Production waits on the month's own facts: its readiness ticks
     answered, and its content meeting held or marked not applicable. The
     month's stage is worked out from those facts on the page and is never
     stored, so the stored status is not read here (2026-09-27). A task with
     no month (ad hoc, internal) has nothing to wait on. */
  if p_next = 'in_production' and t.engagement_id is not null then
    select * into eng from public.ops_engagements where id = t.engagement_id;
    if exists (select 1 from public.ops_engagement_checks c
                where c.engagement_id = eng.id
                  and c.state in ('not_started', 'waiting_client', 'in_progress')) then
      return jsonb_build_object('error', 'planning-incomplete');
    end if;
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
  /* The draft reaches the client as a link on the task or through the
     team's WhatsApp group with the client. Either way the record says how:
     the link, or a note naming where it went. */
  if p_next = 'client_review' and not has_draft
     and nullif(btrim(coalesce(p_note, '')), '') is null then
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
                 and stage_group <> 'revision' and not retired
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
    /* Leaving Cancelled for a live stage is a reopening, and the stamp
       leaves with it, as completed_at does; left behind, the task went on
       reading cancelled at the stage it had been reopened to. */
    cancelled_at = case when p_next = 'cancelled' then coalesce(cancelled_at, now())
                        when not nxt.is_terminal then null
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
    || (case when going_back then jsonb_build_object('back', true) else '{}'::jsonb end)
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

-- END OF MONTH STAGES FOLLOW THE WORK --------------------------------------
