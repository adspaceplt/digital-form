-- ===========================================================================
-- A SIGN-IN EMAIL MOVES ONLY THROUGH AN ADMIN — a colleague's sign-in email
-- is changed by an admin alone (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 7; the user: a colleague's email changes only
-- through an admin): `team_admin_guard` held the email on an admin's row
-- alone, so Team Full Access could re-point a colleague's sign-in email to
-- an address of their own and sign in as them.
--
-- WHAT IT CHANGES
--   * Trigger `team_email_guard` (before an update of `email`): with a
--     sign-in, anybody but an admin changing a colleague's email is refused
--     `admin-only`. Deleting a colleague's details (`team_member_remove`,
--     which empties the email as it stamps the erasure) and a run with no
--     sign-in are not held. A system account changing its own address stays
--     as `team_members_system_guard` allows (it is an admin).
--   * The Team page offers the email to an admin alone.
--
-- ORDER: this file, then the pages (an open page from before meets the
-- refusal in words). Safe to run twice.
-- Rollback: `drop trigger team_email_guard on public.team_members` and its
-- function in the SQL Editor.
-- ===========================================================================

create or replace function public.team_email_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.jwt() ->> 'email', '') = '' or public.allowed('admin') then return new; end if;
  if lower(new.email) is not distinct from lower(old.email) then return new; end if;
  if new.erased_at is not null and old.erased_at is null and new.email is null then return new; end if;
  raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes a sign-in email.';
end $$;
revoke all on function public.team_email_guard() from public, anon, authenticated;
create or replace trigger team_email_guard before update of email on public.team_members
  for each row execute function public.team_email_guard();

-- END OF A SIGN-IN EMAIL MOVES ONLY THROUGH AN ADMIN ------------------------

select public.functions_tidy();
