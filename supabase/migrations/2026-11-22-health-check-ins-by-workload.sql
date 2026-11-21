-- ===========================================================================
-- HEALTH CHECK-INS BY WORKLOAD — a mood check-in, asked weekly while a
-- colleague's planned work is near their weekly capacity, else monthly
-- (2026-11-22)
-- ===========================================================================
-- WHY (the user, 2026-11-22, approving the Health redesign, artifact version
-- 3): a check-in after Apple Health's State of Mind, asked by each
-- colleague's own open work rather than every half month; late tasks count
-- in the week's load; a weekly capacity of 0 is not measured (asked
-- monthly); 90% is near capacity; a task with no estimate counts 2 hours;
-- the load is the work due in this Malaysian calendar week, by its draft due
-- date, else its final due date; admins are told of a heavy week even for a
-- colleague who has not agreed (no answers in it); the terms move to version
-- 2 and are asked again. Every figure is a Business setting.
--
-- WHAT IT CHANGES
--   * `health_moods` (RLS on, no policy, no grant): a check-in, its period
--     (`week` from Monday, `month` from the 1st, MYT), mood 1 to 7, workload
--     1 to 5, the feelings and influences chosen from fixed lists, a note of
--     1,000 characters, and the week's planned work, late work and capacity
--     as they stood when it was saved. The half-month `health_checkins` stay
--     as they are, read as Earlier check-ins.
--   * Settings (`app_settings`, from 14 Aug 2023): `health_cap_default` 45
--     (hours, where a colleague has no weekly capacity), `health_near_pct` 90,
--     `health_task_hours` 2 (a task with no estimate), `health_remind_days` 2
--     (0 none), `health_alert` 1 (the heavy workload notice); bounds,
--     names and units in `app_settings_set`.
--   * `health_week(day)`, `health_load(member, day)` (open tasks the colleague
--     owns, due in the week or late, by draft due unless the draft is in,
--     else final due; an admin, a system account or a capacity of 0 is not
--     measured), `health_period(member, day)`: internal helpers.
--   * `health_mine()` also sends `period` (week or month, its days, the load,
--     whether a check-in is due, the current check-in) and `moods`.
--   * `health_mood_save(p_start, p_mood, p_workload, p_feelings,
--     p_influences, p_note)`: `no-consent`, `stale-period` (with the period
--     open), `no-mood`, `no-workload`, `bad-tag`, `too-long`; saved into the
--     period open, edited until it ends.
--   * `health_team(p_token)` also sends each colleague's `moods` (while their
--     agreement stands, saved since it), `load` and `period` (for every
--     active colleague), the 12 weeks' average mood (`trend`, a week of
--     fewer than 3 check-ins sent without its average) and the average mood
--     by load (`bands`, the same floor).
--   * `health_daily(p_today)` (pg_cron `health-daily`, 08:10 MYT): a
--     colleague agreed with a check-in due is reminded `health_remind_days`
--     after the period opens (never on a public holiday); while a
--     colleague's week is heavy, every active admin is told once a week
--     (`health.load`, the name alone, opening Team: Health).
--   * `health_wordings` version 2; `my_hr_remind` no longer sends the
--     half-month health reminder; `privacy_retention` also keeps the new
--     check-ins to `health_keep_months` and a leaver's to
--     `health_leaver_months`.
--
-- ORDER: this file, then the pages. An old page keeps reading `health_mine`
-- (its fields stay) and meets the version 2 terms; its half-month save still
-- answers. A new page on the old database reads no `period` and says the
-- feature is not available yet. Safe to run twice.
-- ROLLBACK: run HEALTH TERMS ARE VERSIONED's `health_mine`, PERFORMANCE AND
-- HEALTH HOLD TO THEIR RULES' `health_team(text)`, RECOGNITION's
-- `my_hr_remind`, VERIFY CHECKS COUNTED's
-- `privacy_retention` and SWITCHED-OFF ACTS' band's `app_settings_set`
-- again; unschedule `health-daily`; `delete from health_wordings where
-- version = 2` (every agreement to it then stands on version 1's words
-- again). The table and settings may stay unread.
-- ===========================================================================

create table if not exists public.health_moods (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  period         text not null check (period in ('week', 'month')),
  period_start   date not null,
  mood           smallint not null check (mood between 1 and 7),
  workload       smallint not null check (workload between 1 and 5),
  feelings       text[] not null default '{}',
  influences     text[] not null default '{}',
  note           text check (note is null or char_length(note) <= 1000),
  load_minutes   integer,
  late_minutes   integer,
  cap_minutes    integer,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (team_member_id, period, period_start)
);
create index if not exists health_moods_start_idx on public.health_moods (period_start);
alter table public.health_moods enable row level security;
revoke all on table public.health_moods from public, anon, authenticated;

insert into public.app_settings (key, from_date, value)
select 'health_cap_default', date '2023-08-14', 45
 where not exists (select 1 from public.app_settings s where s.key = 'health_cap_default');
insert into public.app_settings (key, from_date, value)
select 'health_near_pct', date '2023-08-14', 90
 where not exists (select 1 from public.app_settings s where s.key = 'health_near_pct');
insert into public.app_settings (key, from_date, value)
select 'health_task_hours', date '2023-08-14', 2
 where not exists (select 1 from public.app_settings s where s.key = 'health_task_hours');
insert into public.app_settings (key, from_date, value)
select 'health_remind_days', date '2023-08-14', 2
 where not exists (select 1 from public.app_settings s where s.key = 'health_remind_days');
insert into public.app_settings (key, from_date, value)
select 'health_alert', date '2023-08-14', 1
 where not exists (select 1 from public.app_settings s where s.key = 'health_alert');

insert into public.health_wordings (version, care, terms, made_at)
select 2, jsonb_build_array(
    'Life at work and life at home both shape how you feel, in body and in mind, and we care about all of it. Take a few seconds to tell us how you really are. When your workload is heavy, we will ask each week.',
    'Please answer honestly. There are no right or wrong answers, only a true picture that helps us look after you. If something feels heavy, ask for a talk: reaching out early is a strength, and we would always rather hear from you and help.'),
  jsonb_build_array(
    'You record how you feel on a scale of one to seven and your workload, and may add your feelings, what affects them and a note.',
    'You are asked once a month, or each week while the work planned for you in My Work this week is near your weekly capacity. Admins are told when this applies to you; the notice never includes your answers.',
    'ADspace management reads your answers with your name, only to understand how you are and to support you.',
    'Your answers are never part of your performance review.',
    'You can withdraw at any time here, and your answers leave management''s view.'),
  now()
 where not exists (select 1 from public.health_wordings w where w.version = 2);

/* The week's Monday, Malaysia's calendar. */
create or replace function public.health_week(p_day date)
returns date language sql immutable set search_path = public as $$
  select p_day - (extract(isodow from p_day)::integer - 1)
$$;
revoke all on function public.health_week(date) from public, anon, authenticated;

/* A colleague's planned work this week against their weekly capacity: every
   open task they own whose day falls in the week, or has passed (late work
   counts, and is told apart). A task's day is its draft due while the draft
   is not in, else its final due. An admin, a system account and a capacity
   of 0 are not measured. */
create or replace function public.health_load(p_member uuid, p_day date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_m     public.team_members;
  v_ws    date := public.health_week(p_day);
  v_cap   integer;
  v_near  numeric := coalesce(public.app_setting('health_near_pct', p_day), 90);
  v_each  integer := round(coalesce(public.app_setting('health_task_hours', p_day), 2) * 60)::integer;
  v_load  integer := 0; v_late integer := 0; v_n integer := 0; v_nl integer := 0; v_ne integer := 0;
begin
  select * into v_m from public.team_members t where t.id = p_member;
  if v_m.id is null then return null; end if;
  v_cap := coalesce(v_m.capacity_minutes_week,
                    round(coalesce(public.app_setting('health_cap_default', p_day), 45) * 60)::integer);
  select coalesce(sum(x.mins), 0), coalesce(sum(x.mins) filter (where x.day < p_day), 0),
         count(*), count(*) filter (where x.day < p_day), count(*) filter (where x.est is null)
    into v_load, v_late, v_n, v_nl, v_ne
    from (select t.estimate_minutes as est, coalesce(t.estimate_minutes, v_each) as mins,
                 (case when t.first_draft_submitted_at is null and t.current_first_draft_due_at is not null
                       then t.current_first_draft_due_at else t.current_final_due_at end
                  at time zone 'Asia/Kuala_Lumpur')::date as day
            from public.ops_tasks t
           where t.completed_at is null and t.cancelled_at is null and t.archived_at is null
             and exists (select 1 from public.ops_task_assignees a
                          where a.task_id = t.id and a.team_member_id = p_member
                            and a.responsibility = 'owner' and a.ended_at is null)) x
   where x.day is not null and x.day <= v_ws + 6;
  return jsonb_build_object('week', v_ws, 'week_end', v_ws + 6,
    'measured', not (coalesce(v_m.is_admin, false) or v_m.role = 'admin' or coalesce(v_m.system, false) or v_cap <= 0),
    'cap', v_cap, 'load', v_load, 'late', v_late, 'tasks', v_n, 'late_tasks', v_nl, 'no_estimate', v_ne,
    'pct', case when v_cap > 0 then round(v_load * 100.0 / v_cap) end,
    'near', v_near,
    'heavy', not (coalesce(v_m.is_admin, false) or v_m.role = 'admin' or coalesce(v_m.system, false) or v_cap <= 0)
             and v_load * 100.0 >= v_cap * v_near);
end $$;
revoke all on function public.health_load(uuid, date) from public, anon, authenticated;

create or replace function public.health_mood_json(c public.health_moods)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', c.id, 'period', c.period, 'start', c.period_start,
    'end', case when c.period = 'week' then c.period_start + 6
                else (c.period_start + interval '1 month' - interval '1 day')::date end,
    'mood', c.mood, 'workload', c.workload, 'feelings', to_jsonb(c.feelings), 'influences', to_jsonb(c.influences),
    'note', c.note, 'load', c.load_minutes, 'late', c.late_minutes, 'cap', c.cap_minutes,
    'at', c.created_at, 'updated_at', c.updated_at)
$$;
revoke all on function public.health_mood_json(public.health_moods) from public, anon, authenticated;

/* The period a colleague is asked for today: the week while it is heavy,
   else the month; the check-in saved inside it, if any, and whether one is
   due. A check-in saved earlier in the month counts for a month that turns
   monthly, so nobody is asked twice for it. */
create or replace function public.health_period(p_member uuid, p_day date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_l jsonb; v_kind text; v_s date; v_e date; v_c public.health_moods;
begin
  v_l := public.health_load(p_member, p_day);
  if coalesce((v_l ->> 'heavy')::boolean, false) then
    v_kind := 'week'; v_s := public.health_week(p_day); v_e := v_s + 6;
  else
    v_kind := 'month'; v_s := date_trunc('month', p_day)::date; v_e := (v_s + interval '1 month' - interval '1 day')::date;
  end if;
  select * into v_c from public.health_moods k
   where k.team_member_id = p_member
     and greatest(k.period_start, (k.created_at at time zone 'Asia/Kuala_Lumpur')::date) between v_s and v_e
   order by (k.period = v_kind and k.period_start = v_s) desc, k.created_at desc limit 1;
  return jsonb_build_object('kind', v_kind, 'start', v_s, 'end', v_e, 'load', v_l,
    'due', v_c.id is null, 'current', case when v_c.id is null then null else public.health_mood_json(v_c) end);
end $$;
revoke all on function public.health_period(uuid, date) from public, anon, authenticated;

create or replace function public.health_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; c public.health_consents; h date;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  select * into c from public.health_consents where team_member_id = m.id;
  h := public.health_half(public.health_today());
  return jsonb_build_object(
    'consent', case when c.team_member_id is null then null else jsonb_build_object(
      'agreed_at', c.agreed_at, 'withdrawn_at', c.withdrawn_at, 'wording', c.wording) end,
    'wording', (select jsonb_build_object('version', w.version, 'care', w.care, 'terms', w.terms, 'made_at', w.made_at)
                  from public.health_wordings w where w.version = public.health_wording_now()),
    'half', h, 'half_end', public.health_half_end(h),
    'period', public.health_period(m.id, public.health_today()),
    'moods', coalesce((select jsonb_agg(public.health_mood_json(x) order by x.created_at desc)
                         from (select * from public.health_moods k
                                where k.team_member_id = m.id order by k.created_at desc limit 26) x), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(public.health_checkin_json(x) order by x.half desc)
                           from (select * from public.health_checkins k
                                  where k.team_member_id = m.id order by k.half desc limit 12) x), '[]'::jsonb),
    'asked', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'with', w.name, 'with_id', t.with_id,
                         'note', t.note, 'status', t.status, 'at', t.created_at, 'closed_at', t.closed_at)
                         order by (t.status = 'open') desc, t.created_at desc)
                         from (select * from public.health_talks x where x.team_member_id = m.id
                                order by (x.status = 'open') desc, x.created_at desc limit 20) t
                         join public.team_members w on w.id = t.with_id), '[]'::jsonb),
    'asked_me', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'from', f.name, 'from_id', t.team_member_id,
                            'note', t.note, 'status', t.status, 'at', t.created_at, 'closed_at', t.closed_at)
                            order by (t.status = 'open') desc, t.created_at desc)
                            from (select * from public.health_talks x where x.with_id = m.id and x.status <> 'withdrawn'
                                   order by (x.status = 'open') desc, x.created_at desc limit 20) t
                            join public.team_members f on f.id = t.team_member_id), '[]'::jsonb),
    'colleagues', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'staff_code', t.staff_code)
                              order by t.staff_code nulls last, t.name)
                              from public.team_members t where t.active and t.id <> m.id), '[]'::jsonb));
end $$;
revoke all on function public.health_mine() from public, anon, authenticated;
grant execute on function public.health_mine() to authenticated;

create or replace function public.health_mood_save(p_start date, p_mood integer, p_workload integer,
  p_feelings text[], p_influences text[], p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; p jsonb; l jsonb;
  v_feel constant text[] := array['Calm', 'Content', 'Motivated', 'Confident', 'Grateful', 'Hopeful',
    'Tired', 'Stressed', 'Anxious', 'Frustrated', 'Overwhelmed', 'Sad'];
  v_infl constant text[] := array['Workload', 'Clients', 'Colleagues', 'Family', 'Friends', 'Health', 'Sleep', 'Finances'];
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  if not public.health_agreed(m.id) then return jsonb_build_object('error', 'no-consent'); end if;
  p := public.health_period(m.id, public.health_today());
  if p_start is distinct from (p ->> 'start')::date then
    return jsonb_build_object('error', 'stale-period', 'period', p);
  end if;
  if p_mood is null then return jsonb_build_object('error', 'no-mood'); end if;
  if p_mood not between 1 and 7 then return jsonb_build_object('error', 'bad-tag'); end if;
  if p_workload is null then return jsonb_build_object('error', 'no-workload'); end if;
  if p_workload not between 1 and 5 then return jsonb_build_object('error', 'bad-tag'); end if;
  if not (coalesce(p_feelings, '{}') <@ v_feel) or not (coalesce(p_influences, '{}') <@ v_infl) then
    return jsonb_build_object('error', 'bad-tag');
  end if;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  l := p -> 'load';
  insert into public.health_moods (team_member_id, period, period_start, mood, workload, feelings, influences, note,
                                   load_minutes, late_minutes, cap_minutes)
  values (m.id, p ->> 'kind', p_start, p_mood, p_workload,
          array(select distinct x from unnest(coalesce(p_feelings, '{}')) x order by x),
          array(select distinct x from unnest(coalesce(p_influences, '{}')) x order by x),
          nullif(btrim(coalesce(p_note, '')), ''),
          (l ->> 'load')::integer, (l ->> 'late')::integer, case when (l ->> 'measured')::boolean then (l ->> 'cap')::integer end)
  on conflict (team_member_id, period, period_start) do update
     set mood = excluded.mood, workload = excluded.workload, feelings = excluded.feelings,
         influences = excluded.influences, note = excluded.note, load_minutes = excluded.load_minutes,
         late_minutes = excluded.late_minutes, cap_minutes = excluded.cap_minutes, updated_at = now();
  return public.health_mine();
end $$;
revoke all on function public.health_mood_save(date, integer, integer, text[], text[], text) from public, anon, authenticated;
grant execute on function public.health_mood_save(date, integer, integer, text[], text[], text) to authenticated;

create or replace function public.health_team(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; h date; e text; d date := public.health_today(); w0 date;
begin
  m := public.ops_me();
  e := public.health_check(p_token);
  if e is not null then return jsonb_build_object('error', e); end if;
  h := public.health_half(d);
  w0 := public.health_week(d) - 77;
  return jsonb_build_object('half', h, 'half_end', public.health_half_end(h), 'today', d,
    'people', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'staff_code', t.staff_code, 'designation', t.designation,
        'department', t.department, 'role', t.role,
        'consent', case when c.team_member_id is null then null else jsonb_build_object(
          'agreed_at', c.agreed_at, 'withdrawn_at', c.withdrawn_at,
          'current', c.wording >= public.health_wording_now()) end,
        'period', public.health_period(t.id, d) - 'current'
                  || jsonb_build_object('current', case when public.health_agreed(t.id)
                       then public.health_period(t.id, d) -> 'current' end),
        'moods', case when public.health_agreed(t.id) then coalesce((
            select jsonb_agg(public.health_mood_json(x) order by x.created_at desc)
              from (select * from public.health_moods k
                     where k.team_member_id = t.id and k.updated_at >= c.agreed_at
                     order by k.created_at desc limit 26) x), '[]'::jsonb) else '[]'::jsonb end,
        'checkins', case when public.health_agreed(t.id) then coalesce((
            select jsonb_agg(public.health_checkin_json(x) order by x.half desc)
              from (select * from public.health_checkins k
                     where k.team_member_id = t.id and k.updated_at >= c.agreed_at
                     order by k.half desc limit 12) x), '[]'::jsonb) else '[]'::jsonb end)
        order by t.staff_code nulls last, t.name)
        from public.team_members t
        left join public.health_consents c on c.team_member_id = t.id
       where t.active), '[]'::jsonb),
    /* What the team reads together never names a colleague: a week, or a
       band, of fewer than 3 check-ins is sent without its average. */
    'trend', (select jsonb_agg(jsonb_build_object('week', wk.w, 'n', coalesce(s.n, 0),
                'avg', case when coalesce(s.n, 0) >= 3 then s.avg end) order by wk.w)
                from generate_series(w0, public.health_week(d), interval '7 days') wk0(x)
                cross join lateral (select wk0.x::date as w) wk
                left join (select public.health_week(greatest(k.period_start, (k.created_at at time zone 'Asia/Kuala_Lumpur')::date)) as w,
                                  count(*)::integer as n, round(avg(k.mood), 1) as avg
                             from public.health_moods k
                             join public.health_consents c2 on c2.team_member_id = k.team_member_id
                             join public.team_members t2 on t2.id = k.team_member_id and t2.active
                            where public.health_agreed(k.team_member_id) and k.updated_at >= c2.agreed_at
                              and greatest(k.period_start, (k.created_at at time zone 'Asia/Kuala_Lumpur')::date) >= w0
                            group by 1) s on s.w = wk.w),
    'bands', (select jsonb_agg(jsonb_build_object('band', b.band, 'n', coalesce(s.n, 0),
                'avg', case when coalesce(s.n, 0) >= 3 then s.avg end) order by b.band)
                from (values (1), (2), (3)) b(band)
                left join (select case when k.load_minutes * 100.0 < k.cap_minutes * 50 then 1
                                       when k.load_minutes * 100.0 < k.cap_minutes * coalesce(public.app_setting('health_near_pct', d), 90) then 2
                                       else 3 end as band,
                                  count(*)::integer as n, round(avg(k.mood), 1) as avg
                             from public.health_moods k
                             join public.health_consents c2 on c2.team_member_id = k.team_member_id
                             join public.team_members t2 on t2.id = k.team_member_id and t2.active
                            where public.health_agreed(k.team_member_id) and k.updated_at >= c2.agreed_at
                              and k.cap_minutes > 0 and k.load_minutes is not null
                              and greatest(k.period_start, (k.created_at at time zone 'Asia/Kuala_Lumpur')::date) >= w0
                            group by 1) s on s.band = b.band),
    'talks', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'from', f.name, 'from_id', k.team_member_id, 'with', w.name, 'with_id', k.with_id,
        'status', k.status, 'at', k.created_at, 'closed_at', k.closed_at)
        order by (k.status = 'open') desc, k.created_at desc)
        from public.health_talks k
        join public.team_members f on f.id = k.team_member_id
        join public.team_members w on w.id = k.with_id
       where k.status <> 'withdrawn' and k.created_at > now() - interval '90 days'
         and public.health_agreed(k.team_member_id)), '[]'::jsonb));
end $$;
revoke all on function public.health_team(text) from public, anon, authenticated;
grant execute on function public.health_team(text) to authenticated;

/* Each morning: the reminder of a check-in due, and the heavy week told to
   every admin once. Never a page's to call. */
create or replace function public.health_daily(p_today date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_today  date := coalesce(p_today, public.health_today());
  v_days   integer := coalesce(public.app_setting('health_remind_days', coalesce(p_today, public.health_today())), 2)::integer;
  v_alert  boolean := coalesce(public.app_setting('health_alert', coalesce(p_today, public.health_today())), 1) = 1;
  v_hol    boolean := public.public_holiday_on(coalesce(p_today, public.health_today())) is not null;
  v_p      jsonb;
  v_end    date;
  m        record;
  a        record;
  n        integer := 0;
begin
  for m in select t.id, t.name from public.team_members t
            where t.active and not coalesce(t.system, false) order by t.id loop
    v_p := public.health_period(m.id, v_today);
    v_end := (v_p ->> 'end')::date;
    if v_days > 0 and not v_hol and (v_p ->> 'due')::boolean and public.health_agreed(m.id)
       and v_today = (v_p ->> 'start')::date + v_days and v_today <= v_end then
      insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
      values (m.id, null, 'health.remind',
              'Check in on your health by ' || public.register_day(v_end) || ' (' || trim(to_char(v_end, 'FMDay')) || ').',
              null, 'health.remind.' || m.id || '.' || (v_p ->> 'start'))
      on conflict (dedupe_key) do nothing;
      n := n + 1;
    end if;
    if v_alert and coalesce((v_p #>> '{load,heavy}')::boolean, false) then
      for a in select t.id from public.team_members t
                where t.active and t.id <> m.id and not coalesce(t.system, false)
                  and (coalesce(t.is_admin, false) or t.role = 'admin') loop
        insert into public.ops_notifications (team_member_id, task_id, kind, title, body, link, dedupe_key)
        values (a.id, null, 'health.load', 'Check in with ' || m.name || '.',
                'Their work this week is near their weekly capacity.',
                'https://digital.adspace.me/admin/?s=team&tab=health',
                'health.load.' || m.id || '.' || (v_p #>> '{load,week}') || '.' || a.id)
        on conflict (dedupe_key) do nothing;
        n := n + 1;
      end loop;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.health_daily(date) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: the health reminders wait until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'health-daily';
  perform cron.schedule('health-daily', '10 0 * * *', 'select public.health_daily()');
end $$;

create or replace function public.my_hr_remind(p_today date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_today    date := coalesce(p_today, public.health_today());
  v_again    integer := coalesce(public.perf_setting('remind_again_days', coalesce(p_today, public.health_today())), 3)::integer;
  v_month    date := date_trunc('month', coalesce(p_today, public.health_today()))::date;
  v_last     date;
  m          record;
  n          integer := 0;
begin
  /* Rate yourself alone: the health check-in reminds by itself
     (`health_daily`, HEALTH CHECK-INS BY WORKLOAD, 2026-11-22). */
  v_last := (v_month - interval '1 month')::date;
  if not (extract(day from v_today) = 1 or (v_again > 0 and extract(day from v_today) = 1 + v_again)) then return 0; end if;
  for m in select t.id from public.team_members t where t.active order by t.id loop
    if not public.perf_reviewed(m.id) then continue; end if;
    if public.perf_self_open(m.id, v_last) is not null
       or exists (select 1 from public.perf_self_ratings s where s.team_member_id = m.id and s.period = v_last) then
      continue;
    end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
    values (m.id, null, 'perf.remind', 'Rate yourself for ' || public.perf_month_word(v_last) || '.', null,
            'myhr.remind.' || m.id || '.' || v_today)
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.my_hr_remind(date) from public, anon, authenticated;

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0; v_vt integer := 0; v_vd integer := 0; v_vc integer := 0; v_hm integer := 0;
  v_today date := (p_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_keep integer := coalesce(public.app_setting('health_keep_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 24)::integer;
  v_left integer := coalesce(public.app_setting('health_leaver_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 6)::integer;
  v_gone uuid[];
begin
  update public.wa_outbox o
     set to_number = '', to_name = null, params = '[]'::jsonb, button = null
   where o.created_at < p_now - interval '12 months'
     and o.state not in ('queued', 'sending')
     and (o.to_number <> '' or o.to_name is not null or o.params <> '[]'::jsonb or o.button is not null);
  get diagnostics v_wa = row_count;
  delete from public.activity_log a where a.created_at < p_now - interval '3 years';
  get diagnostics v_act = row_count;
  delete from public.health_checkins k where k.half < v_today - make_interval(months => v_keep);
  get diagnostics v_hc = row_count;
  delete from public.health_moods k where k.period_start < v_today - make_interval(months => v_keep);
  get diagnostics v_hm = row_count;
  v_hc := v_hc + v_hm;
  select coalesce(array_agg(m.id), '{}') into v_gone from public.team_members m
   where not m.active and coalesce(m.removed_at, m.expired_at) < p_now - make_interval(months => v_left);
  if array_length(v_gone, 1) > 0 then
    delete from public.health_checkins k where k.team_member_id = any(v_gone);
    get diagnostics v_hl = row_count;
    delete from public.health_moods k where k.team_member_id = any(v_gone);
    get diagnostics v_hm = row_count;
    v_hl := v_hl + v_hm;
    delete from public.health_talks t where t.team_member_id = any(v_gone) or t.with_id = any(v_gone);
    delete from public.health_log l where l.team_member_id = any(v_gone);
    delete from public.health_consents c where c.team_member_id = any(v_gone);
  end if;
  -- A caller's address against a link's passcode, once it has had nothing
  -- to say for 30 days and holds no lock (audit 2026-10-18, item 14).
  delete from public.link_tries t
   where greatest(t.last_at, coalesce(t.ok_at, t.last_at)) < p_now - interval '30 days'
     and coalesce(t.locked_until, t.last_at) < p_now;
  get diagnostics v_lt = row_count;
  -- A caller's address against /verify/, once its hour began 30 days ago.
  delete from public.verify_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vt = row_count;
  -- And against /verify/'s details (VERIFY DETAILS, 2026-11-20).
  delete from public.verify_detail_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vd = row_count;
  -- And a check's address hash, 30 days after its day; the document's
  -- total stays (VERIFY CHECKS COUNTED, 2026-11-21).
  delete from public.verify_checks v where v.day < v_today - 30;
  get diagnostics v_vc = row_count;
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt, 'verify_tries_removed', v_vt, 'verify_detail_tries_removed', v_vd,
    'verify_checks_removed', v_vc);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text; v_pre text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days', 'wa_repeat_hours',
    'bench_cpr_low', 'bench_cpr_mid', 'bench_cpr_high', 'bench_cpr_top', 'bench_msg_min', 'bench_msg_target', 'bench_msg_max',
    'bench_form_min', 'bench_form_target', 'bench_form_max', 'bench_cpm_min', 'bench_cpm_max', 'bench_cpl_rise',
    'bench_reels_share', 'bench_ad_spend_pct', 'bench_adset_daily', 'vic_lead_followup_hours', 'vic_proposal_followup_days', 'fx_sgd',
    'health_keep_months', 'health_leaver_months', 'abroad_days', 'abroad_remind_hours', 'analytics_from',
    'analytics_change_pct', 'analytics_churn_pct', 'quote_reply_days', 'quote_wa_day', 'client_email_on', 'ai_price_image', 'report_post_links',
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'plan_db_mb', 'plan_db_alert_pct',
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'hiring_decision_days', 'verify_code_from',
    'work_start', 'work_end', 'work_lunch_min', 'work_weekend',
    'health_cap_default', 'health_near_pct', 'health_task_hours', 'health_remind_days', 'health_alert'];
  v_moved text[] := '{}';
  v_drop boolean; v_fw text; v_fv text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, case when v_k = 'fx_sgd' then 4 else 2 end) <> v_v
       or (v_k = 'fx_sgd' and (v_v < 0.5 or v_v > 10))
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'task_past_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_invite_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_link_days' and (v_v < 7 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_pool_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_keep_months' and (v_v < 1 or v_v > 36 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_mb' and (v_v < 100 or v_v > 1000000 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_alert_pct' and (v_v < 10 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_late_days' and (v_v < 0 or v_v > 30 or round(v_v, 1) <> v_v))
       or (v_k = 'stage_back_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_reply_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'session_idle_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_decision_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'quote_reply_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k in ('creator_pay_days_myr', 'creator_pay_days_other') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k = 'quote_wa_day' and (v_v < 0 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'health_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'health_leaver_months' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'health_cap_default' and (v_v < 1 or v_v > 80 or v_v <> trunc(v_v)))
       or (v_k = 'health_near_pct' and (v_v < 50 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'health_task_hours' and (v_v < 0.5 or v_v > 40 or v_v * 2 <> trunc(v_v * 2)))
       or (v_k = 'health_remind_days' and (v_v < 0 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_from' and (v_v < 202308 or v_v > 209912 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 12))
       or (v_k = 'verify_code_from' and (v_v < 20230814 or v_v > 20991231 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 31 or mod(trunc(v_v / 100), 100) not between 1 and 12))
       or (v_k in ('work_start', 'work_end') and (v_v < 0 or v_v > 2345 or v_v <> trunc(v_v) or mod(v_v, 100) not in (0, 15, 30, 45)))
       or (v_k = 'work_lunch_min' and (v_v < 0 or v_v > 180 or v_v <> trunc(v_v) or mod(v_v, 15) <> 0))
       or (v_k = 'work_weekend' and v_v not in (0, 1, 2))
       or (v_k = 'analytics_change_pct' and (v_v < 1 or v_v > 50 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_churn_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k in ('bench_reels_share') and (v_v < 0 or v_v > 100))
       or (v_k = 'bench_ad_spend_pct' and (v_v < 1 or v_v > 100))
       or (v_k = 'bench_cpl_rise' and (v_v < -100 or v_v > 100))
       or (v_k like 'bench_%' and v_k not in ('bench_reels_share', 'bench_ad_spend_pct', 'bench_cpl_rise') and (v_v < 0 or v_v > 10000)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  /* A working day ends after it starts, as the two stand on the From day. */
  if (p_values ? 'work_start' or p_values ? 'work_end')
     and coalesce((p_values ->> 'work_end')::numeric, public.app_setting('work_end', p_from))
      <= coalesce((p_values ->> 'work_start')::numeric, public.app_setting('work_start', p_from)) then
    return jsonb_build_object('error', 'bad-hours');
  end if;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      /* A planned change saved back to the value in force the day before is
         withdrawn: its row goes, rather than a second row restating it. */
      v_drop := p_from > v_today
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date = p_from)
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date < p_from)
        and public.app_setting(v_k, p_from - 1) = v_v;
      if v_drop then
        delete from public.app_settings s where s.key = v_k and s.from_date = p_from;
      else
        insert into public.app_settings (key, from_date, value, set_by, set_at)
        values (v_k, p_from, v_v, v_me.id, now())
        on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      end if;
      v_name := case v_k when 'lead_followup_hours' then 'Lead follow-up limit' when 'proposal_followup_days' then 'Proposal follow-up limit'
        when 'vic_lead_followup_hours' then 'VIC lead follow-up limit' when 'vic_proposal_followup_days' then 'VIC proposal follow-up limit'
        when 'sst_pct' then 'SST' when 'term_1_3' then 'Under 3 months' when 'term_4_5' then '3-month commitment'
        when 'term_6_11' then '6-month commitment' when 'term_12_23' then '12-month commitment' when 'term_18_23' then '18-month commitment' when 'term_24' then '24-month commitment'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input price per million tokens'
        when 'ai_price_out' then 'AI output price per million tokens' when 'ai_price_search' then 'AI web search price per thousand searches' when 'ai_price_image' then 'AI price per scene picture' when 'meta_checks' then 'Meta checks' when 'client_email_on' then 'Send by email' when 'report_post_links' then 'Posts linked to tasks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
        when 'plan_db_mb' then 'Database plan' when 'plan_db_alert_pct' then 'Database alert'
        when 'timely_pct' then 'On time or early target' when 'timely_late_days' then 'Average lateness target'
        when 'stage_back_days' then 'Past dates on stage moves'
        when 'hiring_reply_days' then 'Interview reply time'
        when 'session_idle_days' then 'Signed-in devices'
        when 'hiring_decision_days' then 'Decision time'
        when 'creator_pay_days_myr' then 'Creator payment in MYR' when 'creator_pay_days_other' then 'Creator payment in other currencies'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'quote_wa_day' then 'Website quotations on WhatsApp'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Yearly rise in cost per lead' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend share of the budget' when 'bench_adset_daily' then 'Minimum daily budget per ad set'
        when 'fx_sgd' then 'Singapore dollar rate'
        when 'health_keep_months' then 'Health check-ins kept' when 'health_leaver_months' then 'Leavers'' health data kept'
        when 'health_cap_default' then 'Health default weekly capacity' when 'health_near_pct' then 'Health near capacity'
        when 'health_task_hours' then 'Health default hours per task' when 'health_remind_days' then 'Health check-in reminder'
        when 'health_alert' then 'Health heavy workload notice'
        when 'abroad_days' then 'Overseas approval' when 'abroad_remind_hours' then 'Overseas reminder'
        when 'analytics_from' then 'Analytics counts from'
        when 'verify_code_from' then 'Document IDs printed from'
        when 'work_start' then 'Working hours start' when 'work_end' then 'Working hours end'
        when 'work_lunch_min' then 'Lunch' when 'work_weekend' then 'Saturday and Sunday'
        when 'analytics_change_pct' then 'Analytics change threshold' when 'analytics_churn_pct' then 'Analytics quarterly churn alert'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' per S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours', 'abroad_remind_hours', 'health_cap_default', 'health_task_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'health_remind_days') then ' days'
        when v_k in ('quote_reply_days', 'creator_pay_days_myr', 'creator_pay_days_other', 'hiring_decision_days') then ' working days'
        when v_k = 'quote_wa_day' then ' per day'
        when v_k = 'plan_db_mb' then ' MB'
        when v_k = 'work_lunch_min' then ' minutes'
        when v_k in ('health_keep_months', 'hiring_pool_months', 'hiring_keep_months', 'health_leaver_months') then ' months'
        when v_pre <> '' then '' else '%' end;
      v_fw := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then case when v_was = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then coalesce(public.work_hours_word(v_k, v_was), 'not set')
              when v_k = 'analytics_from' then coalesce(substr(public.register_day(to_date(v_was::bigint::text, 'YYYYMM')), 3), 'not set')
              when v_k = 'verify_code_from' then coalesce(public.register_day(to_date(v_was::bigint::text, 'YYYYMMDD')), 'not set') else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') end;
      v_fv := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then case when v_v = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then public.work_hours_word(v_k, v_v)
              when v_k = 'analytics_from' then substr(public.register_day(to_date(v_v::bigint::text, 'YYYYMM')), 3)
              when v_k = 'verify_code_from' then public.register_day(to_date(v_v::bigint::text, 'YYYYMMDD')) else v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              case when v_drop then v_name || ': planned change withdrawn · ' || v_fw || ' from ' || public.register_day(p_from) ||
                ', stays ' || v_fv else
              case when v_k in ('analytics_from', 'verify_code_from') or (v_k like 'work\_%' and v_k <> 'work_lunch_min') then v_name || ': ' || v_fw || ' → ' || v_fv || ' · from ' || public.register_day(p_from) else
              v_name || ': ' || case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then '' else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') || ' → ' || v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end end end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;

-- END OF HEALTH CHECK-INS BY WORKLOAD ---------------------------------------
select public.functions_tidy();
