-- ===========================================================================
-- ADMINS MADE BY ADMINS — only an admin makes a colleague or a group admin,
-- or changes an admin's standing. 2026-10-17. Safe to run twice. Rollback
-- at the foot. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/levels.js compares the two.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding E)
--   Team Full Access (`team_admin`, `roles_admin`: `allowed('team',
--   'manage')`) could move a colleague, themselves included, into the Admin
--   group, tick Admin on any group (`team_role_defaults` copies `is_admin`
--   from the group), or change an admin's group, access, access date, sign-in
--   email or standing; nothing but `team_keep_one_admin` (one's own row)
--   stood in the way. So Team Full Access was admin.
--   1. Trigger `team_admin_guard` on `team_members`, for a signed-in caller
--      who is not an admin: refuses a row made admin (its group is Admin or
--      an admin group), and on an admin's row a change of group, access,
--      access date or time, sign-in email, active or removed, or its removal
--      (`admin-only`). It fires before `team_role_defaults`, so the group
--      named is what is judged. A group's re-stamp (a trigger inside a
--      trigger) and a run with no sign-in (the expiry job, the SQL Editor)
--      pass, as every other guard on the table lets them.
--   2. Trigger `team_roles_admin_guard` on `team_roles`, for the same
--      caller: refuses a group made admin, any change to an admin group,
--      and its removal (`admin-only`).
--   3. `team_set_expiry_at` (the bar's Set access expiry) leaves an admin's
--      date alone when the caller is not an admin, rather than failing for
--      everyone; `team_member_remove_check` answers `admin-only` before any
--      work is handed over.
--   An admin's own acts are unchanged.
--
-- ROLLBACK
--   drop trigger if exists team_admin_guard on public.team_members;
--   drop trigger if exists team_roles_admin_guard on public.team_roles;
--   drop function if exists public.team_admin_guard();
--   drop function if exists public.team_roles_admin_guard();
--   Run team_set_expiry_at from SYSTEM ACCOUNT and team_member_remove_check
--   from COLLEAGUE REMOVE CHECK again.
-- ===========================================================================

create or replace function public.team_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who      text := lower(coalesce(auth.jwt() ->> 'email', ''));
  was      boolean;
  will     boolean;
begin
  if who = '' or pg_trigger_depth() > 1 or public.allowed('admin') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op <> 'INSERT' then was := coalesce(old.is_admin, false) or old.role = 'admin'; end if;
  if tg_op <> 'DELETE' then
    will := new.role = 'admin'
         or exists (select 1 from public.team_roles r where r.slug = new.role and r.is_admin);
  end if;
  if tg_op = 'DELETE' then
    if was then
      raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin removes an admin.';
    end if;
    return old;
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
  return new;
end $$;
revoke all on function public.team_roles_admin_guard() from public, anon, authenticated;

create or replace trigger team_roles_admin_guard before insert or update or delete on public.team_roles
  for each row execute function public.team_roles_admin_guard();

create or replace function public.team_set_expiry_at(p_until date, p_time time)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_time time := case when p_until is null then null else p_time end;
  v_admin boolean := public.allowed('admin');
  n int;
begin
  if not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if p_until is not null and public.team_access_ends(p_until, v_time) <= now() then
    return jsonb_build_object('error', 'past-date');
  end if;
  update public.team_members t set access_until = p_until, access_until_time = v_time
   where t.active and lower(t.email) <> who and not t.system
     and (v_admin or not (coalesce(t.is_admin, false) or t.role = 'admin'))
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

create or replace function public.team_member_remove_check(p_member uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  v_m public.team_members;
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_m from public.team_members x where x.id = p_member;
  if v_m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_m.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and not public.allowed('admin') then
    return jsonb_build_object('error', 'admin-only');
  end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and v_m.active
     and not exists (select 1 from public.team_members x where x.id <> v_m.id and x.active
                       and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    return jsonb_build_object('error', 'last-admin');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_member_remove_check(uuid) from public, anon;
grant execute on function public.team_member_remove_check(uuid) to authenticated;

-- END OF ADMINS MADE BY ADMINS -----------------------------------------------

select public.functions_tidy();
