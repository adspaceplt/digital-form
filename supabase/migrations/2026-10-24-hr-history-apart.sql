-- ===========================================================================
-- HR HISTORY APART — an HR letter's history is read at HR Letters, its own
-- part of the Activity record (2026-10-24)
-- ===========================================================================
-- WHY (the permissions audit of 2026-10-24, S5; the user decided "file it
-- apart")
--   An HR document's history (issued, edited, voided, deleted; filed under
--   subject HR with its kind alone) is tagged as a Documents act, so the
--   Activity record's Documents part opened it: the View only and Manager
--   presets, which hold the Activity record at View and never HR Letters,
--   read when each colleague's letters were issued and voided.
--
-- WHAT CHANGED
--   * The read policy `activity_read` answers a Documents row filed under
--     subject HR only where the reader holds the Activity record's own part
--     for it, HR letters (`activity.hr`), and HR Letters themselves
--     (`register.hr`) at View. Every other row is read as before, by its
--     section's part. `activity_section()` and the tags are unchanged.
--   * The policy is altered in place (`alter policy`), so nothing is
--     dropped and a page reading the record keeps reading it meanwhile.
--
-- ORDER
--   This file, then the page (the Section select offers HR letters, and
--   Documents reads without them). An open page before reads Documents
--   without the HR rows a reader may no longer see.
--
-- Safe to run twice. Rollback:
--   alter policy activity_read on public.activity_log
--     using (public.allowed('activity.' || public.activity_section(action), 'view'));
-- ===========================================================================

alter policy activity_read on public.activity_log
  using (case when public.activity_section(action) = 'register' and subject = 'HR'
              then public.allowed('activity.hr', 'view') and public.allowed('register.hr', 'view')
              else public.allowed('activity.' || public.activity_section(action), 'view') end);

-- END OF HR HISTORY APART ----------------------------------------------------

select public.functions_tidy();
