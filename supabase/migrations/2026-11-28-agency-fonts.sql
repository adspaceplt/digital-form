-- ===========================================================================
-- AGENCY FONTS (2026-11-28)
-- ===========================================================================
-- WHY: the restructure's release 10 (docs/MAP.md §G). The faces a PDF is
-- drawn in were file names typed in js/config.js beside the profile, and
-- named for one agency's licensed faces. They are the install's files now
-- (css/fonts/: text, bold, medium, mark), and the profile names them, so an
-- install with other faces, or none, changes the profile and the folder.
-- WHAT IT CHANGES
--   * `agency_profile` gains `font_text`, `font_bold`, `font_medium` and
--     `font_mark`, seeded with the files the pages draw today. A key already
--     set keeps its value. A blank one draws Helvetica in a PDF (the medium
--     face takes the bold one), as before.
-- ORDER: the pages first or this file first, either: no page reads these
-- keys from the database (the page's copy is `ADspaceAgency`, held equal to
-- this seed by tests/agencysql.js), and `agency_profile_read()` answers the
-- four extra keys to a caller that reads none of them.
-- ROLLBACK: delete from public.agency_profile where key in ('font_text',
-- 'font_bold', 'font_medium', 'font_mark');. Safe to run twice.
-- ===========================================================================

-- AGENCY FONTS --------------------------------------------------------------

insert into public.agency_profile (key, value) values
  ('font_text', '/css/fonts/text.ttf'),
  ('font_bold', '/css/fonts/bold.ttf'),
  ('font_medium', '/css/fonts/medium.ttf'),
  ('font_mark', '/css/fonts/mark.ttf')
on conflict (key) do nothing;

-- END OF AGENCY FONTS -------------------------------------------------------

select public.functions_tidy();
