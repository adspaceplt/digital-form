-- ===========================================================================
-- ONE PRESS, ONE NOTICE — a step that hands a task on tells its new owner
-- once. 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte
-- for byte in supabase/schema.sql under the same banner; tests/ops.js
-- compares the two.
--
-- WHAT CHANGED (review of 2026-10-18, item 13)
--   ops_transition_task with p_assignee files assignment_changed (the new
--   owner told "Handed to you by … at …") and then stage_changed, which told
--   the same person "Moved to … by …": two notices and two pushes for one
--   press. ops_log now leaves out the stage notice when, in the same
--   transaction, the task was handed to that owner (an assignment_changed
--   event marked handover, stamped with the same now()). A move with no
--   hand-off, and a hand-off with no move, are told as before.
--
-- ROLLBACK
--   Run ops_log as THE CONTENT MEETING ON GOOGLE MEET stated it (the
--   previous last definition in schema.sql).
-- ===========================================================================

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
    /* One press, one notice (2026-10-18): a move that also handed the task
       on has already told its new owner, in the same transaction, with the
       stage it was handed at. */
    if exists (select 1 from public.ops_task_events e
                where e.task_id = p_task and e.event_type = 'assignment_changed'
                  and e.created_at = now()
                  and coalesce((e.detail ->> 'handover')::boolean, false)
                  and e.to_value ->> 'owner_id' = owner::text) then
      return;
    end if;
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
  elsif p_type = 'commented' then
    body := who || ' commented: ' ||
      case when length(coalesce(p_detail ->> 'note', '')) > 140
           then left(p_detail ->> 'note', 139) || '…' else coalesce(p_detail ->> 'note', '') end;
  else
    return;
  end if;

  perform public.ops_notify(owner, p_task, p_type,
    public.ops_serial(t.task_no) || ' · ' || public.ops_title(t), body,
    p_type || ':' || p_task::text || ':' || owner::text || ':' ||
      /* Two comments in one minute are two things said; the same change
         twice in a minute is one. */
      case when p_type = 'commented' then md5(body) else to_char(now(), 'YYYYMMDDHH24MI') end);
end $$;

-- END OF ONE PRESS, ONE NOTICE ----------------------------------------------

select public.functions_tidy();
