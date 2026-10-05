-- ===========================================================================
-- PERFORMANCE QUARTER LIVE — the quarter is ranked as its months are
-- released, not only once all three are final.
-- 2026-10-05. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-05: "since i have alr added Q3 (july and
-- august 2026) data ... could alr started just that it is not final until
-- the full three months per quarter has alr updated ... management would be
-- able to view it the realtime sequence")
--   1. `perf_quarter_calc` averages, ranks and names the leader from every
--      month released to its member (any state but draft), not from final
--      months alone. Each row says how many of its months are final
--      (`finals`); a person with no released month reads `no-month`.
--   2. The quarter says `provisional` while it runs, a month is not final,
--      or an ended month was never entered. Confirm is unchanged: it still
--      waits for every month to be final, so a confirmed quarter is never
--      provisional.
--
-- ROLLBACK
--   Run the PERFORMANCE REWARD SETTINGS section's perf_quarter_calc again.
-- ===========================================================================

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
    'ended', v_ended, 'provisional', not v_ended or v_open > 0 or v_missing > 0,
    'people', v_people, 'individual', v_ind,
    'departments', v_depts, 'department_prize', v_dp,
    'open_months', v_open, 'missing_months', v_missing,
    'rules', jsonb_build_object('individual', v_ip, 'department', v_dpool, 'min_total', v_dmin));
end $$;

revoke all on function public.perf_quarter_calc(date) from public, anon, authenticated;
