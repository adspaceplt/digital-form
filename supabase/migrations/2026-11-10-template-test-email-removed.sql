-- ===========================================================================
-- TEMPLATE TEST EMAIL REMOVED — Send test to me is taken out of Email
-- templates (2026-11-10; the user: "remove")
-- ===========================================================================
-- Drops what TEMPLATE TEST EMAIL added: `mail_test_begin`, `template_sample`
-- and `mail_tests` (held no row). Run after the pages and `supplier-mail`
-- stop asking for them. Safe to run twice.
-- ROLLBACK: run 2026-11-10-template-test-email.sql again.
-- ===========================================================================

drop function if exists public.mail_test_begin(text, text, text, text, text);
drop function if exists public.template_sample(text, text, text);
drop table if exists public.mail_tests;

-- END OF TEMPLATE TEST EMAIL REMOVED -----------------------------------------

select public.functions_tidy();
