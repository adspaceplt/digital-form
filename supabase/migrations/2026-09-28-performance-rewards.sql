-- ===========================================================================
-- PERFORMANCE REWARDS — the quarter and its two prizes, flexible hours, the
-- bonus pool and the company trip, and growth commission, each worked out
-- from finalised months.
-- 2026-09-28. Safe to run twice. Run after
-- 2026-09-26-performance-records-trail-and-check.sql. Rollback at the foot of
-- this header. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/perf.js compares the two.
--
-- THE RULES, confirmed by the user on 2026-09-27. Grades read the monthly
-- bands (A 90 and over, B 80, C 70, D 60, E under 60).
--  1. A quarter is a calendar quarter; the first is Q3 2026. A member's
--     quarterly average is the mean of their FINALISED monthly final scores
--     in it, graded on the same bands.
--  2. Individual prize, RM 400 a quarter: the highest average among the
--     eligible takes it, a tie splits it. Eligible: an average of 70 or more,
--     no E month, no Level 4 breach in the quarter, active, on the review
--     list. Nobody eligible is no payout, said so.
--  3. Department prize, RM 600 a quarter: management enters each
--     department's five criteria and a tick for an unresolved critical
--     issue. The higher total wins if it is 80 or more with no critical
--     issue, else nobody. Tied departments are joint winners and a winner
--     that does not qualify drops out, so a tie with both qualifying splits
--     the pool and a tie with one qualifying pays that one the whole pool.
--     A winning share is split equally among the department's active
--     members on the review list.
--  4. Flexible hours: a month unlocks the next month once every active
--     member on the review list has a final review of it and 50% or more of
--     them scored 70 or more. A member may use it where their own month is
--     70 or more with no Level 3 or 4 breach.
--  5. Bonus pool and company trip, over two quarters (a period, named by its
--     first quarter): revenue and profit are entered by an admin and read by
--     nobody else. The pool opens at RM 500,000 revenue and is at most 10%
--     of profit, set by the admin, never more. The trip opens at
--     RM 1,000,000 with a budget the admin sets. A member qualifies with 3 or
--     more months at B or better in the six, no E month, no Level 4 breach,
--     active. Units from the grade of their six-month average: A 3.0, B 1.5,
--     C 0.5, D and E none. Each share is units over all units times the
--     amount.
--  6. Growth commission: management enters each deal (the member, the client
--     if any, a description, the month invoiced, the net profit, the rate).
--     Payable only where that month is final at 70 or more with no Level 3 or
--     4 breach; otherwise it is recorded as not payable, with the reason, or
--     pending while the month is not final. The amount is net profit times
--     the rate, to the cent.
--  Money is divided in cents: each share is rounded down to the cent and
--  what the rounding leaves is stated as the remainder, never lost.
--
-- WHO READS WHAT. Every table below has row level security on and no policy.
-- Management functions ask `team.performance` and a live master-code unlock
-- (perf_check), the same two locks as a month. Revenue and profit are read
-- and written only by an admin (perf_is_admin); the rest of management sees
-- the amounts and never the figures behind them. The caller's own row is sent
-- with its name alone. A member reads their own confirmed quarters and
-- periods, their flexible hours once a month is decided and their
-- commissions once the month is final, through perf_rewards_mine(), behind
-- the same fresh code as My performance.
--
-- CONFIRM AND REOPEN. A quarter's or a period's outcome is worked out on every
-- read. Confirm keeps a snapshot (perf_rewards), which is what the member
-- reads; Reopen removes it, files the snapshot in the history and never
-- asks. Every entry, confirmation and reopening is filed in perf_events;
-- no notification carries a score or an amount.
--
-- ROLLBACK
--   drop function if exists public.perf_rewards_mine(), public.perf_commission_restore(text, uuid),
--     public.perf_commission_remove(text, uuid), public.perf_commission_add(text, jsonb),
--     public.perf_commissions(text), public.perf_period_reopen(text, date),
--     public.perf_period_confirm(text, date), public.perf_company_set(text, date, jsonb),
--     public.perf_period(text, date), public.perf_flex(text, date),
--     public.perf_quarter_reopen(text, date), public.perf_quarter_confirm(text, date),
--     public.perf_dept_save(text, date, text, jsonb), public.perf_quarter(text, date),
--     public.perf_reward_events(text[], text), public.perf_hide_own(jsonb, uuid),
--     public.perf_commission_json(public.perf_commissions), public.perf_period_calc(date),
--     public.perf_flex_calc(date), public.perf_quarter_calc(date), public.perf_is_admin(),
--     public.perf_period_word(date), public.perf_quarter_word(date), public.perf_today() cascade;
--   drop table if exists public.perf_commissions, public.perf_company, public.perf_rewards,
--     public.perf_dept_scores cascade;
-- ===========================================================================

-- 1. The record -----------------------------------------------------------------------
/* What management enters for a department's quarter: the five criteria in
   the framework's order, each out of its own maximum, and the tick. */
create table if not exists public.perf_dept_scores (
  quarter     date not null check (quarter >= date '2026-07-01'
                                   and extract(day from quarter) = 1 and extract(month from quarter) in (1, 4, 7, 10)),
  department  text not null check (department in ('creative', 'marketing')),
  c1          numeric(4,1) not null check (c1 between 0 and 25),
  c2          numeric(4,1) not null check (c2 between 0 and 25),
  c3          numeric(4,1) not null check (c3 between 0 and 20),
  c4          numeric(4,1) not null check (c4 between 0 and 15),
  c5          numeric(4,1) not null check (c5 between 0 and 15),
  critical    boolean not null default false,
  entered_by  uuid references public.team_members(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (quarter, department)
);

/* A confirmed quarter or period: the outcome as it was worked out at the
   press. The row's absence is the way back. */
create table if not exists public.perf_rewards (
  kind          text not null check (kind in ('quarter', 'period')),
  period        date not null,
  snapshot      jsonb not null,
  confirmed_by  uuid references public.team_members(id) on delete set null,
  confirmed_at  timestamptz not null default now(),
  primary key (kind, period)
);

/* The company's figures for a period of two quarters, named by the first.
   Read and written by an admin alone. */
create table if not exists public.perf_company (
  period       date primary key check (period >= date '2026-07-01'
                                       and extract(day from period) = 1 and extract(month from period) in (1, 4, 7, 10)),
  revenue      numeric(14,2) not null check (revenue >= 0),
  profit       numeric(14,2) not null,
  pool         numeric(14,2) not null default 0 check (pool >= 0),
  trip_budget  numeric(14,2) not null default 0 check (trip_budget >= 0),
  entered_by   uuid references public.team_members(id) on delete set null,
  updated_at   timestamptz not null default now()
);

create table if not exists public.perf_commissions (
  id              uuid primary key default gen_random_uuid(),
  team_member_id  uuid not null references public.team_members(id) on delete cascade,
  client_id       uuid references public.clients(id) on delete set null,
  description     text not null,
  month           date not null check (extract(day from month) = 1),
  net_profit      numeric(14,2) not null check (net_profit >= 0),
  pct             numeric(5,2) not null check (pct > 0 and pct <= 100),
  created_by      uuid references public.team_members(id) on delete set null,
  created_at      timestamptz not null default now(),
  removed_at      timestamptz,
  removed_by      uuid references public.team_members(id) on delete set null
);
create index if not exists perf_commissions_member_idx on public.perf_commissions(team_member_id, month);

-- 2. Nobody reads a table directly -------------------------------------------------
alter table public.perf_dept_scores enable row level security;
alter table public.perf_rewards enable row level security;
alter table public.perf_company enable row level security;
alter table public.perf_commissions enable row level security;
revoke all on public.perf_dept_scores, public.perf_rewards, public.perf_company, public.perf_commissions
  from anon, authenticated;
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies
            where schemaname = 'public'
              and tablename in ('perf_dept_scores', 'perf_rewards', 'perf_company', 'perf_commissions') loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- 3. The rules, stated once ----------------------------------------------------------
/* Today, in one place, so every "has it ended" asks the same clock. */
create or replace function public.perf_today()
returns date language sql stable as $$
  select current_date
$$;
create or replace function public.perf_quarter_word(p_quarter date)
returns text language sql immutable as $$
  select 'Q' || extract(quarter from p_quarter)::int || ' ' || extract(year from p_quarter)::int
$$;
/* Two quarters, named without a dash: "Q3 and Q4 2026", "Q4 2026 and Q1 2027". */
create or replace function public.perf_period_word(p_from date)
returns text language sql immutable as $$
  select case when extract(year from p_from) = extract(year from (p_from + interval '3 months'))
              then 'Q' || extract(quarter from p_from)::int || ' and Q'
                   || extract(quarter from (p_from + interval '3 months'))::int || ' ' || extract(year from p_from)::int
              else public.perf_quarter_word(p_from) || ' and '
                   || public.perf_quarter_word((p_from + interval '3 months')::date) end
$$;
create or replace function public.perf_is_admin()
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_me public.team_members;
begin
  v_me := public.ops_me();
  return v_me.id is not null and (coalesce(v_me.is_admin, false) or v_me.role = 'admin');
end $$;

/* The quarter, worked out: every person with a final month in it or on the
   review list, their average and why they are or are not eligible, the
   individual prize, and the department prize. Never stored except by
   Confirm. */
create or replace function public.perf_quarter_calc(p_quarter date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q date := date_trunc('quarter', p_quarter)::date;
  v_qe date := (date_trunc('quarter', p_quarter) + interval '3 months')::date;
  v_people jsonb; v_wins integer; v_each numeric; v_ind jsonb;
  v_depts jsonb; v_dwins integer; v_both boolean; v_why text; v_dp jsonb;
begin
  with m as (
    select t.id as mid, t.name as mname, t.staff_code as mcode, t.department as mdept, t.active as mactive,
           public.perf_reviewed(t.id) as monlist, f.nmonths, f.mean, f.emonth,
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
    select w.*, count(*) filter (where w.won) over () as nwon from w
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'team_member_id', p.mid, 'name', p.mname, 'staff_code', p.mcode, 'department', p.mdept,
           'active', p.mactive, 'reviewed', p.monlist, 'months', p.nmonths, 'average', p.mean,
           'grade', case when p.nmonths > 0 then public.perf_grade_of(p.mean) end,
           'e_month', p.emonth, 'l4', p.ml4, 'eligible', p.ok, 'reasons', to_jsonb(p.why),
           'prize', case when p.won then floor(40000.0 / p.nwon) / 100 else 0 end)
         order by p.ok desc, p.mean desc nulls last, p.mname), '[]'::jsonb),
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

  return jsonb_build_object('quarter', v_q, 'word', public.perf_quarter_word(v_q),
    'ended', public.perf_today() >= v_qe, 'people', v_people, 'individual', v_ind,
    'departments', v_depts, 'department_prize', v_dp);
end $$;

/* One month's flexible hours: the month decides the next once every active
   member on the review list is final, and unlocks it at half or more at 70
   or over. Each person's own filter beside it. */
create or replace function public.perf_flex_calc(p_period date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p date := date_trunc('month', p_period)::date;
  v_total integer; v_finals integer; v_at integer; v_rows jsonb;
begin
  with m as (
    select t.id as mid, t.name as mname, t.staff_code as mcode,
           case when r.id is not null then coalesce(r.result, public.perf_calc(r)) end as res
      from public.team_members t
      left join public.perf_reviews r on r.team_member_id = t.id and r.period = v_p and r.status = 'final'
     where t.active and public.perf_reviewed(t.id)
  )
  select count(*)::int, count(m.res)::int,
         (count(*) filter (where (m.res ->> 'final')::numeric >= 70))::int,
         coalesce(jsonb_agg(jsonb_build_object('team_member_id', m.mid, 'name', m.mname, 'staff_code', m.mcode,
           'final', m.res -> 'final', 'grade', m.res ->> 'grade',
           'breach', coalesce((m.res ->> 'l3')::boolean or (m.res ->> 'l4')::boolean, false),
           'eligible', coalesce((m.res ->> 'final')::numeric >= 70
                                and not (m.res ->> 'l3')::boolean and not (m.res ->> 'l4')::boolean, false))
           order by m.mname), '[]'::jsonb)
    into v_total, v_finals, v_at, v_rows
    from m;
  return jsonb_build_object('period', v_p, 'month', public.perf_month_word(v_p),
    'next', (v_p + interval '1 month')::date,
    'next_month', public.perf_month_word((v_p + interval '1 month')::date),
    'members', v_total, 'finals', v_finals, 'at_70', v_at,
    'decided', v_total > 0 and v_finals = v_total,
    'unlocked', v_total > 0 and v_finals = v_total and v_at * 2 >= v_total,
    'people', v_rows);
end $$;

/* A period of two quarters: who qualifies, their units, and their share of
   the bonus pool and of the trip. Revenue and profit never leave this
   function; only whether each gate opened and the amounts set. */
create or replace function public.perf_period_calc(p_from date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_f date := date_trunc('quarter', p_from)::date;
  v_t date := (date_trunc('quarter', p_from) + interval '6 months')::date;
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

/* One commission, read against the month it was invoiced in. */
create or replace function public.perf_commission_json(c public.perf_commissions)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_r public.perf_reviews; v_res jsonb; v_state text; v_why text;
begin
  select * into v_r from public.perf_reviews where team_member_id = c.team_member_id and period = c.month;
  v_res := case when v_r.id is not null and v_r.status = 'final' then coalesce(v_r.result, public.perf_calc(v_r)) end;
  if v_res is null then
    v_state := 'pending'; v_why := 'month-not-final';
  elsif (v_res ->> 'final')::numeric < 70 then
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
    'removed_at', c.removed_at);
end $$;

/* The caller's own row goes to management with its name alone: their own
   outcome is theirs to read in My performance. */
create or replace function public.perf_hide_own(p_rows jsonb, p_me uuid)
returns jsonb
language sql immutable as $$
  select coalesce(jsonb_agg(case when x ->> 'team_member_id' = p_me::text
                                 then jsonb_build_object('team_member_id', x -> 'team_member_id',
                                        'name', x -> 'name', 'staff_code', x -> 'staff_code', 'own', true)
                                 else x end order by n), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) with ordinality as a(x, n)
$$;

/* The history of a quarter, a period or the commissions: what was entered,
   confirmed and reopened, by whom and when. */
create or replace function public.perf_reward_events(p_kinds text[], p_key text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', e.kind, 'detail', e.detail - 'was', 'at', e.created_at,
           'by', coalesce(t.name, e.actor_email)) order by e.created_at desc), '[]'::jsonb)
    from (select * from public.perf_events pe
           where pe.kind = any(p_kinds) and (p_key is null or pe.detail ->> 'key' = p_key)
           order by pe.created_at desc limit 30) e
    left join public.team_members t on t.id = e.actor_id
$$;

-- 4. Management: the quarter -----------------------------------------------------------
create or replace function public.perf_quarter(p_token text, p_quarter date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_q date; v_rw public.perf_rewards; v_out jsonb;
begin
  v_err := public.perf_check(p_token, 'view');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_q := date_trunc('quarter', coalesce(p_quarter, public.perf_today()))::date;
  if v_q < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  select * into v_rw from public.perf_rewards where kind = 'quarter' and period = v_q;
  v_out := coalesce(v_rw.snapshot, public.perf_quarter_calc(v_q));
  return v_out || jsonb_build_object(
    'people', public.perf_hide_own(v_out -> 'people', v_me.id),
    'confirmed', v_rw.period is not null, 'confirmed_at', v_rw.confirmed_at,
    'confirmed_by', (select t.name from public.team_members t where t.id = v_rw.confirmed_by),
    'ended', public.perf_today() >= (v_q + interval '3 months')::date,
    'events', public.perf_reward_events(array['dept_scored', 'quarter_confirmed', 'quarter_reopened'], v_q::text));
end $$;

create or replace function public.perf_dept_save(p_token text, p_quarter date, p_department text, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err text; v_me public.team_members; v_q date; v_c jsonb; v_i integer; v_v jsonb; v_n numeric[] := '{}';
  v_max constant numeric[] := array[25, 25, 20, 15, 15]; v_was public.perf_dept_scores; v_crit boolean;
  v_changed jsonb := '[]'::jsonb; v_old numeric[];
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_q := date_trunc('quarter', p_quarter)::date;
  if v_q is null or v_q < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if p_department is null or p_department not in ('creative', 'marketing') then
    return jsonb_build_object('error', 'bad-department');
  end if;
  if exists (select 1 from public.perf_rewards where kind = 'quarter' and period = v_q) then
    return jsonb_build_object('error', 'confirmed');
  end if;
  v_c := p_payload -> 'criteria';
  if v_c is null or jsonb_typeof(v_c) <> 'array' then return jsonb_build_object('error', 'bad-payload'); end if;
  if jsonb_array_length(v_c) <> 5 then return jsonb_build_object('error', 'bad-payload'); end if;
  for v_i in 1..5 loop
    v_v := v_c -> (v_i - 1);
    if jsonb_typeof(v_v) <> 'number' then
      return jsonb_build_object('error', 'bad-score', 'index', v_i, 'max', v_max[v_i]);
    end if;
    if (v_v #>> '{}')::numeric not between 0 and v_max[v_i]
       or round((v_v #>> '{}')::numeric, 1) <> (v_v #>> '{}')::numeric then
      return jsonb_build_object('error', 'bad-score', 'index', v_i, 'max', v_max[v_i]);
    end if;
    v_n := v_n || (v_v #>> '{}')::numeric;
  end loop;
  v_crit := coalesce((p_payload ->> 'critical')::boolean, false);
  select * into v_was from public.perf_dept_scores where quarter = v_q and department = p_department for update;
  insert into public.perf_dept_scores (quarter, department, c1, c2, c3, c4, c5, critical, entered_by, updated_at)
  values (v_q, p_department, v_n[1], v_n[2], v_n[3], v_n[4], v_n[5], v_crit, v_me.id, now())
  on conflict (quarter, department) do update set
    c1 = excluded.c1, c2 = excluded.c2, c3 = excluded.c3, c4 = excluded.c4, c5 = excluded.c5,
    critical = excluded.critical, entered_by = excluded.entered_by, updated_at = now();
  v_old := array[v_was.c1, v_was.c2, v_was.c3, v_was.c4, v_was.c5];
  for v_i in 1..5 loop
    if v_old[v_i] is distinct from v_n[v_i] then
      v_changed := v_changed || jsonb_build_array(jsonb_build_object('key', 'c' || v_i, 'from', v_old[v_i], 'to', v_n[v_i]));
    end if;
  end loop;
  if v_was.critical is distinct from v_crit then
    v_changed := v_changed || jsonb_build_array(jsonb_build_object('key', 'critical', 'from', v_was.critical, 'to', v_crit));
  end if;
  if jsonb_array_length(v_changed) > 0 then
    perform public.perf_log(null, null, 'dept_scored',
      jsonb_build_object('key', v_q::text, 'department', p_department, 'changed', v_changed));
  end if;
  return public.perf_quarter(p_token, v_q);
end $$;

create or replace function public.perf_quarter_confirm(p_token text, p_quarter date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_q date; v_snap jsonb; v_x jsonb;
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

create or replace function public.perf_quarter_reopen(p_token text, p_quarter date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_q date; v_rw public.perf_rewards;
begin
  v_err := public.perf_check(p_token, 'manage');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_q := date_trunc('quarter', p_quarter)::date;
  select * into v_rw from public.perf_rewards where kind = 'quarter' and period = v_q for update;
  if v_rw.period is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  perform public.perf_log(null, null, 'quarter_reopened', jsonb_build_object('key', v_q::text, 'was', v_rw.snapshot,
    'confirmed_at', v_rw.confirmed_at));
  delete from public.perf_rewards where kind = 'quarter' and period = v_q;
  return public.perf_quarter(p_token, v_q);
end $$;

-- 5. Management: flexible hours, the period, commission ---------------------------------
create or replace function public.perf_flex(p_token text, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_out jsonb;
begin
  v_err := public.perf_check(p_token, 'view');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_out := public.perf_flex_calc(p_period);
  return v_out || jsonb_build_object('people', public.perf_hide_own(v_out -> 'people', v_me.id));
end $$;

create or replace function public.perf_period(p_token text, p_from date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_f date; v_rw public.perf_rewards; v_c public.perf_company; v_out jsonb;
begin
  v_err := public.perf_check(p_token, 'view');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_f := date_trunc('quarter', coalesce(p_from, public.perf_today()))::date;
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
  v_f := date_trunc('quarter', p_from)::date;
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
  v_f := date_trunc('quarter', p_from)::date;
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
  v_f := date_trunc('quarter', p_from)::date;
  select * into v_rw from public.perf_rewards where kind = 'period' and period = v_f for update;
  if v_rw.period is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  perform public.perf_log(null, null, 'period_reopened', jsonb_build_object('key', v_f::text, 'was', v_rw.snapshot,
    'confirmed_at', v_rw.confirmed_at));
  delete from public.perf_rewards where kind = 'period' and period = v_f;
  return public.perf_period(p_token, v_f);
end $$;

/* Every standing commission but the caller's own, the clients a deal may
   name and the colleagues it may be entered for. */
create or replace function public.perf_commissions(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members;
begin
  v_err := public.perf_check(p_token, 'view');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(public.perf_commission_json(c) order by c.month desc, c.created_at desc)
                        from public.perf_commissions c
                       where c.removed_at is null and c.team_member_id <> v_me.id), '[]'::jsonb),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id', cl.id, 'name', cl.name, 'client_code', cl.client_code)
                                          order by cl.name)
                           from public.clients cl
                          where cl.stage in ('active', 'paused', 'past')), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'staff_code', t.staff_code)
                                          order by t.name)
                           from public.team_members t where t.active and t.id <> v_me.id), '[]'::jsonb),
    'events', public.perf_reward_events(array['commission_added', 'commission_removed', 'commission_restored'], null));
end $$;

create or replace function public.perf_commission_add(p_token text, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err text; v_me public.team_members; v_mem uuid; v_cl uuid; v_mon date; v_np numeric; v_pct numeric;
  v_row public.perf_commissions;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  begin v_mem := (p_payload ->> 'team_member_id')::uuid; exception when others then v_mem := null; end;
  if v_mem is null or not exists (select 1 from public.team_members where id = v_mem and active) then
    return jsonb_build_object('error', 'bad-member');
  end if;
  if v_mem = v_me.id then return jsonb_build_object('error', 'own-review'); end if;
  if coalesce(p_payload ->> 'client_id', '') <> '' then
    begin v_cl := (p_payload ->> 'client_id')::uuid; exception when others then v_cl := null; end;
    if v_cl is null or not exists (select 1 from public.clients where id = v_cl) then
      return jsonb_build_object('error', 'bad-client');
    end if;
  end if;
  if coalesce(btrim(p_payload ->> 'description'), '') = '' then return jsonb_build_object('error', 'description-needed'); end if;
  begin v_mon := (p_payload ->> 'month')::date; exception when others then v_mon := null; end;
  if v_mon is null or extract(day from v_mon) <> 1 or v_mon < date '2026-06-01'
     or v_mon > date_trunc('month', public.perf_today())::date then
    return jsonb_build_object('error', 'bad-month');
  end if;
  if coalesce(jsonb_typeof(p_payload -> 'net_profit'), '') <> 'number' then return jsonb_build_object('error', 'bad-amount'); end if;
  v_np := (p_payload ->> 'net_profit')::numeric;
  if v_np < 0 or round(v_np, 2) <> v_np or v_np >= 1e12 then return jsonb_build_object('error', 'bad-amount'); end if;
  if coalesce(jsonb_typeof(p_payload -> 'pct'), '') <> 'number' then return jsonb_build_object('error', 'bad-pct'); end if;
  v_pct := (p_payload ->> 'pct')::numeric;
  if v_pct <= 0 or v_pct > 100 or round(v_pct, 2) <> v_pct then return jsonb_build_object('error', 'bad-pct'); end if;
  insert into public.perf_commissions (team_member_id, client_id, description, month, net_profit, pct, created_by)
  values (v_mem, v_cl, btrim(p_payload ->> 'description'), v_mon, v_np, v_pct, v_me.id)
  returning * into v_row;
  perform public.perf_log(null, v_mem, 'commission_added', jsonb_build_object('commission', v_row.id,
    'month', v_mon, 'net_profit', v_np, 'pct', v_pct));
  return public.perf_commission_json(v_row);
end $$;

create or replace function public.perf_commission_remove(p_token text, p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_row public.perf_commissions;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  select * into v_row from public.perf_commissions where id = p_id for update;
  if v_row.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_row.team_member_id = v_me.id then return jsonb_build_object('error', 'own-review'); end if;
  if v_row.removed_at is null then
    update public.perf_commissions set removed_at = now(), removed_by = v_me.id where id = p_id returning * into v_row;
    perform public.perf_log(null, v_row.team_member_id, 'commission_removed', jsonb_build_object('commission', p_id));
  end if;
  return public.perf_commission_json(v_row);
end $$;

create or replace function public.perf_commission_restore(p_token text, p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_row public.perf_commissions;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  select * into v_row from public.perf_commissions where id = p_id for update;
  if v_row.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_row.team_member_id = v_me.id then return jsonb_build_object('error', 'own-review'); end if;
  if v_row.removed_at is not null then
    update public.perf_commissions set removed_at = null, removed_by = null where id = p_id returning * into v_row;
    perform public.perf_log(null, v_row.team_member_id, 'commission_restored', jsonb_build_object('commission', p_id));
  end if;
  return public.perf_commission_json(v_row);
end $$;

-- 6. The member: their own outcome ------------------------------------------------------
/* The signed-in person's own confirmed quarters and periods, flexible hours
   for each month once it is decided, and commissions once the month is
   final. Never another person's score, share or figure. */
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
               'confirmed_at', rw.confirmed_at, 'me', me_row,
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

-- 7. Who may call what ----------------------------------------------------------------
revoke all on function public.perf_today() from public, anon, authenticated;
revoke all on function public.perf_quarter_word(date) from public, anon, authenticated;
revoke all on function public.perf_period_word(date) from public, anon, authenticated;
revoke all on function public.perf_is_admin() from public, anon, authenticated;
revoke all on function public.perf_quarter_calc(date) from public, anon, authenticated;
revoke all on function public.perf_flex_calc(date) from public, anon, authenticated;
revoke all on function public.perf_period_calc(date) from public, anon, authenticated;
revoke all on function public.perf_commission_json(public.perf_commissions) from public, anon, authenticated;
revoke all on function public.perf_hide_own(jsonb, uuid) from public, anon, authenticated;
revoke all on function public.perf_reward_events(text[], text) from public, anon, authenticated;
revoke all on function public.perf_quarter(text, date) from public, anon, authenticated;
revoke all on function public.perf_dept_save(text, date, text, jsonb) from public, anon, authenticated;
revoke all on function public.perf_quarter_confirm(text, date) from public, anon, authenticated;
revoke all on function public.perf_quarter_reopen(text, date) from public, anon, authenticated;
revoke all on function public.perf_flex(text, date) from public, anon, authenticated;
revoke all on function public.perf_period(text, date) from public, anon, authenticated;
revoke all on function public.perf_company_set(text, date, jsonb) from public, anon, authenticated;
revoke all on function public.perf_period_confirm(text, date) from public, anon, authenticated;
revoke all on function public.perf_period_reopen(text, date) from public, anon, authenticated;
revoke all on function public.perf_commissions(text) from public, anon, authenticated;
revoke all on function public.perf_commission_add(text, jsonb) from public, anon, authenticated;
revoke all on function public.perf_commission_remove(text, uuid) from public, anon, authenticated;
revoke all on function public.perf_commission_restore(text, uuid) from public, anon, authenticated;
revoke all on function public.perf_rewards_mine() from public, anon, authenticated;
grant execute on function public.perf_quarter(text, date) to authenticated;
grant execute on function public.perf_dept_save(text, date, text, jsonb) to authenticated;
grant execute on function public.perf_quarter_confirm(text, date) to authenticated;
grant execute on function public.perf_quarter_reopen(text, date) to authenticated;
grant execute on function public.perf_flex(text, date) to authenticated;
grant execute on function public.perf_period(text, date) to authenticated;
grant execute on function public.perf_company_set(text, date, jsonb) to authenticated;
grant execute on function public.perf_period_confirm(text, date) to authenticated;
grant execute on function public.perf_period_reopen(text, date) to authenticated;
grant execute on function public.perf_commissions(text) to authenticated;
grant execute on function public.perf_commission_add(text, jsonb) to authenticated;
grant execute on function public.perf_commission_remove(text, uuid) to authenticated;
grant execute on function public.perf_commission_restore(text, uuid) to authenticated;
grant execute on function public.perf_rewards_mine() to authenticated;

-- END OF PERFORMANCE REWARDS ------------------------------------------------
