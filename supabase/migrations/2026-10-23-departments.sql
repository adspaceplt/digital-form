-- ===========================================================================
-- DEPARTMENTS — the team's departments are a list kept in Settings, and the
-- department prize is worked out across the departments that take part
-- (2026-10-23)
-- ===========================================================================
-- WHY (the user, 2026-10-23: "can add more departments?", then "Editable
-- list in Settings"; on the department prize: "creative and marketing for
-- now. in the future could add more like sales etc. so do necessary changes
-- and prep for this"): a colleague's department was Creative or Marketing,
-- fixed by a check on three tables and by the department prize, which named
-- the two in its own code.
--
-- WHAT IT ADDS
--   * `departments` (key, name, active, in_prize, criteria, position): RLS
--     on, no policy, no grant. The key is made once from the name and never
--     moves; a rename changes the name alone. Seeded once, into an empty
--     table, with Creative and Marketing, both in the prize with the five
--     criteria the Performance page named for them.
--   * `team_members.department`, `perf_people.department` and
--     `perf_dept_scores.department` reference `departments(key)`, so a
--     department named anywhere is one on the list. The checks naming the
--     two are taken away by the SQL Editor part,
--     2026-10-23-departments-editor.sql; until it runs, a colleague can be
--     put only in Creative or Marketing.
--   * `departments_list()` (the team): every department, its colleagues
--     (active), whether it is in the prize and its criteria, in its order.
--   * `department_save(p_key, p_name, p_in_prize, p_criteria)` (Business
--     settings): adds a department (p_key null) or changes one. A name of 2
--     to 40 characters, unique in any case (`bad-name`, `taken`); a
--     department in the prize names its five criteria, each 2 to 60
--     characters (`criteria-needed`, `bad-criteria`); filed `team.changed`
--     under Departments, from and to.
--   * `department_set_active(p_key, p_on)` (Business settings): an
--     inactive department is offered to nobody and leaves the prize;
--     its colleagues keep it. Never asks; filed.
--   * The department prize (`perf_quarter_calc`, `perf_quarter_confirm`,
--     `perf_dept_save`) takes every active department in the prize, in the
--     list's order: Confirm waits for each one's scores
--     (`dept-scores-needed`), scores are entered only for one of them
--     (`bad-department`), and each department carries its criteria names
--     (`names`), kept in a confirmed snapshot. With none in the prize the
--     reason is `no-departments`.
--
-- ORDER: this file, then the pages, then the SQL Editor part. An old page
-- reads the two departments it knows from its own words and writes only
-- them, which the list holds. Safe to run twice. Rollback: run the
-- perf_quarter_calc, perf_quarter_confirm and perf_dept_save definitions
-- of DEPARTMENT SCORES ARE AN ADMIN'S and PERFORMANCE QUARTER LIVE in
-- supabase/schema.sql again, then revoke execute on the three department
-- functions from authenticated (the table and the references may stay).
-- ===========================================================================

create table if not exists public.departments (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{1,23}$'),
  name text not null,
  active boolean not null default true,
  in_prize boolean not null default false,
  criteria jsonb,
  position int not null default 100,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.departments enable row level security;
revoke all on table public.departments from public, anon, authenticated;
create unique index if not exists departments_name_idx on public.departments (lower(name));

do $$
begin
  if exists (select 1 from public.departments) then return; end if;
  insert into public.departments (key, name, active, in_prize, criteria, position) values
    ('creative', 'Creative', true, true, jsonb_build_array('On-time creative delivery', 'Creative quality and revision',
       'Client performance support', 'Asset organisation', 'Cross-functional responsiveness'), 1),
    ('marketing', 'Marketing', true, true, jsonb_build_array('Client account health', 'Campaign planning and execution',
       'Posting and servicing accuracy', 'Reporting and proactive improvement', 'Brief and handover quality'), 2);
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'team_members_department_fkey') then
    alter table public.team_members add constraint team_members_department_fkey
      foreign key (department) references public.departments(key);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'perf_people_department_fkey') then
    alter table public.perf_people add constraint perf_people_department_fkey
      foreign key (department) references public.departments(key);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'perf_dept_scores_department_fkey') then
    alter table public.perf_dept_scores add constraint perf_dept_scores_department_fkey
      foreign key (department) references public.departments(key);
  end if;
end $$;

/* Every department, for the Team sheet, Performance and Settings. */
create or replace function public.departments_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'key', d.key, 'name', d.name, 'active', d.active, 'in_prize', d.in_prize,
      'criteria', coalesce(d.criteria, '[]'::jsonb),
      'members', (select count(*)::int from public.team_members t where t.department = d.key and t.active))
      order by d.position, lower(d.name))
    from public.departments d), '[]'::jsonb);
end $$;
revoke all on function public.departments_list() from public, anon;
grant execute on function public.departments_list() to authenticated;

/* The criteria a department's prize scores are entered under: five names,
   each 2 to 60 characters, else null. */
create or replace function public.department_criteria_ok(p_criteria jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare v_out jsonb := '[]'::jsonb; v_i int; v_t text;
begin
  if p_criteria is null or jsonb_typeof(p_criteria) <> 'array' or jsonb_array_length(p_criteria) <> 5 then return null; end if;
  for v_i in 0..4 loop
    if jsonb_typeof(p_criteria -> v_i) <> 'string' then return null; end if;
    v_t := btrim(regexp_replace(p_criteria ->> v_i, '\s+', ' ', 'g'));
    if char_length(v_t) < 2 or char_length(v_t) > 60 then return null; end if;
    v_out := v_out || to_jsonb(v_t);
  end loop;
  return v_out;
end $$;
revoke all on function public.department_criteria_ok(jsonb) from public, anon, authenticated;

/* Add a department (p_key null) or change one. */
create or replace function public.department_save(p_key text, p_name text, p_in_prize boolean, p_criteria jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members;
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_old public.departments;
  v_crit jsonb;
  v_key text; v_base text; v_n int := 1;
  v_moves text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if char_length(v_name) < 2 or char_length(v_name) > 40 then return jsonb_build_object('error', 'bad-name'); end if;
  if p_key is not null then
    select * into v_old from public.departments d where d.key = p_key for update;
    if v_old.key is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if exists (select 1 from public.departments d where lower(d.name) = lower(v_name) and d.key is distinct from p_key) then
    return jsonb_build_object('error', 'taken');
  end if;
  if p_criteria is not null and jsonb_typeof(p_criteria) = 'array' and jsonb_array_length(p_criteria) > 0 then
    v_crit := public.department_criteria_ok(p_criteria);
    if v_crit is null then return jsonb_build_object('error', 'bad-criteria'); end if;
  end if;
  if coalesce(p_in_prize, false) and v_crit is null then return jsonb_build_object('error', 'criteria-needed'); end if;
  if v_old.key is null then
    v_base := left(btrim(regexp_replace(lower(v_name), '[^a-z0-9]+', '_', 'g'), '_'), 20);
    if v_base !~ '^[a-z]' then v_base := 'dept_' || v_base; end if;
    v_base := left(v_base, 20);
    if char_length(v_base) < 2 then v_base := 'dept'; end if;
    v_key := v_base;
    while exists (select 1 from public.departments d where d.key = v_key) loop
      v_n := v_n + 1; v_key := v_base || v_n;
    end loop;
    insert into public.departments (key, name, active, in_prize, criteria, position, updated_at, updated_by)
    values (v_key, v_name, true, coalesce(p_in_prize, false), v_crit,
            coalesce((select max(d.position) from public.departments d), 0) + 1, now(),
            (select m.id from public.team_members m where m.id = v_me.id));
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(v_me.name, 'admin'), 'team.changed', 'Departments',
      'Added: ' || v_name || case when coalesce(p_in_prize, false) then ' · in the department prize' else '' end);
    return jsonb_build_object('ok', true, 'key', v_key);
  end if;
  if v_old.name <> v_name then v_moves := v_moves || ('Name: ' || v_old.name || ' → ' || v_name); end if;
  if v_old.in_prize is distinct from coalesce(p_in_prize, false) then
    v_moves := v_moves || ('Department prize: ' || case when v_old.in_prize then 'In' else 'Out' end || ' → '
      || case when coalesce(p_in_prize, false) then 'In' else 'Out' end);
  end if;
  if v_old.criteria is distinct from v_crit then v_moves := v_moves || 'Criteria changed'::text; end if;
  if cardinality(v_moves) = 0 then return jsonb_build_object('ok', true, 'key', v_old.key); end if;
  update public.departments d set name = v_name, in_prize = coalesce(p_in_prize, false), criteria = v_crit,
         updated_at = now(), updated_by = (select m.id from public.team_members m where m.id = v_me.id)
   where d.key = v_old.key;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Departments', v_old.name || ' · ' || array_to_string(v_moves, ' · '));
  return jsonb_build_object('ok', true, 'key', v_old.key);
end $$;
revoke all on function public.department_save(text, text, boolean, jsonb) from public, anon;
grant execute on function public.department_save(text, text, boolean, jsonb) to authenticated;

/* Offer a department, or stop offering it. */
create or replace function public.department_set_active(p_key text, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.team_members; v_old public.departments;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  select * into v_old from public.departments d where d.key = p_key for update;
  if v_old.key is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_old.active = coalesce(p_on, false) then return jsonb_build_object('ok', true); end if;
  update public.departments d set active = coalesce(p_on, false), updated_at = now(),
         updated_by = (select m.id from public.team_members m where m.id = v_me.id)
   where d.key = p_key;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Departments',
    v_old.name || ' · ' || case when p_on then 'Inactive → Active' else 'Active → Inactive' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.department_set_active(text, boolean) from public, anon;
grant execute on function public.department_set_active(text, boolean) to authenticated;

/* The quarter, its department prize across the departments in the prize. */
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
    select k.key as dep, k.name as dname, k.criteria as dnames, s.c1, s.c2, s.c3, s.c4, s.c5, coalesce(s.critical, false) as crit,
           s.c1 + s.c2 + s.c3 + s.c4 + s.c5 as total, s.quarter is not null as entered,
           row_number() over (order by k.position, lower(k.name)) as ord
      from public.departments k
      left join public.perf_dept_scores s on s.quarter = v_q and s.department = k.key
     where k.active and k.in_prize
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
           'department', z.dep, 'name', z.dname, 'names', coalesce(z.dnames, '[]'::jsonb), 'entered', z.entered,
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
    'reason', case when v_depts is null then 'no-departments' when not v_both then 'scores-needed' else v_why end);

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
    'departments', coalesce(v_depts, '[]'::jsonb), 'department_prize', v_dp,
    'open_months', v_open, 'missing_months', v_missing,
    'rules', jsonb_build_object('individual', v_ip, 'department', v_dpool, 'min_total', v_dmin,
      'grades', jsonb_build_object('A', public.perf_setting('grade_a', v_q), 'B', public.perf_setting('grade_b', v_q),
                                   'C', public.perf_setting('grade_c', v_q), 'D', public.perf_setting('grade_d', v_q))));
end $$;
revoke all on function public.perf_quarter_calc(date) from public, anon, authenticated;

/* A quarter is confirmed once every department in the prize is scored. */
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
  if exists (select 1 from public.departments k
              where k.active and k.in_prize
                and not exists (select 1 from public.perf_dept_scores s where s.quarter = v_q and s.department = k.key)) then
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
revoke all on function public.perf_quarter_confirm(text, date) from public, anon;
grant execute on function public.perf_quarter_confirm(text, date) to authenticated;

/* A department's prize scores, for a department in the prize alone. */
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
  /* The department prize is decided by an admin alone: a member scoring
     another department could swing it. */
  if not public.perf_is_admin() then return jsonb_build_object('error', 'admin-only'); end if;
  v_me := public.ops_me();
  v_q := date_trunc('quarter', p_quarter)::date;
  if v_q is null or v_q < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if p_department is null or not exists (select 1 from public.departments k
                                          where k.key = p_department and k.active and k.in_prize) then
    return jsonb_build_object('error', 'bad-department');
  end if;
  /* Nobody scores their own department: its members share its prize. */
  if v_me.department is not distinct from p_department then
    return jsonb_build_object('error', 'own-department');
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
revoke all on function public.perf_dept_save(text, date, text, jsonb) from public, anon, authenticated;
grant execute on function public.perf_dept_save(text, date, text, jsonb) to authenticated;

-- END OF DEPARTMENTS --------------------------------------------------------

select public.functions_tidy();
