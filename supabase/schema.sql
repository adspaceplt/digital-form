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
  poster_url  text,
  created_at  timestamptz not null default now(),
  unique (client_id, drive_id)
);
-- safe to re-run on a database created before posters existed
alter table public.drive_assets add column if not exists poster_url text;
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

-- ---------------------------------------------------------------------------
-- Short links (go.adspace.me/<slug>)
-- The list the redirector will serve. It is filled in before the domain moves
-- so the switch is a DNS change and nothing else: every slug already carries
-- the address it is printed with.
--
-- The slug IS the key. There is no separate id, because the slug is what the
-- outside world holds and two rows claiming one slug is not a state worth
-- being able to represent.
-- ---------------------------------------------------------------------------
create table if not exists public.links (
  slug        text primary key,
  target_url  text not null,
  title       text,
  active      boolean not null default true,
  created_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
-- Lowercase, URL safe, and never the empty string.
alter table public.links drop constraint if exists links_slug_shape;
alter table public.links add constraint links_slug_shape
  check (slug ~ '^[a-z0-9][a-z0-9._-]{0,79}$');
alter table public.links enable row level security;
create index if not exists links_created_idx on public.links(created_at desc);

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

-- Deleting a client takes every set, post and approval with it, so it does not
-- go through the blanket policy above. The only way through is delete_client
-- below, which runs as the owner and asks for the code first. Policies are
-- additive, so the blanket one has to be narrowed rather than sat beside.
drop policy if exists team_all      on public.clients;
drop policy if exists clients_read   on public.clients;
drop policy if exists clients_write  on public.clients;
drop policy if exists clients_update on public.clients;
create policy clients_read   on public.clients for select to authenticated using (true);
create policy clients_write  on public.clients for insert to authenticated with check (true);
create policy clients_update on public.clients for update to authenticated using (true) with check (true);

-- Short links are internal: the team manages them, anonymous visitors get no
-- direct table access at all. When the redirector is built it reads this table
-- with the service role, not with the anon key, so nothing here has to open up.
drop policy if exists links_team on public.links;
create policy links_team on public.links
  for all to authenticated using (true) with check (true);

-- Kept honest in the database rather than trusted to every caller.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists links_touch on public.links;
create trigger links_touch before update on public.links
  for each row execute function public.touch_updated_at();
-- deliberately no delete policy: see delete_client

-- ---------------------------------------------------------------------------
-- Settings the browser must never be handed
-- ---------------------------------------------------------------------------
-- The deletion code lived in js/config.js, which is a public file on a public
-- site: anyone who could open the page could read it. It lives here instead,
-- behind a policy that grants nobody any access at all. Only a security
-- definer function, which runs as the table's owner, can read it.
create table if not exists public.app_secrets (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;
drop policy if exists secrets_none on public.app_secrets;
-- No policy is created. With RLS on and no policy, every direct read and write
-- is refused, including from a signed in team member's browser console.

-- Set the code with this, run in the SQL editor. Change the text, keep the key:
--   insert into public.app_secrets (key, value) values ('delete_code', 'your-code-here')
--   on conflict (key) do update set value = excluded.value, updated_at = now();
--
-- Remove it, and deletion asks the person to type the client's name instead:
--   delete from public.app_secrets where key = 'delete_code';

create or replace function public.delete_client(p_client uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  want text;
  who  text := auth.jwt() ->> 'email';
begin
  if who is null then
    raise exception 'Not signed in';
  end if;

  select value into want from public.app_secrets where key = 'delete_code';

  -- No code set: the interface asks for the client's name instead, and has
  -- already checked it. Nothing more to enforce here.
  if want is not null and want <> '' then
    if p_code is null or p_code <> want then
      return 'wrong-code';
    end if;
  end if;

  delete from public.clients where id = p_client;
  if not found then
    return 'not-found';
  end if;
  return 'deleted';
end $$;

-- Whether a code is set at all is not a secret, and the interface needs to know
-- which question to ask before it asks it.
create or replace function public.delete_code_set()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_secrets where key = 'delete_code' and value <> '');
$$;

revoke all on function public.delete_client(uuid, text) from anon;
revoke all on function public.delete_code_set() from anon;
grant execute on function public.delete_client(uuid, text) to authenticated;
grant execute on function public.delete_code_set() to authenticated;

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
