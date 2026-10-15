-- ===========================================================================
-- PUBLIC HOLIDAYS — the days the office is closed, kept by the team, read by
-- the front door and My Work (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-14: "is there a possibility to set public holidays
-- in Malaysia", then "prefill and let manually change and apply to my work")
--   The front door's Service hours drew every weekday 10:00 to 18:00, a
--   public holiday included. The office follows the national holidays and
--   Johor's own, some fixed only weeks ahead and others declared at short
--   notice, so the list is the team's to keep: prefilled from the published
--   Johor calendars for 2026 and 2027, changed by hand as dates are
--   confirmed.
--
-- WHAT IT ADDS
--   * `public_holidays` (day, name): RLS on, no policy, no grant.
--   * `public_holidays_between(p_from, p_to)` (anon): the holidays in a
--     span of at most 800 days, each its day and name; the front door asks
--     for the week ahead, My Work for the month on show, Settings for this
--     year and the next.
--   * `public_holiday_save(p_day, p_name, p_was)` and
--     `public_holiday_delete(p_day)`: Business settings (`team.settings`
--     at Work); a day holds one holiday (`taken`), a name of 2 to 80
--     characters (`bad-name`), a day from 2023 to 2099 (`bad-day`); each
--     filed `team.changed` under Public holidays, from and to.
--   * `public_holiday_on(p_day)`: the holiday's name on a day, else null;
--     the functions' own, closed to every page.
--   * The weekday reminders skip a holiday: the noon reminder
--     (`tasks-reminder`) and the hourly task reminders (`tasks-nudge`) run
--     only on a day that is not one.
--   * The seed: Johor's published holidays for 2026 and 2027, written only
--     into an empty table (a seed is a first run, not a running list).
--
-- ORDER: after 2026-10-07-function-hygiene.sql, whose `open_to_anon` grants
-- anon this section's public reads; run before it, they are revoked.
-- Safe to run twice. Rollback: drop the four functions and the table, and
-- schedule the two reminders again with their earlier commands
-- ('select public.ops_tasks_remind()', 'select public.ops_tasks_nudge()').
-- ===========================================================================

create table if not exists public.public_holidays (
  day date primary key,
  name text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.team_members(id) on delete set null
);
alter table public.public_holidays enable row level security;
revoke all on table public.public_holidays from public, anon, authenticated;

/* The holiday on a day, for the functions that skip one. */
create or replace function public.public_holiday_on(p_day date)
returns text
language sql stable security definer set search_path = public
as $$
  select h.name from public.public_holidays h where h.day = p_day;
$$;
revoke all on function public.public_holiday_on(date) from public, anon, authenticated;

/* The holidays in a span, for the front door and My Work. */
create or replace function public.public_holidays_between(p_from date, p_to date)
returns table (day date, name text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then return; end if;
  return query select h.day, h.name from public.public_holidays h
    where h.day between p_from and p_to order by h.day;
end $$;
revoke all on function public.public_holidays_between(date, date) from public;
grant execute on function public.public_holidays_between(date, date) to anon, authenticated;

/* Add a holiday, or change one (p_was its day before). */
create or replace function public.public_holiday_save(p_day date, p_name text, p_was date default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_me public.team_members;
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_old public.public_holidays;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_day is null or p_day < date '2023-01-01' or p_day > date '2099-12-31' then
    return jsonb_build_object('error', 'bad-day');
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if p_was is not null then
    select * into v_old from public.public_holidays h where h.day = p_was;
    if v_old.day is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if exists (select 1 from public.public_holidays h where h.day = p_day and h.day is distinct from p_was) then
    return jsonb_build_object('error', 'taken', 'name', (select h.name from public.public_holidays h where h.day = p_day));
  end if;
  if v_old.day is not null then
    if v_old.day = p_day and v_old.name = v_name then return jsonb_build_object('ok', true, 'day', p_day); end if;
    delete from public.public_holidays h where h.day = p_was;
  end if;
  insert into public.public_holidays (day, name, updated_at, updated_by)
  values (p_day, v_name, now(), (select m.id from public.team_members m where m.id = v_me.id));
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Public holidays',
    case when v_old.day is null then 'Added: ' || public.register_day(p_day) || ' · ' || v_name
         else 'Changed: ' || public.register_day(v_old.day) || ' · ' || v_old.name || ' → '
              || public.register_day(p_day) || ' · ' || v_name end);
  return jsonb_build_object('ok', true, 'day', p_day);
end $$;
revoke all on function public.public_holiday_save(date, text, date) from public, anon;
grant execute on function public.public_holiday_save(date, text, date) to authenticated;

/* Take a holiday off the list. */
create or replace function public.public_holiday_delete(p_day date)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_me public.team_members;
  v_old public.public_holidays;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  select * into v_old from public.public_holidays h where h.day = p_day;
  if v_old.day is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from public.public_holidays h where h.day = p_day;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, 'admin'), 'team.changed', 'Public holidays',
    'Removed: ' || public.register_day(v_old.day) || ' · ' || v_old.name);
  return jsonb_build_object('ok', true, 'day', p_day, 'name', v_old.name);
end $$;
revoke all on function public.public_holiday_delete(date) from public, anon;
grant execute on function public.public_holiday_delete(date) to authenticated;

/* The seed: Johor's published holidays, 2026 and 2027, into an empty table
   alone. Dates for 2027 were published as estimates; the team corrects them
   as they are gazetted. */
do $$
begin
  if exists (select 1 from public.public_holidays) then return; end if;
  insert into public.public_holidays (day, name) values
    ('2026-02-01', 'Thaipusam'),
    ('2026-02-02', 'Thaipusam (replacement holiday)'),
    ('2026-02-17', 'Chinese New Year'),
    ('2026-02-18', 'Chinese New Year (second day)'),
    ('2026-02-19', 'Awal Ramadan'),
    ('2026-03-20', 'Hari Raya Aidilfitri (additional holiday)'),
    ('2026-03-21', 'Hari Raya Aidilfitri'),
    ('2026-03-22', 'Hari Raya Aidilfitri (second day)'),
    ('2026-03-23', 'Birthday of the Sultan of Johor'),
    ('2026-03-24', 'Hari Raya Aidilfitri (replacement holiday)'),
    ('2026-05-01', 'Labour Day'),
    ('2026-05-27', 'Hari Raya Haji'),
    ('2026-05-31', 'Wesak Day'),
    ('2026-06-01', 'Birthday of the Yang di-Pertuan Agong'),
    ('2026-06-02', 'Wesak Day (replacement holiday)'),
    ('2026-06-17', 'Awal Muharram'),
    ('2026-07-21', 'Hari Hol Almarhum Sultan Iskandar'),
    ('2026-08-25', 'Maulidur Rasul'),
    ('2026-08-31', 'National Day'),
    ('2026-09-16', 'Malaysia Day'),
    ('2026-11-08', 'Deepavali'),
    ('2026-11-09', 'Deepavali (replacement holiday)'),
    ('2026-12-25', 'Christmas Day'),
    ('2027-01-22', 'Thaipusam'),
    ('2027-02-06', 'Chinese New Year'),
    ('2027-02-07', 'Chinese New Year (second day)'),
    ('2027-02-08', 'Awal Ramadan; Chinese New Year (replacement holiday)'),
    ('2027-02-09', 'Awal Ramadan (replacement holiday)'),
    ('2027-03-10', 'Hari Raya Aidilfitri'),
    ('2027-03-11', 'Hari Raya Aidilfitri (second day)'),
    ('2027-03-23', 'Birthday of the Sultan of Johor'),
    ('2027-05-01', 'Labour Day'),
    ('2027-05-17', 'Hari Raya Haji'),
    ('2027-05-20', 'Wesak Day'),
    ('2027-06-06', 'Awal Muharram'),
    ('2027-06-07', 'Birthday of the Yang di-Pertuan Agong'),
    ('2027-06-08', 'Awal Muharram (replacement holiday)'),
    ('2027-07-11', 'Hari Hol Almarhum Sultan Iskandar'),
    ('2027-07-12', 'Hari Hol Almarhum Sultan Iskandar (replacement holiday)'),
    ('2027-08-15', 'Maulidur Rasul'),
    ('2027-08-16', 'Maulidur Rasul (replacement holiday)'),
    ('2027-08-31', 'National Day'),
    ('2027-09-16', 'Malaysia Day'),
    ('2027-10-28', 'Deepavali'),
    ('2027-12-25', 'Christmas Day');
end $$;

/* The weekday reminders skip a public holiday. */
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: the reminders keep their schedules until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'tasks-reminder';
  perform cron.schedule('tasks-reminder', '0 4 * * 1-5',
    'select public.ops_tasks_remind() where public.public_holiday_on((now() at time zone ''Asia/Kuala_Lumpur'')::date) is null');
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'tasks-nudge';
  perform cron.schedule('tasks-nudge', '0 2-9 * * 1-5',
    'select public.ops_tasks_nudge() where public.public_holiday_on((now() at time zone ''Asia/Kuala_Lumpur'')::date) is null');
end $$;

-- END OF PUBLIC HOLIDAYS ----------------------------------------------------
select public.functions_tidy();
