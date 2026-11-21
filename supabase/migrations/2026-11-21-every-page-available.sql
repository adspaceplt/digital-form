-- ===========================================================================
-- EVERY PAGE AVAILABLE (2026-11-21)
-- ===========================================================================
-- WHY: the user, 2026-11-21, after a candidate picked an interview time on
-- /careers/ while every listed page was under Upgrade in progress: "Every
-- new pages added should also go into the availability section", then
-- "makes all pages up, including the main page ... leave it at the system
-- pages ... the select all doesn't cover the select all for the three
-- system pages, but it will be split under another select all".
--
-- WHAT IT CHANGES
--   * `page_keys()` (restated from PAGE AVAILABILITY) adds `careers` (a
--     candidate's page) beside the ten, then the three system pages: `home`
--     (the front door, /), `notfound` (the 404) and `card` (a colleague's
--     namecard). `page_states_all`, `page_set` and `page_pulse` read it, so
--     each can be set as any page; the console's sheet keeps the system
--     pages under their own Select all.
--   * `page_name(p)` (restated) names them: Candidate page, Front page,
--     Page not found, Namecards.
--   Nothing else moves: a page is covered as before (a cover, never a lock).
--
-- ORDER: this file, then the pages. An old Settings sheet lists the ten it
-- knows and ignores the rest; a new sheet on the old database reads the ten.
-- Safe to run twice.
--
-- ROLLBACK: restore `page_keys` and `page_name` from PAGE AVAILABILITY; then
-- delete from app_flags where key in ('page:careers', 'page:home',
-- 'page:notfound', 'page:card') (SQL Editor).

create or replace function public.page_keys()
returns text[]
language sql immutable set search_path = public as $$
  select array['admin', 'client', 'review', 'script', 'details', 'creators', 'creator', 'quote', 'supplier', 'verify',
               'careers', 'home', 'notfound', 'card']
$$;
revoke all on function public.page_keys() from public, anon, authenticated;

create or replace function public.page_name(p text)
returns text
language sql immutable set search_path = public as $$
  select case p when 'admin' then 'Console' when 'client' then 'Client portal' when 'review' then 'Content Review'
    when 'script' then 'Video Scripts' when 'details' then 'Details form' when 'creators' then 'Creator selection'
    when 'creator' then 'Creator page' when 'quote' then 'Quotation website' when 'supplier' then 'Supplier form'
    when 'verify' then 'Verify a document' when 'careers' then 'Candidate page' when 'home' then 'Front page'
    when 'notfound' then 'Page not found' when 'card' then 'Namecards' end
$$;
revoke all on function public.page_name(text) from public, anon, authenticated;

-- END OF EVERY PAGE AVAILABLE ------------------------------------------------

select public.functions_tidy();
