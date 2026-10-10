-- ===========================================================================
-- APPROVAL AS SEEN — a client's decision is on the version of the post the
-- page showed, and keeps what that was (audit F2, 2026-10-10).
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/approvalseen.js
-- compares the two. Holds no word the connector stops on.
--
-- WHAT CHANGED
--   1. `posts.content_version` counts every change to a post's file, copy or
--      title, a correction before any decision included (which stays a
--      correction of the same round: the round is the posts_revision
--      trigger's alone). Stamped by trigger `posts_content_version`; a page
--      cannot set it.
--   2. `get_review_feed` sends each post's `version`.
--   3. `submit_review_seen(… p_version)`: the client's link checked first,
--      then the post locked and its version compared; a post changed since
--      the page read it is refused `changed` (with the version now), and the
--      decision is filed through `submit_review` with what was decided on
--      kept as `reviews.seen` (version, round, title, caption, caption_zh,
--      media). Joins `open_to_anon`: run 2026-10-07-function-hygiene.sql
--      again BEFORE this file. `submit_review` stays for a page loaded
--      before this one.
--
-- ROLLBACK
--   Pages first (they fall back to `submit_review` where the new function
--   is missing), then re-run the REEL COVER PAIRS section's get_review_feed
--   and remove the trigger, the function and the two columns in the SQL
--   Editor.
-- ===========================================================================

alter table public.posts add column if not exists content_version integer not null default 1;
alter table public.reviews add column if not exists seen jsonb;

create or replace function public.posts_content_version() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.media, new.caption, new.caption_zh, new.title)
     is distinct from (old.media, old.caption, old.caption_zh, old.title) then
    new.content_version := coalesce(old.content_version, 1) + 1;
  else
    new.content_version := old.content_version;
  end if;
  return new;
end $$;
revoke all on function public.posts_content_version() from public, anon, authenticated;
create or replace trigger posts_content_version before update on public.posts
  for each row execute function public.posts_content_version();

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

create or replace function public.submit_review_seen(
  p_token      text,
  p_post_id    uuid,
  p_decision   text,
  p_version    integer,
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
  v_post public.posts%rowtype;
  v_res  jsonb;
begin
  -- The link first, as submit_review asks it, so a post id alone says nothing.
  if not exists (select 1
                   from public.posts p
                   join public.batches b on b.id = p.batch_id
                   join public.clients c on c.id = b.client_id
                  where p.id = p_post_id and b.published
                    and c.access_token = p_token and c.active and not c.review_hidden
                    and (c.passcode is null or c.passcode = p_passcode)) then
    return jsonb_build_object('error', 'not_found');
  end if;
  select * into v_post from public.posts where id = p_post_id for update;
  if p_version is null or p_version is distinct from v_post.content_version then
    return jsonb_build_object('error', 'changed', 'version', v_post.content_version);
  end if;
  v_res := public.submit_review(p_token, p_post_id, p_decision, p_note, p_reviewer,
                                p_passcode, p_caption, p_caption_zh);
  if coalesce((v_res ->> 'ok')::boolean, false) then
    update public.reviews r
       set seen = jsonb_build_object('version', v_post.content_version, 'round', v_post.round,
                                     'title', v_post.title, 'caption', v_post.caption,
                                     'caption_zh', v_post.caption_zh, 'media', v_post.media)
     where r.post_id = p_post_id and r.created_at = now() and r.seen is null;
  end if;
  return v_res;
end $$;

revoke all on function public.submit_review_seen(text, uuid, text, integer, text, text, text, text, text) from public;
grant execute on function public.submit_review_seen(text, uuid, text, integer, text, text, text, text, text) to anon, authenticated;

-- END OF APPROVAL AS SEEN -----------------------------------------------------

select public.functions_tidy();
