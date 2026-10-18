-- ===========================================================================
-- DUE DATE MOVES THROUGH ITS ASK — ops_change_due_date is closed to every
-- browser. 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored
-- byte for byte in supabase/schema.sql under the same banner; tests/sql.js
-- compares the two.
--
-- WHAT CHANGED (review of 2026-10-18, item 2)
--   ops_change_due_date moves a date the moment it is called. It was still
--   executable by every signed-in account, so a task's assignee could move
--   its final due date straight through it and skip the creator's approval
--   that ops_request_due_change asks for. No page, edge function or cron job
--   calls it (checked in the repo on 2026-10-18); its callers are
--   ops_request_due_change (the creator's or an admin's own move, and the
--   team's first draft date) and ops_decide_due_change (an approved ask),
--   both security definer, which keep reaching it as its owner. It is
--   revoked from public, anon and authenticated.
--
-- ROLLBACK
--   grant execute on function public.ops_change_due_date(uuid, text, timestamptz, text, text, integer) to authenticated;
-- ===========================================================================

revoke all on function public.ops_change_due_date(uuid, text, timestamptz, text, text, integer) from public, anon, authenticated;

-- END OF DUE DATE MOVES THROUGH ITS ASK --------------------------------------

select public.functions_tidy();
