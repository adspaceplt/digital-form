-- ===========================================================================
-- PORTAL MEETINGS FROM MALAYSIA'S MONTH — the client portal's meetings are
-- read from the first of the month three months back, on Malaysia's
-- calendar. 2026-10-17. Safe to run twice. Rollback at the foot. Mirrored
-- byte for byte in supabase/schema.sql under the same banner; tests/sql.js
-- compares the two.
--
-- WHAT CHANGED (the review of the audit's fix batches, finding 8)
--   MALAYSIA TIME IN THE DATABASE wrote `portal_meetings`' window as
--   `date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time
--   zone 'Asia/Kuala_Lumpur' - interval '3 months'`. `at time zone` binds
--   before `-`, so the month's start became a moment first and the three
--   months were taken on the server's UTC calendar: in March the window
--   opened on 29 November (MYT), not 1 December. The months are now taken
--   on Malaysia's local time, then made a moment. No other function holds
--   the shape (tests/sql.js holds that none does).
--
-- ROLLBACK
--   Run portal_meetings again from MALAYSIA TIME IN THE DATABASE.
-- ===========================================================================

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
     The link is sent only while the meeting is still ahead. The three
     months are counted on Malaysia's calendar, then made a moment
     (2026-10-17: `at time zone` binds before `-`, so they were counted on
     the UTC calendar, and in March the window opened on 29 November). */
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
         and e.meeting_at >= (date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') - interval '3 months') at time zone 'Asia/Kuala_Lumpur'
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
         and t.meet_at >= (date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') - interval '3 months') at time zone 'Asia/Kuala_Lumpur') x), '[]'::jsonb));
end $$;
revoke all on function public.portal_meetings(uuid) from public, anon;
grant execute on function public.portal_meetings(uuid) to authenticated;

-- END OF PORTAL MEETINGS FROM MALAYSIA'S MONTH -----------------------------

select public.functions_tidy();
