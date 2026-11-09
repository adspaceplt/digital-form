-- ===========================================================================
-- CREATOR PROFILES THROUGH THEIR FUNCTION (2026-11-09)
-- ===========================================================================
-- WHY (security audit run 2, 2026-11-09; the user's scheduled audit: "fix and
-- release confirmed ones"):
-- Direct writes to creator_profiles at Creators List Work stored any address, skipped
-- profile_of and the change log, and reached the client's selection page.
--
-- WHAT IT CHANGES
--   creator_profiles_write/_edit/_del admit nothing; check creator_profiles_url_web (https).
--
-- ORDER: this file, then the pages. Safe to run twice.
--
-- ROLLBACK: alter policy creator_profiles_write on public.creator_profiles with check (public.allowed('campaigns.creators', 'work')); (and _edit, _del) and, in the SQL Editor, alter table public.creator_profiles drop constraint if exists creator_profiles_url_web.
-- ===========================================================================

-- CREATOR PROFILES THROUGH THEIR FUNCTION ------------------------------------

/* A creator's profile links are saved through profiles_replace alone
   (security audit 2026-11-09): creator_profiles took direct writes at
   Creators List Work, which skipped profile_of (a real profile on the four
   platforms, its link rebuilt, one holder) and the change log, and stored any
   address, which the client's selection page drew as View on {platform}. The
   console saves through creator_save_profiles and the creator's page through
   creator_set_profiles, both security definer, so the direct write policies
   admit nothing, and the column is held to https as the other stored links
   are (FILE LINKS HELD TO THE WEB). Checked live on 2026-11-09 before adding
   it: none of 20 profiles fails. */
alter policy creator_profiles_write on public.creator_profiles with check (false);
alter policy creator_profiles_edit on public.creator_profiles using (false) with check (false);
alter policy creator_profiles_del on public.creator_profiles using (false);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'creator_profiles_url_web') then
    alter table public.creator_profiles add constraint creator_profiles_url_web
      check (url ~* '^https://[^\s"''<>`\\]+$');
  end if;
end $$;

-- END OF CREATOR PROFILES THROUGH THEIR FUNCTION -----------------------------


select public.functions_tidy();
