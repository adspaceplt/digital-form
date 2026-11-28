-- ===========================================================================
-- AGENCY PROFILE FIELDS (2026-11-28)
-- ===========================================================================
-- WHY: the restructure's release 9 (docs/MAP.md §G). Two values that name
-- the agency stood typed on the pages: its own short domain (a field's
-- example, the media pass's cookie) and its Facebook page (the feedback
-- page's link, a creator's profile example, which named a page the agency
-- does not hold; the user confirmed the page on 2026-11-28).
-- WHAT IT CHANGES
--   * `agency_profile` gains `short_domain` and `facebook_url`, seeded once
--     with the values js/config.js `ADspaceAgency` prints (`tests/agencysql.js`
--     holds the two equal). A key already set keeps its value.
-- ORDER: the pages first or this file first, either way: no page or
-- function reads these two keys from the database yet; the pages read
-- their own copy in js/config.js.
-- ROLLBACK: delete from public.agency_profile where key in ('short_domain',
-- 'facebook_url'). Safe to run twice.

-- AGENCY PROFILE FIELDS ------------------------------------------------------

insert into public.agency_profile (key, value) values
  ('short_domain', 'adspace.me'),
  ('facebook_url', 'https://facebook.com/adspacestudios')
on conflict (key) do nothing;

-- END OF AGENCY PROFILE FIELDS -----------------------------------------------

select public.functions_tidy();
