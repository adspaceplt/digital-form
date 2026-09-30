-- ===========================================================================
-- REVIEW CONFIRMED INTERNALLY — the team approves a post for the client, under
-- the colleague's own name, and can take it back.
-- 2026-10-01. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `reviews.source`: who decided, 'client' (the review link) or 'team'
--      (Confirm internally in the console). Every row before this is the
--      client's.
--   2. `reviews.undone_at` / `undone_by`: a team approval taken back
--      (Revert confirmation) is kept, marked undone, and no longer answers
--      for the post. A client's decision is never undone here; the team asks
--      again with Request re-approval.
--   3. `review_confirm(p_post)`: Content Review (sets) at Work approves the
--      round on show as the signed-in colleague. Refused where the round is
--      already approved or the set is not published.
--   4. `review_revert_confirm(p_post)`: takes back the team's approval of the
--      round on show, and only that. The post falls back to the decision
--      before it (Pending, or the client's request).
--   5. `get_review_feed` sends `by_team` on the decision, so the client's page
--      reads Confirmed internally by {name}; an undone decision is never sent.
--      It also sends the client's own suggested caption on the decision
--      standing, so Edit request reopens the request as they sent it.
--   6. `posts_revision` counts only a decision that stands.
--
-- ROLLBACK
--   drop function if exists public.review_revert_confirm(uuid);
--   drop function if exists public.review_confirm(uuid);
--   alter table public.reviews drop constraint if exists reviews_source_check;
--   alter table public.reviews drop column if exists undone_by;
--   alter table public.reviews drop column if exists undone_at;
--   alter table public.reviews drop column if exists source;
--   Re-run get_review_feed and posts_revision from POST REVISIONS.
-- ===========================================================================

alter table public.reviews add column if not exists source text not null default 'client';
alter table public.reviews add column if not exists undone_at timestamptz;
alter table public.reviews add column if not exists undone_by uuid references public.team_members(id) on delete set null;
alter table public.reviews drop constraint if exists reviews_source_check;
alter table public.reviews add constraint reviews_source_check check (source in ('client', 'team'));

/* A change to what the client decided on is the next round; a decision
   taken back (undone, or asked again with Request re-approval) no longer
   counts, so an edit after it is a correction. */
create or replace function public.posts_revision() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.media, new.caption, new.caption_zh, new.title)
     is not distinct from (old.media, old.caption, old.caption_zh, old.title) then
    return new;
  end if;
  if not exists (select 1 from public.reviews r
                  where r.post_id = old.id and r.round = old.round and r.undone_at is null
                    and (old.review_reset_at is null or r.created_at > old.review_reset_at)) then
    return new;
  end if;
  insert into public.post_versions (post_id, round, platform, format, title, caption, caption_zh, media, replaced_by)
  values (old.id, old.round, old.platform, old.format, old.title, old.caption, old.caption_zh, old.media,
          nullif(auth.jwt() ->> 'email', ''))
  on conflict (post_id, round) do nothing;
  new.round := old.round + 1;
  return new;
end $$;
revoke all on function public.posts_revision() from public, anon, authenticated;

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
  where access_token = p_token and active;

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
                    'reviewer',   r.reviewer,
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

/* The client said yes by word of mouth: the team approves the round on show
   under its own name. The client's page reads Confirmed internally by
   {name}; the activity record files it as an approval by the colleague. */
create or replace function public.review_confirm(p_post uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  v_post   public.posts%rowtype;
  v_pub    boolean;
  v_title  text;
  v_client text;
  v_now    text;
begin
  if not public.allowed('review.sets', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into v_post from public.posts where id = p_post for update;
  if v_post.id is null then return jsonb_build_object('error', 'no-post'); end if;
  select b.published, b.title, c.name into v_pub, v_title, v_client
    from public.batches b join public.clients c on c.id = b.client_id
   where b.id = v_post.batch_id;
  if not coalesce(v_pub, false) then return jsonb_build_object('error', 'not-published'); end if;
  select r.decision into v_now from public.reviews r
   where r.post_id = v_post.id and r.round = v_post.round and r.undone_at is null
     and (v_post.review_reset_at is null or r.created_at > v_post.review_reset_at)
   order by r.created_at desc limit 1;
  if v_now = 'approved' then return jsonb_build_object('error', 'already-approved'); end if;

  insert into public.reviews (post_id, decision, reviewer, source)
  values (v_post.id, 'approved', me.name, 'team');

  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(nullif(auth.jwt() ->> 'email', ''), me.name), 'review.approved', v_client,
          v_title || ' · ' || coalesce(nullif(v_post.platform, ''), 'post') ||
          case when v_post.round > 1 then ' · revision ' || v_post.round else '' end ||
          ' · confirmed internally');
  return jsonb_build_object('ok', true, 'reviewer', me.name);
end $$;
revoke all on function public.review_confirm(uuid) from public, anon;
grant execute on function public.review_confirm(uuid) to authenticated;

/* Takes back the team's own approval of the round on show, and nothing else:
   a client's decision stays theirs. The row is kept, marked undone. */
create or replace function public.review_revert_confirm(p_post uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  v_post   public.posts%rowtype;
  v_rv     public.reviews%rowtype;
  v_title  text;
  v_client text;
begin
  if not public.allowed('review.sets', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into v_post from public.posts where id = p_post for update;
  if v_post.id is null then return jsonb_build_object('error', 'no-post'); end if;
  select r.* into v_rv from public.reviews r
   where r.post_id = v_post.id and r.round = v_post.round and r.undone_at is null
     and (v_post.review_reset_at is null or r.created_at > v_post.review_reset_at)
   order by r.created_at desc limit 1;
  if v_rv.id is null or v_rv.decision <> 'approved' or v_rv.source <> 'team' then
    return jsonb_build_object('error', 'not-confirmed');
  end if;
  update public.reviews set undone_at = now(), undone_by = me.id where id = v_rv.id;

  select b.title, c.name into v_title, v_client
    from public.batches b join public.clients c on c.id = b.client_id
   where b.id = v_post.batch_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(nullif(auth.jwt() ->> 'email', ''), me.name), 'reapproval.requested', v_client,
          coalesce(v_title, '') || ' · ' || coalesce(nullif(v_post.platform, ''), 'post') ||
          ' · internal confirmation reverted');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.review_revert_confirm(uuid) from public, anon;
grant execute on function public.review_revert_confirm(uuid) to authenticated;

-- END OF REVIEW CONFIRMED INTERNALLY ----------------------------------------
