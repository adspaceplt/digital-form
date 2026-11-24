-- ===========================================================================
-- THE SETS STILL WAITING ON THE CLIENT (2026-11-24)
-- ===========================================================================
-- WHY: the review of 2026-11-24 (C3). The Dashboard read every published
-- set ever made, a thousand a page, then counted them all, to keep the few
-- still waiting on the client: a read that only grows.
--
-- WHAT IT ADDS
--   * `review_sets_waiting()`: the published sets with posts the client has
--     not approved on the round on show, counted as `review_set_counts`
--     counts them (it reads through it, as the caller: row level security
--     and the client scope hold as for every read). The Dashboard reads
--     these alone, then those sets by id.
--
-- ORDER: this migration, then the pages (a page from this release asks the
-- function). A page from before reads as it did.
--
-- ROLLBACK: the pages first; the function may stay (nothing else reads it).
-- ===========================================================================

create or replace function public.review_sets_waiting()
returns table (set_id uuid, n_posts integer, n_approved integer, n_changes integer)
language sql stable security invoker set search_path = public as $$
  select c.set_id, c.n_posts, c.n_approved, c.n_changes
    from public.review_set_counts(array(select b.id from public.batches b where b.published)) c
   where c.n_posts > 0 and c.n_approved < c.n_posts
$$;
revoke all on function public.review_sets_waiting() from public, anon;
grant execute on function public.review_sets_waiting() to authenticated;

-- END OF THE SETS STILL WAITING ON THE CLIENT ---------------------------------

select public.functions_tidy();
