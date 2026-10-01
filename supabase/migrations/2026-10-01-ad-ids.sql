-- ===========================================================================
-- AD IDS ON THE REPORT — each ad row keeps the Ads Manager Ad IDs it was
-- built from, and the ad account's ID, for the team to find the ad again.
-- 2026-10-01. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `sm_report_ads.ad_ids`: the Ad IDs a row gathers (copies of one
--      creative are one row, so it can hold several). Filled from an export's
--      Ad ID column; a later paste matches its rows by them first.
--   2. `sm_report_ads.ad_account`: the ad account's ID, from an Account ID
--      column, so the console can open the ads in Ads Manager.
--   Both are the team's references: the console shows them, the PDF never
--   prints them.
--
-- ROLLBACK
--   alter table public.sm_report_ads drop column if exists ad_account;
--   alter table public.sm_report_ads drop column if exists ad_ids;
-- ===========================================================================

alter table public.sm_report_ads add column if not exists ad_ids text[];
alter table public.sm_report_ads add column if not exists ad_account text;

-- END OF AD IDS ON THE REPORT ------------------------------------------------
