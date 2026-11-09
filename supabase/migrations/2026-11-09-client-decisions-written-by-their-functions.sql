-- ===========================================================================
-- CLIENT DECISIONS WRITTEN BY THEIR FUNCTIONS (2026-11-09)
-- ===========================================================================
-- WHY (security audit run 2, 2026-11-09; the user's scheduled audit: "fix and
-- release confirmed ones"):
-- A colleague at Work could insert an approval marked as the client's, or rewrite
-- the client's request for changes, through direct writes to reviews and
-- option_reviews, and could move a post's round back onto an earlier approval.
--
-- WHAT IT CHANGES
--   Policies reviews_write/_edit/_del and option_reviews_write/_edit/_del admit
--   nothing; trigger posts_round_guard refuses a page moving round or clearing review_reset_at.
--
-- ORDER: this file, then the pages. Safe to run twice.
--
-- ROLLBACK: alter policy reviews_write on public.reviews with check (public.allowed('review.sets', 'work')); (and _edit, _del, and the option_reviews three at campaigns.campaigns) and drop trigger posts_round_guard on public.posts (SQL Editor).
-- ===========================================================================

-- CLIENT DECISIONS WRITTEN BY THEIR FUNCTIONS --------------------------------

/* A decision recorded as the client's is the client's own, and the team's is
   filed under the colleague (security audit 2026-11-09): reviews and
   option_reviews took insert, update and delete at their section's Work and
   Manage through the generated policies, so a colleague could insert an
   approval marked as the client's under a client's name, or rewrite the
   client's own request for changes, with no Activity record. Every writer is
   a security definer function (submit_review, submit_review_seen,
   review_draft, review_confirm, review_revert_confirm, campaign_proceed,
   campaign_send_back, campaign_revert_approval, campaign_revert_changes), so
   the direct write policies admit nothing, as campaign_confirmations' do.
   A post's round, which binds a decision to what the client saw, is the
   database's alone (posts_revision, review_caption_undo): a page's own update
   cannot move it, and review_reset_at only moves forward, never cleared or
   set back (posts_round_guard, run as the caller). */
alter policy reviews_write on public.reviews with check (false);
alter policy reviews_edit on public.reviews using (false) with check (false);
alter policy reviews_del on public.reviews using (false);
alter policy option_reviews_write on public.option_reviews with check (false);
alter policy option_reviews_edit on public.option_reviews using (false) with check (false);
alter policy option_reviews_del on public.option_reviews using (false);

create or replace function public.posts_round_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  -- Runs as the caller: a page's own update is 'authenticated' here, while
  -- review_caption_undo's checked rewind runs as the database.
  if current_user = 'authenticated' then
    if new.round is distinct from old.round then
      raise exception 'round-function' using errcode = '42501';
    end if;
    if new.review_reset_at is distinct from old.review_reset_at
       and (new.review_reset_at is null or (old.review_reset_at is not null and new.review_reset_at < old.review_reset_at)) then
      raise exception 'reset-forward' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.posts_round_guard() from public, anon, authenticated;
create or replace trigger posts_round_guard before update of round, review_reset_at on public.posts
  for each row execute function public.posts_round_guard();

-- END OF CLIENT DECISIONS WRITTEN BY THEIR FUNCTIONS -------------------------


select public.functions_tidy();
