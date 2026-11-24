-- ===========================================================================
-- A DELETED TRIP TAKES ITS VISITS (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24, after #OS trip OS/20261101 was deleted: "isnt
-- my outstation alr been deleted, why is there still record in here". A
-- trip's delete kept the visits it had filed on the clients' Calls and
-- visits, so a trip started by mistake left a visit that never happened.
--
-- WHAT IT CHANGES
--   * `outstation_trip_delete` removes the visits the trip's stops filed
--     (`client_touches` named by `outstation_stops.touch_id`) before the
--     trip, its stops and photo rows. Every other check stands. A visit
--     the team wrote by hand is never touched.
--
-- ORDER: this file alone; the page is unchanged. Safe to run twice.
-- ROLLBACK: run OUTSTATION TRIP NUMBER AND DELETE's `outstation_trip_delete`
-- again.
-- ===========================================================================

create or replace function public.outstation_trip_delete(p_trip uuid, p_confirm text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.team_members; v_t public.outstation_trips; v_driver text; v_stops integer;
begin
  v_me := public.ops_me();
  if v_me.id is null or not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_t from public.outstation_trips t where t.id = p_trip for update;
  if v_t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_t.driver_id <> v_me.id and not (v_me.is_admin or v_me.role = 'admin') then
    return jsonb_build_object('error', 'denied');
  end if;
  if upper(regexp_replace(coalesce(p_confirm, ''), '[^A-Za-z0-9]', '', 'g'))
     <> upper(regexp_replace(v_t.ref, '[^A-Za-z0-9]', '', 'g')) then
    return jsonb_build_object('error', 'confirm-required');
  end if;
  select m.name into v_driver from public.team_members m where m.id = v_t.driver_id;
  select count(*) into v_stops from public.outstation_stops s where s.trip_id = v_t.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, v_me.email), 'ops.deleted', v_t.ref,
          'Outstation trip · ' || public.register_day((v_t.started_at at time zone 'Asia/Kuala_Lumpur')::date)
          || ' · ' || coalesce(v_driver, 'a colleague') || ' · ' || v_stops || case when v_stops = 1 then ' stop' else ' stops' end);
  /* The visits it filed go with it: a trip deleted did not happen (the
     user, 2026-11-24). */
  delete from public.client_touches
   where id in (select s.touch_id from public.outstation_stops s where s.trip_id = v_t.id and s.touch_id is not null);
  delete from public.outstation_trips where id = v_t.id;
  return jsonb_build_object('ok', true, 'deleted', true, 'ref', v_t.ref);
end $$;
revoke all on function public.outstation_trip_delete(uuid, text) from public, anon;
grant execute on function public.outstation_trip_delete(uuid, text) to authenticated;

-- END OF A DELETED TRIP TAKES ITS VISITS ------------------------------------

select public.functions_tidy();
