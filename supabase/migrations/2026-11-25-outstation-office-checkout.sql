-- ===========================================================================
-- OUTSTATION CHECK-OUT AT THE OFFICE (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25: an iPhone web app cannot read the location in
-- the background, so the portal acts when it is opened. A driver who checks
-- out back at the office left the last site a drive earlier; a trip left
-- open is reminded once and closed at midnight.
--
-- WHAT IT CHANGES
--   * Two Business settings, effective from a date: `outstation_office_radius_m`
--     (100, within this of Settings' office pin is "at the office") and
--     `outstation_remind_hours` (3, after the last stop's last activity).
--   * `outstation_stops.left_how` ('site', 'office', 'auto'; null reads as
--     site) and `outstation_trips.reminded_at`.
--   * `outstation_check_out_office(...)`: Check out with a reading within the
--     accuracy limit and the office radius (`not-office` otherwise); the last
--     stop is left 'office', its end worked out once outstation-geo has the
--     drive back (`outstation_back_drive(p_trip, p_mins)`, the service
--     role's): the arrival at the office less the drive, never before the
--     stop's check-in nor its last photo. The visit filed for the client
--     reads it.
--   * `outstation_remind()`: one push a trip (`ops_notifications`, kind
--     `outstation`), once the trip has stood open the set hours after its
--     last stop's check-in or last photo; every 15 minutes.
--   * `outstation_close_open()`: at 00:00 Malaysia time a trip still open
--     closes itself at its last stop's last activity, left 'auto', filed
--     `ops.trip_closed` in the Activity record; safe to run twice.
--   * `outstation_checkout_edit(p_trip, p_note, p_rating)`: the driver adds a
--     note and a rating to a trip closed automatically.
--   * `outstation_trip_json`: each stop carries `left_how`.
--   * Part B (the SQL Editor, below this band in schema.sql): `app_settings_set`
--     takes the two settings; `activity_section` files `ops.trip_closed`
--     under My Work.
--
-- ORDER: this part, then outstation-geo (duration with the distance), then
-- the pages, then Part B in the SQL Editor. An old open tab meets nothing
-- new: its Check out is the one before; a trip it shows may close at
-- midnight and read Checked out on its next load. Before Part B, Settings
-- refuses the two new figures (their defaults stand).
--
-- ROLLBACK: unschedule `outstation-remind` and `outstation-close`; run OUTSTATION
-- PHOTOS SHOWN AND REMOVED's `outstation_trip_json` again; revoke the five
-- new functions. The columns and settings may stay.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select x.k, date '2023-08-14', x.v
  from (values ('outstation_office_radius_m', 100::numeric), ('outstation_remind_hours', 3::numeric)) as x(k, v)
 where not exists (select 1 from public.app_settings s where s.key = x.k);

alter table public.outstation_stops add column if not exists left_how text;
alter table public.outstation_trips add column if not exists reminded_at timestamptz;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'outstation_stops_left_how_check') then
    alter table public.outstation_stops add constraint outstation_stops_left_how_check
      check (left_how is null or left_how in ('site', 'office', 'auto'));
  end if;
end $$;

/* The trip as the page reads it, each stop with how it was left. */
create or replace function public.outstation_trip_json(p_trip uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', t.id, 'ref', t.ref, 'driver_id', t.driver_id,
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
        'client_logo', (select c.logo_url from public.clients c where c.id = s.client_id),
        'venue', s.venue, 'lat', s.lat, 'lng', s.lng, 'accuracy_m', s.accuracy_m, 'read_at', s.read_at,
        'address', s.address, 'zone', s.zone, 'arrived_at', s.arrived_at, 'left_at', s.left_at, 'left_how', s.left_how,
        'km_from_prev', s.km_from_prev, 'filed', s.touch_id is not null, 'note', s.note,
        'photos', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'taken_at', p.taken_at,
            'lat', p.lat, 'lng', p.lng, 'accuracy_m', p.accuracy_m, 'removed_at', p.removed_at,
            'removed_by', case when p.removed_at is null then null
                               else coalesce((select m.name from public.team_members m where m.id = p.removed_by), 'Former colleague') end) order by p.taken_at)
          from public.outstation_photos p
         where p.stop_id = s.id and (p.removed_at is null or public.ops_granted('ops.outstation', 'view'))), '[]'::jsonb)) order by s.seq)
      from public.outstation_stops s where s.trip_id = t.id), '[]'::jsonb))
  from public.outstation_trips t where t.id = p_trip
$$;
revoke all on function public.outstation_trip_json(uuid) from public, anon, authenticated;

/* The great-circle distance in metres between two points. */
create or replace function public.outstation_metres(p_lat1 numeric, p_lng1 numeric, p_lat2 numeric, p_lng2 numeric)
returns numeric
language sql immutable set search_path = public as $$
  select (2 * 6371000 * asin(sqrt(
    power(sin(radians((p_lat2 - p_lat1)::float8) / 2), 2) +
    cos(radians(p_lat1::float8)) * cos(radians(p_lat2::float8)) * power(sin(radians((p_lng2 - p_lng1)::float8) / 2), 2))))::numeric
$$;
revoke all on function public.outstation_metres(numeric, numeric, numeric, numeric) from public, anon, authenticated;

/* The last stop's last activity: its check-in, or its last photo kept. */
create or replace function public.outstation_last_activity(p_stop uuid)
returns timestamptz
language sql stable security definer set search_path = public as $$
  select greatest(s.arrived_at, coalesce((select max(p.taken_at) from public.outstation_photos p
                                           where p.stop_id = s.id and p.removed_at is null), s.arrived_at))
    from public.outstation_stops s where s.id = p_stop
$$;
revoke all on function public.outstation_last_activity(uuid) from public, anon, authenticated;

/* Check out at the office: a reading within the accuracy limit and within
   the office radius of Settings' pin. The last stop is left 'office'; its
   end is worked out once the drive back is known (outstation_back_drive). */
create or replace function public.outstation_check_out_office(
  p_trip uuid, p_lat numeric, p_lng numeric, p_accuracy numeric, p_read_at timestamptz, p_note text, p_rating integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_t public.outstation_trips; v_last public.outstation_stops; v_err jsonb; v_day date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_lat numeric := public.app_setting('outstation_office_lat', v_day); v_lng numeric := public.app_setting('outstation_office_lng', v_day);
  v_radius numeric := coalesce(public.app_setting('outstation_office_radius_m', v_day), 100);
begin
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_t := public.outstation_own_trip(p_trip);
  if v_t.id is null then return jsonb_build_object('error', 'no-trip'); end if;
  if v_t.state <> 'open' then return jsonb_build_object('error', 'closed'); end if;
  if length(coalesce(p_note, '')) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  if p_rating is not null and p_rating not between 1 and 5 then return jsonb_build_object('error', 'bad-rating'); end if;
  v_err := public.outstation_reading_error(p_lat, p_lng, p_accuracy, p_read_at);
  if v_err is not null then return v_err; end if;
  if v_lat is null or v_lng is null or public.outstation_metres(p_lat, p_lng, v_lat, v_lng) > v_radius then
    return jsonb_build_object('error', 'not-office', 'radius', v_radius);
  end if;
  select * into v_last from public.outstation_stops s where s.trip_id = v_t.id order by s.seq desc limit 1 for update;
  if not exists (select 1 from public.outstation_photos p where p.stop_id = v_last.id and p.removed_at is null) then
    return jsonb_build_object('error', 'no-photo');
  end if;
  update public.outstation_stops set left_at = now(), left_how = 'office' where id = v_last.id;
  perform public.outstation_file_visit(v_last.id);
  update public.outstation_trips
     set state = 'closed', ended_at = now(), end_lat = p_lat, end_lng = p_lng, end_accuracy_m = p_accuracy,
         end_note = nullif(btrim(coalesce(p_note, '')), ''), rating = p_rating, updated_at = now()
   where id = v_t.id;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_check_out_office(uuid, numeric, numeric, numeric, timestamptz, text, integer) from public, anon;
grant execute on function public.outstation_check_out_office(uuid, numeric, numeric, numeric, timestamptz, text, integer) to authenticated;

/* The drive back, as outstation-geo measured it: a trip checked out at the
   office left its last stop the drive's minutes before it arrived, never
   before the stop's own check-in nor its last photo. Worked out from the
   arrival each time, so asked twice it answers the same. */
create or replace function public.outstation_back_drive(p_trip uuid, p_mins numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_t public.outstation_trips; v_last public.outstation_stops; v_end timestamptz;
begin
  select * into v_t from public.outstation_trips where id = p_trip;
  if v_t.id is null or v_t.state <> 'closed' or v_t.ended_at is null then return jsonb_build_object('error', 'not-closed'); end if;
  if p_mins is null or p_mins < 0 or p_mins > 1440 then return jsonb_build_object('error', 'bad-value'); end if;
  select * into v_last from public.outstation_stops s where s.trip_id = v_t.id order by s.seq desc limit 1 for update;
  if v_last.left_how is distinct from 'office' then return jsonb_build_object('ok', true, 'left_at', v_last.left_at); end if;
  v_end := least(v_t.ended_at, greatest(v_t.ended_at - make_interval(secs => round(p_mins * 60)::int),
                                        public.outstation_last_activity(v_last.id)));
  update public.outstation_stops set left_at = v_end where id = v_last.id;
  perform public.outstation_file_visit(v_last.id);
  return jsonb_build_object('ok', true, 'left_at', v_end);
end $$;
revoke all on function public.outstation_back_drive(uuid, numeric) from public, anon, authenticated;
grant execute on function public.outstation_back_drive(uuid, numeric) to service_role;

/* One push a trip left open: the set hours after its last stop's last
   activity, once (`reminded_at`), opening the trip. */
create or replace function public.outstation_remind()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
  v_hours numeric := coalesce(public.app_setting('outstation_remind_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 3);
begin
  for r in
    select t.id, t.ref, t.driver_id,
           (select public.outstation_last_activity(s.id) from public.outstation_stops s where s.trip_id = t.id order by s.seq desc limit 1) as last_at
      from public.outstation_trips t
     where t.state = 'open' and t.reminded_at is null
     for update of t skip locked
  loop
    continue when r.last_at is null or r.last_at + make_interval(mins => round(v_hours * 60)::int) > now();
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    values (r.driver_id, 'outstation', 'Your trip is still open. Check out?', coalesce(r.ref, 'Outstation trip'),
            'https://digital.adspace.me/admin/?s=work&view=outstation', 'outstation.open.' || r.id::text)
    on conflict (dedupe_key) do nothing;
    update public.outstation_trips set reminded_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.outstation_remind() from public, anon, authenticated;

/* At 00:00 Malaysia time a trip still open from an earlier day closes at
   its last stop's last activity, left 'auto', filed in the Activity record.
   A second run finds nothing open. */
create or replace function public.outstation_close_open()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0; v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date; v_at timestamptz;
begin
  for r in
    select t.id, t.ref, t.driver_id,
           (select s.id from public.outstation_stops s where s.trip_id = t.id order by s.seq desc limit 1) as last_stop
      from public.outstation_trips t
     where t.state = 'open' and (t.started_at at time zone 'Asia/Kuala_Lumpur')::date < v_today
     for update of t skip locked
  loop
    v_at := coalesce(public.outstation_last_activity(r.last_stop), now());
    if r.last_stop is not null then
      update public.outstation_stops set left_at = v_at, left_how = 'auto' where id = r.last_stop;
      perform public.outstation_file_visit(r.last_stop);
    end if;
    update public.outstation_trips set state = 'closed', ended_at = v_at, updated_at = now() where id = r.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Portal', 'ops.trip_closed', r.ref,
            'Outstation trip · ' || coalesce((select m.name from public.team_members m where m.id = r.driver_id), 'Former colleague') ||
            ' · ended at midnight, at its last activity');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.outstation_close_open() from public, anon, authenticated;

/* A trip closed automatically takes its note and rating afterwards, from
   its driver. */
create or replace function public.outstation_checkout_edit(p_trip uuid, p_note text, p_rating integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_t public.outstation_trips;
begin
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_t := public.outstation_own_trip(p_trip);
  if v_t.id is null then return jsonb_build_object('error', 'no-trip'); end if;
  if v_t.state <> 'closed' or not exists (select 1 from public.outstation_stops s where s.trip_id = v_t.id and s.left_how = 'auto') then
    return jsonb_build_object('error', 'not-auto');
  end if;
  if length(coalesce(p_note, '')) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  if p_rating is not null and p_rating not between 1 and 5 then return jsonb_build_object('error', 'bad-rating'); end if;
  update public.outstation_trips set end_note = nullif(btrim(coalesce(p_note, '')), ''), rating = p_rating, updated_at = now()
   where id = v_t.id;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_checkout_edit(uuid, text, integer) from public, anon;
grant execute on function public.outstation_checkout_edit(uuid, text, integer) to authenticated;

do $$ begin
  perform cron.unschedule('outstation-remind') where exists (select 1 from cron.job where jobname = 'outstation-remind');
  perform cron.schedule('outstation-remind', '*/15 * * * *', 'select public.outstation_remind()');
  perform cron.unschedule('outstation-close') where exists (select 1 from cron.job where jobname = 'outstation-close');
  perform cron.schedule('outstation-close', '0 16 * * *', 'select public.outstation_close_open()');
exception when undefined_table or invalid_schema_name or undefined_function then null;
end $$;

-- END OF OUTSTATION CHECK-OUT AT THE OFFICE ----------------------------------

select public.functions_tidy();
