-- ===========================================================================
-- SYSTEM ACCOUNT — a login kept for IT and development: a full admin that
-- is never offered for work, and that no other admin can stand down, expire
-- or move.
-- 2026-10-08. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/team.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-08: "disable users from selecting one admin on assigned
--   to or all others, as this account is used for system IT development only
--   … its own account wouldn't be restricted".
--   1. `team_members.system` (false by default). It is set only from the SQL
--      editor or the connector (no sign-in on the call); a browser that tries
--      is refused `system-account`. Which account is set is data, never this
--      file.
--   2. Trigger `team_members_system_guard` (before update): on a system
--      account, only the account itself changes whether it is active, its
--      access date and time, its group, its admin mark or its email; anyone
--      else is refused `system-account`. A cascade from its group
--      (`pg_trigger_depth() > 1`) and a call with no sign-in (the access
--      sweep, the SQL editor) pass.
--   3. `team_set_expiry_at` (Set access expiry for everyone) leaves system
--      accounts out.
--   4. `sm_report_may_review` never names a system account, so it is never
--      offered as a report's reviewer.
--   The console's pickers leave it out (`ADspaceAdmin.isSystem`); Team shows
--   it with a System tag and no ⋯ for anyone else.
--
-- ROLLBACK
--   drop trigger team_members_system_guard on public.team_members;
--   drop function public.team_members_system_guard();
--   alter table public.team_members drop column system;
--   (team_set_expiry_at and sm_report_may_review: re-run their sections.)
-- ===========================================================================

alter table public.team_members add column if not exists system boolean not null default false;

create or replace function public.team_members_system_guard()
returns trigger
language plpgsql set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if who = '' or pg_trigger_depth() > 1 then return new; end if;
  if new.system is distinct from old.system then
    raise exception 'system-account' using hint = 'A system account is set from the database.';
  end if;
  if old.system and lower(old.email) <> who and (
       new.active is distinct from old.active
    or new.access_until is distinct from old.access_until
    or new.access_until_time is distinct from old.access_until_time
    or new.role is distinct from old.role
    or new.is_admin is distinct from old.is_admin
    or lower(new.email) is distinct from lower(old.email)) then
    raise exception 'system-account' using hint = 'This is a system account.';
  end if;
  return new;
end $$;
revoke all on function public.team_members_system_guard() from public, anon, authenticated;

create or replace trigger team_members_system_guard before update on public.team_members
  for each row execute function public.team_members_system_guard();

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
   where t.active and lower(t.email) <> who and not t.system
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

create or replace function public.sm_report_may_review(p_member uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.team_members m
     where m.id = p_member and m.active and not m.system
       and (coalesce(m.is_admin, false) or m.role = 'admin'
            or public.level_rank(coalesce(m.access ->> 'reports', 'none')) >= public.level_rank('manage')))
$$;
revoke all on function public.sm_report_may_review(uuid) from public, anon, authenticated;

-- END OF SYSTEM ACCOUNT -------------------------------------------------------

select public.functions_tidy();
