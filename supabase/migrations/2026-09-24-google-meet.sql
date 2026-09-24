-- ===========================================================================
-- THE CONTENT MEETING ON GOOGLE MEET — a length, a link, and the calendar
-- event it lives on.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   1. Three columns on `ops_engagements`: `meeting_minutes` (how long, 15 to
--      240, 30 by default, so the message to the client can say when it
--      ends), `meeting_link` (the Meet link, generated or pasted), and
--      `meeting_event_id` (the event on the shared Google calendar, so a
--      moved meeting moves the event and a cancelled one removes it).
--
--   2. `ops_engagement_set_meeting` takes the length and a pasted link. Its
--      older six-argument shape is dropped first, because PostgREST cannot
--      tell a call that names six arguments from one that names six and
--      leaves two to their defaults. Marking the month as having no meeting
--      clears the link; the calendar event is removed by the page through
--      the meet-create function.
--
--   3. `ops_engagement_meet_prepare` and `ops_engagement_set_meet`, the two
--      calls the meet-create edge function makes as the signed-in person: the
--      first answers what the calendar needs (and refuses a person who may
--      not work the month), the second records the link and the event. Both
--      ask what every write on the month asks: ops Work, and a month the
--      person may see.
--
--   4. `ops_log` tells a task's owner when somebody else comments on it, with
--      the first 140 characters of the comment. Every other rule is as the
--      daily tracker left it: nobody is told about their own act.
--
-- ROLLBACK
--   drop function if exists public.ops_engagement_meet_prepare(uuid);
--   drop function if exists public.ops_engagement_set_meet(uuid, text, text);
--   drop function if exists public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean, integer, text);
--   Re-run 2026-09-23-operations-phase4.sql for the six-argument
--   ops_engagement_set_meeting and 2026-09-24-my-work-daily-tasks.sql for
--   ops_log, then:
--   alter table public.ops_engagements drop column if exists meeting_minutes,
--     drop column if exists meeting_link, drop column if exists meeting_event_id;
-- ===========================================================================

-- 1. The length, the link and the event --------------------------------------
alter table public.ops_engagements add column if not exists meeting_minutes integer not null default 30;
alter table public.ops_engagements add column if not exists meeting_link text;
alter table public.ops_engagements add column if not exists meeting_event_id text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ops_engagements_minutes_check') then
    alter table public.ops_engagements add constraint ops_engagements_minutes_check
      check (meeting_minutes between 15 and 240);
  end if;
end $$;

-- 2. The meeting takes its length and a pasted link ------------------------------
drop function if exists public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean);
/* The content meeting. When it is first put in the diary the date is today
   or later; once it has been held the record stays as it was, because a past
   meeting is a fact and not a mistake. Not applicable is its own answer, and
   clears the link. A link is Google Meet's, Zoom's or Teams', never anything
   else, because it is sent to a client as it stands. */
create or replace function public.ops_engagement_set_meeting(
  p_engagement uuid, p_at timestamptz, p_channel text default null,
  p_owner uuid default null, p_note text default null, p_na boolean default false,
  p_minutes integer default null, p_link text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements; lk text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce(p_na, false) then
    update public.ops_engagements set meeting_na = true, meeting_note = coalesce(p_note, meeting_note),
           meeting_link = null, updated_at = now(), version = version + 1 where id = p_engagement;
    perform public.ops_engagement_log(p_engagement, 'meeting_na', jsonb_build_object('note', p_note));
    return public.ops_engagement_json(p_engagement);
  end if;
  if p_at is null then return jsonb_build_object('error', 'no-date'); end if;
  if p_channel is not null and p_channel not in ('onsite', 'google_meet', 'zoom', 'other') then
    return jsonb_build_object('error', 'bad-channel');
  end if;
  if e.meeting_at is null and p_at::date < current_date then
    return jsonb_build_object('error', 'meeting-in-past');
  end if;
  if p_minutes is not null and (p_minutes < 15 or p_minutes > 240) then
    return jsonb_build_object('error', 'bad-minutes');
  end if;
  lk := nullif(btrim(coalesce(p_link, '')), '');
  if lk is not null and lk !~* '^https://([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com)/' then
    return jsonb_build_object('error', 'bad-meeting-link');
  end if;
  update public.ops_engagements set
    meeting_at = p_at, meeting_channel = coalesce(p_channel, meeting_channel),
    meeting_owner_id = coalesce(p_owner, meeting_owner_id, m.id),
    meeting_note = case when p_note is null then meeting_note else nullif(btrim(p_note), '') end,
    meeting_minutes = coalesce(p_minutes, meeting_minutes),
    meeting_link = case when p_link is null then meeting_link else lk end,
    meeting_na = false, updated_at = now(), version = version + 1
  where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'meeting_set',
    jsonb_build_object('at', p_at, 'channel', p_channel, 'owner_id', p_owner, 'was', e.meeting_at,
                       'minutes', p_minutes));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean, integer, text) to authenticated;

-- 3. The two calls the calendar function makes ------------------------------------
/* What the shared calendar needs to book the month's meeting, asked as the
   person pressing the button: a person who may not work the month is refused
   here, before Google is asked anything. */
create or replace function public.ops_engagement_meet_prepare(p_engagement uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements; cl text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  select * into e from public.ops_engagements where id = p_engagement;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select c.name into cl from public.clients c where c.id = e.client_id;
  return jsonb_build_object(
    'id', e.id, 'client_name', coalesce(cl, 'Client'),
    'month_word', to_char(to_date(e.period || '-01', 'YYYY-MM-DD'), 'Mon YYYY'),
    'meeting_at', e.meeting_at, 'meeting_minutes', e.meeting_minutes,
    'meeting_channel', e.meeting_channel, 'meeting_na', e.meeting_na,
    'meeting_link', e.meeting_link, 'meeting_event_id', e.meeting_event_id);
end $$;
grant execute on function public.ops_engagement_meet_prepare(uuid) to authenticated;

/* The link and the event the calendar made, recorded on the month. A null
   pair is the event removed, and takes the Meet link with it; a Zoom or
   Teams link somebody typed is theirs and stays. */
create or replace function public.ops_engagement_set_meet(p_engagement uuid, p_link text, p_event text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_link is not null and p_link !~* '^https://meet\.google\.com/' then
    return jsonb_build_object('error', 'bad-meeting-link');
  end if;
  update public.ops_engagements set meeting_link = case
           when p_link is not null then p_link
           when p_event is null and meeting_link ~* '^https://meet\.google\.com/' then null
           else meeting_link end,
         meeting_event_id = p_event, meeting_channel = case when p_link is not null then 'google_meet' else meeting_channel end,
         updated_at = now(), version = version + 1
   where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, case when p_event is null then 'meet_removed' else 'meet_booked' end,
    jsonb_build_object('link', p_link, 'event', p_event));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meet(uuid, text, text) to authenticated;


-- 4. A comment tells the task's owner ------------------------------------------------
/* ops_log as the daily tracker left it, and a comment somebody else made on
   a task tells its owner what was said. */
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


-- END OF THE CONTENT MEETING ON GOOGLE MEET --------------------------------
