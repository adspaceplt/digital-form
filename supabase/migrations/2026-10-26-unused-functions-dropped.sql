-- ===========================================================================
-- UNUSED FUNCTIONS DROPPED — functions no page, function, trigger, policy,
-- job or edge function calls (2026-10-26)
-- ===========================================================================
-- WHY (the whole-repo audit of 2026-10-26, findings 14 to 17): each was
-- replaced and left standing. Checked in the repo and live on 2026-10-26:
-- nothing calls any of them, and each still answers whoever may run it.
--   ops_generate_month: the Bulk add the New sheet replaced (2026-10-12).
--   ops_add_work_session, ops_correct_work_session, ops_start_work,
--   ops_stop_work: the first model's timer, gone from the task card.
--   ops_complete_task, ops_reopen_task: closed 2026-10-18; a task moves
--   through ops_transition_task.
--   ops_record_review_decision, ops_request_revision, ops_complete_revision:
--   the first model's review steps; reviews are stages now.
--   ops_set_blocked: Blocked is a stage, moved by ops_transition_task
--   (ops_clear_blocked stays: the page uses it).
--   wa_report_prepare, wa_feedback_prepare, wa_record, wa_creator_send,
--   wa_sent: the sends before the composer (closed 2026-10-19); wa-send
--   files through wa_send_begin and wa_send_done.
--   script_decide, script_shot_link: the client's script link decides and
--   records nothing (2026-10-09); both answered `closed`.
--
-- ORDER: the SQL Editor (the connector holds a drop), after the pages of
-- the same release. Then `select public.functions_tidy();`.
--
-- ROLLBACK: run each function's last definition in this file again.
-- ===========================================================================

drop function if exists public.ops_generate_month(jsonb, boolean, text);
drop function if exists public.ops_add_work_session(uuid, timestamptz, timestamptz, text);
drop function if exists public.ops_correct_work_session(uuid, timestamptz, timestamptz, text);
drop function if exists public.ops_start_work(uuid, text);
drop function if exists public.ops_stop_work(uuid, text);
drop function if exists public.ops_complete_task(uuid, text, integer);
drop function if exists public.ops_reopen_task(uuid, text, integer);
drop function if exists public.ops_record_review_decision(uuid, uuid, boolean, text);
drop function if exists public.ops_request_revision(uuid, jsonb, text);
drop function if exists public.ops_complete_revision(uuid);
drop function if exists public.ops_set_blocked(uuid, text, text, integer);
drop function if exists public.wa_report_prepare(uuid);
drop function if exists public.wa_feedback_prepare(uuid);
drop function if exists public.wa_record(text, uuid, uuid, text, text, text, jsonb, boolean, text, text);
drop function if exists public.wa_creator_send(uuid);
drop function if exists public.wa_sent(text, uuid, text, uuid, text, text, text, jsonb, boolean, text, text);
drop function if exists public.script_decide(text, uuid, text, text, text);
drop function if exists public.script_shot_link(text, uuid, uuid, boolean, text);

-- END OF UNUSED FUNCTIONS DROPPED ---------------------------------------------

select public.functions_tidy();
