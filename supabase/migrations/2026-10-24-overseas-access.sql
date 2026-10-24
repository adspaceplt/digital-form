-- ===========================================================================
-- OVERSEAS ACCESS — the console answers a colleague outside Malaysia and
-- Singapore only once an admin has approved it, for 14 days at most
-- (2026-10-24)
-- ===========================================================================
-- WHY (the user, 2026-10-24: "due to safety purposes … once detected located
-- overseas then prompt a window to submit request access and the request
-- would go to admin for approval … admin excluded"; "Allowed in Malaysia
-- Singapore"; "14 days per cycle"; "Admins only"): a sign-in used from
-- abroad, a colleague's or a stolen one, should not read the team's data
-- without somebody deciding it may.
--
-- WHAT IT ADDS
--   * `request_country()`: the country Cloudflare saw the request come from
--     (`cf-ipcountry`, which Cloudflare sets and a caller cannot: checked on
--     the live API, 2026-10-24), empty where there is no request (pg_cron,
--     the SQL Editor). Internal.
--   * `team_place_ok(p_admin, p_member)`: true for an admin, a request from
--     Malaysia or Singapore or with no country, or a colleague holding an
--     approved request whose day (MYT) has not passed. Internal.
--   * `is_team()`, `allowed(p_section, p_level)`, `ops_granted`, `ops_me()`
--     and `me()` ask it, so every policy and every function that asks them
--     refuses a colleague abroad without approval. `allowed('admin')` is an
--     admin's alone and needs no change. Client pages never ask them.
--   * `team_abroad` (RLS on, no policy, no grant): a request a row, waiting,
--     approved (until a day), declined or ended.
--   * `abroad_state()`: the signed-in colleague's own country, whether they
--     are held, their latest request and the days an approval may run.
--   * `abroad_request(p_reason, p_until)`: a colleague who is not an admin
--     asks (`bad-reason` 3 to 300, `bad-until` today to today plus
--     `abroad_days`); a waiting request is replaced; every active admin but a
--     system account is told (kind `abroad.request`).
--   * `abroad_list()`, `abroad_decide(p_id, p_approve, p_until, p_note)`,
--     `abroad_end(p_id)`: an admin's; each decision filed `team.changed`
--     under Overseas access, and the colleague told (kind `abroad.decided`).
--   * `abroad_days` (14), a Business setting (Settings, Portal: Overseas
--     approval, 1 to 30), which `app_settings_set` takes from OVERSEAS
--     APPROVAL DAYS, the SQL Editor's part.
--
-- ORDER: this file (the connector), then
-- 2026-10-24-overseas-access-days.sql (the SQL Editor: it holds a delete),
-- then the pages. A page served before it asks nothing;
-- a colleague abroad then reads Access denied until the pages are live.
-- Safe to run twice. Rollback: the five functions as ACCESS ENDS ON THE
-- MINUTE and TEAM ACCESS left them (drop the new ones in the SQL Editor).
-- ===========================================================================

create table if not exists public.team_abroad (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  country        text not null default '',
  reason         text not null,
  until          date not null,
  status         text not null default 'waiting',
  note           text,
  asked_at       timestamptz not null default now(),
  decided_by     uuid references public.team_members(id) on delete set null,
  decided_at     timestamptz,
  constraint team_abroad_status_check check (status in ('waiting', 'approved', 'declined', 'ended'))
);
create index if not exists team_abroad_member_idx on public.team_abroad (team_member_id, status, until);
alter table public.team_abroad enable row level security;
revoke all on public.team_abroad from public, anon, authenticated;

insert into public.app_settings (key, from_date, value)
select 'abroad_days', date '2023-08-14', 14
 where not exists (select 1 from public.app_settings s where s.key = 'abroad_days');

create or replace function public.request_country()
returns text
language sql stable set search_path = public as $$
  select upper(left(coalesce(nullif(btrim(h ->> 'cf-ipcountry'), ''), ''), 2))
  from (select coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json as h) r
$$;
revoke all on function public.request_country() from public, anon, authenticated;

create or replace function public.team_home_country(p_country text)
returns boolean
language sql immutable set search_path = public as $$
  select coalesce(p_country, '') in ('', 'MY', 'SG')
$$;
revoke all on function public.team_home_country(text) from public, anon, authenticated;

create or replace function public.team_place_ok(p_admin boolean, p_member uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(p_admin, false)
      or public.team_home_country(public.request_country())
      or exists (select 1 from public.team_abroad a
                  where a.team_member_id = p_member and a.status = 'approved'
                    and a.until >= (now() at time zone 'Asia/Kuala_Lumpur')::date)
$$;
revoke all on function public.team_place_ok(boolean, uuid) from public, anon, authenticated;

create or replace function public.is_team()
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.team_members t
    where t.active and lower(t.email) = lower(auth.jwt() ->> 'email')
      and (t.access_until is null or t.is_admin or t.role = 'admin'
           or public.team_access_ends(t.access_until, t.access_until_time) > now())
      and public.team_place_ok(t.is_admin or t.role = 'admin', t.id))
$$;
grant execute on function public.is_team() to authenticated;

create or replace function public.allowed(p_section text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members;
  k text := lower(coalesce(p_section, ''));
  lv text;
begin
  select * into t from public.team_members x
    where lower(x.email) = lower(auth.jwt() ->> 'email') and x.active
      and (x.access_until is null or x.is_admin or x.role = 'admin'
           or public.team_access_ends(x.access_until, x.access_until_time) > now())
    limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  if not public.team_place_ok(false, t.id) then return false; end if;
  lv := t.access ->> k;
  if lv is null and position('.' in k) > 0 then
    lv := t.access ->> split_part(k, '.', 1);
  end if;
  return public.level_rank(lv) >= public.level_rank(p_level);
end $$;
grant execute on function public.allowed(text, text) to authenticated;

create or replace function public.ops_granted(p_key text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
   where active and lower(email) = lower(auth.jwt() ->> 'email') limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  if not public.team_place_ok(false, t.id) then return false; end if;
  return public.level_rank(t.access ->> p_key) >= public.level_rank(p_level);
end $$;
grant execute on function public.ops_granted(text, text) to authenticated;

create or replace function public.ops_me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members t
   where t.active and lower(t.email) = lower(auth.jwt() ->> 'email')
     and (t.access_until is null or t.is_admin or t.role = 'admin'
          or public.team_access_ends(t.access_until, t.access_until_time) > now())
     and public.team_place_ok(t.is_admin or t.role = 'admin', t.id)
   limit 1
$$;
grant execute on function public.ops_me() to authenticated;

create or replace function public.me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members t
  where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active
    and (t.access_until is null or t.is_admin or t.role = 'admin'
         or public.team_access_ends(t.access_until, t.access_until_time) > now())
    and public.team_place_ok(t.is_admin or t.role = 'admin', t.id)
  limit 1
$$;
grant execute on function public.me() to authenticated;

/* The colleague signed in, whatever the country: who the cover is for. */
create or replace function public.abroad_who()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members t
  where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active
    and (t.access_until is null or t.is_admin or t.role = 'admin'
         or public.team_access_ends(t.access_until, t.access_until_time) > now())
  limit 1
$$;
revoke all on function public.abroad_who() from public, anon, authenticated;

create or replace function public.abroad_state()
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members := public.abroad_who();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_admin boolean;
  a public.team_abroad;
begin
  if t.id is null then return jsonb_build_object('team', false); end if;
  v_admin := t.is_admin or t.role = 'admin';
  select * into a from public.team_abroad x where x.team_member_id = t.id order by x.asked_at desc limit 1;
  return jsonb_build_object(
    'team', true, 'admin', v_admin, 'country', public.request_country(),
    'held', not public.team_place_ok(v_admin, t.id),
    'today', v_today,
    'days', coalesce(public.app_setting('abroad_days', v_today), 14)::int,
    'request', case when a.id is null then null else jsonb_build_object(
      'id', a.id, 'status', case when a.status = 'approved' and a.until < v_today then 'expired' else a.status end,
      'until', a.until, 'country', a.country, 'reason', a.reason, 'note', a.note,
      'asked_at', a.asked_at, 'decided_at', a.decided_at) end);
end $$;
revoke all on function public.abroad_state() from public, anon;
grant execute on function public.abroad_state() to authenticated;

create or replace function public.abroad_request(p_reason text, p_until date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t public.team_members := public.abroad_who();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days int := coalesce(public.app_setting('abroad_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 14)::int;
  v_reason text := btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g'));
  v_country text := public.request_country();
  v_id uuid;
begin
  if t.id is null then return jsonb_build_object('error', 'denied'); end if;
  if t.is_admin or t.role = 'admin' then return jsonb_build_object('error', 'admin'); end if;
  if char_length(v_reason) < 3 or char_length(v_reason) > 300 then return jsonb_build_object('error', 'bad-reason'); end if;
  if p_until is null or p_until < v_today or p_until > v_today + v_days then
    return jsonb_build_object('error', 'bad-until', 'max', v_today + v_days);
  end if;
  select x.id into v_id from public.team_abroad x
   where x.team_member_id = t.id and x.status = 'waiting' order by x.asked_at desc limit 1 for update;
  if v_id is null then
    insert into public.team_abroad (team_member_id, country, reason, until)
    values (t.id, v_country, v_reason, p_until) returning id into v_id;
  else
    update public.team_abroad set country = v_country, reason = v_reason, until = p_until, asked_at = now()
     where id = v_id;
  end if;
  insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
  select m.id, 'abroad.request', 'Overseas access requested · ' || t.name,
         case when v_country <> '' then 'From ' || v_country || ' · ' else '' end ||
         'until ' || public.register_day(p_until) || ' · ' || v_reason,
         'abroad:' || v_id || ':' || m.id || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI')
    from public.team_members m
   where m.active and (m.is_admin or m.role = 'admin') and not coalesce(m.system, false)
  on conflict (dedupe_key) do nothing;
  return public.abroad_state();
end $$;
revoke all on function public.abroad_request(text, date) from public, anon;
grant execute on function public.abroad_request(text, date) to authenticated;

create or replace function public.abroad_list()
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'today', v_today,
    'days', coalesce(public.app_setting('abroad_days', v_today), 14)::int,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'member', a.team_member_id, 'name', m.name, 'code', m.staff_code,
        'country', a.country, 'reason', a.reason, 'until', a.until, 'note', a.note,
        'status', case when a.status = 'approved' and a.until < v_today then 'expired' else a.status end,
        'asked_at', a.asked_at, 'decided_at', a.decided_at,
        'decided_by', (select d.name from public.team_members d where d.id = a.decided_by))
        order by (a.status = 'waiting') desc, (a.status = 'approved' and a.until >= v_today) desc, a.asked_at desc)
      from public.team_abroad a join public.team_members m on m.id = a.team_member_id
     where a.status = 'waiting' or (a.status = 'approved' and a.until >= v_today)
        or a.asked_at > now() - interval '90 days'), '[]'::jsonb));
end $$;
revoke all on function public.abroad_list() from public, anon;
grant execute on function public.abroad_list() to authenticated;

create or replace function public.abroad_decide(p_id uuid, p_approve boolean, p_until date default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days int := coalesce(public.app_setting('abroad_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 14)::int;
  v_note text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
  a public.team_abroad; v_name text;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.team_abroad x where x.id = p_id for update;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if a.status <> 'waiting' then return jsonb_build_object('error', 'not-waiting'); end if;
  if char_length(coalesce(v_note, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  if coalesce(p_approve, false) and (p_until is null or p_until < v_today or p_until > v_today + v_days) then
    return jsonb_build_object('error', 'bad-until', 'max', v_today + v_days);
  end if;
  update public.team_abroad
     set status = case when p_approve then 'approved' else 'declined' end,
         until = case when p_approve then p_until else until end,
         note = v_note, decided_by = v_me.id, decided_at = now()
   where id = a.id;
  select m.name into v_name from public.team_members m where m.id = a.team_member_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Overseas access',
    coalesce(v_name, 'A colleague') || ': ' ||
    case when p_approve then 'approved until ' || public.register_day(p_until) else 'declined' end ||
    case when a.country <> '' then ' · from ' || a.country else '' end ||
    case when v_note is not null then ' · ' || v_note else '' end);
  insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
  values (a.team_member_id, 'abroad.decided',
    case when p_approve then 'Overseas access approved until ' || public.register_day(p_until)
         else 'Overseas access declined' end,
    v_note, 'abroad.decided:' || a.id)
  on conflict (dedupe_key) do nothing;
  return public.abroad_list();
end $$;
revoke all on function public.abroad_decide(uuid, boolean, date, text) from public, anon;
grant execute on function public.abroad_decide(uuid, boolean, date, text) to authenticated;

create or replace function public.abroad_end(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  a public.team_abroad; v_name text;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.team_abroad x where x.id = p_id for update;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if a.status <> 'approved' or a.until < v_today then return jsonb_build_object('error', 'not-approved'); end if;
  update public.team_abroad set status = 'ended', decided_by = v_me.id, decided_at = now() where id = a.id;
  select m.name into v_name from public.team_members m where m.id = a.team_member_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Overseas access',
    coalesce(v_name, 'A colleague') || ': ended · was approved until ' || public.register_day(a.until));
  insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
  values (a.team_member_id, 'abroad.decided', 'Overseas access ended', null, 'abroad.ended:' || a.id)
  on conflict (dedupe_key) do nothing;
  return public.abroad_list();
end $$;
revoke all on function public.abroad_end(uuid) from public, anon;
grant execute on function public.abroad_end(uuid) to authenticated;

-- END OF OVERSEAS ACCESS ----------------------------------------------------

select public.functions_tidy();
