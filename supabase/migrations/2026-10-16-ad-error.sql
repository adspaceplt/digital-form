-- ===========================================================================
-- AD ERROR ON THE REPORT — the team marks an ad row as an ad error (a fault
-- in Meta's delivery or the export, such as RM 0.01 spent for 40 results),
-- with its reason. 2026-10-16. Safe to run twice. Rollback at the foot.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/smsql.js compares the two.
--
-- WHAT CHANGED
--   1. `sm_report_ads.ad_error`: the reason, empty while the ad is not
--      marked; 1 to 200 characters. Written by the page on a draft, as every
--      other figure of the row (the draft guard and the policies hold it).
--      The ad stays in every total; the PDF leaves it out of the ranking,
--      never marks it cheapest, and notes it under its table. The snapshot
--      carries it, so a published version prints as it was published.
--
-- ROLLBACK
--   alter table public.sm_report_ads drop constraint if exists sm_report_ads_ad_error_chk;
--   alter table public.sm_report_ads drop column if exists ad_error;
-- ===========================================================================

alter table public.sm_report_ads add column if not exists ad_error text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sm_report_ads_ad_error_chk') then
    alter table public.sm_report_ads add constraint sm_report_ads_ad_error_chk
      check (ad_error is null or char_length(btrim(ad_error)) between 1 and 200);
  end if;
end $$;

-- END OF AD ERROR ON THE REPORT ----------------------------------------------
