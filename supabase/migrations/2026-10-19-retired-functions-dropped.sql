-- ===========================================================================
-- RETIRED FUNCTIONS DROPPED — eleven functions no page calls any more.
-- 2026-10-19. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two. Run in the SQL Editor: the connector holds a `drop`.
--
-- WHAT CHANGED (the third audit, item 15)
--   Each was kept for a page loaded before its successor, and each is a
--   function a signed-in browser could still call. No page, edge function,
--   worker, policy, trigger or other function names any of them (read on
--   the live database, 2026-10-19):
--     wa_recent                 → wa_messages (the WhatsApp section)
--     wa_template_save          → wa_template_set
--     team_set_expiry           → team_set_expiry_at
--     namecard_save_mine        → namecard_save
--     namecard_save_card        → namecard_save
--     perf_guard_set            → the email code is always asked
--     video_script_create       → video_script_new
--     report_partner_save       → white label on the client's Brand
--     report_partner_set_active → (the same)
--     sm_report_white_label     → sm_report_brand
--     sm_report_label           → sm_report_brand
--   Their tables are left as they are.
--
-- ROLLBACK
--   Run again the section that last defined each: wa_recent and
--   wa_template_save 2026-10-10-whatsapp-section.sql; team_set_expiry
--   2026-10-03-team-access-time.sql; namecard_save_mine
--   2026-10-03-team-namecards.sql; namecard_save_card
--   2026-10-03-namecard-short-links.sql; perf_guard_set
--   2026-09-24-performance-email-code.sql; video_script_create
--   2026-10-09-video-scripts.sql; report_partner_save and
--   report_partner_set_active 2026-10-06-report-partners.sql;
--   sm_report_white_label 2026-10-06-report-white-label.sql;
--   sm_report_label 2026-10-07-white-label-on-the-client.sql.
-- ===========================================================================

drop function if exists public.wa_recent();
drop function if exists public.wa_template_save(text, text, text, integer, boolean);
drop function if exists public.team_set_expiry(date);
drop function if exists public.namecard_save_mine(text, text);
drop function if exists public.namecard_save_card(text, text);
drop function if exists public.perf_guard_set(boolean);
drop function if exists public.video_script_create(uuid, text, uuid, text);
drop function if exists public.report_partner_save(uuid, text, text, uuid[]);
drop function if exists public.report_partner_set_active(uuid, boolean);
drop function if exists public.sm_report_white_label(uuid, uuid, text);
drop function if exists public.sm_report_label(uuid, uuid, text);

-- END OF RETIRED FUNCTIONS DROPPED ------------------------------------------

select public.functions_tidy();
