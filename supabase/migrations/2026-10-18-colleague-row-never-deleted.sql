-- ===========================================================================
-- A COLLEAGUE'S ROW IS NEVER DELETED — the team table takes inserts and
-- updates at Team Full Access, and no delete from anybody (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 5): policy `team_admin` was `for all`, so Team Full
-- Access or an admin could DELETE a colleague's row over REST, cascading into
-- their performance reviews, commissions, health and notifications with no
-- activity entry, where a colleague is only ever stood down or removed.
--
-- WHAT IT CHANGES
--   * `team_insert` (insert) and `team_update` (update), each at
--     `allowed('team', 'manage')` as before; `team_read` is unchanged.
--   * `team_admin` is dropped, so no policy admits a delete: a page's delete
--     is answered with no row, for an admin too. Removal stays the function's
--     (`team_member_remove`), which deletes nothing of the row.
--
-- ORDER: this file alone (no page deletes a colleague). The drop is held by
-- the connector: the two policies are applied first, then the drop in the
-- SQL Editor; until then the old policy stands beside them. Safe to run
-- twice.
-- Rollback: `create policy team_admin on public.team_members for all to
-- authenticated using (public.allowed('team', 'manage')) with check
-- (public.allowed('team', 'manage'));` then drop the two policies.
-- ===========================================================================

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'team_members' and policyname = 'team_insert') then
    create policy team_insert on public.team_members for insert to authenticated
      with check (public.allowed('team', 'manage'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'team_members' and policyname = 'team_update') then
    create policy team_update on public.team_members for update to authenticated
      using (public.allowed('team', 'manage'))
      with check (public.allowed('team', 'manage'));
  end if;
end $$;
drop policy if exists team_admin on public.team_members;

-- END OF A COLLEAGUE'S ROW IS NEVER DELETED ---------------------------------

select public.functions_tidy();
