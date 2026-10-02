-- ===========================================================================
-- TEAM ACCESS EXPIRY — a colleague's access ends on a date unless extended.
-- 2026-10-01. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/levels.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `team_members.access_until`: the last day, in Malaysia, a colleague's
--      access runs; empty for no end. `expired_at` says when it ended.
--   2. Every morning at 00:05 in Malaysia, `team_expire_access()` stands
--      down each active colleague whose day has passed (`active` false, as
--      Set inactive does, so every policy, function and picker that asks
--      for an active colleague refuses them), and files it under Access
--      changed. The last admin with access is never stood down: the console
--      cannot be run without one.
--   3. `team_access_guard`: nobody sets their own date (`own-expiry`), and a
--      date moved to today or later on an expired colleague brings them back
--      at once; Set active on one whose date has passed is refused
--      (`expired-date`) until the date is moved.
--   4. `team_set_expiry(p_until)`: Team at Manage sets one date (or none)
--      for every active colleague but the caller, refusing a past date.
--   5. `my_access_expired()`: whether the signed-in address was stood down
--      by its date, so the console says Access expired, not Access denied.
--
-- ROLLBACK
--   select cron.unschedule('team-access-expiry');
--   drop trigger if exists team_access_guard on public.team_members;
--   drop function if exists public.team_access_guard(), public.team_expire_access(),
--     public.team_set_expiry(date), public.my_access_expired();
--   The two columns may stay; nothing else reads them.
-- ===========================================================================

alter table public.team_members add column if not exists access_until date;
alter table public.team_members add column if not exists expired_at timestamptz;

create or replace function public.team_access_guard()
returns trigger language plpgsql as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if new.access_until is distinct from old.access_until and who <> '' and lower(old.email) = who then
    raise exception 'own-expiry' using hint = 'Another admin sets your access date.';
  end if;
  if new.active and not old.active then
    if new.access_until is not null and new.access_until < today then
      raise exception 'expired-date' using hint = 'Move the access date first.';
    end if;
    new.expired_at := null;
  elsif old.expired_at is not null and new.access_until is distinct from old.access_until
        and (new.access_until is null or new.access_until >= today) then
    new.active := true;
    new.expired_at := null;
  end if;
  return new;
end $$;
drop trigger if exists team_access_guard on public.team_members;
create trigger team_access_guard before update on public.team_members
  for each row execute function public.team_access_guard();

create or replace function public.team_expire_access()
returns int language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  m public.team_members;
  n int := 0;
begin
  for m in select * from public.team_members t
            where t.active and t.access_until is not null and t.access_until < today
            order by t.access_until, t.name loop
    if (m.is_admin or m.role = 'admin') and not exists (
         select 1 from public.team_members o
          where o.id <> m.id and o.active and (o.is_admin or o.role = 'admin')
            and (o.access_until is null or o.access_until >= today)) then
      continue;
    end if;
    update public.team_members set active = false, expired_at = now() where id = m.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('system', 'team.changed', m.name,
            'Access expired after ' || replace(to_char(m.access_until, 'FMDD Mon YYYY'), ' Sep ', ' Sept '));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.team_expire_access() from public, anon, authenticated;

create or replace function public.team_set_expiry(p_until date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  n int;
begin
  if not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if p_until is not null and p_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'past-date');
  end if;
  update public.team_members t set access_until = p_until
   where t.active and lower(t.email) <> who and t.access_until is distinct from p_until;
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'team.changed', 'Team',
            'Access until ' || coalesce(replace(to_char(p_until, 'FMDD Mon YYYY'), ' Sep ', ' Sept '), 'not set')
            || ' for ' || n || case when n = 1 then ' colleague' else ' colleagues' end);
  end if;
  return jsonb_build_object('ok', true, 'count', n);
end $$;
grant execute on function public.team_set_expiry(date) to authenticated;

create or replace function public.my_access_expired()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.team_members t
                  where lower(t.email) = lower(auth.jwt() ->> 'email')
                    and not t.active and t.expired_at is not null)
$$;
grant execute on function public.my_access_expired() to authenticated;

/* Every morning at 00:05 in Malaysia (16:05 UTC). */
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'team-access-expiry: pg_cron is not installed, so no schedule was written.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'team-access-expiry';
  perform cron.schedule('team-access-expiry', '5 16 * * *', 'select public.team_expire_access()');
end $$;

-- END OF TEAM ACCESS EXPIRY ---------------------------------------------------
