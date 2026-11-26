-- ===========================================================================
-- REVIEW FEED SENDS THE CONTENT MONTH (2026-11-27)
-- ===========================================================================
-- WHY (the Content Review top, approved by the user 2026-11-26): the review
-- page names a set by its content month, "November 2026 · 6 posts". The feed
-- sent the day a set was made, which differs from its month wherever a
-- colleague made it early or moved it (the set's Content month).
-- `get_review_feed` now sends `period` beside `created_at`; nothing else in
-- the payload changes, and no contact or colleague detail is added.
--
-- ORDER: pages first (they read `period` where sent, else the month the set
-- was made), then this file. Safe to run twice. Holds no drop or delete.
-- ROLLBACK: run PAGES IN THE CLIENT'S LANGUAGE's `get_review_feed` again;
-- the page falls back to the month the set was made.
-- ===========================================================================

-- REVIEW FEED SENDS THE CONTENT MONTH ----------------------------------------

/* A set's content month (`batches.period`, YYYY-MM, empty for Ad hoc), so the
   review page names a set by the month it is for, not the day it was made. */
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

  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4); a passcode asked for names nobody (item 6).
  case public.link_passcode('review', v_client.access_token, v_client.passcode, p_passcode)
    when 'locked' then return public.link_locked('review', v_client.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode_required');
    else null;
  end case;

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
          'period',     b.period,
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
                'version',    p.content_version,
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
                    'reviewer',   case when r.source = 'team' then null else r.reviewer end,
                    'by_team',    r.source = 'team',
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
  ) || jsonb_build_object('lang', public.client_lang(v_client.id));
end $$;

-- END OF REVIEW FEED SENDS THE CONTENT MONTH ---------------------------------

select public.functions_tidy();
