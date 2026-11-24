-- ===========================================================================
-- OUTSTATION VISITS FOR THE CLIENT (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: "shouldnt it be as long as its for that
-- specific client, then it should be recorded under. cos we are carrying
-- out outstation works for the clients. even overseas". A stop was a
-- client's site or an Other venue with no client, so work for a client
-- away from its site (a shoot, an event, abroad) reached no client; and a
-- visit was filed only once its stop was left.
--
-- WHAT IT CHANGES
--   * A stop holds its client and its venue together: Check in and Add stop
--     keep the venue typed whether or not a client is chosen.
--   * `outstation_file_visit` files a client's stop on Calls and visits as
--     it begins ("from 2:00pm (in progress)", the venue named) and
--     completes the same line with its end time once left (Add stop, Check
--     out); `outstation_check_in` and `outstation_stop_add` file the new stop
--     at once. A trip deleted still takes its visits.
--
-- ORDER: this file, then the page (the place is asked apart from the
-- client). An old tab still sends a client or a venue, both accepted.
-- Safe to run twice.
-- ROLLBACK: run CHECK IN ONCE / COMPANIONS WHO MAY WORK's
-- `outstation_check_in`, OUTSTATION RECORD's `outstation_stop_add` and
-- `outstation_file_visit` again.
-- ===========================================================================

create or replace function public.outstation_file_visit(p_stop uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_s public.outstation_stops; v_t public.outstation_trips; v_driver text; v_with text; v_touch uuid; v_line text;
begin
  select * into v_s from public.outstation_stops where id = p_stop;
  if v_s.id is null or v_s.client_id is null then return; end if;
  select * into v_t from public.outstation_trips where id = v_s.trip_id;
  select m.name into v_driver from public.team_members m where m.id = v_t.driver_id;
  select string_agg(m.name, ', ' order by m.name) into v_with from public.team_members m where m.id = any(v_t.companions);
  /* Filed when the stop begins, in progress, and completed with its end
     time once left (the user, 2026-11-24: "as long as its for that
     specific client, then it should be recorded under"). */
  v_line := 'Outstation visit: ' || initcap(v_t.purpose)
    || coalesce(', at ' || nullif(btrim(v_s.venue), ''), '') || ', '
    || case when v_s.left_at is null
            then 'from ' || lower(to_char(v_s.arrived_at at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')) || ' (in progress)'
            else lower(to_char(v_s.arrived_at at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')) || ' to '
                 || lower(to_char(v_s.left_at at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')) end
    || coalesce(', with ' || v_with, '') || '.'
    || coalesce(' ' || nullif(btrim(v_t.note), ''), '');
  begin
    if v_s.touch_id is not null and exists (select 1 from public.client_touches c where c.id = v_s.touch_id) then
      update public.client_touches set summary = v_line where id = v_s.touch_id;
    else
      insert into public.client_touches (client_id, kind, happened_at, by_whom, summary)
      values (v_s.client_id, 'visit', (v_s.arrived_at at time zone 'Asia/Kuala_Lumpur')::date, v_driver, v_line)
      returning id into v_touch;
      update public.outstation_stops set touch_id = v_touch where id = p_stop;
    end if;
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
declare v_me public.team_members; v_err jsonb; v_trip uuid; v_with uuid[]; v_stop uuid;
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
                               or not public.allowed('clients', 'view')
                               or not public.client_scope_ok('client', p_client, 'view')) then
    return jsonb_build_object('error', 'bad-client');
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_with from unnest(coalesce(p_companions, '{}'::uuid[])) x;
  if array_length(v_with, 1) > 10 or v_me.id = any(v_with)
     or exists (select 1 from unnest(v_with) x where not exists (
          select 1 from public.team_members m where m.id = x and m.active and m.removed_at is null and not coalesce(m.system, false)
             /* A companion may work My Work, as the driver must: a colleague
                kept for the namecard alone is never one (2026-11-24). */
             and (coalesce(m.is_admin, false) or coalesce(m.role, '') = 'admin' or public.level_rank(m.access ->> 'ops') >= 2))) then
    return jsonb_build_object('error', 'bad-companion');
  end if;
  v_err := public.outstation_reading_error(p_lat, p_lng, p_accuracy, p_read_at);
  if v_err is not null then return v_err; end if;
  -- two presses at once both pass the check above; the one open trip a
  -- driver may hold (outstation_trips_one_open) refuses the second
  begin
    insert into public.outstation_trips (driver_id, companions, purpose, note)
    values (v_me.id, v_with, p_purpose, nullif(btrim(coalesce(p_note, '')), ''))
    returning id into v_trip;
  exception when unique_violation then
    return jsonb_build_object('error', 'open-trip');
  end;
  -- A client's stop keeps its venue too: work for the client away from
  -- its own site (2026-11-24); its visit is filed at once, in progress.
  insert into public.outstation_stops (trip_id, seq, client_id, venue, lat, lng, accuracy_m, read_at)
  values (v_trip, 1, p_client, nullif(btrim(coalesce(p_venue, '')), ''), p_lat, p_lng, p_accuracy, p_read_at)
  returning id into v_stop;
  perform public.outstation_file_visit(v_stop);
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_trip));
end $$;
revoke all on function public.outstation_check_in(uuid, text, text, text, uuid[], numeric, numeric, numeric, timestamptz) from public, anon;
grant execute on function public.outstation_check_in(uuid, text, text, text, uuid[], numeric, numeric, numeric, timestamptz) to authenticated;

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
  if not exists (select 1 from public.outstation_photos p where p.stop_id = v_last.id) then
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

-- END OF OUTSTATION VISITS FOR THE CLIENT -------------------------------------

select public.functions_tidy();
