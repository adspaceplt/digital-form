-- ===========================================================================
-- INTERNAL HELPERS STAY INTERNAL — the database's own helper functions can no
-- longer be called from outside it.
-- 2026-09-27. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the security review the user approved on 2026-09-27):
--   The open finding said the CRM and campaign tables let any signed-in
--   account read and write every row. Checked live on 2026-09-27, that is no
--   longer true: every public table has row level security on, no policy
--   reads `true`, and every policy asks `allowed()`, which answers false for
--   anybody who is not an active colleague. What was still open is a level
--   below the tables. Supabase grants EXECUTE on every new function to
--   `anon` and `authenticated`, and a security definer function runs as its
--   owner, so a helper written to be called only from inside other functions
--   could be called straight through the API with the public key:
--     - writes: `ops_notify` (a notification in any colleague's bell),
--       `ops_log` and `ops_engagement_log` (history rows), `campaign_qc_reset`,
--       `ops_record_review_decision`, `ops_next_seq`, `ops_code_of`;
--     - reads: `ops_task_json` and `ops_engagement_json` (a task or a month
--       whole, to anyone holding its id), `letter_sole_services`,
--       `ops_due_decider`, `ops_stage`, `serial_taken` (whether a reference
--       exists), `option_qc_count`, `option_qc_ok`, `campaign_booked`,
--       `ops_owner_may_move`, `ops_due_order_ok`, `ops_scope_error`.
--   None of them is called by a page, a policy, a view, a constraint, a
--   default or an invoker function (checked live), so they are revoked from
--   everybody but their owner. The functions that call them are security
--   definer and run as the owner, so every flow is unchanged.
--
--   A function added later is granted the same way by default: every new
--   helper that is not an API function revokes itself in the file that
--   creates it.
--
-- ROLLBACK
--   Grant each back with
--   grant execute on function <the signature below> to anon, authenticated;
-- ===========================================================================

/* Each by its exact signature, and only where it exists, so the file runs
   on any copy of the schema. */
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.campaign_booked(uuid)',
    'public.campaign_qc_reset(uuid)',
    'public.letter_sole_services(uuid)',
    'public.ops_code_of(text, integer, integer)',
    'public.ops_due_decider(uuid, text)',
    'public.ops_due_order_ok(timestamp with time zone, timestamp with time zone)',
    'public.ops_engagement_json(uuid)',
    'public.ops_engagement_log(uuid, text, jsonb)',
    'public.ops_log(uuid, text, jsonb, jsonb, jsonb)',
    'public.ops_next_seq(uuid, text)',
    'public.ops_notify(uuid, uuid, text, text, text, text)',
    'public.ops_owner_may_move(uuid)',
    'public.ops_record_review_decision(uuid, uuid, boolean, text)',
    'public.ops_scope_error(text, uuid)',
    'public.ops_stage(uuid, text)',
    'public.ops_task_json(uuid)',
    'public.option_qc_count(uuid)',
    'public.option_qc_ok(uuid)',
    'public.serial_taken(text)'
  ] loop
    if to_regprocedure(f) is not null then
      execute format('revoke all on function %s from public, anon, authenticated', f);
    end if;
  end loop;
end $$;

-- END OF INTERNAL HELPERS STAY INTERNAL ------------------------------------
