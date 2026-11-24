-- ===========================================================================
-- FEEDBACK PAGE AVAILABLE (2026-11-24)
-- ===========================================================================
-- WHY: every new page joins Page availability in the push that builds it
-- (the user, 2026-11-21). /feedback/, a client's feedback on its link
-- (CLIENT FEEDBACK), is that page.
--
-- WHAT IT CHANGES
--   * `page_keys()` (restated from EVERY PAGE AVAILABLE) adds `feedback`.
--   * `page_name(p)` (restated) names it Feedback form.
--   `page_states_all`, `page_set` and `page_pulse` read both, so the page
--   can be set Upgrade in progress or Temporarily unavailable as any other.
--
-- ORDER: this file, then the pages. An old Settings sheet lists the pages it
-- knows and ignores the rest. Safe to run twice.
--
-- ROLLBACK: restore `page_keys` and `page_name` from EVERY PAGE AVAILABLE;
-- then remove the `page:feedback` row from app_flags (SQL Editor).

create or replace function public.page_keys()
returns text[]
language sql immutable set search_path = public as $$
  select array['admin', 'client', 'review', 'script', 'details', 'creators', 'creator', 'quote', 'supplier', 'verify',
               'careers', 'feedback', 'home', 'notfound', 'card']
$$;
revoke all on function public.page_keys() from public, anon, authenticated;

create or replace function public.page_name(p text)
returns text
language sql immutable set search_path = public as $$
  select case p when 'admin' then 'Console' when 'client' then 'Client portal' when 'review' then 'Content Review'
    when 'script' then 'Video Scripts' when 'details' then 'Details form' when 'creators' then 'Creator selection'
    when 'creator' then 'Creator page' when 'quote' then 'Quotation website' when 'supplier' then 'Supplier form'
    when 'verify' then 'Verify a document' when 'careers' then 'Candidate page' when 'feedback' then 'Feedback form'
    when 'home' then 'Front page' when 'notfound' then 'Page not found' when 'card' then 'Namecards' end
$$;
revoke all on function public.page_name(text) from public, anon, authenticated;

-- END OF FEEDBACK PAGE AVAILABLE ---------------------------------------------
select public.functions_tidy();
