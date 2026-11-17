-- ============================================================================
-- A USER GROUP DELETED WITH ITS MEMBERS MOVED (2026-11-17)
-- ============================================================================
-- The user, 2026-11-17: "why never give Team > Groups not able to delete??
-- i thot i have given multiple instructions to have delete options for every
-- create". Until now Delete was offered only on an empty group.
--
--   * `team_role_delete(p_slug, p_to)`: an admin's alone (`admin-only`); an
--     admin group, or members moved into one, the super admin's while one is
--     active (`super-only`); the Admin group never (`fixed`). A group holding
--     colleagues (removed ones too: the foreign key) moves every one of them
--     to `p_to` in the same transaction (`no-target` without one), so each
--     takes that group's access through `team_role_defaults`; the last admin
--     is kept by `team_members_last_admin` as on any move (`last-admin`). A
--     group that others report to leaves them reporting to nobody (the
--     foreign key's `on delete set null`). Filed `team.group_removed` with
--     how many moved and where.
--
-- ORDER: this file (connector), then the pages. An old page keeps its own
-- delete of an empty group, which still works. Safe to run twice.
-- ROLLBACK: `drop function public.team_role_delete(text, text);`
-- ============================================================================

-- A USER GROUP DELETED -------------------------------------------------------

create or replace function public.team_role_delete(p_slug text, p_to text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.team_roles;
  t public.team_roles;
  n int;
begin
  if me.id is null or not public.allowed('admin') then return jsonb_build_object('error', 'admin-only'); end if;
  select * into r from public.team_roles g where g.slug = p_slug for update;
  if r.slug is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.slug = 'admin' then return jsonb_build_object('error', 'fixed'); end if;
  if coalesce(r.is_admin, false) and not public.team_super_ok() then return jsonb_build_object('error', 'super-only'); end if;
  select count(*) into n from public.team_members m where m.role = r.slug;
  if n > 0 then
    select * into t from public.team_roles g where g.slug = p_to;
    if t.slug is null or t.slug = r.slug then return jsonb_build_object('error', 'no-target', 'members', n); end if;
    if (coalesce(t.is_admin, false) or t.slug = 'admin') and not public.team_super_ok() then
      return jsonb_build_object('error', 'super-only');
    end if;
    update public.team_members m set role = t.slug where m.role = r.slug;
  end if;
  delete from public.team_roles g where g.slug = r.slug;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.group_removed', r.name,
          case when n > 0 then n || case when n = 1 then ' member' else ' members' end || ' moved to ' || t.name else 'No members' end);
  return jsonb_build_object('ok', true, 'moved', n);
end $$;
grant execute on function public.team_role_delete(text, text) to authenticated;

-- END OF A USER GROUP DELETED ------------------------------------------------

select public.functions_tidy();
