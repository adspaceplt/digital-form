-- ===========================================================================
-- PERSONNEL IS AN ADMIN TOOL (2026-11-16), the SQL Editor's part of
-- 2026-11-16-personnel-records.sql
-- ===========================================================================
-- WHY: `team.personnel` is a granted part, an admin tool: only an admin
-- turns it on, changes it or takes it off on any group, as every other
-- granted part (2026-10-24, S2).
--
-- WHAT CHANGED
--   * `team_roles_admin_guard` holds `team.personnel` with the other
--     granted parts (`admin-only`).
--
-- ORDER: after 2026-11-16-personnel-records.sql, in the SQL Editor (its
-- body names DELETE, which the connector holds). Safe to run twice.
--
-- ROLLBACK: team_roles_admin_guard from SUPER ADMIN.
-- ===========================================================================

-- PERSONNEL IS AN ADMIN TOOL ------------------------------------------------

create or replace function public.team_roles_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_granted constant text[] := array['ops.all', 'ops.reports', 'ops.workflows', 'ops.time', 'ops.numbering',
    'ops.override', 'team.performance', 'team.perfadmin', 'team.settings', 'team.upgrade', 'team.invite',
    'team.handbook', 'team.announce', 'team.notice', 'reports.whitelabel', 'reports.transfer', 'reports.ai',
    'reports.meta', 'register.types', 'campaigns.files_delete', 'clients.vic', 'suppliers.pay',
    'team.analytics', 'campaigns.pay', 'team.hiring', 'team.personnel'];
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

-- END OF PERSONNEL IS AN ADMIN TOOL -----------------------------------------

select public.functions_tidy();
