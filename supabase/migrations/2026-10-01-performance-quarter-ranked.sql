-- ===========================================================================
-- THE QUARTER RANKED — a quarter lists its people best to worst with each
-- one's whole reward, is confirmed only once every month in it is final, and
-- the bonus pool runs over fixed halves of the year.
-- 2026-10-01. Safe to run twice. Run after
-- 2026-09-28-performance-rewards.sql. Rollback at the foot of this header.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/perf.js compares the two.
--
-- WHAT CHANGED
--   1. perf_quarter_calc: every person carries `rank` (1 is the highest
--      average; equal averages share a rank; nobody without a final month is
--      ranked), `open` (their months in the quarter not yet final),
--      `department_share` (their part of a department prize won) and `total`
--      (the individual prize plus that share). The list runs best to worst
--      by average. The quarter carries `open_months` (reviews in it not yet
--      final) and `missing_months` (months already ended that an active
--      member on the review list has no review for).
--   2. perf_quarter_confirm refuses `months-open` while any review in the
--      quarter is not final, naming how many: a month still in dispute or
--      waiting to be finalised would otherwise be left out of an average
--      that is then kept. A missing month does not refuse; the page asks
--      first.
--   3. The period of the bonus pool and the trip is a half of the year: Q1
--      and Q2, or Q3 and Q4 (perf_half), so two periods never share a
--      quarter and no month is paid twice. Any date given is read as the
--      half it falls in. `perf_company.period` is held to 1 January or
--      1 July.
--   4. perf_rewards_mine sends a member their own quarter without `rank`:
--      the ranking is management's.
--
-- ROLLBACK
--   Run the PERFORMANCE REWARDS section of supabase/schema.sql again (it
--   restores the five period functions, perf_quarter_calc,
--   perf_quarter_confirm and perf_rewards_mine), then:
--   alter table public.perf_company drop constraint if exists perf_company_period_half;
--   drop function if exists public.perf_half(date);
-- ===========================================================================

/* The half of the year a date falls in: 1 January or 1 July. */
create or replace function public.perf_half(p_date date)
returns date language sql immutable as $$
  select (date_trunc('year', p_date)
          + case when extract(month from p_date) >= 7 then interval '6 months' else interval '0 months' end)::date
$$;
revoke all on function public.perf_half(date) from public, anon, authenticated;

alter table public.perf_company drop constraint if exists perf_company_period_check;
alter table public.perf_company drop constraint if exists perf_company_period_half;
alter table public.perf_company add constraint perf_company_period_half
  check (period >= date '2026-07-01' and extract(day from period) = 1 and extract(month from period) in (1, 7));

create or replace function public.perf_quarter_calc(p_quarter date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q date := date_trunc('quarter', p_quarter)::date;
  v_qe date := (date_trunc('quarter', p_quarter) + interval '3 months')::date;
  v_people jsonb; v_wins integer; v_each numeric; v_ind jsonb;
  v_depts jsonb; v_dwins integer; v_both boolean; v_why text; v_dp jsonb;
  v_open integer; v_missing integer;
begin
  with m as (
    select t.id as mid, t.name as mname, t.staff_code as mcode, t.department as mdept, t.active as mactive,
           public.perf_reviewed(t.id) as monlist, f.nmonths, f.mean, f.emonth,
           (select count(*)::int from public.perf_reviews o
             where o.team_member_id = t.id and o.status <> 'final'
               and o.period >= v_q and o.period < v_qe) as nopen,
           exists (select 1 from public.perf_breaches b
                    where b.team_member_id = t.id and b.voided_at is null and b.severity = 4
                      and b.period >= v_q and b.period < v_qe) as ml4
      from public.team_members t
      cross join lateral (
        select count(*)::int as nmonths, round(avg((x.res ->> 'final')::numeric), 2) as mean,
               coalesce(bool_or(x.res ->> 'grade' = 'E'), false) as emonth
          from (select coalesce(r.result, public.perf_calc(r)) as res
                  from public.perf_reviews r
                 where r.team_member_id = t.id and r.status = 'final'
                   and r.period >= v_q and r.period < v_qe) x) f
     where f.nmonths > 0 or (t.active and public.perf_reviewed(t.id))
  ), e as (
    select m.*, array_remove(array[
             case when m.nmonths = 0 then 'no-final-month' end,
             case when m.nmonths > 0 and m.mean < 70 then 'below-c' end,
             case when m.emonth then 'e-month' end,
             case when m.ml4 then 'critical-breach' end,
             case when not m.mactive then 'inactive' end,
             case when not m.monlist then 'not-reviewed' end], null) as why
      from m
  ), w as (
    select e.*, cardinality(e.why) = 0 as ok,
           coalesce(cardinality(e.why) = 0
                    and e.mean = max(e.mean) filter (where cardinality(e.why) = 0) over (), false) as won
      from e
  ), p as (
    select w.*, count(*) filter (where w.won) over () as nwon,
           case when w.nmonths > 0 then rank() over (order by w.mean desc nulls last) end as mrank
      from w
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'team_member_id', p.mid, 'name', p.mname, 'staff_code', p.mcode, 'department', p.mdept,
           'active', p.mactive, 'reviewed', p.monlist, 'months', p.nmonths, 'open', p.nopen,
           'rank', p.mrank, 'average', p.mean,
           'grade', case when p.nmonths > 0 then public.perf_grade_of(p.mean) end,
           'e_month', p.emonth, 'l4', p.ml4, 'eligible', p.ok, 'reasons', to_jsonb(p.why),
           'prize', case when p.won then floor(40000.0 / p.nwon) / 100 else 0 end)
         order by p.mean desc nulls last, p.mname), '[]'::jsonb),
         coalesce(max(p.nwon), 0)
    into v_people, v_wins
    from p;
  v_each := case when v_wins > 0 then floor(40000.0 / v_wins) / 100 end;
  v_ind := jsonb_build_object('pool', 400, 'winners', v_wins, 'each', v_each,
    'paid', coalesce(v_each * v_wins, 0), 'remainder', 400 - coalesce(v_each * v_wins, 0),
    'reason', case when v_wins = 0 then 'nobody-eligible' end);

  with d as (
    select k.dep, s.c1, s.c2, s.c3, s.c4, s.c5, coalesce(s.critical, false) as crit,
           s.c1 + s.c2 + s.c3 + s.c4 + s.c5 as total, s.quarter is not null as entered, k.ord
      from (values ('creative', 1), ('marketing', 2)) k(dep, ord)
      left join public.perf_dept_scores s on s.quarter = v_q and s.department = k.dep
  ), x as (
    select d.*, bool_and(d.entered) over () as bothin,
           coalesce(d.total = max(d.total) over (), false) as istop
      from d
  ), y as (
    select x.*, (x.bothin and x.istop and x.total >= 80 and not x.crit) as won,
           coalesce((select array_agg(t.id order by t.name) from public.team_members t
                      where t.active and t.department = x.dep and public.perf_reviewed(t.id)), '{}'::uuid[]) as mems
      from x
  ), z as (
    select y.*, count(*) filter (where y.won) over () as nwon,
           case when y.won then floor(60000.0 / count(*) filter (where y.won) over ()) end as sharec
      from y
  )
  select jsonb_agg(jsonb_build_object(
           'department', z.dep, 'entered', z.entered,
           'criteria', case when z.entered then jsonb_build_array(z.c1, z.c2, z.c3, z.c4, z.c5) end,
           'total', z.total, 'grade', case when z.entered then public.perf_grade_of(z.total) end,
           'critical', z.crit, 'top', z.bothin and z.istop,
           'qualifies', z.entered and z.total >= 80 and not z.crit, 'won', z.won,
           'share', coalesce(z.sharec / 100, 0), 'members', to_jsonb(z.mems),
           'each', case when z.won and cardinality(z.mems) > 0 then floor(z.sharec / cardinality(z.mems)) / 100 end,
           'remainder', case when z.won then case when cardinality(z.mems) > 0
                               then (z.sharec - floor(z.sharec / cardinality(z.mems)) * cardinality(z.mems)) / 100
                               else z.sharec / 100 end end)
         order by z.ord),
         coalesce(max(z.nwon), 0), bool_and(z.bothin),
         case when bool_and(z.bothin) and max(z.nwon) = 0 then
           case when bool_or(z.istop and z.total >= 80 and z.crit) then 'critical-issue' else 'below-b' end end
    into v_depts, v_dwins, v_both, v_why
    from z;
  v_dp := jsonb_build_object('pool', 600, 'winners', v_dwins,
    'paid', case when v_dwins > 0 then floor(60000.0 / v_dwins) * v_dwins / 100 else 0 end,
    'remainder', case when v_dwins > 0 then 600 - floor(60000.0 / v_dwins) * v_dwins / 100 else 600 end,
    'reason', case when not v_both then 'scores-needed' else v_why end);

  /* Each person's part of a department prize won, and their whole reward. */
  select coalesce(jsonb_agg(a.x || jsonb_build_object('department_share', s.ds,
                                                       'total', (a.x ->> 'prize')::numeric + s.ds)
                            order by a.n), '[]'::jsonb)
    into v_people
    from jsonb_array_elements(v_people) with ordinality a(x, n)
    cross join lateral (
      select coalesce((select (dd ->> 'each')::numeric from jsonb_array_elements(v_depts) dd
                        where (dd ->> 'won')::boolean and dd -> 'members' ? (a.x ->> 'team_member_id')
                          and dd ->> 'each' is not null
                        limit 1), 0) as ds) s;

  select count(*)::int into v_open
    from public.perf_reviews r
   where r.status <> 'final' and r.period >= v_q and r.period < v_qe;
  select count(*)::int into v_missing
    from public.team_members t
    cross join generate_series(v_q, (v_qe - interval '1 month')::date, interval '1 month') g(mo)
   where t.active and public.perf_reviewed(t.id)
     and (g.mo + interval '1 month')::date <= public.perf_today()
     and not exists (select 1 from public.perf_reviews r where r.team_member_id = t.id and r.period = g.mo::date);

  return jsonb_build_object('quarter', v_q, 'word', public.perf_quarter_word(v_q),
    'ended', public.perf_today() >= v_qe, 'people', v_people, 'individual', v_ind,
    'departments', v_depts, 'department_prize', v_dp,
    'open_months', v_open, 'missing_months', v_missing);
end $$;

create or replace function public.perf_quarter_confirm(p_token text, p_quarter date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_q date; v_snap jsonb; v_x jsonb; v_open integer;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_q := date_trunc('quarter', p_quarter)::date;
  if v_q is null or v_q < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if exists (select 1 from public.perf_rewards where kind = 'quarter' and period = v_q) then
    return public.perf_quarter(p_token, v_q);
  end if;
  if public.perf_today() < (v_q + interval '3 months')::date then
    return jsonb_build_object('error', 'quarter-open');
  end if;
  select count(*)::int into v_open
    from public.perf_reviews r
   where r.status <> 'final' and r.period >= v_q and r.period < (v_q + interval '3 months')::date;
  if v_open > 0 then
    return jsonb_build_object('error', 'months-open', 'count', v_open);
  end if;
  if (select count(*) from public.perf_dept_scores where quarter = v_q) < 2 then
    return jsonb_build_object('error', 'dept-scores-needed');
  end if;
  v_snap := public.perf_quarter_calc(v_q);
  insert into public.perf_rewards (kind, period, snapshot, confirmed_by) values ('quarter', v_q, v_snap, v_me.id)
  on conflict (kind, period) do nothing;
  perform public.perf_log(null, null, 'quarter_confirmed', jsonb_build_object('key', v_q::text,
    'winners', v_snap -> 'individual' -> 'winners', 'departments', v_snap -> 'department_prize' -> 'winners'));
  for v_x in select * from jsonb_array_elements(v_snap -> 'people') loop
    if (v_x ->> 'active')::boolean then
      perform public.perf_notify((v_x ->> 'team_member_id')::uuid, 'perf.quarter',
        'Your ' || public.perf_quarter_word(v_q) || ' quarterly outcome is ready.',
        'perf.quarter.' || v_q || '.' || (v_x ->> 'team_member_id') || '.' || extract(epoch from now())::bigint);
    end if;
  end loop;
  return public.perf_quarter(p_token, v_q);
end $$;

/* A period of two quarters, now a half of the year. */
create or replace function public.perf_period_calc(p_from date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_f date := public.perf_half(p_from);
  v_t date := (public.perf_half(p_from) + interval '6 months')::date;
  v_c public.perf_company; v_pool numeric; v_trip numeric; v_popen boolean; v_topen boolean;
  v_rows jsonb; v_units numeric; v_bpaid numeric; v_tpaid numeric;
begin
  select * into v_c from public.perf_company where period = v_f;
  v_popen := coalesce(v_c.revenue, 0) >= 500000;
  v_topen := coalesce(v_c.revenue, 0) >= 1000000;
  v_pool := case when v_popen then coalesce(v_c.pool, 0) else 0 end;
  v_trip := case when v_topen then coalesce(v_c.trip_budget, 0) else 0 end;
  with m as (
    select t.id as mid, t.name as mname, t.staff_code as mcode, t.active as mactive,
           f.nmonths, f.nb, f.mean, f.emonth,
           exists (select 1 from public.perf_breaches b
                    where b.team_member_id = t.id and b.voided_at is null and b.severity = 4
                      and b.period >= v_f and b.period < v_t) as ml4
      from public.team_members t
      cross join lateral (
        select count(*)::int as nmonths,
               (count(*) filter (where x.res ->> 'grade' in ('A', 'B')))::int as nb,
               round(avg((x.res ->> 'final')::numeric), 2) as mean,
               coalesce(bool_or(x.res ->> 'grade' = 'E'), false) as emonth
          from (select coalesce(r.result, public.perf_calc(r)) as res
                  from public.perf_reviews r
                 where r.team_member_id = t.id and r.status = 'final'
                   and r.period >= v_f and r.period < v_t) x) f
     where f.nmonths > 0 or (t.active and public.perf_reviewed(t.id))
  ), e as (
    select m.*, array_remove(array[
             case when m.nmonths = 0 then 'no-final-month' end,
             case when m.nmonths > 0 and m.nb < 3 then 'few-b-months' end,
             case when m.emonth then 'e-month' end,
             case when m.ml4 then 'critical-breach' end,
             case when not m.mactive then 'inactive' end], null) as why
      from m
  ), u as (
    select e.*, cardinality(e.why) = 0 as ok,
           case when cardinality(e.why) = 0 then
             case public.perf_grade_of(e.mean) when 'A' then 3.0 when 'B' then 1.5 when 'C' then 0.5 else 0 end
           else 0 end as units
      from e
  ), s as (
    select u.*, sum(u.units) over () as allunits from u
  ), o as (
    select s.*,
           case when s.allunits > 0 then floor(v_pool * 100 * s.units / s.allunits) / 100 else 0 end as bonus,
           case when s.allunits > 0 then floor(v_trip * 100 * s.units / s.allunits) / 100 else 0 end as tripshare
      from s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'team_member_id', o.mid, 'name', o.mname, 'staff_code', o.mcode, 'active', o.mactive,
           'months', o.nmonths, 'months_b', o.nb, 'average', o.mean,
           'grade', case when o.nmonths > 0 then public.perf_grade_of(o.mean) end,
           'e_month', o.emonth, 'l4', o.ml4, 'eligible', o.ok, 'reasons', to_jsonb(o.why),
           'units', o.units, 'bonus', o.bonus, 'trip', o.tripshare)
         order by o.ok desc, o.units desc, o.mean desc nulls last, o.mname), '[]'::jsonb),
         coalesce(sum(o.units), 0), coalesce(sum(o.bonus), 0), coalesce(sum(o.tripshare), 0)
    into v_rows, v_units, v_bpaid, v_tpaid
    from o;
  return jsonb_build_object('period', v_f, 'word', public.perf_period_word(v_f),
    'last_month', (v_t - interval '1 month')::date, 'ended', public.perf_today() >= v_t,
    'figures', v_c.period is not null, 'total_units', v_units, 'people', v_rows,
    'bonus', jsonb_build_object('open', v_popen, 'pool', v_pool, 'paid', v_bpaid, 'remainder', v_pool - v_bpaid,
      'reason', case when v_c.period is null then 'figures-needed' when not v_popen then 'below-gate'
                     when v_pool = 0 then 'no-pool' when v_units = 0 then 'nobody-eligible' end),
    'trip', jsonb_build_object('open', v_topen, 'budget', v_trip, 'paid', v_tpaid, 'remainder', v_trip - v_tpaid,
      'reason', case when v_c.period is null then 'figures-needed' when not v_topen then 'below-gate'
                     when v_trip = 0 then 'no-budget' when v_units = 0 then 'nobody-eligible' end));
end $$;

create or replace function public.perf_period(p_token text, p_from date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_f date; v_rw public.perf_rewards; v_c public.perf_company; v_out jsonb;
begin
  v_err := public.perf_check(p_token, 'view');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_f := public.perf_half(coalesce(p_from, public.perf_today()));
  if v_f < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  select * into v_rw from public.perf_rewards where kind = 'period' and period = v_f;
  v_out := coalesce(v_rw.snapshot, public.perf_period_calc(v_f));
  v_out := v_out || jsonb_build_object(
    'people', public.perf_hide_own(v_out -> 'people', v_me.id),
    'admin', public.perf_is_admin(),
    'confirmed', v_rw.period is not null, 'confirmed_at', v_rw.confirmed_at,
    'confirmed_by', (select t.name from public.team_members t where t.id = v_rw.confirmed_by),
    'ended', public.perf_today() >= (v_f + interval '6 months')::date,
    'events', public.perf_reward_events(array['company_set', 'period_confirmed', 'period_reopened'], v_f::text));
  /* Revenue and profit, and the ceiling they set, for an admin alone. */
  if public.perf_is_admin() then
    select * into v_c from public.perf_company where period = v_f;
    if v_c.period is not null then
      v_out := v_out || jsonb_build_object('company', jsonb_build_object('revenue', v_c.revenue, 'profit', v_c.profit,
        'pool', v_c.pool, 'trip_budget', v_c.trip_budget, 'max_pool', greatest(0, floor(v_c.profit * 10) / 100)));
    end if;
  end if;
  return v_out;
end $$;

create or replace function public.perf_company_set(p_token text, p_from date, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err text; v_me public.team_members; v_f date; v_rev numeric; v_pro numeric; v_pool numeric; v_trip numeric;
  v_was public.perf_company; v_max numeric; v_changed jsonb := '[]'::jsonb;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  if not public.perf_is_admin() then return jsonb_build_object('error', 'admin-only'); end if;
  v_me := public.ops_me();
  v_f := public.perf_half(p_from);
  if v_f is null or v_f < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if exists (select 1 from public.perf_rewards where kind = 'period' and period = v_f) then
    return jsonb_build_object('error', 'confirmed');
  end if;
  if coalesce(jsonb_typeof(p_payload -> 'revenue'), '') <> 'number'
     or coalesce(jsonb_typeof(p_payload -> 'profit'), '') <> 'number'
     or coalesce(jsonb_typeof(p_payload -> 'pool'), 'number') not in ('number', 'null')
     or coalesce(jsonb_typeof(p_payload -> 'trip_budget'), 'number') not in ('number', 'null') then
    return jsonb_build_object('error', 'bad-amount');
  end if;
  v_rev := (p_payload ->> 'revenue')::numeric;
  v_pro := (p_payload ->> 'profit')::numeric;
  v_pool := coalesce((p_payload ->> 'pool')::numeric, 0);
  v_trip := coalesce((p_payload ->> 'trip_budget')::numeric, 0);
  if v_rev < 0 or v_pool < 0 or v_trip < 0
     or round(v_rev, 2) <> v_rev or round(v_pro, 2) <> v_pro or round(v_pool, 2) <> v_pool or round(v_trip, 2) <> v_trip
     or greatest(abs(v_rev), abs(v_pro), v_pool, v_trip) >= 1e12 then
    return jsonb_build_object('error', 'bad-amount');
  end if;
  v_max := greatest(0, floor(v_pro * 10) / 100);
  if v_pool > 0 and v_rev < 500000 then return jsonb_build_object('error', 'pool-closed'); end if;
  if v_pool > v_max then return jsonb_build_object('error', 'pool-over', 'max', v_max); end if;
  if v_trip > 0 and v_rev < 1000000 then return jsonb_build_object('error', 'trip-closed'); end if;
  select * into v_was from public.perf_company where period = v_f for update;
  insert into public.perf_company (period, revenue, profit, pool, trip_budget, entered_by, updated_at)
  values (v_f, v_rev, v_pro, v_pool, v_trip, v_me.id, now())
  on conflict (period) do update set revenue = excluded.revenue, profit = excluded.profit, pool = excluded.pool,
    trip_budget = excluded.trip_budget, entered_by = excluded.entered_by, updated_at = now();
  /* Revenue and profit are filed by name only, so the history an admin
     shares with the rest of management never carries them. */
  if v_was.revenue is distinct from v_rev then v_changed := v_changed || '[{"key":"revenue"}]'::jsonb; end if;
  if v_was.profit is distinct from v_pro then v_changed := v_changed || '[{"key":"profit"}]'::jsonb; end if;
  if v_was.pool is distinct from v_pool then
    v_changed := v_changed || jsonb_build_array(jsonb_build_object('key', 'pool', 'from', v_was.pool, 'to', v_pool));
  end if;
  if v_was.trip_budget is distinct from v_trip then
    v_changed := v_changed || jsonb_build_array(jsonb_build_object('key', 'trip_budget', 'from', v_was.trip_budget, 'to', v_trip));
  end if;
  if jsonb_array_length(v_changed) > 0 then
    perform public.perf_log(null, null, 'company_set', jsonb_build_object('key', v_f::text, 'changed', v_changed));
  end if;
  return public.perf_period(p_token, v_f);
end $$;

create or replace function public.perf_period_confirm(p_token text, p_from date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_f date; v_snap jsonb; v_x jsonb;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_f := public.perf_half(p_from);
  if v_f is null or v_f < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if exists (select 1 from public.perf_rewards where kind = 'period' and period = v_f) then
    return public.perf_period(p_token, v_f);
  end if;
  if public.perf_today() < (v_f + interval '6 months')::date then
    return jsonb_build_object('error', 'period-open');
  end if;
  if not exists (select 1 from public.perf_company where period = v_f) then
    return jsonb_build_object('error', 'figures-needed');
  end if;
  v_snap := public.perf_period_calc(v_f);
  insert into public.perf_rewards (kind, period, snapshot, confirmed_by) values ('period', v_f, v_snap, v_me.id)
  on conflict (kind, period) do nothing;
  perform public.perf_log(null, null, 'period_confirmed', jsonb_build_object('key', v_f::text));
  for v_x in select * from jsonb_array_elements(v_snap -> 'people') loop
    if (v_x ->> 'active')::boolean then
      perform public.perf_notify((v_x ->> 'team_member_id')::uuid, 'perf.period',
        'Your ' || public.perf_period_word(v_f) || ' bonus and trip outcome is ready.',
        'perf.period.' || v_f || '.' || (v_x ->> 'team_member_id') || '.' || extract(epoch from now())::bigint);
    end if;
  end loop;
  return public.perf_period(p_token, v_f);
end $$;

create or replace function public.perf_period_reopen(p_token text, p_from date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_f date; v_rw public.perf_rewards;
begin
  v_err := public.perf_check(p_token, 'manage');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_f := public.perf_half(p_from);
  select * into v_rw from public.perf_rewards where kind = 'period' and period = v_f for update;
  if v_rw.period is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  perform public.perf_log(null, null, 'period_reopened', jsonb_build_object('key', v_f::text, 'was', v_rw.snapshot,
    'confirmed_at', v_rw.confirmed_at));
  delete from public.perf_rewards where kind = 'period' and period = v_f;
  return public.perf_period(p_token, v_f);
end $$;

/* The member's own outcome, as before, with the ranking left out. */
create or replace function public.perf_rewards_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.team_members; v_id text;
begin
  v_me := public.ops_me();
  if v_me.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(v_me.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  v_id := v_me.id::text;
  return jsonb_build_object(
    'quarters', coalesce((
      select jsonb_agg(jsonb_build_object('quarter', rw.period, 'word', rw.snapshot ->> 'word',
               'confirmed_at', rw.confirmed_at, 'me', me_row - 'rank',
               'individual', jsonb_build_object('winners', rw.snapshot -> 'individual' -> 'winners',
                                                'reason', rw.snapshot -> 'individual' -> 'reason'),
               'department', (select jsonb_build_object('department', d ->> 'department', 'total', d -> 'total',
                                       'grade', d -> 'grade', 'won', d -> 'won', 'each', d -> 'each')
                                from jsonb_array_elements(rw.snapshot -> 'departments') d
                               where d -> 'members' ? v_id limit 1))
             order by rw.period desc)
        from public.perf_rewards rw
        cross join lateral (select p as me_row from jsonb_array_elements(rw.snapshot -> 'people') p
                             where p ->> 'team_member_id' = v_id limit 1) mine
       where rw.kind = 'quarter'), '[]'::jsonb),
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object('period', rw.period, 'word', rw.snapshot ->> 'word',
               'confirmed_at', rw.confirmed_at, 'me', me_row,
               'bonus_open', rw.snapshot -> 'bonus' -> 'open', 'trip_open', rw.snapshot -> 'trip' -> 'open')
             order by rw.period desc)
        from public.perf_rewards rw
        cross join lateral (select p as me_row from jsonb_array_elements(rw.snapshot -> 'people') p
                             where p ->> 'team_member_id' = v_id limit 1) mine
       where rw.kind = 'period'), '[]'::jsonb),
    'flex', coalesce((
      select jsonb_agg(jsonb_build_object('period', f.fx ->> 'period', 'month', f.fx ->> 'month',
               'next_month', f.fx ->> 'next_month', 'unlocked', f.fx -> 'unlocked',
               'eligible', (select p -> 'eligible' from jsonb_array_elements(f.fx -> 'people') p
                             where p ->> 'team_member_id' = v_id limit 1))
             order by f.pd desc)
        from (select r.period as pd, public.perf_flex_calc(r.period) as fx
                from public.perf_reviews r
               where r.team_member_id = v_me.id and r.status = 'final') f
       where (f.fx ->> 'decided')::boolean
         and exists (select 1 from jsonb_array_elements(f.fx -> 'people') p where p ->> 'team_member_id' = v_id)), '[]'::jsonb),
    'commissions', coalesce((
      select jsonb_agg(x.j - 'created_by' - 'removed_at' - 'name' - 'staff_code' order by x.mo desc, x.ca desc)
        from (select public.perf_commission_json(c) as j, c.month as mo, c.created_at as ca
                from public.perf_commissions c
               where c.team_member_id = v_me.id and c.removed_at is null) x
       where x.j ->> 'state' <> 'pending'), '[]'::jsonb));
end $$;

/* Who may call what: create or replace keeps each function's grants, and
   these state them again. */
revoke all on function public.perf_quarter_calc(date) from public, anon, authenticated;
revoke all on function public.perf_period_calc(date) from public, anon, authenticated;
revoke all on function public.perf_quarter_confirm(text, date) from public, anon, authenticated;
revoke all on function public.perf_period(text, date) from public, anon, authenticated;
revoke all on function public.perf_company_set(text, date, jsonb) from public, anon, authenticated;
revoke all on function public.perf_period_confirm(text, date) from public, anon, authenticated;
revoke all on function public.perf_period_reopen(text, date) from public, anon, authenticated;
revoke all on function public.perf_rewards_mine() from public, anon, authenticated;
grant execute on function public.perf_quarter_confirm(text, date) to authenticated;
grant execute on function public.perf_period(text, date) to authenticated;
grant execute on function public.perf_company_set(text, date, jsonb) to authenticated;
grant execute on function public.perf_period_confirm(text, date) to authenticated;
grant execute on function public.perf_period_reopen(text, date) to authenticated;
grant execute on function public.perf_rewards_mine() to authenticated;

-- END OF THE QUARTER RANKED --------------------------------------------------
