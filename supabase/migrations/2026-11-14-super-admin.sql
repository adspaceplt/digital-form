-- ===========================================================================
-- SUPER ADMIN (2026-11-14)
-- ===========================================================================
-- WHY (the user, 2026-11-14): the system account is the super admin, "the
-- only one who can make or remove admins", and it "can stop receiving any
-- work notices".
--
-- WHAT IT CHANGES
--   * `team_super_ok()`: true for the active system account, or for anyone
--     while no active system account exists. Triggers alone call it.
--   * `team_admin_guard` refuses `super-only` a colleague made admin, or an
--     admin's group, admin mark, standing or removal changed, by anybody
--     but the super admin; the rest as OWN GROUP THROUGH AN ADMIN left it.
--   * `team_roles_admin_guard` refuses `super-only` a group made admin or
--     made plain, or an admin group made or deleted, by anybody but it.
--   * Trigger `ops_notifications_a_super_quiet` writes no notice to a system
--     account but a failed scheduled job's.
--
-- ORDER: this file, then the pages. A page served before offers an admin
-- the acts the database now refuses; the refusal reads as its own.
-- Safe to run twice.
--
-- ROLLBACK: restate `team_admin_guard` from OWN GROUP THROUGH AN ADMIN and
-- `team_roles_admin_guard` from its last band before this one, then
-- drop trigger ops_notifications_a_super_quiet on public.ops_notifications;
-- drop function public.ops_notifications_super_quiet(), public.team_super_ok().
-- ===========================================================================

-- SUPER ADMIN ----------------------------------------------------------------

/* The system account is the super admin (the user, 2026-11-14: "make it the
   only one who can make or remove admins. He has the most highest power on
   the portal", "can stop receiving any work notices"). While an active
   system account exists, only it makes a colleague or a group admin, or
   changes an admin's group, admin mark or standing; with none, an admin does,
   as before, so the portal is never left with nobody able to. Signed out
   (the SQL Editor, the connector) nothing is refused. */
create or replace function public.team_super_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.team_members s
                      where s.system and s.active and s.removed_at is null)
      or exists (select 1 from public.team_members s
                  where s.system and s.active and s.removed_at is null
                    and lower(s.email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
revoke all on function public.team_super_ok() from public, anon, authenticated;

create or replace function public.team_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who      text := lower(coalesce(auth.jwt() ->> 'email', ''));
  was      boolean;
  will     boolean;
begin
  if who = '' or pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op <> 'INSERT' then was := coalesce(old.is_admin, false) or old.role = 'admin'; end if;
  if tg_op <> 'DELETE' then
    will := new.role = 'admin'
         or exists (select 1 from public.team_roles r where r.slug = new.role and r.is_admin);
  end if;
  /* Making or removing an admin is the super admin's alone; its own row
     is `team_members_system_guard`'s. */
  if not public.team_super_ok() and not (tg_op <> 'INSERT' and coalesce(old.system, false)) then
    if tg_op = 'DELETE' and was then
      raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin removes an admin.';
    end if;
    if tg_op <> 'DELETE' and will and not coalesce(was, false) then
      raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin makes a colleague admin.';
    end if;
    if tg_op = 'UPDATE' and was and (
         new.role is distinct from old.role
      or new.is_admin is distinct from old.is_admin
      or new.active is distinct from old.active
      or new.removed_at is distinct from old.removed_at) then
      raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin changes an admin.';
    end if;
  end if;
  if public.allowed('admin') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    if was then
      raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin removes an admin.';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and new.role is distinct from old.role and lower(old.email) = who then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes your own group.';
  end if;
  if will and not coalesce(was, false) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin makes a colleague admin.';
  end if;
  if tg_op = 'UPDATE' and was and (
       new.role is distinct from old.role
    or new.is_admin is distinct from old.is_admin
    or new.access is distinct from old.access
    or new.access_until is distinct from old.access_until
    or new.access_until_time is distinct from old.access_until_time
    or new.active is distinct from old.active
    or new.removed_at is distinct from old.removed_at
    or lower(new.email) is distinct from lower(old.email)) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin.';
  end if;
  return new;
end $$;
revoke all on function public.team_admin_guard() from public, anon, authenticated;

create or replace trigger team_admin_guard before insert or update or delete on public.team_members
  for each row execute function public.team_admin_guard();

create or replace function public.team_roles_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_granted constant text[] := array['ops.all', 'ops.reports', 'ops.workflows', 'ops.time', 'ops.numbering',
    'ops.override', 'team.performance', 'team.perfadmin', 'team.settings', 'team.upgrade', 'team.invite',
    'team.handbook', 'team.announce', 'team.notice', 'reports.whitelabel', 'reports.transfer', 'reports.ai',
    'reports.meta', 'register.types', 'campaigns.files_delete', 'clients.vic', 'suppliers.pay',
    'team.analytics', 'campaigns.pay'];
  k text;
begin
  if who = '' or pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  /* A group made admin, an admin group made plain, made or deleted: the
     super admin's alone. */
  if not public.team_super_ok() and (
       (tg_op = 'INSERT' and (coalesce(new.is_admin, false) or new.slug = 'admin'))
    or (tg_op = 'DELETE' and (coalesce(old.is_admin, false) or old.slug = 'admin'))
    or (tg_op = 'UPDATE' and coalesce(new.is_admin, false) is distinct from coalesce(old.is_admin, false))) then
    raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin makes or removes an admin group.';
  end if;
  if public.allowed('admin') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if (tg_op <> 'INSERT' and (coalesce(old.is_admin, false) or old.slug = 'admin'))
     or (tg_op <> 'DELETE' and (coalesce(new.is_admin, false) or new.slug = 'admin')) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin group.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  foreach k in array v_granted loop
    if coalesce(new.access ->> k, '') is distinct from
       (case when tg_op = 'INSERT' then '' else coalesce(old.access ->> k, '') end) then
      raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin tool.';
    end if;
  end loop;
  return new;
end $$;
revoke all on function public.team_roles_admin_guard() from public, anon, authenticated;

/* The super admin takes no work notices: a notice to it is not written, so
   no bell, push or WhatsApp follows. A failed scheduled job (`jobs.failed`)
   still reaches it, as the account kept for IT. */
create or replace function public.ops_notifications_super_quiet()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind is distinct from 'jobs.failed'
     and exists (select 1 from public.team_members s where s.id = new.team_member_id and s.system) then
    return null;
  end if;
  return new;
end $$;
revoke all on function public.ops_notifications_super_quiet() from public, anon, authenticated;
create or replace trigger ops_notifications_a_super_quiet
  before insert on public.ops_notifications
  for each row execute function public.ops_notifications_super_quiet();

-- END OF SUPER ADMIN ---------------------------------------------------------

select public.functions_tidy();
