-- ===========================================================================
-- ACCEPT CAPTION UNDONE — Undo after Accept caption puts back the caption and
-- the round as they were, never starting a further round.
-- 2026-10-15. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner.
--
-- WHY
--   Accept caption writes the client's suggested caption over a round the
--   client decided on, so `posts_revision` makes it round N+1 and keeps round
--   N in `post_versions`. Writing the old caption back is then a correction
--   of round N+1 (nobody decided on it), so the round stays N+1 and the
--   client is asked about a "new" round holding the very caption they asked
--   to change. A page never writes `round` (a value that depends on a
--   change is stamped by the database), so the way back is a function.
--
-- WHAT CHANGED
--   `review_caption_undo(p_post, p_round, p_caption, p_caption_zh)`: Content
--   Review (sets) at Work. Refused unless the post is on round p_round + 1
--   with no decision standing on it (`moved`: the client decided, or
--   another edit followed), the caption put back and the round returned to
--   p_round; the page files `post.edited` (accepted caption undone) as it
--   files the acceptance. Round p_round's
--   decision and its `post_versions` row stay as they were: they describe
--   exactly the caption now on show again. The update passes the client
--   scope guard as any edit of the post does.
--
-- ROLLBACK
--   drop function if exists public.review_caption_undo(uuid, int, text, text);
--   (The page falls back to restoring the caption alone, as before.)
-- ===========================================================================

create or replace function public.review_caption_undo(p_post uuid, p_round int, p_caption text, p_caption_zh text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  v_post   public.posts%rowtype;
begin
  if not public.allowed('review.sets', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into v_post from public.posts where id = p_post for update;
  if v_post.id is null then return jsonb_build_object('error', 'no-post'); end if;
  if p_round is null or v_post.round is distinct from p_round + 1
     or exists (select 1 from public.reviews r
                 where r.post_id = v_post.id and r.round = v_post.round and r.undone_at is null
                   and (v_post.review_reset_at is null or r.created_at > v_post.review_reset_at)) then
    return jsonb_build_object('error', 'moved');
  end if;
  update public.posts
     set caption = p_caption, caption_zh = p_caption_zh, round = p_round
   where id = v_post.id;

  return jsonb_build_object('ok', true, 'round', p_round);
end $$;
revoke all on function public.review_caption_undo(uuid, int, text, text) from public, anon;
grant execute on function public.review_caption_undo(uuid, int, text, text) to authenticated;

-- END OF ACCEPT CAPTION UNDONE ------------------------------------------------
select public.functions_tidy();
