-- ===========================================================================
-- CLIENT POSTS (2026-11-22)
-- ===========================================================================
-- WHY: the user approved the simpler stages on 2026-11-22 (the stage
-- timeline proposal): a task whose post the client publishes is marked so
-- from the task's ⋯, once, in place of skipping Live and Performance review
-- with a typed reason every time (8 live tasks skipped them, "Posting by
-- client"). No client default (the user: rare). Scheduled is kept: the date
-- the client will post.
--
-- WHAT IT CHANGES
--   * `ops_tasks.client_posts` (boolean, false): the client posts this
--     content. Read as every other column of the task.
--   * `ops_set_client_posts(p_task, p_on, p_version)` (My Work at Work, the
--     task's owner as a stage move asks, `ops_owner_may_move`): sets it,
--     filed `details_changed` from and to. `not-team`, `denied`,
--     `not-found`, `stale` (with the task), `not-owner`, `no-live-stage` (a
--     workflow without Live), `already-live` (the task went live, or stands
--     on Live, Performance review or Taken down).
--   * `ops_transition_task` (restated whole from HELD TASKS RESUME WHERE THEY
--     LEFT, every refusal kept): a task the client posts is refused Live and
--     Performance review (`client-posts`, so `ops_mark_live` refuses too and
--     no result is recorded: `ops_set_results` asks for its live date), and
--     moves from Scheduled to Completed as a step; a skip past them files
--     neither as skipped.
--   * The tasks whose skip of Live reads "Posting by client" are marked; their
--     skip records stay.
--
-- ORDER: this file, then the pages. An old page never offers the mark, and
-- moves every task as before (the column is false). A new page meeting the
-- old database finds no column and offers no mark. Safe to run twice.
--
-- ROLLBACK: run `ops_transition_task` from HELD TASKS RESUME WHERE THEY LEFT
-- again; drop function ops_set_client_posts(uuid, boolean, integer); the
-- column may stay (nothing else reads it), or
-- alter table public.ops_tasks drop column client_posts.
-- ===========================================================================

alter table public.ops_tasks add column if not exists client_posts boolean not null default false;

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
  held text[] := array['on_hold', 'blocked', 'cancelled'];
  resume_to text[];
  first_key text;
  resuming boolean := false;
  by_client boolean := false;
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
  /* A task on hold, blocked or cancelled goes back to the stage it left
     (held_from, stamped by ops_tasks_held_from), and a cancelled one also
     to the start of the line; never on past stages it had not reached
     (the user, 2026-10-18: keep it light, AQC review happens on WhatsApp).
     Moving between the three is a step as before. A task held before the
     column knew where from keeps the steps of its workflow. */
  if cur.key = any (held) and not (p_next = any (held)) and t.held_from is not null then
    select s.key into first_key from public.ops_workflow_stages s
     where s.workflow_id = t.workflow_id and not s.retired
       and not (s.stage_group = any (side)) and s.stage_group <> 'revision'
       and not (s.key = any (held))
     order by s.position limit 1;
    resume_to := array[t.held_from];
    if cur.key = 'cancelled' or coalesce((public.ops_stage(t.workflow_id, t.held_from)).retired, true) then
      resume_to := resume_to || first_key;
    end if;
    if not (p_next = any (resume_to)) then
      return jsonb_build_object('error', 'held-resume', 'allowed', to_jsonb(resume_to));
    end if;
    resuming := true;
  end if;
  /* Content the client posts has no Live stage and no performance review
     of ours: Scheduled leads straight to Completed, a step and never a skip
     (CLIENT POSTS, 2026-11-22). */
  if coalesce(t.client_posts, false) then
    if p_next in ('live', 'performance_review') then
      return jsonb_build_object('error', 'client-posts');
    end if;
    by_client := cur.key = 'scheduled' and p_next = 'completed';
  end if;
  if not resuming and not by_client and not (p_next = any (cur.next_stage_keys)) then
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
                 and not (coalesce(t.client_posts, false) and key in ('live', 'performance_review'))
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

create or replace function public.ops_set_client_posts(p_task uuid, p_on boolean, p_version integer default null)
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
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if t.client_posts = coalesce(p_on, false) then return public.ops_task_json(p_task); end if;
  if not public.ops_owner_may_move(p_task) then return jsonb_build_object('error', 'not-owner'); end if;
  if not exists (select 1 from public.ops_workflow_stages s
                  where s.workflow_id = t.workflow_id and s.key = 'live') then
    return jsonb_build_object('error', 'no-live-stage');
  end if;
  if t.live_at is not null or t.stage_key in ('live', 'performance_review', 'taken_down') then
    return jsonb_build_object('error', 'already-live');
  end if;
  update public.ops_tasks
     set client_posts = coalesce(p_on, false), version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'details_changed',
    jsonb_build_object('client_posts', t.client_posts),
    jsonb_build_object('client_posts', coalesce(p_on, false)), '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
revoke all on function public.ops_set_client_posts(uuid, boolean, integer) from public, anon;
grant execute on function public.ops_set_client_posts(uuid, boolean, integer) to authenticated;

/* The tasks whose Live was skipped because the client posts. */
update public.ops_tasks t set client_posts = true
 where not t.client_posts and t.live_at is null
   and exists (select 1 from public.ops_task_events e
                where e.task_id = t.id and e.event_type = 'stage_skipped'
                  and e.from_value ->> 'stage_key' = 'live'
                  and e.detail ->> 'reason' ilike '%posting by client%');

-- END OF CLIENT POSTS ------------------------------------------------------

select public.functions_tidy();
