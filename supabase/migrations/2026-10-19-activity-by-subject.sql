-- ===========================================================================
-- ACTIVITY BY SUBJECT — the record panes' Activity read by an index.
-- 2026-10-19. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED (the third audit, item 11)
--   A client's and a campaign's Activity read `activity_log` by its subject,
--   newest first (`.eq('subject', …).order('created_at', desc)`), and the
--   table held an index on created_at alone, so each open scanned the record
--   the team keeps for three years. One index on (subject, created_at desc)
--   answers that read in order.
--
-- ROLLBACK
--   drop index if exists public.activity_log_subject_idx;
-- ===========================================================================

create index if not exists activity_log_subject_idx on public.activity_log (subject, created_at desc);

-- END OF ACTIVITY BY SUBJECT -------------------------------------------------

select public.functions_tidy();
