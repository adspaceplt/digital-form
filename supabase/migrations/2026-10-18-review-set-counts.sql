-- ===========================================================================
-- REVIEW SET COUNTS — where each content set's posts stand, counted by the
-- database in one request. 2026-10-18. Safe to run twice. Rollback at the
-- foot. Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/sql.js compares the two.
--
-- WHAT CHANGED
--   The Dashboard's Sets waiting on clients and My Work's Waiting for you
--   (Client changes, Awaiting approval) read every post of the sets they
--   showed, then every decision on those posts, passing up to a thousand
--   ids in the address. PostgREST answers at most a thousand rows a read,
--   so past that the counts stopped short without a word (second audit,
--   item 14). review_set_counts(p_sets) answers, for each set named, its
--   posts, how many the client approved, how many have changes requested,
--   how many are undecided, and when the oldest standing change request was
--   made. A post's decision is the newest that stands on its round on show
--   (not undone, its round, after any re-approval request), as the set's
--   own page reads it.
--   Security invoker: it reads posts and reviews under their own policies
--   (Content Review: Sets at View, client scope), so it answers nothing a
--   colleague could not read row by row.
--
-- ROLLBACK
--   drop function if exists public.review_set_counts(uuid[]);
--   (the pages then read the posts as before; deploy the earlier pages first)
-- ===========================================================================

create or replace function public.review_set_counts(p_sets uuid[])
returns table (set_id uuid, n_posts integer, n_approved integer, n_changes integer,
               n_undecided integer, changes_since timestamptz)
language sql stable security invoker set search_path = public as $$
  with p as (
    select po.id, po.batch_id, coalesce(po.round, 1) as rnd, po.review_reset_at
      from public.posts po
     where po.batch_id = any(p_sets[1:500])
  ), d as (
    select distinct on (p.id) p.id, p.batch_id, r.decision, r.created_at
      from p
      left join public.reviews r
        on r.post_id = p.id and r.undone_at is null and coalesce(r.round, 1) = p.rnd
       and (p.review_reset_at is null or r.created_at > p.review_reset_at)
     order by p.id, r.created_at desc nulls last
  )
  select d.batch_id,
         count(*)::integer,
         (count(*) filter (where d.decision = 'approved'))::integer,
         (count(*) filter (where d.decision = 'changes'))::integer,
         (count(*) filter (where d.decision is null))::integer,
         min(d.created_at) filter (where d.decision = 'changes')
    from d
   group by d.batch_id
$$;

revoke all on function public.review_set_counts(uuid[]) from public, anon;
grant execute on function public.review_set_counts(uuid[]) to authenticated;

-- END OF REVIEW SET COUNTS --------------------------------------------------

select public.functions_tidy();
