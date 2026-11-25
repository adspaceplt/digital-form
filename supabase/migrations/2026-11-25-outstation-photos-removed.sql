-- ===========================================================================
-- OUTSTATION PHOTOS SHOWN AND REMOVED (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25, from an iPhone screenshot of a trip in
-- progress: a stop read only "1 photo". The photos are now drawn under each
-- stop, read through sign-download in one request a trip, and a photo
-- taken by mistake can be removed ("Anything a person can upload, a person
-- can remove"), softly: the file stays in S3 and the row stays, marked.
--
-- WHAT IT CHANGES
--   * `outstation_photos.removed_at` and `removed_by`: a soft remove.
--   * `outstation_photo_remove(p_photo)`: the driver's own photo (only the
--     driver adds photos), while the trip is open, and only while another
--     photo stays at that stop (`no-photo`); the trip row is locked so two
--     removes cannot take a stop's last two photos. Removing a removed
--     photo answers the trip as it stands.
--   * `outstation_photo_restore(p_photo)`: Undo, under the same conditions
--     but the last.
--   * `outstation_trip_json`: each stop carries its client's logo (the
--     trip card's timeline draws it); each photo carries `removed_at` and
--     `removed_by` (the name); a removed photo is drawn only to a reader
--     holding `ops.outstation` (All trips), never to the driver or a
--     colleague who joined.
--   * `outstation_stop_add` and `outstation_check_out`: a removed photo is
--     no photo at the stop (`no-photo`), every other refusal kept.
--   * `outstation_photo_key`: a removed photo is read only at
--     `ops.outstation`.
--   * `outstation_photo_keys(p_trip)`: what sign-download asks as the
--     caller to sign every photo of a trip in one request: the same readers
--     as `outstation_photo_key`, removed photos only at `ops.outstation`.
--
-- ORDER: this migration, then sign-download (its `outstation.trip` read
-- asks `outstation_photo_keys`), then the pages. An open tab from before
-- reads each photo by `outstation.photo`, which still answers; until the
-- page ships nobody can remove a photo.
--
-- ROLLBACK: run OUTSTATION TRIP NUMBER AND DELETE's `outstation_trip_json`,
-- OUTSTATION CHECK-OUT WITHOUT A READING's `outstation_check_out`,
-- OUTSTATION VISITS FOR THE CLIENT's `outstation_stop_add` and OUTSTATION
-- RECORD's `outstation_photo_key` again; revoke the three new functions
-- (the page goes back first). The two columns may stay: nothing before
-- this reads them. A photo removed meanwhile then shows again.
-- ===========================================================================

alter table public.outstation_photos add column if not exists removed_at timestamptz;
alter table public.outstation_photos add column if not exists removed_by uuid;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'outstation_photos_removed_check') then
    alter table public.outstation_photos add constraint outstation_photos_removed_check
      check (removed_at is not null or removed_by is null);
  end if;
end $$;

/* The trip as the page reads it, each photo with its removal; a removed
   photo only for a reader of every trip. */
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
        'address', s.address, 'zone', s.zone, 'arrived_at', s.arrived_at, 'left_at', s.left_at,
        'km_from_prev', s.km_from_prev, 'filed', s.touch_id is not null,
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

create or replace function public.outstation_stop_add(
  p_trip uuid, p_client uuid, p_venue text, p_lat numeric, p_lng numeric, p_accuracy numeric, p_read_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_t public.outstation_trips; v_last public.outstation_stops; v_err jsonb; v_stop uuid;
begin
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_t := public.outstation_own_trip(p_trip);
  if v_t.id is null then return jsonb_build_object('error', 'no-trip'); end if;
  if v_t.state <> 'open' then return jsonb_build_object('error', 'closed'); end if;
  if length(coalesce(p_venue, '')) > 200 then return jsonb_build_object('error', 'too-long'); end if;
  if p_client is null and nullif(btrim(coalesce(p_venue, '')), '') is null then return jsonb_build_object('error', 'no-place'); end if;
  if p_client is not null and (not exists (select 1 from public.clients c where c.id = p_client)
                               or not public.allowed('clients', 'view')
                               or not public.client_scope_ok('client', p_client, 'view')) then
    return jsonb_build_object('error', 'bad-client');
  end if;
  select * into v_last from public.outstation_stops s where s.trip_id = v_t.id order by s.seq desc limit 1 for update;
  if not exists (select 1 from public.outstation_photos p where p.stop_id = v_last.id and p.removed_at is null) then
    return jsonb_build_object('error', 'no-photo');
  end if;
  if v_last.seq >= 20 then return jsonb_build_object('error', 'too-many'); end if;
  v_err := public.outstation_reading_error(p_lat, p_lng, p_accuracy, p_read_at);
  if v_err is not null then return v_err; end if;
  update public.outstation_stops set left_at = now() where id = v_last.id;
  perform public.outstation_file_visit(v_last.id);
  insert into public.outstation_stops (trip_id, seq, client_id, venue, lat, lng, accuracy_m, read_at)
  values (v_t.id, v_last.seq + 1, p_client, nullif(btrim(coalesce(p_venue, '')), ''), p_lat, p_lng, p_accuracy, p_read_at)
  returning id into v_stop;
  perform public.outstation_file_visit(v_stop);
  update public.outstation_trips set updated_at = now() where id = v_t.id;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_stop_add(uuid, uuid, text, numeric, numeric, numeric, timestamptz) from public, anon;
grant execute on function public.outstation_stop_add(uuid, uuid, text, numeric, numeric, numeric, timestamptz) to authenticated;

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
  if not exists (select 1 from public.outstation_photos p where p.stop_id = v_last.id and p.removed_at is null) then
    return jsonb_build_object('error', 'no-photo');
  end if;
  /* A reading is no longer asked at check-out: the way back is measured to
     the office pin. One still sent (a page from before) is held to the same
     limit. */
  if p_lat is not null or p_lng is not null then
    v_err := public.outstation_reading_error(p_lat, p_lng, p_accuracy, p_read_at);
    if v_err is not null then return v_err; end if;
  end if;
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

/* What sign-download asks as the caller to read one photo back: a reader
   of its trip (who drove it, who joined it, or `ops.outstation`); a
   removed photo at `ops.outstation` alone. */
create or replace function public.outstation_photo_key(p_photo uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me public.team_members; v_path text; v_trip uuid; v_gone timestamptz; v_t public.outstation_trips;
begin
  v_me := public.ops_me();
  if v_me.id is null or not public.allowed('ops', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select p.path, s.trip_id, p.removed_at into v_path, v_trip, v_gone
    from public.outstation_photos p join public.outstation_stops s on s.id = p.stop_id where p.id = p_photo;
  select * into v_t from public.outstation_trips t where t.id = v_trip;
  if v_path is null then return jsonb_build_object('error', 'not-kept'); end if;
  if v_gone is not null and not public.ops_granted('ops.outstation', 'view') then return jsonb_build_object('error', 'not-kept'); end if;
  if not (v_t.driver_id = v_me.id or v_me.id = any(v_t.companions) or public.ops_granted('ops.outstation', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('key', v_path, 'trip', v_t.id);
end $$;
revoke all on function public.outstation_photo_key(uuid) from public, anon;
grant execute on function public.outstation_photo_key(uuid) to authenticated;

/* Every photo of a trip the caller may read, in one answer, for
   sign-download to sign at once (a list reads what its rows show in one
   request). */
create or replace function public.outstation_photo_keys(p_trip uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me public.team_members; v_t public.outstation_trips; v_all boolean;
begin
  v_me := public.ops_me();
  if v_me.id is null or not public.allowed('ops', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_t from public.outstation_trips t where t.id = p_trip;
  if v_t.id is null then return jsonb_build_object('error', 'not-kept'); end if;
  v_all := public.ops_granted('ops.outstation', 'view');
  if not (v_t.driver_id = v_me.id or v_me.id = any(v_t.companions) or v_all) then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('trip', v_t.id, 'photos', coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'key', p.path) order by p.taken_at)
      from public.outstation_photos p join public.outstation_stops s on s.id = p.stop_id
     where s.trip_id = v_t.id and (p.removed_at is null or v_all)), '[]'::jsonb));
end $$;
revoke all on function public.outstation_photo_keys(uuid) from public, anon;
grant execute on function public.outstation_photo_keys(uuid) to authenticated;

/* A photo removed by the driver who took it, while the trip is open and
   another photo stays at its stop; the file stays in storage. */
create or replace function public.outstation_photo_remove(p_photo uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.team_members; v_p public.outstation_photos; v_trip uuid; v_t public.outstation_trips;
begin
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  select s.trip_id into v_trip from public.outstation_photos p join public.outstation_stops s on s.id = p.stop_id where p.id = p_photo;
  if v_trip is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into v_t from public.outstation_trips t where t.id = v_trip for update;
  if v_me.id is null or v_t.driver_id is distinct from v_me.id then return jsonb_build_object('error', 'denied'); end if;
  if v_t.state <> 'open' then return jsonb_build_object('error', 'closed'); end if;
  select * into v_p from public.outstation_photos p where p.id = p_photo for update;
  if v_p.removed_at is null then
    if not exists (select 1 from public.outstation_photos o
                    where o.stop_id = v_p.stop_id and o.id <> v_p.id and o.removed_at is null) then
      return jsonb_build_object('error', 'no-photo');
    end if;
    update public.outstation_photos set removed_at = now(), removed_by = v_me.id where id = v_p.id;
    update public.outstation_trips set updated_at = now() where id = v_t.id;
  end if;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_photo_remove(uuid) from public, anon;
grant execute on function public.outstation_photo_remove(uuid) to authenticated;

/* Undo: the same driver, the trip still open. */
create or replace function public.outstation_photo_restore(p_photo uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.team_members; v_trip uuid; v_t public.outstation_trips;
begin
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  select s.trip_id into v_trip from public.outstation_photos p join public.outstation_stops s on s.id = p.stop_id where p.id = p_photo;
  if v_trip is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into v_t from public.outstation_trips t where t.id = v_trip for update;
  if v_me.id is null or v_t.driver_id is distinct from v_me.id then return jsonb_build_object('error', 'denied'); end if;
  if v_t.state <> 'open' then return jsonb_build_object('error', 'closed'); end if;
  update public.outstation_photos set removed_at = null, removed_by = null where id = p_photo and removed_at is not null;
  update public.outstation_trips set updated_at = now() where id = v_t.id;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_photo_restore(uuid) from public, anon;
grant execute on function public.outstation_photo_restore(uuid) to authenticated;

-- END OF OUTSTATION PHOTOS SHOWN AND REMOVED ---------------------------------

select public.functions_tidy();
