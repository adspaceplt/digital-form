-- ===========================================================================
-- TEAM ACCESS TIME — access may end at a time of day, not only at its end.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/levels.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `team_members.access_until_time`: the time in Malaysia on
--      `access_until` that access ends; empty is the end of that day, as
--      before (the user, 2026-10-03: "03/10/2026 6pm or other manual
--      timings"). `team_access_ends(day, time)` is the moment.
--   2. `team_expire_access()` stands down each colleague whose moment has
--      passed, and runs every five minutes instead of once a morning, so a
--      time is kept to within five minutes. The last admin with access is
--      still never stood down.
--   3. `team_access_guard`: a date or time moved past now on an expired
--      colleague brings them back; Set active before that is refused
--      (`expired-date`); nobody sets their own date or time (`own-expiry`).
--   4. `team_set_expiry_at(p_until, p_time)`: Set access expiry for every
--      active colleague but the caller, with an optional time, refusing a
--      moment already past (`past-date`). `team_set_expiry(p_until)` stays
--      and sets the day's end.
--
-- ROLLBACK
--   Re-run the TEAM ACCESS EXPIRY section (2026-10-01-team-access-expiry.sql):
--   it puts back the three functions and the morning schedule. Then
--   drop function if exists public.team_set_expiry_at(date, time),
--     public.team_access_ends(date, time);
--   The column may stay; nothing else reads it.
-- ===========================================================================

alter table public.team_members add column if not exists access_until_time time;

create or replace function public.team_access_ends(p_day date, p_time time)
returns timestamptz language sql stable as $$
  select case when p_day is null then null
              else ((p_day + coalesce(p_time, time '24:00')) at time zone 'Asia/Kuala_Lumpur') end
$$;
/* The guard is an invoker trigger, so a colleague's own update calls it. */
revoke all on function public.team_access_ends(date, time) from public, anon;
grant execute on function public.team_access_ends(date, time) to authenticated;

create or replace function public.team_access_word(p_day date, p_time time)
returns text language sql stable as $$
  select replace(to_char(p_day, 'FMDD Mon YYYY'), ' Sep ', ' Sept ')
         || coalesce(', ' || case when extract(minute from p_time) = 0
                                  then to_char(p_time, 'FMHH12am')
                                  else to_char(p_time, 'FMHH12.MIam') end, '')
$$;
revoke all on function public.team_access_word(date, time) from public, anon, authenticated;

create or replace function public.team_access_guard()
returns trigger language plpgsql as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  ends timestamptz := public.team_access_ends(new.access_until, new.access_until_time);
  moved boolean := new.access_until is distinct from old.access_until
                   or new.access_until_time is distinct from old.access_until_time;
begin
  if moved and who <> '' and lower(old.email) = who then
    raise exception 'own-expiry' using hint = 'Another admin sets your access date.';
  end if;
  if new.active and not old.active then
    if ends is not null and ends <= now() then
      raise exception 'expired-date' using hint = 'Move the access date first.';
    end if;
    new.expired_at := null;
  elsif old.expired_at is not null and moved and (ends is null or ends > now()) then
    new.active := true;
    new.expired_at := null;
  end if;
  return new;
end $$;
create or replace trigger team_access_guard before update on public.team_members
  for each row execute function public.team_access_guard();

create or replace function public.team_expire_access()
returns int language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  n int := 0;
begin
  for m in select * from public.team_members t
            where t.active and t.access_until is not null
              and public.team_access_ends(t.access_until, t.access_until_time) <= now()
            order by t.access_until, t.access_until_time nulls last, t.name loop
    if (m.is_admin or m.role = 'admin') and not exists (
         select 1 from public.team_members o
          where o.id <> m.id and o.active and (o.is_admin or o.role = 'admin')
            and (o.access_until is null
                 or public.team_access_ends(o.access_until, o.access_until_time) > now())) then
      continue;
    end if;
    update public.team_members set active = false, expired_at = now() where id = m.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('system', 'team.changed', m.name,
            case when m.access_until_time is null
                 then 'Access expired after ' || public.team_access_word(m.access_until, null)
                 else 'Access expired at ' || public.team_access_word(m.access_until, m.access_until_time) end);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.team_expire_access() from public, anon, authenticated;

create or replace function public.team_set_expiry_at(p_until date, p_time time)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_time time := case when p_until is null then null else p_time end;
  n int;
begin
  if not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if p_until is not null and public.team_access_ends(p_until, v_time) <= now() then
    return jsonb_build_object('error', 'past-date');
  end if;
  update public.team_members t set access_until = p_until, access_until_time = v_time
   where t.active and lower(t.email) <> who
     and (t.access_until is distinct from p_until or t.access_until_time is distinct from v_time);
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'team.changed', 'Team',
            'Access until ' || coalesce(public.team_access_word(p_until, v_time), 'not set')
            || ' for ' || n || case when n = 1 then ' colleague' else ' colleagues' end);
  end if;
  return jsonb_build_object('ok', true, 'count', n);
end $$;
grant execute on function public.team_set_expiry_at(date, time) to authenticated;

create or replace function public.team_set_expiry(p_until date)
returns jsonb language sql security definer set search_path = public as $$
  select public.team_set_expiry_at(p_until, null)
$$;
grant execute on function public.team_set_expiry(date) to authenticated;

/* Every five minutes, so a time of day is kept to within five minutes. */
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'team-access-expiry: pg_cron is not installed, so no schedule was written.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'team-access-expiry';
  perform cron.schedule('team-access-expiry', '*/5 * * * *', 'select public.team_expire_access()');
end $$;

-- END OF TEAM ACCESS TIME -----------------------------------------------------
