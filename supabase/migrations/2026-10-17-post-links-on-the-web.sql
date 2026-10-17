-- ===========================================================================
-- POST LINKS ON THE WEB — a booking's post link is a web address, never
-- script. 2026-10-17. Safe to run twice. Rollback at the foot. Mirrored byte
-- for byte in supabase/schema.sql under the same banner; tests/sql.js
-- compares the two.
--
-- WHAT CHANGED (the review of the audit's fixes, finding 1)
--   `option_posts.post_url` is written by the creator through
--   `creator_post_save` (held to the platform's own host) and by the team
--   straight into the table at Creator Campaigns Work. The second held
--   anything: `javascript:…` was drawn as a link in the console and on the
--   creator's page and ran on a press. A check holds it to `http://` or
--   `https://`, as LINKS HELD TO THE WEB holds a draft link; the pages draw
--   it only on http or https as well.
--   Checked live on 2026-10-17 before adding it: nine post links held, one
--   failing, a rednote link typed without its first letter
--   (`ttps://xhslink.cn/…`). A link missing only that letter is given it
--   back here; any other failing link stops the run before the check is
--   added, to be looked at by hand.
--
-- ROLLBACK
--   alter table public.option_posts drop constraint if exists option_posts_post_url_web;
--   (the repaired link keeps its letter: it was a typing slip.)
-- ===========================================================================

update public.option_posts set post_url = 'h' || post_url
 where post_url ~* '^ttps?://';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'option_posts_post_url_web') then
    alter table public.option_posts add constraint option_posts_post_url_web
      check (post_url is null or post_url ~* '^https?://[^\s"''<>`\\]+$');
  end if;
end $$;

-- END OF POST LINKS ON THE WEB -----------------------------------------------
