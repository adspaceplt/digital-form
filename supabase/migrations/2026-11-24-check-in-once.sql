-- ===========================================================================
-- CHECK IN ONCE (2026-11-24)
-- ===========================================================================
-- WHY: the audit of 2026-11-24 (the user: "fix all except 2"). Two presses
-- of Check in at once both passed `outstation_check_in`'s open-trip check;
-- the second met `outstation_trips_one_open` and the page read the
-- database's unique_violation.
--
-- WHAT IT CHANGES
--   * `outstation_check_in` answers the second press `open-trip`, as it
--     answers a press with a trip already open.
--
-- ORDER: this file alone. Safe to run twice.
-- ROLLBACK: run outstation_check_in from OUTSTATION RECORD again.
-- ===========================================================================

-- CHECK IN ONCE -------------------------------------------------------------

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
                               or not public.allowed('clients', 'view')
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
  -- two presses at once both pass the check above; the one open trip a
  -- driver may hold (outstation_trips_one_open) refuses the second
  begin
    insert into public.outstation_trips (driver_id, companions, purpose, note)
    values (v_me.id, v_with, p_purpose, nullif(btrim(coalesce(p_note, '')), ''))
    returning id into v_trip;
  exception when unique_violation then
    return jsonb_build_object('error', 'open-trip');
  end;
  insert into public.outstation_stops (trip_id, seq, client_id, venue, lat, lng, accuracy_m, read_at)
  values (v_trip, 1, p_client, case when p_client is null then btrim(p_venue) end, p_lat, p_lng, p_accuracy, p_read_at);
  return jsonb_build_object('ok', true, 'trip', public.outstation_trip_json(v_trip));
end $$;
revoke all on function public.outstation_check_in(uuid, text, text, text, uuid[], numeric, numeric, numeric, timestamptz) from public, anon;
grant execute on function public.outstation_check_in(uuid, text, text, text, uuid[], numeric, numeric, numeric, timestamptz) to authenticated;

-- END OF CHECK IN ONCE ------------------------------------------------------

select public.functions_tidy();
