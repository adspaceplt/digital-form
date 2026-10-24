-- ===========================================================================
-- ADMIN TOOLS ARE AN ADMIN'S — only an admin turns on, changes or takes off a
-- granted part on any group (2026-10-24)
-- ===========================================================================
-- WHY (the permissions audit of 2026-10-24, S2; the user decided "admins
-- only", declining that Team Full Access delegate Performance or HR Letters)
--   A colleague at Team Full Access who is not an admin could open a group,
--   their own included, and switch on any admin tool (Business settings,
--   Upgrade mode, Performance reviews, Supplier bank details …): the tools
--   are granted parts in `access`, and `team_roles_admin_guard` held only a
--   group made admin.
--
-- WHAT CHANGED
--   * `team_roles_admin_guard` also refuses, for a signed-in caller who is
--     not an admin, a group written (made or changed) whose granted parts
--     differ from what it held (`admin-only`). The granted parts are those
--     `ops_granted` is asked for, the page's GRANTED: ops.all, ops.reports,
--     ops.workflows, ops.time, ops.numbering, ops.override,
--     team.performance, team.perfadmin, team.settings, team.upgrade,
--     team.invite, team.handbook, team.announce, team.notice,
--     reports.whitelabel, reports.transfer, reports.ai, reports.meta,
--     register.types, campaigns.files_delete, clients.vic, suppliers.pay.
--     Every other key, and a group's name and scope, stay Team Full
--     Access's. An admin, a write made by another trigger and a run with no
--     sign-in pass, as before.
--
-- ORDER
--   This file, then the page, which disables the switches and granted
--   selects for anyone not an admin. An open page before still offers them
--   and meets the refusal in the team's words.
--
-- Safe to run twice. Rollback: run ADMINS MADE BY ADMINS'
-- team_roles_admin_guard again.
-- ===========================================================================

create or replace function public.team_roles_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_granted constant text[] := array['ops.all', 'ops.reports', 'ops.workflows', 'ops.time', 'ops.numbering',
    'ops.override', 'team.performance', 'team.perfadmin', 'team.settings', 'team.upgrade', 'team.invite',
    'team.handbook', 'team.announce', 'team.notice', 'reports.whitelabel', 'reports.transfer', 'reports.ai',
    'reports.meta', 'register.types', 'campaigns.files_delete', 'clients.vic', 'suppliers.pay'];
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

-- END OF ADMIN TOOLS ARE AN ADMIN'S ------------------------------------------

select public.functions_tidy();
