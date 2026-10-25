-- ===========================================================================
-- ANALYTICS IS AN ADMIN TOOL — the granted part team.analytics joins the
-- admin tools only an admin turns on (2026-10-25)
-- ===========================================================================
-- WHY (the user, 2026-10-25: an internal Analytics section of trends and
-- forecasts, "Admins only (Recommended)")
--   Analytics is a granted part, `team.analytics`, an admin's by itself and
--   any other group's only once an admin gives it. The page alone asks it
--   (every figure it draws is read under the sections' own policies), so the
--   database's part is that nobody but an admin gives it.
--
-- WHAT CHANGED
--   * `team_roles_admin_guard` holds `team.analytics` with the other granted
--     parts: a signed-in caller who is not an admin cannot turn it on,
--     change it or take it off on any group (`admin-only`).
--
-- ORDER
--   The page (which offers the switch to an admin alone), then this file.
--   Until it runs, a non-admin at Team Full Access could give a group
--   Analytics, which reads nothing the group's sections do not already open.
--
-- Safe to run twice. Rollback: run ADMIN TOOLS ARE AN ADMIN'S
-- (2026-10-24-admin-tools-admins-only.sql) again.
-- ===========================================================================

create or replace function public.team_roles_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_granted constant text[] := array['ops.all', 'ops.reports', 'ops.workflows', 'ops.time', 'ops.numbering',
    'ops.override', 'team.performance', 'team.perfadmin', 'team.settings', 'team.upgrade', 'team.invite',
    'team.handbook', 'team.announce', 'team.notice', 'reports.whitelabel', 'reports.transfer', 'reports.ai',
    'reports.meta', 'register.types', 'campaigns.files_delete', 'clients.vic', 'suppliers.pay',
    'team.analytics'];
  k text;
begin
  if who = '' or pg_trigger_depth() > 1 or public.allowed('admin') then
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

-- END OF ANALYTICS IS AN ADMIN TOOL ----------------------------------------

select public.functions_tidy();
