-- ===========================================================================
-- OUTSTATION TRIP NUMBER AND DELETE (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: "add a serial for every record OS/YYYYMMNN",
-- and "go ahead and build trip delete but it will end up at delete
-- requests right". A trip had no number to name it by, and a trip started
-- by mistake had no way out.
--
-- WHAT IT ADDS
--   * `outstation_trips.ref`: the trip number, `OS/{YYYYMM}{NN}`, the month
--     of check-in in Malaysia and the trip's number in that month from 01
--     (two digits, more past 99). Given on insert by trigger from
--     `outstation_ref_months`, one row a month taken under its row lock, so
--     two check-ins at once take two numbers and a number deleted is never
--     given again; never changed after (`code-fixed`). The trips standing
--     take theirs in the order they were made.
--   * `outstation_trip_json` reads it (`ref`), so every trip the page reads
--     carries it.
--   * `outstation_trip_delete(p_trip, p_confirm)`: My Work at Full control,
--     the driver's own trip (open or checked out) or any trip for an admin,
--     the trip number typed back (`confirm-required`). The trip goes with
--     its stops and photo rows; the visits it filed stay on the clients'
--     Calls and visits, and the photo files stay in storage, as every upload
--     does. Filed `ops.deleted` under the trip number. Refusals: `denied`,
--     `not-found`, `confirm-required`.
--   * `delete_kinds` names it (`rpc:outstation_trip_delete`, My Work), so a
--     driver at Edit files a delete request an admin approves in Settings,
--     Portal: Delete requests.
--
-- ORDER: the pages first (a page from before never reads `ref` and never
-- asks the delete; the new page draws a trip without a number and refuses
-- the delete as not available while this file is not run), then this file.
-- Safe to run twice.
-- ROLLBACK: delete the `rpc:outstation_trip_delete` row of `delete_kinds`
-- (and any request naming it); drop `outstation_trip_delete(uuid, text)`;
-- run OUTSTATION RECORD's `outstation_trip_json` again; drop the trigger
-- `outstation_trips_ref`, its function and `outstation_ref_take`; drop the
-- column `ref` and the table `outstation_ref_months`.
-- ===========================================================================

create table if not exists public.outstation_ref_months (
  month text primary key check (month ~ '^[0-9]{6}$'),
  last  integer not null check (last >= 1)
);
alter table public.outstation_ref_months enable row level security;
revoke all on public.outstation_ref_months from public, anon, authenticated;

alter table public.outstation_trips add column if not exists ref text;
create unique index if not exists outstation_trips_ref_idx on public.outstation_trips (ref);

/* The next number of a month, taken under the month's row lock. */
create or replace function public.outstation_ref_take(p_at timestamptz)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_m text := to_char(coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur', 'YYYYMM'); v_n integer;
begin
  insert into public.outstation_ref_months (month, last) values (v_m, 1)
  on conflict (month) do update set last = public.outstation_ref_months.last + 1
  returning last into v_n;
  return 'OS/' || v_m || lpad(v_n::text, greatest(2, length(v_n::text)), '0');
end $$;
revoke all on function public.outstation_ref_take(timestamptz) from public, anon, authenticated;

create or replace function public.outstation_trips_ref()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.ref := public.outstation_ref_take(new.started_at);
  elsif new.ref is distinct from old.ref and old.ref is not null then
    raise exception 'code-fixed';
  end if;
  return new;
end $$;
revoke all on function public.outstation_trips_ref() from public, anon, authenticated;
create or replace trigger outstation_trips_ref before insert or update of ref on public.outstation_trips
  for each row execute function public.outstation_trips_ref();

/* The trips standing take theirs in the order they were made. */
do $$
declare r record;
begin
  for r in select id, started_at from public.outstation_trips where ref is null order by started_at, id loop
    update public.outstation_trips set ref = public.outstation_ref_take(r.started_at) where id = r.id;
  end loop;
end $$;
alter table public.outstation_trips alter column ref set not null;

/* The trip as the page reads it, now with its number. */
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

/* A trip deleted at Full control: the driver's own, or any for an admin,
   its number typed back. At Edit the page files a delete request in its
   place (`delete_kinds`), and the admin who approves it makes this call. */
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
  delete from public.outstation_trips where id = v_t.id;
  return jsonb_build_object('ok', true, 'deleted', true, 'ref', v_t.ref);
end $$;
revoke all on function public.outstation_trip_delete(uuid, text) from public, anon;
grant execute on function public.outstation_trip_delete(uuid, text) to authenticated;

insert into public.delete_kinds (kind, section, id_arg, word, label_table, label_key, label_col) values
  ('rpc:outstation_trip_delete', 'ops', 'p_trip', 'Outstation trip', 'outstation_trips', 'id', 'ref')
on conflict (kind) do update set section = excluded.section, id_arg = excluded.id_arg, word = excluded.word,
  label_table = excluded.label_table, label_key = excluded.label_key, label_col = excluded.label_col;

-- END OF OUTSTATION TRIP NUMBER AND DELETE ----------------------------------

select public.functions_tidy();
