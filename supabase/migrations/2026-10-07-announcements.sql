-- ===========================================================================
-- ANNOUNCEMENTS — one line at the top of the portal, for the team (the
-- console) or for clients (every client page), each its own, one at a time.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after ADMIN PARTS.
--
-- WHAT CHANGED (the user, 2026-10-06: "announcement in the portal ... team
-- and clients. able to choose separately. one at a time.")
--   1. `announcements` (RLS on, no policy, no grant): the audience (`team`
--      or `clients`), the tone (`info` or `important`), the words in English
--      and, optionally, 中文 (300 characters each), an optional https link,
--      an optional start and end, and `ended_at` once stopped or replaced.
--   2. `announcement_now(p_audience)`: the one live for that audience (its
--      start passed or none, its end ahead or none, not ended), newest first.
--      Clients' is read by anyone (every client page, signed in or by link);
--      the team's by the team alone.
--   3. Team: Announcements (`team.announce`, a granted part: an admin's by
--      itself, any other group's once set) writes:
--      `announcement_save(p_id, p_audience, p_tone, p_body_en, p_body_zh,
--      p_link, p_starts, p_ends)` (bad-audience, bad-tone, bad-text,
--      bad-link, bad-window), which ends every other announcement of that
--      audience (one at a time); `announcement_end(p_id, p_on)`, Stop (false)
--      and Restore (true, while its end is ahead; it ends the others again);
--      `announcements_list()`, the latest 20 of each audience. Every write is
--      filed `team.changed` under subject Announcements.
--
-- ROLLBACK
--   Nothing reads the table but these functions; leaving them unused hides
--   every bar.
-- ===========================================================================

create table if not exists public.announcements (
  id         uuid primary key default gen_random_uuid(),
  audience   text not null,
  tone       text not null default 'info',
  body_en    text not null,
  body_zh    text,
  link       text,
  starts_at  timestamptz,
  ends_at    timestamptz,
  ended_at   timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now()
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'announcements_audience') then
    alter table public.announcements add constraint announcements_audience check (audience in ('team', 'clients'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'announcements_tone') then
    alter table public.announcements add constraint announcements_tone check (tone in ('info', 'important'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'announcements_text') then
    alter table public.announcements add constraint announcements_text
      check (char_length(btrim(body_en)) between 1 and 300 and (body_zh is null or char_length(body_zh) <= 300));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'announcements_link') then
    alter table public.announcements add constraint announcements_link check (link is null or link ~ '^https://[^\s]+$');
  end if;
end $$;
create index if not exists announcements_live_idx on public.announcements (audience, updated_at desc) where ended_at is null;
alter table public.announcements enable row level security;
revoke all on table public.announcements from public, anon, authenticated;

create or replace function public.announcement_json(a public.announcements)
returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', a.id, 'audience', a.audience, 'tone', a.tone, 'body_en', a.body_en,
    'body_zh', a.body_zh, 'link', a.link, 'starts_at', a.starts_at, 'ends_at', a.ends_at,
    'ended_at', a.ended_at, 'created_by', a.created_by, 'created_at', a.created_at,
    'updated_by', a.updated_by, 'updated_at', a.updated_at)
$$;
revoke all on function public.announcement_json(public.announcements) from public, anon, authenticated;

create or replace function public.announcement_now(p_audience text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a public.announcements;
begin
  if p_audience not in ('team', 'clients') then return null; end if;
  if p_audience = 'team' and not public.is_team() then return null; end if;
  select * into a from public.announcements x
   where x.audience = p_audience and x.ended_at is null
     and (x.starts_at is null or x.starts_at <= now())
     and (x.ends_at is null or x.ends_at > now())
   order by x.updated_at desc limit 1;
  if a.id is null then return null; end if;
  return public.announcement_json(a) - 'created_by' - 'updated_by' - 'created_at' - 'ended_at';
end $$;
grant execute on function public.announcement_now(text) to anon, authenticated;

create or replace function public.announcements_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ops_granted('team.announce', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('now', now(), 'items', coalesce((
    select jsonb_agg(public.announcement_json(x) order by x.updated_at desc)
      from public.announcements x
     where (select count(*) from public.announcements z
             where z.audience = x.audience and z.updated_at > x.updated_at) < 20), '[]'::jsonb));
end $$;
revoke all on function public.announcements_list() from public, anon;
grant execute on function public.announcements_list() to authenticated;

/* "Team announcement: … · Important · from … · until …", Malaysia time. */
create or replace function public.announcement_said(a public.announcements)
returns text
language sql stable set search_path = public as $$
  select case a.audience when 'team' then 'Team' else 'Clients' end || ' announcement: ' || a.body_en
      || case when a.tone = 'important' then ' · Important' else '' end
      || case when a.starts_at is not null
              then ' · from ' || to_char(a.starts_at at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY HH24:MI') else '' end
      || case when a.ends_at is not null
              then ' · until ' || to_char(a.ends_at at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY HH24:MI') else '' end
$$;
revoke all on function public.announcement_said(public.announcements) from public, anon, authenticated;

create or replace function public.announcement_save(p_id uuid, p_audience text, p_tone text, p_body_en text,
                                                    p_body_zh text, p_link text, p_starts timestamptz,
                                                    p_ends timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_en text := btrim(coalesce(p_body_en, ''));
  v_zh text := nullif(btrim(coalesce(p_body_zh, '')), '');
  v_link text := nullif(btrim(coalesce(p_link, '')), '');
  v_tone text := coalesce(nullif(p_tone, ''), 'info');
  a public.announcements;
  v_was text;
  v_gone int;
begin
  if me.id is null or not public.ops_granted('team.announce', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_audience is null or p_audience not in ('team', 'clients') then return jsonb_build_object('error', 'bad-audience'); end if;
  if v_tone not in ('info', 'important') then return jsonb_build_object('error', 'bad-tone'); end if;
  if char_length(v_en) < 1 or char_length(v_en) > 300 or char_length(coalesce(v_zh, '')) > 300 then
    return jsonb_build_object('error', 'bad-text');
  end if;
  if v_link is not null and v_link !~ '^https://[^\s]+$' then return jsonb_build_object('error', 'bad-link'); end if;
  if p_ends is not null and p_ends <= greatest(coalesce(p_starts, now()), now()) then
    return jsonb_build_object('error', 'bad-window');
  end if;
  if p_id is not null then
    select * into a from public.announcements x where x.id = p_id for update;
    if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if a.audience <> p_audience then return jsonb_build_object('error', 'bad-audience'); end if;
    v_was := public.announcement_said(a);
    update public.announcements x
       set tone = v_tone, body_en = v_en, body_zh = v_zh, link = v_link, starts_at = p_starts,
           ends_at = p_ends, ended_at = null, updated_by = me.name, updated_at = now()
     where x.id = p_id returning * into a;
  else
    insert into public.announcements (audience, tone, body_en, body_zh, link, starts_at, ends_at, created_by, updated_by)
    values (p_audience, v_tone, v_en, v_zh, v_link, p_starts, p_ends, me.name, me.name)
    returning * into a;
  end if;
  /* One at a time: every other announcement for the audience ends here. */
  update public.announcements x set ended_at = now()
   where x.audience = a.audience and x.id <> a.id and x.ended_at is null;
  get diagnostics v_gone = row_count;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Announcements',
    case when v_was is null then public.announcement_said(a)
         else v_was || ' → ' || public.announcement_said(a) end
    || case when v_gone > 0 then ' · the one before stopped' else '' end);
  return jsonb_build_object('ok', true, 'item', public.announcement_json(a));
end $$;
revoke all on function public.announcement_save(uuid, text, text, text, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function public.announcement_save(uuid, text, text, text, text, text, timestamptz, timestamptz) to authenticated;

create or replace function public.announcement_end(p_id uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  a public.announcements;
begin
  if me.id is null or not public.ops_granted('team.announce', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.announcements x where x.id = p_id for update;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(p_on, false) then
    if a.ended_at is null then return jsonb_build_object('ok', true); end if;
    if a.ends_at is not null and a.ends_at <= now() then return jsonb_build_object('error', 'over'); end if;
    update public.announcements x set ended_at = now()
     where x.audience = a.audience and x.id <> a.id and x.ended_at is null;
    update public.announcements x set ended_at = null, updated_by = me.name, updated_at = now()
     where x.id = a.id returning * into a;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Announcements', 'Restored · ' || public.announcement_said(a));
  else
    if a.ended_at is not null then return jsonb_build_object('ok', true); end if;
    update public.announcements x set ended_at = now() where x.id = a.id returning * into a;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Announcements', 'Stopped · ' || public.announcement_said(a));
  end if;
  return jsonb_build_object('ok', true, 'item', public.announcement_json(a));
end $$;
revoke all on function public.announcement_end(uuid, boolean) from public, anon;
grant execute on function public.announcement_end(uuid, boolean) to authenticated;

-- END OF ANNOUNCEMENTS --------------------------------------------------------
