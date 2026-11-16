-- ============================================================================
-- ACCESS SECURITY FIXES, THE SQL EDITOR PART (2026-11-17)
-- ============================================================================
-- Run after 2026-11-17-access-security-fixes.sql: the name-based scope rules
-- nothing calls any more are dropped, so no later restatement can fall back
-- to them. Safe to run twice.

drop function if exists public.client_row_seen_by(text, text, uuid, text);
drop function if exists public.client_row_seen(text, text, text);

-- END OF ACCESS SECURITY FIXES, THE SQL EDITOR PART --------------------------

select public.functions_tidy();
