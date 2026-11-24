-- ===========================================================================
-- OUTSTATION CHECK-OUT WITHOUT A READING (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: "checkout doesnt need to read location again.
-- Only on-site needs to check once would do". Check-out asked the phone's
-- location a second time; the way back is measured from the last stop to
-- the office pin, so the reading measured nothing.
--
-- WHAT IT CHANGES
--   * `outstation_check_out` takes no reading (`p_lat`, `p_lng`,
--     `p_accuracy`, `p_read_at` null), leaving `end_lat`, `end_lng` and
--     `end_accuracy_m` null. A reading still sent is held to the limit as
--     before (`vague`), so a page from before keeps working.
--
-- ORDER: this first, then the page that sends none (a page sending none
-- to the function before would be refused `vague`).
--
-- ROLLBACK: run OUTSTATION RECORD's `outstation_check_out` again; a page
-- that sends no reading is then refused, so the page goes back first.
-- ===========================================================================

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

-- END OF OUTSTATION CHECK-OUT WITHOUT A READING -----------------------------

select public.functions_tidy();
