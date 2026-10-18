-- ===========================================================================
-- A STALE TEAM SAVE IS REFUSED — a colleague's or a group's save is written
-- only over the row as it was read (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 9): the member sheet writes every field each time
-- and a group sends its whole access map, so two people editing the same
-- colleague or group overwrote each other without knowing.
--
-- WHAT IT CHANGES
--   * `team_roles.updated_at`, stamped on every change by trigger
--     `team_roles_touch` (`team_members.updated_at` is already stamped by
--     `team_role_defaults`). The pages write a colleague and a group with
--     `.eq('updated_at', …)` as read, so a row changed meanwhile answers no
--     row; the page tells that apart from a refusal, says so and reads the
--     row again (as a client's request is written, audit C2).
--
-- ORDER: this file, then the pages. Safe to run twice.
-- Rollback: the pages from before; the column and trigger may stay.
-- ===========================================================================

alter table public.team_roles add column if not exists updated_at timestamptz not null default now();

create or replace function public.team_roles_touch()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;
revoke all on function public.team_roles_touch() from public, anon, authenticated;
create or replace trigger team_roles_touch before update on public.team_roles
  for each row execute function public.team_roles_touch();

-- END OF A STALE TEAM SAVE IS REFUSED ---------------------------------------

select public.functions_tidy();
