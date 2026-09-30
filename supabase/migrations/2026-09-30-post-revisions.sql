-- ===========================================================================
-- POST REVISIONS — a post the client has decided on is revised in place, as
-- its next round, and the rounds before it are kept for the team.
-- 2026-09-30. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `posts.round`: which round of the post is the one on show. A change
--      to its file, caption, Chinese caption or title after the client has
--      decided on the round moves it to the next one (trigger
--      `posts_revision`), and the round it replaces is kept whole in
--      `post_versions`. Before any decision an edit is a correction and
--      makes no round.
--   2. `reviews.round`: the round a decision was about, stamped by trigger
--      (`reviews_round`), never by a page. A decision on an earlier round
--      no longer answers for the post.
--   3. `reviews.suggested_caption` / `suggested_caption_zh`: a client may
--      edit the copy inside Request changes. The edit is kept as a
--      suggestion on the request; the post's copy changes only when the
--      team accepts it (which, being a change after a decision, is the
--      next round).
--   4. `get_review_feed` sends each post's round, the decision on that
--      round only, and, for a revised post, what the client asked of the
--      round before (`asked`). Never an earlier round's file or copy: the
--      client sees the revised version alone.
--   5. `submit_review` takes the suggested copy (`p_caption`,
--      `p_caption_zh`). A request needs a note or an edit to the copy.
--   6. `post_versions` is read at Content Review (sets) View and written
--      only by the trigger.
--
-- ROLLBACK
--   drop trigger if exists posts_revision on public.posts;
--   drop function if exists public.posts_revision();
--   drop trigger if exists reviews_round on public.reviews;
--   drop function if exists public.reviews_round();
--   drop table if exists public.post_versions;
--   alter table public.reviews drop column if exists suggested_caption_zh;
--   alter table public.reviews drop column if exists suggested_caption;
--   alter table public.reviews drop column if exists round;
--   alter table public.posts drop column if exists round;
--   drop function if exists public.submit_review(text, uuid, text, text, text, text, text, text);
--   Re-run get_review_feed and submit_review from the Client-facing API
--   section of supabase/schema.sql as it stood before 2026-09-30.
-- ===========================================================================

alter table public.posts add column if not exists round int not null default 1;

alter table public.reviews add column if not exists round int;
alter table public.reviews add column if not exists suggested_caption text;
alter table public.reviews add column if not exists suggested_caption_zh text;
update public.reviews set round = 1 where round is null;
alter table public.reviews alter column round set default 1;
alter table public.reviews alter column round set not null;
create index if not exists reviews_post_round_idx on public.reviews(post_id, round, created_at desc);

create table if not exists public.post_versions (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.posts(id) on delete cascade,
  round        int not null,
  platform     text,
  format       text,
  title        text,
  caption      text,
  caption_zh   text,
  media        jsonb not null default '[]'::jsonb,
  replaced_at  timestamptz not null default now(),
  replaced_by  text,
  unique (post_id, round)
);
alter table public.post_versions enable row level security;
drop policy if exists post_versions_read on public.post_versions;
create policy post_versions_read on public.post_versions for select to authenticated
  using (public.allowed('review.sets', 'view'));

/* The round a decision is about is the post's round when it was made. */
create or replace function public.reviews_round() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select p.round into new.round from public.posts p where p.id = new.post_id;
  new.round := coalesce(new.round, 1);
  return new;
end $$;
revoke all on function public.reviews_round() from public, anon, authenticated;
drop trigger if exists reviews_round on public.reviews;
create trigger reviews_round before insert on public.reviews
  for each row execute function public.reviews_round();

/* A change to what the client decided on is the next round; the round it
   replaces is kept whole. A decision taken back by Request re-approval
   (`review_reset_at`) no longer counts, so an edit after it is a
   correction of the round the client is being asked about again. */
create or replace function public.posts_revision() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.media, new.caption, new.caption_zh, new.title)
     is not distinct from (old.media, old.caption, old.caption_zh, old.title) then
    return new;
  end if;
  if not exists (select 1 from public.reviews r
                  where r.post_id = old.id and r.round = old.round
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
drop trigger if exists posts_revision on public.posts;
create trigger posts_revision before update on public.posts
  for each row execute function public.posts_revision();

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
                /* The decision on the round on show, never one about a round
                   the client no longer sees. */
                'review',     (
                  select jsonb_build_object(
                    'decision',   r.decision,
                    'note',       r.note,
                    'reviewer',   r.reviewer,
                    'created_at', r.created_at,
                    'suggested',  (r.suggested_caption is not null or r.suggested_caption_zh is not null))
                  from public.reviews r
                  where r.post_id = p.id and r.round = p.round
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

/* The signature grows, so the old one goes first: PostgREST cannot choose
   between two functions a call fits. */
drop function if exists public.submit_review(text, uuid, text, text, text, text);
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

revoke all on function public.get_review_feed(text, text) from public;
revoke all on function public.submit_review(text, uuid, text, text, text, text, text, text) from public;
grant execute on function public.get_review_feed(text, text) to anon, authenticated;
grant execute on function public.submit_review(text, uuid, text, text, text, text, text, text) to anon, authenticated;

-- END OF POST REVISIONS -----------------------------------------------------
