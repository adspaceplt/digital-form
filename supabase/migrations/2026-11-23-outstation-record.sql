-- ===========================================================================
-- OUTSTATION RECORD (2026-11-23)
-- ===========================================================================
-- WHY: the user, 2026-11-23, approving the outstation mockup (screens 1, 2
-- and 5): the Lark form "Outstation Record Form" (go.adspace.me/outstation)
-- moves into My Work. The driver checks in at the first stop with the
-- colleagues going together, adds each next stop and its photos, and checks
-- out; the visit date and the hours on site come from the times, the place
-- from the phone's own location, never typed. Claims are release 2: the
-- zone and the road distance are kept here so they can be priced then.
--
-- WHAT IT ADDS
--   * `outstation_trips`, `outstation_stops`, `outstation_photos`: RLS on,
--     no policy, no grant; read and written only through the functions
--     below. A stop holds its client (or a venue), its reading (lat, lng,
--     accuracy in metres, when it was read), the address and zone the
--     geocoder answered (Johor, Singapore, Beyond Johor), its arrive and
--     leave times, the road km from the stop before (the office for the
--     first) and the visit it filed. A trip holds the km back to the office
--     and the total.
--   * `ops.outstation`, a granted part (an admin's by itself): every trip,
--     read only, with its export.
--   * `outstation_check_in`, `outstation_stop_add`, `outstation_photo_add`,
--     `outstation_check_out` (My Work at Work, the driver's alone), and
--     `outstation_trips(p_from, p_to, p_all)`: the trips the caller drove or
--     joined, every trip with `p_all` at `ops.outstation`. Each refuses in
--     the team's words through its code: `denied`, `open-trip`, `no-trip`,
--     `closed`, `bad-purpose`, `no-place`, `bad-client`, `bad-companion`,
--     `vague` (with the limit), `bad-location`, `no-photo`, `too-many`,
--     `bad-key`, `too-long`, `bad-rating`.
--   * A reading worse than the accuracy limit is refused (`vague`), as the
--     page refuses it first; a stop's photos must be one at least before
--     the next stop or check-out.
--   * Each client stop, once left, files a visit on the client's Calls and
--     visits (`client_touches`, kind visit), under the driver's name; one
--     the client scope refuses is left unfiled, never failing the trip.
--   * `outstation_photo_may(p_trip)` and `outstation_photo_key(p_photo)`:
--     what sign-upload and sign-download ask as the caller.
--   * `outstation_geo_may`, `outstation_geo_turn`, `outstation_stop_place`,
--     `outstation_route_set`: what the `outstation-geo` edge function asks
--     (the first as the caller, the rest as the service role): one
--     OpenStreetMap lookup a second across the portal, the address and zone
--     of a stop, the road km of a trip's legs.
--   * Settings, My Work: Outstation: `outstation_office_lat`,
--     `outstation_office_lng` (the office's pin), `outstation_accuracy_m`
--     (50) and `outstation_keep_months` (24), through `app_settings_set`
--     (the rest of it TONE SWEEP 6's as it stands).
--   * `outstation_prune()` (pg_cron `outstation-prune`, 03:47 MYT): a trip
--     ended more than the months kept is deleted with its stops and photo
--     rows; the visits it filed stay with the client. The photos in S3 stay,
--     as every upload does.
--
-- ORDER: the pages first (a page from before never asks), then this file,
-- then the `outstation-geo` function, then sign-upload and sign-download.
-- An open tab from before meets nothing new. Safe to run twice.
-- ROLLBACK: unschedule `outstation-prune`; drop the functions and the three
-- tables; delete the four settings and the access key; run app_settings_set
-- from TONE SWEEP 6's band (HEALTH CHECK-INS BY WORKLOAD) again.
-- ===========================================================================

insert into public.access_keys (key, tier, label) values ('ops.outstation', 'granted', 'ops.outstation')
on conflict (key) do nothing;

create table if not exists public.outstation_trips (
  id          uuid primary key default gen_random_uuid(),
  driver_id   uuid not null references public.team_members(id),
  companions  uuid[] not null default '{}',
  purpose     text not null check (purpose in ('meeting', 'shooting', 'event', 'other')),
  note        text check (note is null or length(note) <= 2000),
  rating      smallint check (rating is null or rating between 1 and 5),
  started_at  timestamptz not null default now(),
  ended_at    timestamptz,
  end_lat     numeric(9,6),
  end_lng     numeric(9,6),
  end_accuracy_m numeric(7,1),
  end_note    text check (end_note is null or length(end_note) <= 2000),
  km_back     numeric(8,1),
  km_total    numeric(8,1),
  state       text not null default 'open' check (state in ('open', 'closed')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists outstation_trips_driver_idx on public.outstation_trips(driver_id, started_at desc);
create index if not exists outstation_trips_started_idx on public.outstation_trips(started_at desc);
create unique index if not exists outstation_trips_one_open on public.outstation_trips(driver_id) where state = 'open';
alter table public.outstation_trips enable row level security;
revoke all on public.outstation_trips from public, anon, authenticated;

create table if not exists public.outstation_stops (
  id           uuid primary key default gen_random_uuid(),
  trip_id      uuid not null references public.outstation_trips(id) on delete cascade,
  seq          integer not null check (seq >= 1),
  client_id    uuid references public.clients(id) on delete set null,
  venue        text check (venue is null or length(venue) <= 200),
  lat          numeric(9,6) not null check (lat between -90 and 90),
  lng          numeric(9,6) not null check (lng between -180 and 180),
  accuracy_m   numeric(7,1) not null check (accuracy_m >= 0),
  read_at      timestamptz not null,
  address      text,
  zone         text check (zone is null or zone in ('johor', 'singapore', 'beyond')),
  arrived_at   timestamptz not null default now(),
  left_at      timestamptz,
  km_from_prev numeric(8,1),
  touch_id     uuid references public.client_touches(id) on delete set null,
  unique (trip_id, seq)
);
create index if not exists outstation_stops_client_idx on public.outstation_stops(client_id);
alter table public.outstation_stops enable row level security;
revoke all on public.outstation_stops from public, anon, authenticated;

create table if not exists public.outstation_photos (
  id          uuid primary key default gen_random_uuid(),
  stop_id     uuid not null references public.outstation_stops(id) on delete cascade,
  path        text not null check (path ~ '^private/outstation/[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'),
  taken_at    timestamptz not null,
  lat         numeric(9,6),
  lng         numeric(9,6),
  accuracy_m  numeric(7,1),
  created_at  timestamptz not null default now()
);
create index if not exists outstation_photos_stop_idx on public.outstation_photos(stop_id, taken_at);
alter table public.outstation_photos enable row level security;
revoke all on public.outstation_photos from public, anon, authenticated;

-- One row: when the portal last asked OpenStreetMap (one a second).
create table if not exists public.outstation_geo_turns (
  id   boolean primary key default true check (id),
  last timestamptz not null default now()
);
alter table public.outstation_geo_turns enable row level security;
revoke all on public.outstation_geo_turns from public, anon, authenticated;
insert into public.outstation_geo_turns (id) values (true) on conflict (id) do nothing;

-- The figures, seeded once (the office's pin from OpenStreetMap's street).
insert into public.app_settings (key, from_date, value)
select x.k, date '2023-08-14', x.v
  from (values ('outstation_office_lat', 1.553501::numeric), ('outstation_office_lng', 103.784857::numeric),
               ('outstation_accuracy_m', 50::numeric), ('outstation_keep_months', 24::numeric)) as x(k, v)
 where not exists (select 1 from public.app_settings s where s.key = x.k);

/* The trip as the page reads it: its stops in order, each with its photos,
   and the names the page draws. */
create or replace function public.outstation_trip_json(p_trip uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', t.id, 'driver_id', t.driver_id,
    'driver', (select m.name from public.team_members m where m.id = t.driver_id),
    'driver_code', (select m.staff_code from public.team_members m where m.id = t.driver_id),
    'companions', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'code', m.staff_code) order by m.name)
                              from public.team_members m where m.id = any(t.companions)), '[]'::jsonb),
    'purpose', t.purpose, 'note', t.note, 'rating', t.rating, 'state', t.state,
    'started_at', t.started_at, 'ended_at', t.ended_at, 'end_note', t.end_note,
    'end', case when t.end_lat is null then null else jsonb_build_object('lat', t.end_lat, 'lng', t.end_lng, 'accuracy_m', t.end_accuracy_m) end,
    'km_back', t.km_back, 'km_total', t.km_total,
    'stops', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'seq', s.seq, 'client_id', s.client_id,
        'client', (select c.name from public.clients c where c.id = s.client_id),
        'client_code', (select c.client_code from public.clients c where c.id = s.client_id),
        'venue', s.venue, 'lat', s.lat, 'lng', s.lng, 'accuracy_m', s.accuracy_m, 'read_at', s.read_at,
        'address', s.address, 'zone', s.zone, 'arrived_at', s.arrived_at, 'left_at', s.left_at,
        'km_from_prev', s.km_from_prev, 'filed', s.touch_id is not null,
        'photos', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'taken_at', p.taken_at,
            'lat', p.lat, 'lng', p.lng, 'accuracy_m', p.accuracy_m) order by p.taken_at)
          from public.outstation_photos p where p.stop_id = s.id), '[]'::jsonb)) order by s.seq)
      from public.outstation_stops s where s.trip_id = t.id), '[]'::jsonb))
  from public.outstation_trips t where t.id = p_trip
$$;
revoke all on function public.outstation_trip_json(uuid) from public, anon, authenticated;

/* The caller's own open trip, driven by them; null else. */
create or replace function public.outstation_own_trip(p_trip uuid)
returns public.outstation_trips
language sql stable security definer set search_path = public as $$
  select t.* from public.outstation_trips t
   where t.id = p_trip and t.driver_id = (public.ops_me()).id
$$;
revoke all on function public.outstation_own_trip(uuid) from public, anon, authenticated;

/* A reading the page sends, held to the limit in force today. */
create or replace function public.outstation_reading_error(p_lat numeric, p_lng numeric, p_accuracy numeric, p_read_at timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_limit numeric := coalesce(public.app_setting('outstation_accuracy_m', (now() at time zone 'Asia/Kuala_Lumpur')::date), 50);
begin
  if p_lat is null or p_lng is null or p_accuracy is null or p_read_at is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 or p_accuracy < 0
     or p_read_at > now() + interval '2 minutes' or p_read_at < now() - interval '10 minutes' then
    return jsonb_build_object('error', 'bad-location');
  end if;
  if p_accuracy > v_limit then return jsonb_build_object('error', 'vague', 'limit', v_limit, 'accuracy', round(p_accuracy)); end if;
  return null;
end $$;
revoke all on function public.outstation_reading_error(numeric, numeric, numeric, timestamptz) from public, anon, authenticated;

/* A client stop once left files a visit on Calls and visits. One the
   client scope refuses is left unfiled; the trip never fails for it. */
create or replace function public.outstation_file_visit(p_stop uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_s public.outstation_stops; v_t public.outstation_trips; v_driver text; v_with text; v_touch uuid;
begin
  select * into v_s from public.outstation_stops where id = p_stop;
  if v_s.id is null or v_s.client_id is null or v_s.touch_id is not null or v_s.left_at is null then return; end if;
  select * into v_t from public.outstation_trips where id = v_s.trip_id;
  select m.name into v_driver from public.team_members m where m.id = v_t.driver_id;
  select string_agg(m.name, ', ' order by m.name) into v_with from public.team_members m where m.id = any(v_t.companions);
  begin
    insert into public.client_touches (client_id, kind, happened_at, by_whom, summary)
    values (v_s.client_id, 'visit', (v_s.arrived_at at time zone 'Asia/Kuala_Lumpur')::date, v_driver,
            'Outstation visit: ' || initcap(v_t.purpose) || ', '
            || lower(to_char(v_s.arrived_at at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')) || ' to '
            || lower(to_char(v_s.left_at at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam'))
            || coalesce(', with ' || v_with, '') || '.'
            || coalesce(' ' || nullif(btrim(v_t.note), ''), ''))
    returning id into v_touch;
    update public.outstation_stops set touch_id = v_touch where id = p_stop;
  exception when others then
    return;
  end;
end $$;
revoke all on function public.outstation_file_visit(uuid) from public, anon, authenticated;

create or replace function public.outstation_check_in(
  p_client uuid, p_venue text, p_purpose text, p_note text, p_companions uuid[],
  p_lat numeric, p_lng numeric, p_accuracy numeric, p_read_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.team_members; v_err jsonb; v_trip uuid; v_with uuid[];
begin
  v_me := public.ops_me();
  if v_me.id is null or not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if exists (select 1 from public.outstation_trips t where t.driver_id = v_me.id and t.state = 'open') then
    return jsonb_build_object('error', 'open-trip');
  end if;
  if p_purpose is null or p_purpose not in ('meeting', 'shooting', 'event', 'other') then return jsonb_build_object('error', 'bad-purpose'); end if;
  if length(coalesce(p_note, '')) > 2000 or length(coalesce(p_venue, '')) > 200 then return jsonb_build_object('error', 'too-long'); end if;
  if p_client is null and nullif(btrim(coalesce(p_venue, '')), '') is null then return jsonb_build_object('error', 'no-place'); end if;
  if p_client is not null and (not exists (select 1 from public.clients c where c.id = p_client)
                               or not public.client_scope_ok('client', p_client, 'view')) then
    return jsonb_build_object('error', 'bad-client');
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_with from unnest(coalesce(p_companions, '{}'::uuid[])) x;
  if array_length(v_with, 1) > 10 or v_me.id = any(v_with)
     or exists (select 1 from unnest(v_with) x where not exists (
          select 1 from public.team_members m where m.id = x and m.active and m.removed_at is null and not coalesce(m.system, false))) then
    return jsonb_build_object('error', 'bad-companion');
  end if;
  v_err := public.outstation_reading_error(p_lat, p_lng, p_accuracy, p_read_at);
  if v_err is not null then return v_err; end if;
  insert into public.outstation_trips (driver_id, companions, purpose, note)
  values (v_me.id, v_with, p_purpose, nullif(btrim(coalesce(p_note, '')), ''))
  returning id into v_trip;
  insert into public.outstation_stops (trip_id, seq, client_id, venue, lat, lng, accuracy_m, read_at)
  values (v_trip, 1, p_client, case when p_client is null then btrim(p_venue) end, p_lat, p_lng, p_accuracy, p_read_at);
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_trip));
end $$;
revoke all on function public.outstation_check_in(uuid, text, text, text, uuid[], numeric, numeric, numeric, timestamptz) from public, anon;
grant execute on function public.outstation_check_in(uuid, text, text, text, uuid[], numeric, numeric, numeric, timestamptz) to authenticated;

create or replace function public.outstation_stop_add(
  p_trip uuid, p_client uuid, p_venue text, p_lat numeric, p_lng numeric, p_accuracy numeric, p_read_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_t public.outstation_trips; v_last public.outstation_stops; v_err jsonb;
begin
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_t := public.outstation_own_trip(p_trip);
  if v_t.id is null then return jsonb_build_object('error', 'no-trip'); end if;
  if v_t.state <> 'open' then return jsonb_build_object('error', 'closed'); end if;
  if length(coalesce(p_venue, '')) > 200 then return jsonb_build_object('error', 'too-long'); end if;
  if p_client is null and nullif(btrim(coalesce(p_venue, '')), '') is null then return jsonb_build_object('error', 'no-place'); end if;
  if p_client is not null and (not exists (select 1 from public.clients c where c.id = p_client)
                               or not public.client_scope_ok('client', p_client, 'view')) then
    return jsonb_build_object('error', 'bad-client');
  end if;
  select * into v_last from public.outstation_stops s where s.trip_id = v_t.id order by s.seq desc limit 1 for update;
  if not exists (select 1 from public.outstation_photos p where p.stop_id = v_last.id) then
    return jsonb_build_object('error', 'no-photo');
  end if;
  if v_last.seq >= 20 then return jsonb_build_object('error', 'too-many'); end if;
  v_err := public.outstation_reading_error(p_lat, p_lng, p_accuracy, p_read_at);
  if v_err is not null then return v_err; end if;
  update public.outstation_stops set left_at = now() where id = v_last.id;
  perform public.outstation_file_visit(v_last.id);
  insert into public.outstation_stops (trip_id, seq, client_id, venue, lat, lng, accuracy_m, read_at)
  values (v_t.id, v_last.seq + 1, p_client, case when p_client is null then btrim(p_venue) end, p_lat, p_lng, p_accuracy, p_read_at);
  update public.outstation_trips set updated_at = now() where id = v_t.id;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_stop_add(uuid, uuid, text, numeric, numeric, numeric, timestamptz) from public, anon;
grant execute on function public.outstation_stop_add(uuid, uuid, text, numeric, numeric, numeric, timestamptz) to authenticated;

/* What sign-upload asks as the caller: the driver's open trip, else null. */
create or replace function public.outstation_photo_may(p_trip uuid)
returns uuid
language sql stable security definer set search_path = public as $$
  select t.id from public.outstation_trips t
   where t.id = p_trip and t.state = 'open' and t.driver_id = (public.ops_me()).id
     and public.allowed('ops', 'work')
$$;
revoke all on function public.outstation_photo_may(uuid) from public, anon;
grant execute on function public.outstation_photo_may(uuid) to authenticated;

create or replace function public.outstation_photo_add(
  p_stop uuid, p_path text, p_taken_at timestamptz, p_lat numeric, p_lng numeric, p_accuracy numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s public.outstation_stops; v_t public.outstation_trips;
begin
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_s from public.outstation_stops where id = p_stop;
  if v_s.id is null then return jsonb_build_object('error', 'no-trip'); end if;
  v_t := public.outstation_own_trip(v_s.trip_id);
  if v_t.id is null then return jsonb_build_object('error', 'no-trip'); end if;
  if v_t.state <> 'open' or v_s.left_at is not null then return jsonb_build_object('error', 'closed'); end if;
  if p_path is null or p_path !~ ('^private/outstation/' || v_t.id || '/[0-9a-f-]{36}\.jpg$') then
    return jsonb_build_object('error', 'bad-key');
  end if;
  if p_taken_at is null or p_taken_at > now() + interval '2 minutes' or p_taken_at < v_t.started_at - interval '10 minutes' then
    return jsonb_build_object('error', 'bad-location');
  end if;
  if (p_lat is not null and p_lat not between -90 and 90) or (p_lng is not null and p_lng not between -180 and 180)
     or (p_accuracy is not null and p_accuracy < 0) then
    return jsonb_build_object('error', 'bad-location');
  end if;
  if (select count(*) from public.outstation_photos p where p.stop_id = v_s.id) >= 10 then
    return jsonb_build_object('error', 'too-many');
  end if;
  insert into public.outstation_photos (stop_id, path, taken_at, lat, lng, accuracy_m)
  values (v_s.id, p_path, p_taken_at, p_lat, p_lng, p_accuracy);
  update public.outstation_trips set updated_at = now() where id = v_t.id;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_photo_add(uuid, text, timestamptz, numeric, numeric, numeric) from public, anon;
grant execute on function public.outstation_photo_add(uuid, text, timestamptz, numeric, numeric, numeric) to authenticated;

create or replace function public.outstation_check_out(
  p_trip uuid, p_lat numeric, p_lng numeric, p_accuracy numeric, p_read_at timestamptz, p_note text, p_rating integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_t public.outstation_trips; v_last public.outstation_stops; v_err jsonb;
begin
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_t := public.outstation_own_trip(p_trip);
  if v_t.id is null then return jsonb_build_object('error', 'no-trip'); end if;
  if v_t.state <> 'open' then return jsonb_build_object('error', 'closed'); end if;
  if length(coalesce(p_note, '')) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  if p_rating is not null and p_rating not between 1 and 5 then return jsonb_build_object('error', 'bad-rating'); end if;
  select * into v_last from public.outstation_stops s where s.trip_id = v_t.id order by s.seq desc limit 1 for update;
  if not exists (select 1 from public.outstation_photos p where p.stop_id = v_last.id) then
    return jsonb_build_object('error', 'no-photo');
  end if;
  v_err := public.outstation_reading_error(p_lat, p_lng, p_accuracy, p_read_at);
  if v_err is not null then return v_err; end if;
  update public.outstation_stops set left_at = now() where id = v_last.id;
  perform public.outstation_file_visit(v_last.id);
  update public.outstation_trips
     set state = 'closed', ended_at = now(), end_lat = p_lat, end_lng = p_lng, end_accuracy_m = p_accuracy,
         end_note = nullif(btrim(coalesce(p_note, '')), ''), rating = p_rating, updated_at = now()
   where id = v_t.id;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_check_out(uuid, numeric, numeric, numeric, timestamptz, text, integer) from public, anon;
grant execute on function public.outstation_check_out(uuid, numeric, numeric, numeric, timestamptz, text, integer) to authenticated;

/* The trips the caller drove or joined that started in the period
   (Malaysian days), every trip with `p_all` at `ops.outstation`; the
   caller's own open trip always, whenever it started. */
create or replace function public.outstation_trips(p_from date, p_to date, p_all boolean default false)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me public.team_members;
begin
  v_me := public.ops_me();
  if v_me.id is null or not public.allowed('ops', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_all, false) and not public.ops_granted('ops.outstation', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then return jsonb_build_object('error', 'bad-period'); end if;
  return jsonb_build_object('ok', true, 'me', v_me.id, 'trips', coalesce((
    select jsonb_agg(public.outstation_trip_json(t.id) order by t.started_at desc)
      from public.outstation_trips t
     where ((t.started_at at time zone 'Asia/Kuala_Lumpur')::date between p_from and p_to
            or (t.state = 'open' and t.driver_id = v_me.id))
       and (coalesce(p_all, false) or t.driver_id = v_me.id or v_me.id = any(t.companions))), '[]'::jsonb));
end $$;
revoke all on function public.outstation_trips(date, date, boolean) from public, anon;
grant execute on function public.outstation_trips(date, date, boolean) to authenticated;

/* What sign-download asks as the caller to read one photo back: a reader
   of its trip (who drove it, who joined it, or `ops.outstation`). */
create or replace function public.outstation_photo_key(p_photo uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me public.team_members; v_path text; v_trip uuid; v_t public.outstation_trips;
begin
  v_me := public.ops_me();
  if v_me.id is null or not public.allowed('ops', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select p.path, s.trip_id into v_path, v_trip
    from public.outstation_photos p join public.outstation_stops s on s.id = p.stop_id where p.id = p_photo;
  select * into v_t from public.outstation_trips t where t.id = v_trip;
  if v_path is null then return jsonb_build_object('error', 'not-kept'); end if;
  if not (v_t.driver_id = v_me.id or v_me.id = any(v_t.companions) or public.ops_granted('ops.outstation', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('key', v_path, 'trip', v_t.id);
end $$;
revoke all on function public.outstation_photo_key(uuid) from public, anon;
grant execute on function public.outstation_photo_key(uuid) to authenticated;

/* What outstation-geo asks as the caller before it looks a stop or a trip
   up: the driver's own. Answers the trip. */
create or replace function public.outstation_geo_may(p_stop uuid, p_trip uuid)
returns uuid
language sql stable security definer set search_path = public as $$
  select t.id from public.outstation_trips t
   where t.driver_id = (public.ops_me()).id and public.allowed('ops', 'work')
     and t.id = coalesce(p_trip, (select s.trip_id from public.outstation_stops s where s.id = p_stop))
$$;
revoke all on function public.outstation_geo_may(uuid, uuid) from public, anon;
grant execute on function public.outstation_geo_may(uuid, uuid) to authenticated;

/* One OpenStreetMap lookup a second across the portal: answers how many
   milliseconds the caller waits before its own. */
create or replace function public.outstation_geo_turn()
returns integer
language plpgsql security definer set search_path = public as $$
declare v_at timestamptz; v_next timestamptz;
begin
  select g.last into v_at from public.outstation_geo_turns g where g.id for update;
  v_next := greatest(clock_timestamp(), coalesce(v_at, clock_timestamp()) + interval '1100 milliseconds');
  update public.outstation_geo_turns set last = v_next where id;
  return greatest(0, ceil(extract(epoch from (v_next - clock_timestamp())) * 1000))::integer;
end $$;
revoke all on function public.outstation_geo_turn() from public, anon, authenticated;
grant execute on function public.outstation_geo_turn() to service_role;

create or replace function public.outstation_stop_place(p_stop uuid, p_address text, p_zone text)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_zone is not null and p_zone not in ('johor', 'singapore', 'beyond') then return jsonb_build_object('error', 'bad-zone'); end if;
  update public.outstation_stops set address = left(nullif(btrim(coalesce(p_address, '')), ''), 300), zone = p_zone where id = p_stop;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.outstation_stop_place(uuid, text, text) from public, anon, authenticated;
grant execute on function public.outstation_stop_place(uuid, text, text) to service_role;

/* The road km of each leg in order (office to the first stop, each stop to
   the next) and, once the trip is closed, back to the office. */
create or replace function public.outstation_route_set(p_trip uuid, p_legs numeric[], p_back numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  select count(*) into v_n from public.outstation_stops s where s.trip_id = p_trip;
  if v_n = 0 then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(array_length(p_legs, 1), 0) <> v_n
     or exists (select 1 from unnest(p_legs) x where x is null or x < 0 or x > 5000)
     or (p_back is not null and (p_back < 0 or p_back > 5000)) then
    return jsonb_build_object('error', 'bad-value');
  end if;
  update public.outstation_stops s set km_from_prev = round(p_legs[s.seq], 1) where s.trip_id = p_trip;
  update public.outstation_trips t
     set km_back = case when t.state = 'closed' then round(p_back, 1) end,
         km_total = case when t.state = 'closed' and p_back is not null
                         then round((select sum(round(x, 1)) from unnest(p_legs) x) + round(p_back, 1), 1) end,
         updated_at = now()
   where t.id = p_trip;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.outstation_route_set(uuid, numeric[], numeric) from public, anon, authenticated;
grant execute on function public.outstation_route_set(uuid, numeric[], numeric) to service_role;

/* The trips ended longer ago than the months kept go with their stops and
   photo rows; the visits they filed stay with the client. */
create or replace function public.outstation_prune()
returns integer
language plpgsql security definer set search_path = public as $$
declare v_months integer := coalesce(public.app_setting('outstation_keep_months', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24)::integer;
  v_n integer;
begin
  delete from public.outstation_trips t
   where t.state = 'closed' and t.ended_at < now() - make_interval(months => v_months);
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.outstation_prune() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('outstation-prune') where exists (select 1 from cron.job where jobname = 'outstation-prune');
  perform cron.schedule('outstation-prune', '47 19 * * *', 'select public.outstation_prune()');
exception when undefined_table or invalid_schema_name or undefined_function then null;
end $$;

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text; v_pre text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days', 'wa_repeat_hours',
    'bench_cpr_low', 'bench_cpr_mid', 'bench_cpr_high', 'bench_cpr_top', 'bench_msg_min', 'bench_msg_target', 'bench_msg_max',
    'bench_form_min', 'bench_form_target', 'bench_form_max', 'bench_cpm_min', 'bench_cpm_max', 'bench_cpl_rise',
    'bench_reels_share', 'bench_ad_spend_pct', 'bench_adset_daily', 'vic_lead_followup_hours', 'vic_proposal_followup_days', 'fx_sgd',
    'health_keep_months', 'health_leaver_months', 'abroad_days', 'abroad_remind_hours', 'analytics_from',
    'analytics_change_pct', 'analytics_churn_pct', 'quote_reply_days', 'quote_wa_day', 'client_email_on', 'ai_price_image', 'report_post_links',
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'plan_db_mb', 'plan_db_alert_pct',
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'hiring_decision_days', 'verify_code_from',
    'work_start', 'work_end', 'work_lunch_min', 'work_weekend',
    'health_cap_default', 'health_near_pct', 'health_task_hours', 'health_remind_days', 'health_alert',
    'outstation_office_lat', 'outstation_office_lng', 'outstation_accuracy_m', 'outstation_keep_months'];
  v_moved text[] := '{}';
  v_drop boolean; v_fw text; v_fv text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, case when v_k = 'fx_sgd' then 4 when v_k in ('outstation_office_lat', 'outstation_office_lng') then 6 else 2 end) <> v_v
       or (v_k = 'fx_sgd' and (v_v < 0.5 or v_v > 10))
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'task_past_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_invite_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_link_days' and (v_v < 7 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_pool_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_keep_months' and (v_v < 1 or v_v > 36 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_mb' and (v_v < 100 or v_v > 1000000 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_alert_pct' and (v_v < 10 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_late_days' and (v_v < 0 or v_v > 30 or round(v_v, 1) <> v_v))
       or (v_k = 'stage_back_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_reply_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'session_idle_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_decision_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'quote_reply_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k in ('creator_pay_days_myr', 'creator_pay_days_other') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k = 'quote_wa_day' and (v_v < 0 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'health_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'health_leaver_months' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'health_cap_default' and (v_v < 1 or v_v > 80 or v_v <> trunc(v_v)))
       or (v_k = 'health_near_pct' and (v_v < 50 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'health_task_hours' and (v_v < 0.5 or v_v > 40 or v_v * 2 <> trunc(v_v * 2)))
       or (v_k = 'health_remind_days' and (v_v < 0 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_office_lat' and (v_v < -90 or v_v > 90))
       or (v_k = 'outstation_office_lng' and (v_v < -180 or v_v > 180))
       or (v_k = 'outstation_accuracy_m' and (v_v < 5 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_from' and (v_v < 202308 or v_v > 209912 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 12))
       or (v_k = 'verify_code_from' and (v_v < 20230814 or v_v > 20991231 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 31 or mod(trunc(v_v / 100), 100) not between 1 and 12))
       or (v_k in ('work_start', 'work_end') and (v_v < 0 or v_v > 2345 or v_v <> trunc(v_v) or mod(v_v, 100) not in (0, 15, 30, 45)))
       or (v_k = 'work_lunch_min' and (v_v < 0 or v_v > 180 or v_v <> trunc(v_v) or mod(v_v, 15) <> 0))
       or (v_k = 'work_weekend' and v_v not in (0, 1, 2))
       or (v_k = 'analytics_change_pct' and (v_v < 1 or v_v > 50 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_churn_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k in ('bench_reels_share') and (v_v < 0 or v_v > 100))
       or (v_k = 'bench_ad_spend_pct' and (v_v < 1 or v_v > 100))
       or (v_k = 'bench_cpl_rise' and (v_v < -100 or v_v > 100))
       or (v_k like 'bench_%' and v_k not in ('bench_reels_share', 'bench_ad_spend_pct', 'bench_cpl_rise') and (v_v < 0 or v_v > 10000)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  /* A working day ends after it starts, as the two stand on the From day. */
  if (p_values ? 'work_start' or p_values ? 'work_end')
     and coalesce((p_values ->> 'work_end')::numeric, public.app_setting('work_end', p_from))
      <= coalesce((p_values ->> 'work_start')::numeric, public.app_setting('work_start', p_from)) then
    return jsonb_build_object('error', 'bad-hours');
  end if;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      /* A planned change saved back to the value in force the day before is
         withdrawn: its row goes, rather than a second row restating it. */
      v_drop := p_from > v_today
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date = p_from)
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date < p_from)
        and public.app_setting(v_k, p_from - 1) = v_v;
      if v_drop then
        delete from public.app_settings s where s.key = v_k and s.from_date = p_from;
      else
        insert into public.app_settings (key, from_date, value, set_by, set_at)
        values (v_k, p_from, v_v, v_me.id, now())
        on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      end if;
      v_name := case v_k when 'lead_followup_hours' then 'Lead follow-up limit' when 'proposal_followup_days' then 'Proposal follow-up limit'
        when 'vic_lead_followup_hours' then 'VIC lead follow-up limit' when 'vic_proposal_followup_days' then 'VIC proposal follow-up limit'
        when 'sst_pct' then 'SST' when 'term_1_3' then 'Under 3 months' when 'term_4_5' then '3-month commitment'
        when 'term_6_11' then '6-month commitment' when 'term_12_23' then '12-month commitment' when 'term_18_23' then '18-month commitment' when 'term_24' then '24-month commitment'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input price per million tokens'
        when 'ai_price_out' then 'AI output price per million tokens' when 'ai_price_search' then 'AI web search price per thousand searches' when 'ai_price_image' then 'AI price per scene picture' when 'meta_checks' then 'Meta checks' when 'client_email_on' then 'Send by email' when 'report_post_links' then 'Posts linked to tasks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
        when 'plan_db_mb' then 'Database plan' when 'plan_db_alert_pct' then 'Database alert'
        when 'timely_pct' then 'On time or early target' when 'timely_late_days' then 'Average lateness target'
        when 'stage_back_days' then 'Past dates on stage moves'
        when 'hiring_reply_days' then 'Interview reply time'
        when 'session_idle_days' then 'Signed-in devices'
        when 'hiring_decision_days' then 'Decision time'
        when 'creator_pay_days_myr' then 'Creator payment in MYR' when 'creator_pay_days_other' then 'Creator payment in other currencies'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'quote_wa_day' then 'Website quotations on WhatsApp'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Yearly rise in cost per lead' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend share of the budget' when 'bench_adset_daily' then 'Minimum daily budget per ad set'
        when 'fx_sgd' then 'Singapore dollar rate'
        when 'health_keep_months' then 'Health check-ins kept' when 'health_leaver_months' then 'Leavers'' health data kept'
        when 'health_cap_default' then 'Health default weekly capacity' when 'health_near_pct' then 'Health near capacity'
        when 'health_task_hours' then 'Health default hours per task' when 'health_remind_days' then 'Health check-in reminder'
        when 'health_alert' then 'Health heavy workload notice'
        when 'outstation_office_lat' then 'Office pin latitude' when 'outstation_office_lng' then 'Office pin longitude'
        when 'outstation_accuracy_m' then 'Location accuracy limit' when 'outstation_keep_months' then 'Outstation trips kept'
        when 'abroad_days' then 'Overseas approval' when 'abroad_remind_hours' then 'Overseas reminder'
        when 'analytics_from' then 'Analytics counts from'
        when 'verify_code_from' then 'Document IDs printed from'
        when 'work_start' then 'Working hours start' when 'work_end' then 'Working hours end'
        when 'work_lunch_min' then 'Lunch' when 'work_weekend' then 'Saturday and Sunday'
        when 'analytics_change_pct' then 'Analytics change threshold' when 'analytics_churn_pct' then 'Analytics quarterly churn alert'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' per S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours', 'abroad_remind_hours', 'health_cap_default', 'health_task_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'health_remind_days') then ' days'
        when v_k in ('quote_reply_days', 'creator_pay_days_myr', 'creator_pay_days_other', 'hiring_decision_days') then ' working days'
        when v_k = 'quote_wa_day' then ' per day'
        when v_k = 'plan_db_mb' then ' MB'
        when v_k = 'work_lunch_min' then ' minutes'
        when v_k = 'outstation_accuracy_m' then ' m'
        when v_k in ('outstation_office_lat', 'outstation_office_lng') then ''
        when v_k in ('health_keep_months', 'hiring_pool_months', 'hiring_keep_months', 'health_leaver_months', 'outstation_keep_months') then ' months'
        when v_pre <> '' then '' else '%' end;
      v_fw := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then case when v_was = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then coalesce(public.work_hours_word(v_k, v_was), 'not set')
              when v_k = 'analytics_from' then coalesce(substr(public.register_day(to_date(v_was::bigint::text, 'YYYYMM')), 3), 'not set')
              when v_k = 'verify_code_from' then coalesce(public.register_day(to_date(v_was::bigint::text, 'YYYYMMDD')), 'not set') else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit, 'not set') end;
      v_fv := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then case when v_v = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then public.work_hours_word(v_k, v_v)
              when v_k = 'analytics_from' then substr(public.register_day(to_date(v_v::bigint::text, 'YYYYMM')), 3)
              when v_k = 'verify_code_from' then public.register_day(to_date(v_v::bigint::text, 'YYYYMMDD')) else v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              case when v_drop then v_name || ': planned change withdrawn · ' || v_fw || ' from ' || public.register_day(p_from) ||
                ', stays ' || v_fv else
              case when v_k in ('analytics_from', 'verify_code_from') or (v_k like 'work\_%' and v_k <> 'work_lunch_min') then v_name || ': ' || v_fw || ' → ' || v_fv || ' · from ' || public.register_day(p_from) else
              v_name || ': ' || case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then '' else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit, 'not set') || ' → ' || v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end end end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;

-- END OF OUTSTATION RECORD --------------------------------------------------

select public.functions_tidy();
