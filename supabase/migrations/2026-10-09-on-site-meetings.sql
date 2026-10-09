-- ===========================================================================
-- ON-SITE MEETINGS — a content meeting held at the client's may be recorded
-- after the day, and whoever led it is reminded to submit the outstation
-- record.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-09: "on-site please allow add past date. and add one
--   more reminder for on-site to submit the outstation record
--   (go.adspace.me/outstation)".
--   1. `ops_engagement_set_meeting` accepts a first date in the past for an
--      on-site meeting (channel `onsite`): it was held, and is written down
--      afterwards. An online meeting is still put in the diary from today.
--   2. `ops_notifications.link`: an https address a notice opens (the bell
--      and a push alike), in place of a console page.
--   3. `ops_outstation_remind()` (pg_cron `outstation-reminder`, every
--      fifteen minutes): each on-site meeting that has ended tells whoever
--      led it (else the month's manager), once, to submit the outstation
--      record (kind `outstation`, the form's address as its link).
--      `ops_engagements.outstation_told_at` keeps that it was told; a
--      meeting moved to another time is told again for the new one. The
--      on-site meetings that ended before this file are counted as told.
--
-- ROLLBACK
--   select cron.unschedule('outstation-reminder');
--   drop function if exists public.ops_outstation_remind();
--   Re-run 2026-09-24-content-meeting-google-meet.sql for
--   ops_engagement_set_meeting and 2026-10-08-tasks-reminder.sql for
--   ops_notifications_push, then:
--   alter table public.ops_engagements drop column if exists outstation_told_at;
--   alter table public.ops_notifications drop column if exists link;
-- ===========================================================================

alter table public.ops_engagements add column if not exists outstation_told_at timestamptz;
alter table public.ops_notifications add column if not exists link text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ops_notifications_link_https') then
    alter table public.ops_notifications add constraint ops_notifications_link_https
      check (link is null or link ~* '^https://');
  end if;
end $$;

/* The on-site meetings that ended before reminders began were never owed
   one. */
update public.ops_engagements e set outstation_told_at = e.updated_at
 where e.meeting_channel = 'onsite' and e.outstation_told_at is null
   and e.meeting_at is not null and e.meeting_at < timestamptz '2026-10-09 16:00:00+00'
   and e.updated_at < timestamptz '2026-10-09 16:00:00+00';

/* The content meeting. Put in the diary, an online meeting's first date is
   today or later; an on-site one may be written down after it was held.
   Once held the record stays as it was, because a past meeting is a fact
   and not a mistake. Not applicable is its own answer, and clears the link.
   A link is Google Meet's, Zoom's or Teams', never anything else, because
   it is sent to a client as it stands. A meeting moved to another time owes
   its outstation reminder again. */
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
  if e.meeting_at is null and p_at::date < current_date
     and coalesce(p_channel, e.meeting_channel, '') <> 'onsite' then
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
    outstation_told_at = case when e.meeting_at is distinct from p_at then null else outstation_told_at end,
    meeting_na = false, updated_at = now(), version = version + 1
  where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'meeting_set',
    jsonb_build_object('at', p_at, 'channel', p_channel, 'owner_id', p_owner, 'was', e.meeting_at,
                       'minutes', p_minutes));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean, integer, text) to authenticated;

/* Each on-site meeting that has ended tells whoever led it, once, to submit
   the outstation record; a meeting nobody leads tells the month's manager.
   Run by pg_cron alone. */
create or replace function public.ops_outstation_remind()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  for r in
    select e.id, e.meeting_at, coalesce(e.meeting_owner_id, e.manager_id) as who, c.name as client_name
      from public.ops_engagements e
      left join public.clients c on c.id = e.client_id
     where e.meeting_channel = 'onsite' and not e.meeting_na and e.meeting_at is not null
       and e.outstation_told_at is null
       and e.meeting_at + make_interval(mins => coalesce(e.meeting_minutes, 30)) <= now()
       and coalesce(e.status, '') <> 'cancelled'
     for update of e skip locked
  loop
    if r.who is not null and exists (select 1 from public.team_members t where t.id = r.who and t.active) then
      insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
      values (r.who, 'outstation', 'Submit the outstation record',
              coalesce(r.client_name, 'Client') || ' · on-site meeting on ' ||
                public.register_day((r.meeting_at at time zone 'Asia/Kuala_Lumpur')::date),
              'https://go.adspace.me/outstation',
              'outstation.' || r.id::text || '.' || extract(epoch from r.meeting_at)::bigint::text)
      on conflict (dedupe_key) do nothing;
      n := n + 1;
    end if;
    update public.ops_engagements set outstation_told_at = now() where id = r.id;
  end loop;
  return n;
end $$;
revoke all on function public.ops_outstation_remind() from public, anon, authenticated;

/* A notice with a link opens it, on a phone as in the bell. */
create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.link is not null then new.link
         when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         when new.kind in ('client_left', 'tasks.empty') then '/admin/?s=work'
         when new.kind = 'hr.letter' then '/admin/?s=mine&view=letters'
         when new.kind = 'perf.disputed' then '/admin/?s=team&tab=performance'
         when new.kind = 'perf.reflect' then '/admin/?s=mine&view=reflection'
         when new.kind = 'perf.initiative' then '/admin/?s=mine&view=initiatives'
         when new.kind like 'health.%' then '/admin/?s=mine&view=health'
         when new.kind like 'perf.%' then '/admin/?s=mine'
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         when new.kind = 'hr.letter' then 'hr-letter'
         when new.kind in ('perf.remind', 'perf.reflect', 'health.remind') then 'my-hr'
         when new.kind = 'tasks.empty' then 'tasks-empty'
         when new.kind = 'outstation' then 'outstation'
         else null end);
  return new;
exception when others then
  return new;
end $$;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: no outstation reminders go out until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'outstation-reminder';
  perform cron.schedule('outstation-reminder', '*/15 * * * *', 'select public.ops_outstation_remind()');
end $$;

-- END OF ON-SITE MEETINGS -----------------------------------------------------

select public.functions_tidy();
