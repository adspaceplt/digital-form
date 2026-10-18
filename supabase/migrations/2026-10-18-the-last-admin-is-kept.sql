-- ===========================================================================
-- THE LAST ADMIN IS KEPT — two colleagues standing admins down at the same
-- moment never leave the team with none (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 14): `team_member_remove` and the page's Set
-- inactive each asked whether another admin is active, then wrote, with
-- nothing holding the answer. Two admins removing or standing down each
-- other at once both found the other still active, and both went.
--
-- WHAT IT CHANGES
--   * Trigger `team_members_last_admin` (before update of active, role,
--     is_admin): a signed-in write that takes away an active admin first
--     takes the team's admin lock (an advisory lock held to the end of its
--     transaction), then refuses `last-admin` where no other active admin
--     stands. The second of two such writes waits for the first and reads
--     what it committed. It takes an advisory lock rather than the admin
--     rows' own, since each write already holds its own row and two row
--     locks taken in turn by two writes would deadlock.
--   * `team_member_remove` and `team_keep_one_admin` are not restated: each
--     body holds a word the connector stops on, and the trigger covers
--     every write they make. With no sign-in (the access expiry's run, the
--     SQL Editor) nothing is held, as before.
--
-- ORDER: this file; the pages read `last-admin` already. Safe to run twice.
-- Rollback: drop the trigger and the function (SQL Editor).
-- ===========================================================================

create or replace function public.team_members_last_admin()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.jwt() ->> 'email', '') = '' then return new; end if;
  if not (old.active and (coalesce(old.is_admin, false) or old.role = 'admin')) then return new; end if;
  if new.active and (new.role = 'admin'
                     or coalesce((select r.is_admin from public.team_roles r where r.slug = new.role), false)) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('team-last-admin'));
  if not exists (select 1 from public.team_members x
                  where x.id <> old.id and x.active
                    and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    raise exception 'last-admin' using errcode = 'P0001',
      hint = 'This is the last admin with access. Make another colleague admin first.';
  end if;
  return new;
end $$;
revoke all on function public.team_members_last_admin() from public, anon, authenticated;
create or replace trigger team_members_last_admin
  before update of active, role, is_admin on public.team_members
  for each row execute function public.team_members_last_admin();
-- END OF THE LAST ADMIN IS KEPT ---------------------------------------------

select public.functions_tidy();
