-- ===========================================================================
-- OUTSTATION WRITES HELD (2026-11-25)
-- ===========================================================================
-- WHY (the review of everything merged since 15 Nov, approved by the user
-- on 2026-11-25): a stop, a photo or a check-out made as the midnight close
-- ran read the trip open and wrote into a trip the close had just ended;
-- and a photo removed still counted against a stop's ten.
--
-- WHAT CHANGES
--   * `outstation_own_trip` (restated from OUTSTATION RECORD): the trip's
--     row is taken `for update`, so every writer waits for the close
--     (`outstation_close_open`, which already locks its trips) and then
--     reads the trip as it stands. Every caller is a writer.
--   * `outstation_photo_add` (restated from OUTSTATION RECORD): the ten a
--     stop counts only photos not removed.
--
-- ORDER: this file alone (connector); the page's own changes (the office
-- read again at each check-out, a drive back never saved asked again)
-- read nothing new. Safe to run twice.
-- ROLLBACK: run both functions from OUTSTATION RECORD again.
-- ===========================================================================

-- OUTSTATION WRITES HELD -------------------------------------------------------

/* The caller's own trip, its row held until the write ends (OUTSTATION
   WRITES HELD): every caller writes, so a stop, a photo or a check-out
   waits for the midnight close and then reads the trip as it closed. */
create or replace function public.outstation_own_trip(p_trip uuid)
returns public.outstation_trips
language sql volatile security definer set search_path = public as $$
  select t.* from public.outstation_trips t
   where t.id = p_trip and t.driver_id = (public.ops_me()).id
   for update of t
$$;
revoke all on function public.outstation_own_trip(uuid) from public, anon, authenticated;

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
    return jsonb_build_object('error', 'bad-time');
  end if;
  if (p_lat is not null and p_lat not between -90 and 90) or (p_lng is not null and p_lng not between -180 and 180)
     or (p_accuracy is not null and p_accuracy < 0) then
    return jsonb_build_object('error', 'bad-location');
  end if;
  if (select count(*) from public.outstation_photos p where p.stop_id = v_s.id and p.removed_at is null) >= 10 then
    return jsonb_build_object('error', 'too-many');
  end if;
  insert into public.outstation_photos (stop_id, path, taken_at, lat, lng, accuracy_m)
  values (v_s.id, p_path, p_taken_at, p_lat, p_lng, p_accuracy);
  update public.outstation_trips set updated_at = now() where id = v_t.id;
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_t.id));
end $$;
revoke all on function public.outstation_photo_add(uuid, text, timestamptz, numeric, numeric, numeric) from public, anon;
grant execute on function public.outstation_photo_add(uuid, text, timestamptz, numeric, numeric, numeric) to authenticated;

-- END OF OUTSTATION WRITES HELD -----------------------------------------------

select public.functions_tidy();
