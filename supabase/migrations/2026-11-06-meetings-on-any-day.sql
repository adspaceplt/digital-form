-- ===========================================================================
-- MEETINGS ON ANY DAY (2026-11-06)
-- ===========================================================================
-- WHY: the user, on the Content meeting sheet: a meeting held on site, on
-- Zoom or on a Google Meet whose link was pasted is written down after it
-- happened, earlier today or on a day before, so only a Google Meet the
-- shared calendar books waits for the next half hour (the page holds that,
-- since the database never knows which link the calendar will make).
--
-- WHAT IT CHANGES
--   `ops_engagement_set_meeting` (restated whole from MALAYSIA TIME IN THE
--   DATABASE): a first meeting on any channel may be on a day before today;
--   a day before 14 Aug 2023 (ADSPACE PLT's registration, the portal's
--   date floor) is refused `meeting-before-floor`. Nothing else changes.
--
-- ORDER: the pages, then this file (an old page refuses a past day on an
-- online meeting itself, as before). Safe to run twice. Rollback:
-- ops_engagement_set_meeting from MALAYSIA TIME IN THE DATABASE again.
-- ===========================================================================

-- MEETINGS ON ANY DAY ------------------------------------------------------

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
  if (p_at at time zone 'Asia/Kuala_Lumpur')::date < date '2023-08-14' then
    return jsonb_build_object('error', 'meeting-before-floor');
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
    outstation_told_at = case when e.meeting_at is distinct from p_at then null else outstation_told_at end,
    meeting_na = false, updated_at = now(), version = version + 1
  where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'meeting_set',
    jsonb_build_object('at', p_at, 'channel', p_channel, 'owner_id', p_owner, 'was', e.meeting_at,
                       'minutes', p_minutes));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean, integer, text) to authenticated;

-- END OF MEETINGS ON ANY DAY -----------------------------------------------

select public.functions_tidy();
