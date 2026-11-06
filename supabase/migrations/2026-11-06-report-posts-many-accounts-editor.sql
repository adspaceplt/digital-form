-- ===========================================================================
-- REPORT POSTS ON SEVERAL ACCOUNTS, THE SQL EDITOR PART (2026-11-06)
-- ===========================================================================
-- Run after 2026-11-06-report-posts-many-accounts.sql (the connector holds
-- a statement naming drop). It lets a task hold one link an account: the
-- index that held one link a task goes; the function keeps one post an
-- account (`same-account`). Safe to run twice. Rollback: in the main file.
-- ===========================================================================

drop index if exists public.sm_report_post_links_task_idx;

-- END OF REPORT POSTS ON SEVERAL ACCOUNTS, THE SQL EDITOR PART --------------
