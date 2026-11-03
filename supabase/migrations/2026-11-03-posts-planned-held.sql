-- ===========================================================================
-- POSTS PLANNED HELD TO A COUNT — a month's posts planned is a whole number
-- from 0 to 200 (2026-11-03)
-- ===========================================================================
-- WHY: the user, on the New month sheet saving with Posts planned left as
-- 0: the review found the page turned an empty box into 0 and sent a
-- negative or a decimal figure on, which nothing in the database refused.
-- The page now asks for the figure; this holds the column too, so no other
-- writer stores what the page refuses.
--
-- WHAT IT CHANGES
--   `ops_engagements_planned_range`: `planned_count` between 0 and 200.
--   Checked live on 2026-11-03 before adding it: every month holds 0 to 12.
--
-- ORDER: the pages, then this file. Safe to run twice.
-- ROLLBACK
--   alter table public.ops_engagements drop constraint if exists ops_engagements_planned_range;
-- ===========================================================================

-- POSTS PLANNED HELD TO A COUNT ---------------------------------------------

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ops_engagements_planned_range') then
    alter table public.ops_engagements add constraint ops_engagements_planned_range
      check (planned_count between 0 and 200);
  end if;
end $$;

-- END OF POSTS PLANNED HELD TO A COUNT --------------------------------------
