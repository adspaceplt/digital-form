-- ===========================================================================
-- A MOVED DATE READS AS THE HOUSE WRITES IT — the notice of a task's moved
-- date names its Malaysian day as `12 Sept 2026`. 2026-10-19. Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT CHANGED (the third audit, item 20)
--   ops_log wrote a moved first draft or final date as
--   to_char(…, 'DD Mon YYYY'): "05 Sep 2026", where the house writes
--   "5 Sept 2026" (register_day), and read on the database's UTC clock, so
--   a date at midnight in Malaysia read as the day before. It now names the
--   Malaysian day through register_day. Every other line is ONE PRESS, ONE
--   NOTICE's, unchanged.
--
-- ROLLBACK
--   Run ops_log as ONE PRESS, ONE NOTICE stated it
--   (2026-10-18-one-press-one-notice.sql).
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
      || ' date moved to ' || public.register_day(((p_to ->> 'value')::timestamptz at time zone 'Asia/Kuala_Lumpur')::date)
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

-- END OF A MOVED DATE READS AS THE HOUSE WRITES IT -------------------------

select public.functions_tidy();
