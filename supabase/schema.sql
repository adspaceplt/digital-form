-- ADspace Content Review Portal
-- Run this once in the Supabase SQL editor (Dashboard > SQL Editor > New query).
-- Safe to re-run: every statement is idempotent.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.clients (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  logo_url      text,
  access_token  text not null unique,
  passcode      text,                       -- optional extra gate, plain text, low sensitivity
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- Remembered Drive folder per client, so next month is one click.
alter table public.clients add column if not exists drive_folder text;

-- The account name shown inside each platform's mockup.
alter table public.clients add column if not exists handle_ig     text;
alter table public.clients add column if not exists handle_fb     text;
alter table public.clients add column if not exists handle_tiktok text;
alter table public.clients add column if not exists handle_xhs    text;

-- Every Drive file we have already copied, kept even if the post is deleted, so
-- re-importing reuses the file in S3 instead of paying to upload it again.
create table if not exists public.drive_assets (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.clients(id) on delete cascade,
  drive_id    text not null,
  url         text not null,
  mime_type   text,
  width       int,
  height      int,
  bytes       bigint,
  created_at  timestamptz not null default now(),
  unique (client_id, drive_id)
);
alter table public.drive_assets enable row level security;

create table if not exists public.batches (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.clients(id) on delete cascade,
  title         text not null,              -- e.g. "March 2026 Content"
  note          text,                       -- optional message to the client
  published     boolean not null default false,
  created_at    timestamptz not null default now()
);

create table if not exists public.posts (
  id            uuid primary key default gen_random_uuid(),
  batch_id      uuid not null references public.batches(id) on delete cascade,
  platform      text not null default 'instagram',
    -- instagram | facebook | tiktok | xhs
  format        text not null default 'feed',
    -- feed | carousel | reel | story | note
  handle        text,                       -- display handle inside the mockup
  caption       text,
  caption_zh    text,
  title         text,                       -- XiaoHongShu note title
  media         jsonb not null default '[]'::jsonb,
    -- [{ "url": "...", "type": "image"|"video", "poster": "..." }]
  position      int not null default 0,
  created_at    timestamptz not null default now()
);

-- Asking a client to look again after they have already approved. The previous
-- approval stays in the history, it just no longer counts.
alter table public.posts add column if not exists review_reset_at   timestamptz;
alter table public.posts add column if not exists review_reset_note text;

create table if not exists public.reviews (
  id            uuid primary key default gen_random_uuid(),
  post_id       uuid not null references public.posts(id) on delete cascade,
  decision      text not null check (decision in ('approved', 'changes')),
  note          text,
  reviewer      text,
  created_at    timestamptz not null default now()
);

-- Actions worth being able to answer for later: things that destroy data, and
-- things that change what a client can see. Deliberately not a click log.
--
-- No foreign keys here on purpose. A record of a deletion is worthless if it
-- is deleted along with the thing it describes, so subjects are stored as
-- plain text and survive the cascade.
create table if not exists public.activity_log (
  id           uuid primary key default gen_random_uuid(),
  actor        text,
  action       text not null,
  subject      text,
  detail       text,
  created_at   timestamptz not null default now()
);
create index if not exists activity_log_idx on public.activity_log(created_at desc);
alter table public.activity_log enable row level security;

-- Who may read the activity record. Everyone signed in writes to it, only the
-- people listed here can read it back.
--
-- To grant access, add a row in the Supabase dashboard:
--   insert into activity_viewers (email) values ('name@adspacestudios.com');
create table if not exists public.activity_viewers (
  email      text primary key,
  added_at   timestamptz not null default now()
);
alter table public.activity_viewers enable row level security;

create index if not exists posts_batch_idx    on public.posts(batch_id, position);
create index if not exists batches_client_idx on public.batches(client_id, created_at desc);
create index if not exists reviews_post_idx   on public.reviews(post_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Row level security
-- Anonymous visitors get NO direct table access. They read and write only
-- through the two security-definer functions below, which require the token.
-- ---------------------------------------------------------------------------

alter table public.clients enable row level security;
alter table public.batches enable row level security;
alter table public.posts   enable row level security;
alter table public.reviews enable row level security;

do $$
declare t text;
begin
  foreach t in array array['clients','batches','posts','reviews','drive_assets'] loop
    execute format('drop policy if exists team_all on public.%I', t);
    execute format(
      'create policy team_all on public.%I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- The activity record is deliberately not covered by the blanket policy above.
-- Anyone signed in can write to it, since every logged action is theirs to
-- take, but reading it back is restricted to the listed addresses.
-- If an earlier version of this file ran, activity_log carries the blanket
-- policy the loop above used to create. Policies are additive, so leaving it
-- in place would keep the record readable by everyone regardless of the rule
-- below. Remove it explicitly.
drop policy if exists team_all on public.activity_log;

drop policy if exists activity_write on public.activity_log;
create policy activity_write on public.activity_log
  for insert to authenticated with check (true);

drop policy if exists activity_read on public.activity_log;
create policy activity_read on public.activity_log
  for select to authenticated
  using (exists (
    select 1 from public.activity_viewers v
    where lower(v.email) = lower(auth.jwt() ->> 'email')));

-- Anyone signed in may check the list, which is how the interface knows whether
-- to offer the section at all. Changes are made in the dashboard.
drop policy if exists viewers_read on public.activity_viewers;
create policy viewers_read on public.activity_viewers
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Client-facing API
-- ---------------------------------------------------------------------------

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
                'reset_note', case
                  when p.review_reset_at is not null then p.review_reset_note end,
                'review',     (
                  select jsonb_build_object(
                    'decision',   r.decision,
                    'note',       r.note,
                    'reviewer',   r.reviewer,
                    'created_at', r.created_at)
                  from public.reviews r
                  where r.post_id = p.id
                    and (p.review_reset_at is null or r.created_at > p.review_reset_at)
                  order by r.created_at desc
                  limit 1)
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

create or replace function public.submit_review(
  p_token    text,
  p_post_id  uuid,
  p_decision text,
  p_note     text default null,
  p_reviewer text default null,
  p_passcode text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client_id uuid;
  v_ok        boolean;
begin
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad_decision');
  end if;

  if p_decision = 'changes' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note_required');
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
  select true into v_ok
  from public.posts p
  join public.batches b on b.id = p.batch_id
  where p.id = p_post_id and b.client_id = v_client_id and b.published;

  if v_ok is not true then
    return jsonb_build_object('error', 'not_found');
  end if;

  insert into public.reviews (post_id, decision, note, reviewer)
  values (p_post_id, p_decision, nullif(btrim(p_note), ''), nullif(btrim(p_reviewer), ''));

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.get_review_feed(text, text) from public;
revoke all on function public.submit_review(text, uuid, text, text, text, text) from public;
grant execute on function public.get_review_feed(text, text) to anon, authenticated;
grant execute on function public.submit_review(text, uuid, text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Storage
-- Create a PUBLIC bucket named "content" in Dashboard > Storage, then run this.
-- File paths are random UUIDs, so the URLs are unguessable.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from storage.buckets where id = 'content') then
    drop policy if exists content_public_read on storage.objects;
    drop policy if exists content_team_write  on storage.objects;

    create policy content_public_read on storage.objects
      for select to anon, authenticated using (bucket_id = 'content');

    create policy content_team_write on storage.objects
      for all to authenticated
      using (bucket_id = 'content') with check (bucket_id = 'content');
  end if;
end $$;
