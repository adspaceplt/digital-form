-- ===========================================================================
-- GROUP AND RATE CARD POLICIES, ONE A COMMAND (2026-11-20)
-- ===========================================================================
-- WHY (Supabase's performance advisor, 2026-11-20: multiple permissive
-- policies on `services` and `team_roles` for SELECT; the user: "ok merge
-- the two policies too")
--   Each table held a read policy (`is_team()`) beside one `for all`
--   policy, so every read asked both, and a `for all` policy is what the
--   portal's rule refuses (a delete is checked against USING alone; one
--   policy a command, `2026-10-08-delete-at-its-level.sql`).
--
-- WHAT CHANGES
--   * `services_admin` and `roles_admin` give way to an insert, an update
--     and a delete policy each, on the same condition as before (Services
--     at Full Access; an admin); the read policies stay as they are. Who
--     may read, add, change or remove a rate card line or a user group is
--     unchanged, and `team_roles_admin_guard` still holds every group write.
--
-- ORDER: this file alone; the pages are unchanged. Safe to run twice.
-- Rollback: drop the six policies and create `services_admin` and
-- `roles_admin` again `for all` on the same conditions.
-- ===========================================================================

drop policy if exists services_admin on public.services;
drop policy if exists services_insert on public.services;
drop policy if exists services_update on public.services;
drop policy if exists services_delete on public.services;
create policy services_insert on public.services for insert to authenticated
  with check (public.allowed('services', 'manage'));
create policy services_update on public.services for update to authenticated
  using (public.allowed('services', 'manage')) with check (public.allowed('services', 'manage'));
create policy services_delete on public.services for delete to authenticated
  using (public.allowed('services', 'manage'));

drop policy if exists roles_admin on public.team_roles;
drop policy if exists roles_insert on public.team_roles;
drop policy if exists roles_update on public.team_roles;
drop policy if exists roles_delete on public.team_roles;
create policy roles_insert on public.team_roles for insert to authenticated
  with check (public.allowed('admin'));
create policy roles_update on public.team_roles for update to authenticated
  using (public.allowed('admin')) with check (public.allowed('admin'));
create policy roles_delete on public.team_roles for delete to authenticated
  using (public.allowed('admin'));

-- END OF GROUP AND RATE CARD POLICIES -----------------------------------------
