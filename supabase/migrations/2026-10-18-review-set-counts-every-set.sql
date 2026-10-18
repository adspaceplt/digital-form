-- ===========================================================================
-- REVIEW SET COUNTS EVERY SET — review_set_counts answers every set it is
-- named, with no cap. 2026-10-18. Safe to run twice. Rollback at the foot.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/sql.js compares the two.
--
-- WHAT CHANGED (review of 2026-10-18, item 9)
--   review_set_counts kept only the first 500 sets named (p_sets[1:500]),
--   and My Work's Waiting for you names every published set of the clients
--   a colleague holds, so past 500 sets the rest went uncounted without a
--   word. The cap is removed (the user, 2026-10-18). The work stays bounded
--   by what is named: the ids are read once each, each set's posts through
--   posts_batch_idx, and each post's standing decision is one index-ordered
--   read (reviews_post_round_idx, newest first, limit 1) in place of every
--   decision sorted. The answer is the one REVIEW SET COUNTS gave: a post's
--   decision is the newest that stands on its round on show (not undone, its
--   round, after any re-approval request). Still security invoker.
--
-- ROLLBACK
--   Run review_set_counts as REVIEW SET COUNTS stated it.
-- ===========================================================================

create or replace function public.review_set_counts(p_sets uuid[])
returns table (set_id uuid, n_posts integer, n_approved integer, n_changes integer,
               n_undecided integer, changes_since timestamptz)
language sql stable security invoker set search_path = public as $$
  with s as (
    select distinct x as id from unnest(p_sets) x where x is not null
  ), p as (
    select po.id, po.batch_id, coalesce(po.round, 1) as rnd, po.review_reset_at
      from s join public.posts po on po.batch_id = s.id
  ), d as (
    select p.id, p.batch_id, r.decision, r.created_at
      from p
      left join lateral (
        select r.decision, r.created_at
          from public.reviews r
         where r.post_id = p.id and r.undone_at is null and coalesce(r.round, 1) = p.rnd
           and (p.review_reset_at is null or r.created_at > p.review_reset_at)
         order by r.created_at desc
         limit 1) r on true
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

-- END OF REVIEW SET COUNTS EVERY SET -----------------------------------------

select public.functions_tidy();
