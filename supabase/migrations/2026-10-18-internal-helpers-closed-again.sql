-- ===========================================================================
-- INTERNAL HELPERS CLOSED AGAIN — three helpers that only other functions
-- call are closed to a signed-in account once more. 2026-10-18. Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in supabase/schema.sql
-- under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED
--   INTERNAL HELPERS STAY INTERNAL (2026-09-27) revoked nineteen helpers
--   from public, anon and authenticated. Three were restated later with the
--   grant their first definition carried, which opened them to every
--   signed-in account again (a client contact included):
--     ops_owner_may_move  by ADMIN PARTS (2026-10-07);
--     option_qc_count     by RELEASED FILES (2026-10-10);
--     ops_due_decider     by COLLEAGUE LEAVING (2026-10-15).
--   No page, policy, view, default, constraint or invoker function calls
--   any of them (checked live on 2026-10-18); every caller
--   (ops_request_due_change, ops_transition_task, ops_set_blocked,
--   ops_set_code, ops_set_open, option_qc_ok, campaign_qc_pass) is security
--   definer and runs as the owner, so every flow is unchanged.
--   tests/sql.js now holds that every helper's last word in schema.sql is a
--   revoke, so a restatement that grants it again fails the suite.
--
-- ROLLBACK
--   grant execute on function public.ops_owner_may_move(uuid) to authenticated;
--   grant execute on function public.option_qc_count(uuid) to authenticated;
--   grant execute on function public.ops_due_decider(uuid, text) to authenticated;
-- ===========================================================================

revoke all on function public.ops_owner_may_move(uuid) from public, anon, authenticated;
revoke all on function public.option_qc_count(uuid) from public, anon, authenticated;
revoke all on function public.ops_due_decider(uuid, text) from public, anon, authenticated;

-- END OF INTERNAL HELPERS CLOSED AGAIN --------------------------------------

select public.functions_tidy();
