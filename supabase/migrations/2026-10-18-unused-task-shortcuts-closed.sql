-- ===========================================================================
-- UNUSED TASK SHORTCUTS CLOSED — the first operations model's Finish and
-- Reopen are closed to every browser. 2026-10-18. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (second audit, item 3)
--   ops_complete_task and ops_reopen_task (THE OPERATIONS SYSTEM, 2026-09-19)
--   were still executable by every signed-in account, a client contact
--   included. They write stage keys no workflow holds ('done', 'revision'),
--   pass by the owner, AQC review, client review and draft gates every move
--   takes through ops_transition_task, and ops_reopen_task asks no client
--   scope. No page, policy, view, function, cron job or edge function calls
--   either (checked in the repo and live on 2026-10-18): a task finishes and
--   reopens through ops_transition_task. Both are revoked from public, anon
--   and authenticated; the functions stay, so nothing that names them breaks
--   at create time.
--
-- ROLLBACK
--   grant execute on function public.ops_complete_task(uuid, text, integer) to authenticated;
--   grant execute on function public.ops_reopen_task(uuid, text, integer) to authenticated;
-- ===========================================================================

revoke all on function public.ops_complete_task(uuid, text, integer) from public, anon, authenticated;
revoke all on function public.ops_reopen_task(uuid, text, integer) from public, anon, authenticated;

-- END OF UNUSED TASK SHORTCUTS CLOSED ---------------------------------------

select public.functions_tidy();
