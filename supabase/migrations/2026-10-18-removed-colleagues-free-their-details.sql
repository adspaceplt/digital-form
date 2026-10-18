-- ===========================================================================
-- REMOVED COLLEAGUES FREE THEIR DETAILS — a removed colleague's name, sign-in
-- email and Employee ID may be given to a colleague added again (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 10): a removed colleague is never made active again
-- (`team_access_guard`, `removed`), so one who returns is added again. The
-- name, email and Employee ID indexes counted the removed row, so the new
-- row was refused, and the page read every refusal as "That email is
-- already on the list.".
--
-- WHAT IT CHANGES
--   * Three unique indexes that leave out a removed colleague
--     (`removed_at is null`): `team_members_name_live_idx`,
--     `team_members_email_live_idx`, `team_members_staff_code_live_idx`.
--     Every function that finds a colleague by email already asks an active
--     one (`ops_me`, `allowed`, `is_team`), and an HR reference naming an
--     Employee ID two rows hold names nobody (`hr_member_of`).
--   * The three indexes they replace are dropped. Each `drop` is held by
--     the connector: run the last three lines in the SQL Editor. Until then
--     the old indexes still refuse, and nothing else changes.
--
-- ORDER: the pages (they name the field that clashes) and the edge
-- functions (each asks an active colleague by email), then this file, then
-- the three drops. Safe to run twice.
-- Rollback: create the three old indexes again (it fails while two rows
-- share a value), then drop these three.
-- ===========================================================================

create unique index if not exists team_members_name_live_idx
  on public.team_members (lower(name)) where removed_at is null;
create unique index if not exists team_members_email_live_idx
  on public.team_members (lower(email)) where email is not null and removed_at is null;
create unique index if not exists team_members_staff_code_live_idx
  on public.team_members (upper(staff_code))
  where staff_code is not null and staff_code <> '' and removed_at is null;

drop index if exists public.team_members_name_idx;
drop index if exists public.team_members_email_idx;
drop index if exists public.team_members_staff_code_idx;
-- END OF REMOVED COLLEAGUES FREE THEIR DETAILS ------------------------------

select public.functions_tidy();
