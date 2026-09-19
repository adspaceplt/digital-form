-- ===========================================================================
-- THE OPERATIONS SYSTEM, PHASE 3 — the record tells the person it concerns.
--
-- Phase 1 made `ops_notifications`, a select policy on it and the one direct
-- write a browser may make (marking its own row read), and nothing ever wrote
-- a row. Phase 3 puts the console's board, calendar and bell on the page, so
-- the rows have to exist.
--
-- They are written where every event is already written. `ops_log` is the one
-- function every write in section 6 files its event through, so it is the one
-- place that knows the task, the kind of change and who made it; a second
-- call beside each `ops_log` in fourteen functions would be fourteen chances
-- to forget one, and the day somebody added a fifteenth write it would notify
-- nobody. The rule is stated once here:
--
--   The accountable owner is told about a change to their task that somebody
--   else made. A person is never told about their own act, and a change to
--   a task with no owner tells nobody, because there is nobody to tell.
--   A new owner is told they were assigned, whoever assigned them.
--
-- Nothing else changes. No table, column, policy or permission is added; the
-- events themselves are written exactly as before, and a notification is one
-- row beside the event, keyed so that the same change filed twice inside a
-- minute is one row and not two.
--
-- Safe to run twice. Nothing here is a data migration.
--
-- Rollback (restores phase 1's `ops_log`, which files the event and nothing else):
--   drop function if exists public.ops_notify(uuid, uuid, text, text, text, text);
--   create or replace function public.ops_log(
--     p_task uuid, p_type text, p_from jsonb, p_to jsonb, p_detail jsonb default '{}'::jsonb)
--   returns void language plpgsql security definer set search_path = public as $$
--   declare m public.team_members;
--   begin
--     m := public.ops_me();
--     insert into public.ops_task_events (task_id, event_type, actor_id, actor_email,
--                                         from_value, to_value, detail)
--     values (p_task, p_type, m.id, m.email, p_from, p_to, coalesce(p_detail, '{}'::jsonb));
--   end $$;
-- ===========================================================================

-- 8.1 One row, addressed to one person --------------------------------------------
/* A notification is written by the database and read by the person it names.
   The dedupe key is what makes a double press one row: the browser retries a
   write, or a person moves a stage and moves it back inside a minute, and the
   owner is told once. */
create or replace function public.ops_notify(
  p_member uuid, p_task uuid, p_kind text, p_title text, p_body text, p_dedupe text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_member is null then return; end if;
  insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
  values (p_member, p_task, p_kind, p_title, p_body, p_dedupe)
  on conflict (dedupe_key) do nothing;
end $$;

-- 8.2 The event, and the person it concerns ---------------------------------------
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

  /* Assignment tells the new owner, whoever made it, except where the new
     owner is the person assigning: somebody taking a task for themselves
     already knows. */
  if p_type = 'assignment_changed' then
    owner := (p_to ->> 'owner_id')::uuid;
    if owner is not null and owner is distinct from m.id then
      perform public.ops_notify(owner, p_task, 'assigned',
        'T' || t.task_no || ' · ' || t.title,
        'Assigned to you by ' || who || '.',
        'assigned:' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
    end if;
    return;
  end if;

  /* Every other change tells the accountable owner, and only where somebody
     else made it. What is said is the change in the team's words, never the
     event's key. */
  select team_member_id into owner from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null
   limit 1;
  if owner is null or owner = m.id then return; end if;

  if p_type = 'stage_changed' then
    st := public.ops_stage(t.workflow_id, p_to ->> 'stage_key');
    body := 'Moved to ' || coalesce(st.label, p_to ->> 'stage_key') || ' by ' || who || '.';
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
    'T' || t.task_no || ' · ' || t.title, body,
    p_type || ':' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
end $$;
