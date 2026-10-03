-- ===========================================================================
-- HIDDEN FROM CONTENT REVIEW — a client removed from Content Review keeps
-- every set, and their review link opens nothing while they are hidden.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   The audit of 2026-10-03: Remove from Content Review deleted every set,
--   post and approval of the client before hiding them, with no way back. It
--   now hides the client alone (`clients.review_hidden`), with Undo; Enable
--   Content Review on the client's record brings them back with the same
--   link and everything in it. The link asked only that the client be
--   active, so a hidden client's link went on opening every published set.
--   Both functions it reaches now ask that the client is not hidden, and
--   answer `not_found` (Link not recognised) while they are:
--   1. `get_review_feed` (the page, and `media-pass`, which proves a link
--      through it);
--   2. `submit_review`.
--   Each body is otherwise the one before it: get_review_feed from REVIEW
--   CONFIRMED INTERNALLY, submit_review from POST REVISIONS.
--
-- ROLLBACK
--   Re-run get_review_feed from REVIEW CONFIRMED INTERNALLY and
--   submit_review from POST REVISIONS.
-- ===========================================================================

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

create or replace function public.submit_review(
  p_token      text,
  p_post_id    uuid,
  p_decision   text,
  p_note       text default null,
  p_reviewer   text default null,
  p_passcode   text default null,
  p_caption    text default null,
  p_caption_zh text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client_id uuid;
  v_post      public.posts%rowtype;
  v_cap       text;
  v_cap_zh    text;
begin
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad_decision');
  end if;

  select c.id into v_client_id
  from public.clients c
  where c.access_token = p_token
    and c.active
    and not c.review_hidden
    and (c.passcode is null or c.passcode = p_passcode);

  if v_client_id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  -- the post must belong to a published batch of this client
  select p.* into v_post
  from public.posts p
  join public.batches b on b.id = p.batch_id
  where p.id = p_post_id and b.client_id = v_client_id and b.published;

  if v_post.id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  /* A suggested copy is kept only where it differs from the copy on show,
     and only on a request for changes. */
  if p_decision = 'changes' then
    v_cap    := case when p_caption is not null
                      and p_caption is distinct from coalesce(v_post.caption, '') then p_caption end;
    v_cap_zh := case when p_caption_zh is not null
                      and p_caption_zh is distinct from coalesce(v_post.caption_zh, '') then p_caption_zh end;
  end if;

  if p_decision = 'changes' and coalesce(btrim(p_note), '') = ''
     and v_cap is null and v_cap_zh is null then
    return jsonb_build_object('error', 'note_required');
  end if;

  insert into public.reviews (post_id, decision, note, reviewer, suggested_caption, suggested_caption_zh)
  values (p_post_id, p_decision, nullif(btrim(p_note), ''), nullif(btrim(p_reviewer), ''), v_cap, v_cap_zh);

  /* The activity record is the portal's account of what was decided and by
     whom, and it held only what the team did. A client approving a post is
     the decision the whole section exists to collect, and it left nothing
     anybody could produce later: the verdict sat in `reviews` alone, which
     no screen reads as a history. The reviewer's own typed name is the
     actor, because a person decided it. */
  insert into public.activity_log (actor, action, subject, detail)
  select coalesce(nullif(btrim(coalesce(p_reviewer, '')), ''), 'Client'),
         case when p_decision = 'approved' then 'review.approved' else 'review.changes' end,
         c.name,
         b.title || ' · ' || coalesce(nullif(p.platform, ''), 'post') ||
         case when p.round > 1 then ' · revision ' || p.round else '' end ||
         coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), '') ||
         case when v_cap is not null or v_cap_zh is not null then ' · caption edited' else '' end
    from public.posts p
    join public.batches b on b.id = p.batch_id
    join public.clients c on c.id = b.client_id
   where p.id = p_post_id;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.submit_review(text, uuid, text, text, text, text, text, text) from public;
grant execute on function public.submit_review(text, uuid, text, text, text, text, text, text) to anon, authenticated;

-- END OF HIDDEN FROM CONTENT REVIEW ------------------------------------------
