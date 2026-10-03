-- ===========================================================================
-- REEL COVER PAIRS — a cover names the reel it was made for, and the client's
-- page shows the two as one card.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-03: a set of thirty reels with their covers read as
--   sixty items. `posts.cover_for` names the reel a cover image belongs to
--   (the team pairs them as the files are added, or from the cover's ⋯);
--   `get_review_feed` sends it, and the client's page draws the reel and its
--   cover as one card with a tab each. Each is still its own post with its
--   own decision, round and history; a pairing is not a revision (the
--   revision trigger reads the file, copy and title only). The column holds
--   no foreign key, so removing a reel never waits on its cover: a cover
--   whose reel is gone stands alone on both pages.
--
-- ROLLBACK
--   Re-run the HIDDEN FROM CONTENT REVIEW section of schema.sql (its
--   get_review_feed), then remove the column posts.cover_for.
-- ===========================================================================

alter table public.posts add column if not exists cover_for uuid;

create or replace function public.get_review_feed(p_token text, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client public.clients%rowtype;
begin
  select * into v_client
  from public.clients
  where access_token = p_token and active and not review_hidden;

  if not found then
    return jsonb_build_object('error', 'not_found');
  end if;

  if v_client.passcode is not null
     and (p_passcode is null or p_passcode <> v_client.passcode) then
    return jsonb_build_object('error', 'passcode_required', 'client', v_client.name);
  end if;

  return jsonb_build_object(
    'client', jsonb_build_object(
      'name', v_client.name,
      'logo_url', v_client.logo_url,
      'handles', jsonb_build_object(
        'instagram', v_client.handle_ig,
        'facebook',  v_client.handle_fb,
        'tiktok',    v_client.handle_tiktok,
        'xhs',       v_client.handle_xhs)),
    'batches', coalesce((
      select jsonb_agg(batch order by batch->>'created_at' desc)
      from (
        select jsonb_build_object(
          'id',         b.id,
          'title',      b.title,
          'note',       b.note,
          'created_at', b.created_at,
          'posts', coalesce((
            select jsonb_agg(post order by (post->>'position')::int)
            from (
              select jsonb_build_object(
                'id',         p.id,
                'platform',   p.platform,
                'format',     p.format,
                'handle',     p.handle,
                'caption',    p.caption,
                'caption_zh', p.caption_zh,
                'title',      p.title,
                'media',      p.media,
                'cover_for',  p.cover_for,
                'position',   p.position,
                'round',      p.round,
                'reset_note', case
                  when p.review_reset_at is not null then p.review_reset_note end,
                /* The decision standing on the round on show: never one about
                   a round the client no longer sees, never one taken back. */
                'review',     (
                  select jsonb_build_object(
                    'decision',   r.decision,
                    'note',       r.note,
                    'reviewer',   case when r.source = 'team' then null else r.reviewer end,
                    'created_at', r.created_at,
                    'by_team',    (r.source = 'team'),
                    'suggested',  (r.suggested_caption is not null or r.suggested_caption_zh is not null),
                    /* The client's own edit, so Edit request reopens it. */
                    'suggested_caption',    r.suggested_caption,
                    'suggested_caption_zh', r.suggested_caption_zh)
                  from public.reviews r
                  where r.post_id = p.id and r.round = p.round and r.undone_at is null
                    and (p.review_reset_at is null or r.created_at > p.review_reset_at)
                  order by r.created_at desc
                  limit 1),
                /* What the client asked of the round before, so a revision
                   says what it answers. Words only: the earlier file and copy
                   stay with the team. */
                'asked',      case when p.round > 1 then (
                  select jsonb_build_object(
                    'note',       r.note,
                    'reviewer',   r.reviewer,
                    'created_at', r.created_at,
                    'suggested',  (r.suggested_caption is not null or r.suggested_caption_zh is not null))
                  from public.reviews r
                  where r.post_id = p.id and r.round = p.round - 1 and r.decision = 'changes'
                    and r.undone_at is null
                  order by r.created_at desc
                  limit 1) end
              ) as post
              from public.posts p
              where p.batch_id = b.id
            ) posts
          ), '[]'::jsonb)
        ) as batch
        from public.batches b
        where b.client_id = v_client.id and b.published
      ) batches
    ), '[]'::jsonb)
  );
end $$;
revoke all on function public.get_review_feed(text, text) from public;
grant execute on function public.get_review_feed(text, text) to anon, authenticated;

-- END OF REEL COVER PAIRS ---------------------------------------------------
