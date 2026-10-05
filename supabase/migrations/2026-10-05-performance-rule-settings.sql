-- ===========================================================================
-- PERFORMANCE RULE SETTINGS — the grade bands, the breach deductions and
-- their cap, and the dispute window are settings an admin changes from a
-- quarter on, beside the reward figures.
-- 2026-10-05. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-05: the grade bands, breach deductions
-- and the dispute window made editable, as the reward figures are)
--   1. `perf_settings` gains, from Q3 2026 where the key has no row:
--      grade_a 90, grade_b 80, grade_c 70, grade_d 60 (the least score for
--      each grade); ded_l1 3, ded_l2 7, ded_l3 15, ded_l4 30, ded_repeat 5,
--      ded_late 5 (points taken); ded_cap 35; dispute_days 7.
--   2. `perf_grade_at(score, at)` and `perf_deduction_at(severity,
--      repeated, late, at)` read them as at a month; `perf_grade_of` and
--      `perf_deduction` read them as at today.
--   3. `perf_calc` grades and caps a month by its own quarter's settings
--      and says the cap and the points by level it used (`cap`, `points`);
--      a final month keeps its result.
--   4. The quarter and the half grade averages by their own settings; the
--      quarter says its grade bands (`rules.grades`).
--   5. `perf_release` opens the dispute window the month's setting names.
--   6. `perf_settings_set` takes the new keys, in bounds, and keeps the
--      bands in order (`bad-order`).
--
-- ROLLBACK
--   Run the PERFORMANCE section's perf_grade_of, perf_deduction and
--   perf_calc, the DATE OF EVALUATION section's perf_release and the
--   PERFORMANCE REWARD SETTINGS section and the PERFORMANCE QUARTER LIVE
--   section again; then, in the SQL Editor, drop perf_grade_at and
--   perf_deduction_at.
-- ===========================================================================

insert into public.perf_settings (key, from_period, value)
select k.key, date '2026-07-01', k.value
  from (values ('grade_a', 90), ('grade_b', 80), ('grade_c', 70), ('grade_d', 60),
               ('ded_l1', 3), ('ded_l2', 7), ('ded_l3', 15), ('ded_l4', 30),
               ('ded_repeat', 5), ('ded_late', 5), ('ded_cap', 35), ('dispute_days', 7)) k(key, value)
 where not exists (select 1 from public.perf_settings s where s.key = k.key);

create or replace function public.perf_grade_at(p_score numeric, p_at date)
returns text
language sql stable security definer set search_path = public as $$
  select case when p_score >= public.perf_setting('grade_a', p_at) then 'A'
              when p_score >= public.perf_setting('grade_b', p_at) then 'B'
              when p_score >= public.perf_setting('grade_c', p_at) then 'C'
              when p_score >= public.perf_setting('grade_d', p_at) then 'D' else 'E' end
$$;
create or replace function public.perf_grade_of(p_score numeric)
returns text
language sql stable security definer set search_path = public as $$
  select public.perf_grade_at(p_score, public.perf_today())
$$;
create or replace function public.perf_deduction_at(p_severity integer, p_repeated boolean, p_late boolean, p_at date)
returns integer
language sql stable security definer set search_path = public as $$
  select (- coalesce(case p_severity when 1 then public.perf_setting('ded_l1', p_at) when 2 then public.perf_setting('ded_l2', p_at)
                                    when 3 then public.perf_setting('ded_l3', p_at) when 4 then public.perf_setting('ded_l4', p_at) end, 0)
          - case when p_repeated then public.perf_setting('ded_repeat', p_at) else 0 end
          - case when p_late then public.perf_setting('ded_late', p_at) else 0 end)::integer
$$;
create or replace function public.perf_deduction(p_severity integer, p_repeated boolean, p_late boolean)
returns integer
language sql stable security definer set search_path = public as $$
  select public.perf_deduction_at(p_severity, p_repeated, p_late, public.perf_today())
$$;
revoke all on function public.perf_grade_at(numeric, date) from public, anon, authenticated;
revoke all on function public.perf_grade_of(numeric) from public, anon, authenticated;
revoke all on function public.perf_deduction_at(integer, boolean, boolean, date) from public, anon, authenticated;
revoke all on function public.perf_deduction(integer, boolean, boolean) from public, anon, authenticated;

create or replace function public.perf_calc(r public.perf_reviews)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  base numeric; raw_ded integer; ded integer; fin numeric; l3 boolean; l4 boolean;
  g text; cap integer; rk integer; prev public.perf_reviews; prev_g text; ok boolean;
  complete boolean; path text; ads boolean; bd text; bc text; bm text;
  rank_of constant text := 'ABCDE';
  v_cap numeric;
begin
  if r.status = 'final' and r.result is not null then return r.result; end if;
  complete := r.s_output is not null and r.s_accuracy is not null and r.s_delivery is not null
          and r.s_client is not null and r.s_comms is not null and r.s_initiative is not null;
  base := coalesce(r.s_output, 0) + coalesce(r.s_accuracy, 0) + coalesce(r.s_delivery, 0)
        + coalesce(r.s_client, 0) + coalesce(r.s_comms, 0) + coalesce(r.s_initiative, 0);
  select coalesce(sum(public.perf_deduction_at(severity, repeated, late, r.period)), 0),
         coalesce(bool_or(severity = 3), false), coalesce(bool_or(severity = 4), false)
    into raw_ded, l3, l4
    from public.perf_breaches
   where team_member_id = r.team_member_id and period = r.period and voided_at is null;
  v_cap := public.perf_setting('ded_cap', r.period);
  ded := greatest(raw_ded, -v_cap::integer);
  fin := greatest(0, least(100, base + ded));
  g := public.perf_grade_at(fin, r.period);
  cap := case when l4 then 4 when l3 then 2 else 0 end;
  rk := greatest(position(g in rank_of), cap);
  g := substr(rank_of, rk, 1);

  select * into prev from public.perf_reviews
   where team_member_id = r.team_member_id and period = (r.period - interval '1 month')::date
     and status <> 'draft';
  if prev.id is not null then
    prev_g := (public.perf_calc(prev)) ->> 'grade';
  end if;
  ok := (g in ('A', 'B') or (g = 'C' and prev_g is distinct from 'C')) and not l3 and not l4;
  path := case when g = 'E' or l3 or l4 then 'accountability' when g = 'D' then 'development' end;

  ads := coalesce((select runs_ads from public.perf_people where team_member_id = r.team_member_id), false);
  bd := (select b from unnest(array[public.perf_band(r.r_posting, 95), public.perf_band(r.r_timeline, 90)]) b
          where b is not null order by position(b in 'green amber red') desc limit 1);
  bc := (select b from unnest(array[public.perf_band(r.r_satisfaction, 90),
                                    case when ads then public.perf_pacing_band(r.r_pacing) end]) b
          where b is not null order by position(b in 'green amber red') desc limit 1);
  bm := public.perf_band(r.r_sla, 90);

  return jsonb_build_object(
    'complete', complete, 'base', base, 'deduction', ded, 'deduction_raw', raw_ded,
    'final', fin, 'cap', v_cap,
    'points', jsonb_build_object('1', public.perf_setting('ded_l1', r.period), '2', public.perf_setting('ded_l2', r.period),
                                 '3', public.perf_setting('ded_l3', r.period), '4', public.perf_setting('ded_l4', r.period),
                                 'repeat', public.perf_setting('ded_repeat', r.period), 'late', public.perf_setting('ded_late', r.period)),
    'raw_grade', public.perf_grade_at(fin, r.period), 'grade', g,
    'grade_word', public.perf_grade_word(g),
    'capped', case when rk > position(public.perf_grade_at(fin, r.period) in rank_of) then (case when l4 then 'D' else 'B' end) end,
    'l3', l3, 'l4', l4, 'review', l4,
    'eligible', ok, 'previous_grade', prev_g,
    'path', path,
    'suggested', jsonb_build_object(
      'delivery', case bd when 'green' then 15 when 'amber' then 12 when 'red' then 7.5 end,
      'delivery_band', bd,
      'client', case bc when 'green' then 20 when 'amber' then 16 when 'red' then 10 end,
      'client_band', bc,
      'comms', case bm when 'green' then 15 when 'amber' then 12 when 'red' then 7.5 end,
      'comms_band', bm));
end $$;

create or replace function public.perf_quarter_calc(p_quarter date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q date := date_trunc('quarter', p_quarter)::date;
  v_qe date := (date_trunc('quarter', p_quarter) + interval '3 months')::date;
  v_people jsonb; v_wins integer; v_each numeric; v_ind jsonb;
  v_depts jsonb; v_dwins integer; v_both boolean; v_why text; v_dp jsonb;
  v_open integer; v_missing integer; v_ended boolean := public.perf_today() >= (date_trunc('quarter', p_quarter) + interval '3 months')::date;
  v_ip numeric := public.perf_setting('prize_individual', date_trunc('quarter', p_quarter)::date);
  v_dpool numeric := public.perf_setting('prize_department', date_trunc('quarter', p_quarter)::date);
  v_dmin numeric := public.perf_setting('prize_department_min_total', date_trunc('quarter', p_quarter)::date);
begin
  with m as (
    select t.id as mid, t.name as mname, t.staff_code as mcode, t.department as mdept, t.active as mactive,
           public.perf_reviewed(t.id) as monlist, f.nmonths, f.nfinal, f.mean, f.emonth,
           (select count(*)::int from public.perf_reviews o
             where o.team_member_id = t.id and o.status <> 'final'
               and o.period >= v_q and o.period < v_qe) as nopen,
           exists (select 1 from public.perf_breaches b
                    where b.team_member_id = t.id and b.voided_at is null and b.severity = 4
                      and b.period >= v_q and b.period < v_qe) as ml4
      from public.team_members t
      cross join lateral (
        select count(*)::int as nmonths, (count(*) filter (where x.st = 'final'))::int as nfinal,
               round(avg((x.res ->> 'final')::numeric), 2) as mean,
               coalesce(bool_or(x.res ->> 'grade' = 'E'), false) as emonth
          from (select coalesce(r.result, public.perf_calc(r)) as res, r.status as st
                  from public.perf_reviews r
                 where r.team_member_id = t.id and r.status <> 'draft'
                   and r.period >= v_q and r.period < v_qe) x) f
     where f.nmonths > 0 or (t.active and public.perf_reviewed(t.id))
  ), e as (
    select m.*, array_remove(array[
             case when m.nmonths = 0 then 'no-month' end,
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
           'active', p.mactive, 'reviewed', p.monlist, 'months', p.nmonths, 'finals', p.nfinal, 'open', p.nopen,
           'rank', p.mrank, 'average', p.mean,
           'grade', case when p.nmonths > 0 then public.perf_grade_at(p.mean, v_q) end,
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
           'total', z.total, 'grade', case when z.entered then public.perf_grade_at(z.total, v_q) end,
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
    'ended', v_ended, 'provisional', not v_ended or v_open > 0 or v_missing > 0,
    'people', v_people, 'individual', v_ind,
    'departments', v_depts, 'department_prize', v_dp,
    'open_months', v_open, 'missing_months', v_missing,
    'rules', jsonb_build_object('individual', v_ip, 'department', v_dpool, 'min_total', v_dmin,
      'grades', jsonb_build_object('A', public.perf_setting('grade_a', v_q), 'B', public.perf_setting('grade_b', v_q),
                                   'C', public.perf_setting('grade_c', v_q), 'D', public.perf_setting('grade_d', v_q))));
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
             case public.perf_grade_at(e.mean, v_f) when 'A' then v_ua when 'B' then v_ub when 'C' then v_uc else 0 end
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
           'grade', case when o.nmonths > 0 then public.perf_grade_at(o.mean, v_f) end,
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

create or replace function public.perf_release(p_token text, p_review uuid, p_rev integer, p_notify boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; tm public.team_members;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  if not (public.perf_calc(r) ->> 'complete')::boolean then
    return jsonb_build_object('error', 'incomplete');
  end if;
  select * into tm from public.team_members where id = r.team_member_id;
  if r.serial is null and coalesce(btrim(tm.staff_code), '') = '' then
    return jsonb_build_object('error', 'no-staff-code');
  end if;
  update public.perf_reviews set status = 'released', released_at = now(),
         dispute_until = now() + make_interval(days => public.perf_setting('dispute_days', r.period)::integer), reviewer_id = m.id,
         evaluated_on = coalesce(evaluated_on, (now() at time zone 'Asia/Kuala_Lumpur')::date),
         serial = coalesce(serial, 'ADHR/' || upper(btrim(tm.staff_code)) || '/PR' || to_char(period, 'YYMM')),
         rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'released',
    jsonb_build_object('version', r.version, 'notified', coalesce(p_notify, true)));
  if coalesce(p_notify, true) then
    perform public.perf_notify(r.team_member_id, 'perf.released',
      'Your ' || public.perf_month_word(r.period) || ' performance review is ready.',
      'perf.released.' || r.id || '.' || r.version);
  end if;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_settings_set(p_token text, p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err text; v_me public.team_members; v_from date; v_k text; v_v numeric; v_was numeric;
  v_changed jsonb := '[]'::jsonb;
  v_keys constant text[] := array['prize_individual', 'prize_department', 'prize_department_min_total',
    'flex_team_share', 'flex_member_min', 'bonus_pool_revenue',
    'bonus_pool_profit_pct', 'trip_revenue', 'bonus_months_b', 'units_a', 'units_b', 'units_c', 'commission_min',
    'grade_a', 'grade_b', 'grade_c', 'grade_d', 'ded_l1', 'ded_l2', 'ded_l3', 'ded_l4', 'ded_repeat', 'ded_late',
    'ded_cap', 'dispute_days'];
  v_a numeric; v_b numeric; v_c numeric; v_d numeric;
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
                   'bonus_pool_profit_pct', 'commission_min', 'grade_a', 'grade_b', 'grade_c', 'grade_d',
                   'ded_l1', 'ded_l2', 'ded_l3', 'ded_l4', 'ded_repeat', 'ded_late', 'ded_cap') and v_v > 100)
       or (v_k = 'dispute_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'bonus_months_b' and (v_v > 6 or v_v <> trunc(v_v)))
       or (v_k in ('units_a', 'units_b', 'units_c') and v_v > 10) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  -- The grade bands stay in order from the quarter on: A above B above C above D.
  v_a := coalesce((p_values ->> 'grade_a')::numeric, public.perf_setting('grade_a', v_from));
  v_b := coalesce((p_values ->> 'grade_b')::numeric, public.perf_setting('grade_b', v_from));
  v_c := coalesce((p_values ->> 'grade_c')::numeric, public.perf_setting('grade_c', v_from));
  v_d := coalesce((p_values ->> 'grade_d')::numeric, public.perf_setting('grade_d', v_from));
  if not (v_a > v_b and v_b > v_c and v_c > v_d and v_d > 0) then
    return jsonb_build_object('error', 'bad-order');
  end if;
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

revoke all on function public.perf_release(text, uuid, integer, boolean) from public, anon, authenticated;
grant execute on function public.perf_release(text, uuid, integer, boolean) to authenticated;
revoke all on function public.perf_settings_set(text, date, jsonb) from public, anon, authenticated;
grant execute on function public.perf_settings_set(text, date, jsonb) to authenticated;

-- END OF PERFORMANCE RULE SETTINGS -------------------------------------------
