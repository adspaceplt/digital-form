-- ===========================================================================
-- LEGACY BUCKET UNLISTED — nobody but the team reads the list of files in
-- the old Supabase Storage bucket `content`. 2026-10-17. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding H)
--   1. `content_public_read` let anon and every signed-in account (a
--      client's portal login included) select from `storage.objects` in the
--      bucket `content`, which is listing it: every file's path, size and
--      type, and so every client folder's id. The bucket has held nothing
--      the pages write since uploads moved to S3 (2026-09-28); the policy is
--      dropped. The bucket and its one file stay: a public bucket's files
--      are served at their address without a policy, and the team's own
--      policy (`content_team_write`, is_team()) still reads and writes it.
--
-- ROLLBACK
--   create policy content_public_read on storage.objects
--     for select to anon, authenticated using (bucket_id = 'content');
-- ===========================================================================

do $$
begin
  if exists (select 1 from pg_policies
              where schemaname = 'storage' and tablename = 'objects'
                and policyname = 'content_public_read') then
    drop policy content_public_read on storage.objects;
  end if;
end $$;

-- END OF LEGACY BUCKET UNLISTED -----------------------------------------------
