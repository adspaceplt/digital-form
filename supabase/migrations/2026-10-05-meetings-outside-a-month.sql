-- ===========================================================================
-- MEETINGS OUTSIDE A MONTH — a meeting in a client's Calls and visits takes a
-- time, a length and a link (a Google Meet made for it), and the client's
-- portal lists it beside the month's content meeting.
-- 2026-10-05. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js (§41) compares
-- the two. Runs after EVERY TASK IN A CONFIRMED MONTH (portal_meetings).
--
-- WHAT CHANGED
--   The user: "sometimes we also create adhoc meeting (not new month) but
--   to record inside as extras". `client_touches` gains meet_at,
--   meet_minutes (15 to 240), meet_link (Meet, Zoom or Teams only) and
--   meet_event_id. `client_touch_meet_prepare` and `client_touch_set_meet`
--   are what meet-create asks for an entry, as it asks the month's pair;
--   both run as the caller, so the table's own policies (Clients: Calls
--   at Work, the client scope) decide. portal_meetings adds these meetings.
--
-- ROLLBACK
--   Run portal_meetings from EVERY TASK IN A CONFIRMED MONTH again; the
--   columns and the two functions may stay (nothing else reads them).
-- ===========================================================================

alter table public.client_touches add column if not exists meet_at       timestamptz;
alter table public.client_touches add column if not exists meet_minutes  integer;
alter table public.client_touches add column if not exists meet_link     text;
alter table public.client_touches add column if not exists meet_event_id text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_touches_meet_minutes') then
    alter table public.client_touches add constraint client_touches_meet_minutes
      check (meet_minutes is null or meet_minutes between 15 and 240);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'client_touches_meet_link') then
    alter table public.client_touches add constraint client_touches_meet_link
      check (meet_link is null or meet_link ~* '^https://([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com)/');
  end if;
end $$;

/* What meet-create needs to book an entry's meeting, read as the caller:
   an entry the caller cannot read answers not-found. */
create or replace function public.client_touch_meet_prepare(p_touch uuid)
returns jsonb
language plpgsql security invoker stable set search_path = public as $$
declare t public.client_touches; cl text;
begin
  if not public.allowed('clients.calls', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.client_touches where id = p_touch and archived_at is null;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* An entry that stopped being a meeting is still read while its event
     stands, so the event can be taken off the calendar. */
  if t.kind <> 'meeting' and t.meet_event_id is null then return jsonb_build_object('error', 'not-a-meeting'); end if;
  select c.name into cl from public.clients c where c.id = t.client_id;
  return jsonb_build_object('id', t.id, 'client_name', coalesce(cl, 'Client'),
    'meeting_at', t.meet_at, 'meeting_minutes', coalesce(t.meet_minutes, 30),
    'meeting_link', t.meet_link, 'meeting_event_id', t.meet_event_id);
end $$;
grant execute on function public.client_touch_meet_prepare(uuid) to authenticated;

/* The link and the calendar's event, recorded on the entry as the caller.
   A null pair is the event removed and takes a Meet link with it; a Zoom
   or Teams link somebody typed stays. */
create or replace function public.client_touch_set_meet(p_touch uuid, p_link text, p_event text)
returns jsonb
language plpgsql security invoker set search_path = public as $$
declare t public.client_touches;
begin
  if not public.allowed('clients.calls', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_link is not null and p_link !~* '^https://meet\.google\.com/' then
    return jsonb_build_object('error', 'bad-meeting-link');
  end if;
  update public.client_touches set meet_link = case
           when p_link is not null then p_link
           when p_event is null and meet_link ~* '^https://meet\.google\.com/' then null
           else meet_link end,
         meet_event_id = p_event, updated_at = now()
   where id = p_touch and archived_at is null
  returning * into t;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  return to_jsonb(t);
end $$;
grant execute on function public.client_touch_set_meet(uuid, text, text) to authenticated;

create or replace function public.portal_meetings(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  /* The content meetings the team has put in the diary, from three months
     back. Nothing about the month's tasks, checks or status beyond this: a
     client reads when we meet, never how the work inside the month is going.
     The link is sent only while the meeting is still ahead. */
  /* Beside them, the meetings the team booked outside a month (Calls and
     visits, kind meeting, with a time; 2026-10-05): the time, the length
     and the link, never what was written about it. */
  return jsonb_build_object('meetings', coalesce((
    select jsonb_agg(x.j order by x.at desc) from (
      select e.meeting_at as at, jsonb_build_object(
               'kind', 'content', 'period', e.period, 'at', e.meeting_at, 'minutes', coalesce(e.meeting_minutes, 30),
               'channel', e.meeting_channel,
               'link', case when e.meeting_at + make_interval(mins => coalesce(e.meeting_minutes, 30)) > now()
                            then e.meeting_link end) as j
        from public.ops_engagements e
       where e.client_id = p_client
         and e.meeting_at is not null
         and not coalesce(e.meeting_na, false)
         and e.status <> 'cancelled'
         and e.meeting_at >= date_trunc('month', now()) - interval '3 months'
      union all
      select t.meet_at, jsonb_build_object(
               'kind', 'meeting', 'period', null, 'at', t.meet_at, 'minutes', coalesce(t.meet_minutes, 30),
               'channel', case when t.meet_link ~* 'meet\.google\.com' then 'google_meet'
                               when t.meet_link ~* 'zoom\.us' then 'zoom'
                               when t.meet_link ~* 'teams\.' then 'teams' end,
               'link', case when t.meet_at + make_interval(mins => coalesce(t.meet_minutes, 30)) > now()
                            then t.meet_link end)
        from public.client_touches t
       where t.client_id = p_client
         and t.kind = 'meeting' and t.meet_at is not null and t.archived_at is null
         and t.meet_at >= date_trunc('month', now()) - interval '3 months') x), '[]'::jsonb));
end $$;
revoke all on function public.portal_meetings(uuid) from public, anon;
grant execute on function public.portal_meetings(uuid) to authenticated;

-- END OF MEETINGS OUTSIDE A MONTH -------------------------------------------
