-- ===========================================================================
-- PERFORMANCE REWARD SETTINGS — every amount, threshold and rate the rewards
-- are worked out with is a setting an admin changes from a quarter on;
-- nothing in the rules is a figure typed into the code.
-- 2026-10-05. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-05: "please do not make the figures hard
-- coded. what if i need changes the next quarter")
--   1. `perf_settings` (key, from_period, value): a value holds from its
--      quarter until a later row for the same key. RLS on, no policy, no
--      grant. The first run seeds each key's value as the rules stood, from
--      Q3 2026, only where the key has no row.
--   2. `perf_setting(key, at)`: the value in force at a date (else the
--      earliest), for the functions alone.
--   3. `perf_quarter_calc`, `perf_flex_calc`, `perf_period_calc`,
--      `perf_period`, `perf_company_set` and `perf_commission_json` read
--      their figures from it, as at the quarter, month, half or deal month,
--      and say which (`rules`), so a confirmed snapshot keeps the figures it
--      was worked out with.
--   4. `perf_rewards_mine` sends each confirmed quarter's and half's rules.
--   5. The individual prize has no minimum average (the user, 2026-10-05):
--      the highest average among the eligible takes it whole (a tie
--      shares it). The department prize stays the winning department's,
--      its leader deciding the split.
--   6. `perf_settings_read(p_token)` (management, a live unlock): every
--      key's rows and the changes filed; `perf_settings_set(p_token,
--      p_from, p_values)` (an admin, a live unlock): from a quarter on, never
--      into a quarter or half already confirmed (`confirmed`), each value in
--      its bounds (`bad-value`); a save that changes nothing files nothing,
--      else `settings_set` with each key from and to.
--
-- ROLLBACK
--   Run the PERFORMANCE REWARDS and PERFORMANCE QUARTER RANKED sections'
--   functions named in 3 again; then, in the SQL Editor, drop
--   perf_settings_set, perf_settings_read, perf_setting and the table.
-- ===========================================================================

create table if not exists public.perf_settings (
  key         text not null,
  from_period date not null check (from_period >= date '2026-07-01'
                                    and extract(day from from_period) = 1 and extract(month from from_period) in (1, 4, 7, 10)),
  value       numeric(14,2) not null,
  set_by      uuid references public.team_members(id) on delete set null,
  set_at      timestamptz not null default now(),
  primary key (key, from_period)
);
alter table public.perf_settings enable row level security;
revoke all on table public.perf_settings from public, anon, authenticated;

-- The rules as they stood, from Q3 2026, into a key that has no row.
insert into public.perf_settings (key, from_period, value)
select k.key, date '2026-07-01', k.value
  from (values ('prize_individual', 400),
               ('prize_department', 600), ('prize_department_min_total', 80),
               ('flex_team_share', 50), ('flex_member_min', 70),
               ('bonus_pool_revenue', 500000), ('bonus_pool_profit_pct', 10), ('trip_revenue', 1000000),
               ('bonus_months_b', 3), ('units_a', 3), ('units_b', 1.5), ('units_c', 0.5),
               ('commission_min', 70)) k(key, value)
 where not exists (select 1 from public.perf_settings s where s.key = k.key);

-- The value in force at a date: the latest row from or before it, else the
-- earliest row (a date before the first quarter).
create or replace function public.perf_setting(p_key text, p_at date)
returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select s.value from public.perf_settings s where s.key = p_key and s.from_period <= p_at
      order by s.from_period desc limit 1),
    (select s.value from public.perf_settings s where s.key = p_key order by s.from_period limit 1))
$$;
revoke all on function public.perf_setting(text, date) from public, anon, authenticated;

create or replace function public.perf_quarter_calc(p_quarter date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q date := date_trunc('quarter', p_quarter)::date;
  v_qe date := (date_trunc('quarter', p_quarter) + interval '3 months')::date;
  v_people jsonb; v_wins integer; v_each numeric; v_ind jsonb;
  v_depts jsonb; v_dwins integer; v_both boolean; v_why text; v_dp jsonb;
  v_open integer; v_missing integer;
  v_ip numeric := public.perf_setting('prize_individual', date_trunc('quarter', p_quarter)::date);
  v_dpool numeric := public.perf_setting('prize_department', date_trunc('quarter', p_quarter)::date);
  v_dmin numeric := public.perf_setting('prize_department_min_total', date_trunc('quarter', p_quarter)::date);
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
           'prize', case when p.won then floor(v_ip * 100 / p.nwon) / 100 else 0 end)
         order by p.mean desc nulls last, p.mname), '[]'::jsonb),
         coalesce(max(p.nwon), 0)
    into v_people, v_wins
    from p;
  v_each := case when v_wins > 0 then floor(v_ip * 100 / v_wins) / 100 end;
  v_ind := jsonb_build_object('pool', v_ip, 'winners', v_wins, 'each', v_each,
    'paid', coalesce(v_each * v_wins, 0), 'remainder', v_ip - coalesce(v_each * v_wins, 0),
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
    select x.*, (x.bothin and x.istop and x.total >= v_dmin and not x.crit) as won,
           coalesce((select array_agg(t.id order by t.name) from public.team_members t
                      where t.active and t.department = x.dep and public.perf_reviewed(t.id)), '{}'::uuid[]) as mems
      from x
  ), z as (
    select y.*, count(*) filter (where y.won) over () as nwon,
           case when y.won then floor((v_dpool * 100) / count(*) filter (where y.won) over ()) end as sharec
      from y
  )
  select jsonb_agg(jsonb_build_object(
           'department', z.dep, 'entered', z.entered,
           'criteria', case when z.entered then jsonb_build_array(z.c1, z.c2, z.c3, z.c4, z.c5) end,
           'total', z.total, 'grade', case when z.entered then public.perf_grade_of(z.total) end,
           'critical', z.crit, 'top', z.bothin and z.istop,
           'qualifies', z.entered and z.total >= v_dmin and not z.crit, 'won', z.won,
           'share', coalesce(z.sharec / 100, 0), 'members', to_jsonb(z.mems))
         order by z.ord),
         coalesce(max(z.nwon), 0), bool_and(z.bothin),
         case when bool_and(z.bothin) and max(z.nwon) = 0 then
           case when bool_or(z.istop and z.total >= v_dmin and z.crit) then 'critical-issue' else 'below-b' end end
    into v_depts, v_dwins, v_both, v_why
    from z;
  v_dp := jsonb_build_object('pool', v_dpool, 'winners', v_dwins,
    'paid', case when v_dwins > 0 then floor((v_dpool * 100) / v_dwins) * v_dwins / 100 else 0 end,
    'remainder', case when v_dwins > 0 then v_dpool - floor((v_dpool * 100) / v_dwins) * v_dwins / 100 else v_dpool end,
    'reason', case when not v_both then 'scores-needed' else v_why end);

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
    'open_months', v_open, 'missing_months', v_missing,
    'rules', jsonb_build_object('individual', v_ip, 'department', v_dpool, 'min_total', v_dmin));
end $$;

create or replace function public.perf_flex_calc(p_period date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p date := date_trunc('month', p_period)::date;
  v_total integer; v_finals integer; v_at integer; v_rows jsonb;
  v_share numeric := public.perf_setting('flex_team_share', date_trunc('month', p_period)::date);
  v_fmin numeric := public.perf_setting('flex_member_min', date_trunc('month', p_period)::date);
begin
  with m as (
    select t.id as mid, t.name as mname, t.staff_code as mcode,
           case when r.id is not null then coalesce(r.result, public.perf_calc(r)) end as res
      from public.team_members t
      left join public.perf_reviews r on r.team_member_id = t.id and r.period = v_p and r.status = 'final'
     where t.active and public.perf_reviewed(t.id)
  )
  select count(*)::int, count(m.res)::int,
         (count(*) filter (where (m.res ->> 'final')::numeric >= v_fmin))::int,
         coalesce(jsonb_agg(jsonb_build_object('team_member_id', m.mid, 'name', m.mname, 'staff_code', m.mcode,
           'final', m.res -> 'final', 'grade', m.res ->> 'grade',
           'breach', coalesce((m.res ->> 'l3')::boolean or (m.res ->> 'l4')::boolean, false),
           'eligible', coalesce((m.res ->> 'final')::numeric >= v_fmin
                                and not (m.res ->> 'l3')::boolean and not (m.res ->> 'l4')::boolean, false))
           order by m.mname), '[]'::jsonb)
    into v_total, v_finals, v_at, v_rows
    from m;
  return jsonb_build_object('period', v_p, 'month', public.perf_month_word(v_p),
    'next', (v_p + interval '1 month')::date,
    'next_month', public.perf_month_word((v_p + interval '1 month')::date),
    'members', v_total, 'finals', v_finals, 'at_70', v_at,
    'decided', v_total > 0 and v_finals = v_total,
    'unlocked', v_total > 0 and v_finals = v_total and v_at * 100 >= v_total * v_share,
    'people', v_rows, 'rules', jsonb_build_object('share', v_share, 'min', v_fmin));
end $$;

create or replace function public.perf_period_calc(p_from date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_f date := public.perf_half(p_from);
  v_t date := (public.perf_half(p_from) + interval '6 months')::date;
  v_c public.perf_company; v_pool numeric; v_trip numeric; v_popen boolean; v_topen boolean;
  v_rows jsonb; v_units numeric; v_bpaid numeric; v_tpaid numeric;
  v_prev numeric := public.perf_setting('bonus_pool_revenue', public.perf_half(p_from));
  v_trev numeric := public.perf_setting('trip_revenue', public.perf_half(p_from));
  v_nb numeric := public.perf_setting('bonus_months_b', public.perf_half(p_from));
  v_ua numeric := public.perf_setting('units_a', public.perf_half(p_from));
  v_ub numeric := public.perf_setting('units_b', public.perf_half(p_from));
  v_uc numeric := public.perf_setting('units_c', public.perf_half(p_from));
begin
  select * into v_c from public.perf_company where period = v_f;
  v_popen := coalesce(v_c.revenue, 0) >= v_prev;
  v_topen := coalesce(v_c.revenue, 0) >= v_trev;
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
             case when m.nmonths > 0 and m.nb < v_nb then 'few-b-months' end,
             case when m.emonth then 'e-month' end,
             case when m.ml4 then 'critical-breach' end,
             case when not m.mactive then 'inactive' end], null) as why
      from m
  ), u as (
    select e.*, cardinality(e.why) = 0 as ok,
           case when cardinality(e.why) = 0 then
             case public.perf_grade_of(e.mean) when 'A' then v_ua when 'B' then v_ub when 'C' then v_uc else 0 end
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
    'rules', jsonb_build_object('pool_revenue', v_prev, 'trip_revenue', v_trev, 'months_b', v_nb,
      'units_a', v_ua, 'units_b', v_ub, 'units_c', v_uc,
      'pool_pct', public.perf_setting('bonus_pool_profit_pct', public.perf_half(p_from))),
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
        'pool', v_c.pool, 'trip_budget', v_c.trip_budget, 'max_pool', greatest(0, floor(v_c.profit * public.perf_setting('bonus_pool_profit_pct', v_f)) / 100)));
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
  v_prev numeric; v_trev numeric; v_pct numeric;
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
  v_prev := public.perf_setting('bonus_pool_revenue', v_f);
  v_trev := public.perf_setting('trip_revenue', v_f);
  v_pct := public.perf_setting('bonus_pool_profit_pct', v_f);
  v_max := greatest(0, floor(v_pro * v_pct) / 100);
  if v_pool > 0 and v_rev < v_prev then return jsonb_build_object('error', 'pool-closed', 'at', v_prev); end if;
  if v_pool > v_max then return jsonb_build_object('error', 'pool-over', 'max', v_max, 'pct', v_pct); end if;
  if v_trip > 0 and v_rev < v_trev then return jsonb_build_object('error', 'trip-closed', 'at', v_trev); end if;
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

create or replace function public.perf_commission_json(c public.perf_commissions)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_r public.perf_reviews; v_res jsonb; v_state text; v_why text;
begin
  select * into v_r from public.perf_reviews where team_member_id = c.team_member_id and period = c.month;
  v_res := case when v_r.id is not null and v_r.status = 'final' then coalesce(v_r.result, public.perf_calc(v_r)) end;
  if v_res is null then
    v_state := 'pending'; v_why := 'month-not-final';
  elsif (v_res ->> 'final')::numeric < public.perf_setting('commission_min', c.month) then
    v_state := 'not-payable'; v_why := 'below-c';
  elsif coalesce((v_res ->> 'l3')::boolean, false) or coalesce((v_res ->> 'l4')::boolean, false) then
    v_state := 'not-payable'; v_why := 'breach';
  else
    v_state := 'payable';
  end if;
  return jsonb_build_object('id', c.id, 'team_member_id', c.team_member_id,
    'name', (select t.name from public.team_members t where t.id = c.team_member_id),
    'staff_code', (select t.staff_code from public.team_members t where t.id = c.team_member_id),
    'client_id', c.client_id,
    'client', (select cl.name from public.clients cl where cl.id = c.client_id),
    'client_code', (select cl.client_code from public.clients cl where cl.id = c.client_id),
    'description', c.description, 'month', c.month, 'month_word', public.perf_month_word(c.month),
    'net_profit', c.net_profit, 'pct', c.pct, 'amount', round(c.net_profit * c.pct / 100, 2),
    'state', v_state, 'reason', v_why, 'created_at', c.created_at,
    'created_by', (select t.name from public.team_members t where t.id = c.created_by),
    'removed_at', c.removed_at, 'min', public.perf_setting('commission_min', c.month));
end $$;

/* The member reads the rules their own quarter and half were worked out with. */
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
               'confirmed_at', rw.confirmed_at, 'me', me_row - 'rank', 'rules', rw.snapshot -> 'rules',
               'individual', jsonb_build_object('winners', rw.snapshot -> 'individual' -> 'winners',
                                                'reason', rw.snapshot -> 'individual' -> 'reason'),
               'department', (select jsonb_build_object('department', d ->> 'department', 'total', d -> 'total',
                                       'grade', d -> 'grade', 'won', d -> 'won', 'share', d -> 'share')
                                from jsonb_array_elements(rw.snapshot -> 'departments') d
                               where d -> 'members' ? v_id limit 1))
             order by rw.period desc)
        from public.perf_rewards rw
        cross join lateral (select p as me_row from jsonb_array_elements(rw.snapshot -> 'people') p
                             where p ->> 'team_member_id' = v_id limit 1) mine
       where rw.kind = 'quarter'), '[]'::jsonb),
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object('period', rw.period, 'word', rw.snapshot ->> 'word',
               'confirmed_at', rw.confirmed_at, 'me', me_row, 'rules', rw.snapshot -> 'rules',
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

-- Every key's values by quarter, and the changes filed, for management.
create or replace function public.perf_settings_read(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text;
begin
  v_err := public.perf_check(p_token, 'view');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  return jsonb_build_object(
    'admin', public.perf_is_admin(),
    'settings', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'from', s.from_period,
        'word', public.perf_quarter_word(s.from_period), 'value', s.value,
        'by', (select t.name from public.team_members t where t.id = s.set_by), 'at', s.set_at)
        order by s.key, s.from_period) from public.perf_settings s), '[]'::jsonb),
    'confirmed', jsonb_build_object(
      'quarter', (select max(r.period) from public.perf_rewards r where r.kind = 'quarter'),
      'period', (select max(r.period) from public.perf_rewards r where r.kind = 'period')),
    'events', public.perf_reward_events(array['settings_set'], null));
end $$;

-- From a quarter on, an admin's. A quarter or a half already confirmed keeps
-- its figures: a change never reaches into one.
create or replace function public.perf_settings_set(p_token text, p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err text; v_me public.team_members; v_from date; v_k text; v_v numeric; v_was numeric;
  v_changed jsonb := '[]'::jsonb;
  v_keys constant text[] := array['prize_individual', 'prize_department', 'prize_department_min_total',
    'flex_team_share', 'flex_member_min', 'bonus_pool_revenue',
    'bonus_pool_profit_pct', 'trip_revenue', 'bonus_months_b', 'units_a', 'units_b', 'units_c', 'commission_min'];
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  if not public.perf_is_admin() then return jsonb_build_object('error', 'admin-only'); end if;
  v_me := public.ops_me();
  v_from := date_trunc('quarter', p_from)::date;
  if v_from is null or v_from < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  if exists (select 1 from public.perf_rewards r
              where (r.kind = 'quarter' and r.period >= v_from)
                 or (r.kind = 'period' and (r.period + interval '6 months')::date > v_from)) then
    return jsonb_build_object('error', 'confirmed');
  end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if v_v < 0 or round(v_v, 2) <> v_v
       or (v_k in ('prize_individual', 'prize_department', 'bonus_pool_revenue', 'trip_revenue') and v_v >= 1e9)
       or (v_k in ('prize_department_min_total', 'flex_team_share', 'flex_member_min',
                   'bonus_pool_profit_pct', 'commission_min') and v_v > 100)
       or (v_k = 'bonus_months_b' and (v_v > 6 or v_v <> trunc(v_v)))
       or (v_k in ('units_a', 'units_b', 'units_c') and v_v > 10) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.perf_setting(v_k, v_from);
    if v_was is distinct from v_v then
      insert into public.perf_settings (key, from_period, value, set_by, set_at)
      values (v_k, v_from, v_v, v_me.id, now())
      on conflict (key, from_period) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_changed := v_changed || jsonb_build_array(jsonb_build_object('key', v_k, 'from', v_was, 'to', v_v));
    end if;
  end loop;
  if jsonb_array_length(v_changed) > 0 then
    perform public.perf_log(null, null, 'settings_set', jsonb_build_object('from_period', v_from,
      'word', public.perf_quarter_word(v_from), 'changed', v_changed));
  end if;
  return public.perf_settings_read(p_token);
end $$;

revoke all on function public.perf_settings_read(text) from public, anon, authenticated;
revoke all on function public.perf_settings_set(text, date, jsonb) from public, anon, authenticated;
grant execute on function public.perf_settings_read(text) to authenticated;
grant execute on function public.perf_settings_set(text, date, jsonb) to authenticated;

-- END OF PERFORMANCE REWARD SETTINGS ------------------------------------------
