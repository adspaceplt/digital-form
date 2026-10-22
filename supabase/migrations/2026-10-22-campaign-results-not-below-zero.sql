-- ===========================================================================
-- CAMPAIGN RESULTS NOT BELOW ZERO — a booking's post figures are counts
-- (2026-10-22, CMP-17)
-- ===========================================================================
-- WHY: the console's results fields took a negative impressions figure and
-- saved it; the creator's own page refuses one through creator_post_save,
-- the table did not.
--
-- WHAT IT CHANGES
--   * `option_posts_figures_check`: impressions, engagements and views are
--     null or zero and above. A row already below zero is set to null
--     first (a count below zero was never a figure).
--
-- ORDER: this file, then the pages (or either way: the page already reads
-- a refusal). Safe to run twice.
--
-- ROLLBACK
--   alter table public.option_posts drop constraint if exists option_posts_figures_check;
-- ===========================================================================

update public.option_posts set impressions = null where impressions < 0;
update public.option_posts set engagements = null where engagements < 0;
update public.option_posts set views = null where views < 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'option_posts_figures_check') then
    alter table public.option_posts add constraint option_posts_figures_check
      check (coalesce(impressions, 0) >= 0 and coalesce(engagements, 0) >= 0 and coalesce(views, 0) >= 0);
  end if;
end $$;

-- END OF CAMPAIGN RESULTS NOT BELOW ZERO --------------------------------------
