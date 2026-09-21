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

-- ---------------------------------------------------------------------------
-- CRM. A client is the company, not a name typed into a box, and the same
-- record is what Content Review, Creator Campaigns and Short Links all point
-- at. These columns are what the sales team needs in front of them.
-- ---------------------------------------------------------------------------

-- Lead -> proposal -> active -> paused -> past. One word that tells the team
-- how to treat them. Leads live on the same list as billing clients, so nobody
-- keeps a second one in WhatsApp.
alter table public.clients add column if not exists stage text not null default 'lead';
alter table public.clients add column if not exists industry text;
alter table public.clients add column if not exists owner text;

-- Currency and tax are two separate switches. Currency follows where the
-- client is; Malaysian SST follows the service, so a Singapore client billed
-- from Malaysia can still carry it. Default it on and let finance turn it off
-- per client.
alter table public.clients add column if not exists market text not null default 'MY';
alter table public.clients add column if not exists sst_applies boolean not null default true;

-- What finance needs on an invoice. Filled in by whoever gets it from the
-- client, then never asked for again.
alter table public.clients add column if not exists company_no text;
alter table public.clients add column if not exists sst_no text;
alter table public.clients add column if not exists billing_address text;

alter table public.clients add column if not exists website text;
alter table public.clients add column if not exists source text;
-- Free text the team actually reads before writing: tone, no-go words,
-- competitor names, language mix.
alter table public.clients add column if not exists brand_notes text;
alter table public.clients add column if not exists updated_at timestamptz not null default now();

-- What an e-invoice needs. Every one of these is mandatory before a client can
-- become active, because a client we cannot invoice is not a client. The legal
-- name is kept apart from the display name: "Laman Citra" is what the team
-- says, "S P SETIA BERHAD" is what goes on the invoice, in capitals.
alter table public.clients add column if not exists legal_name        text;
alter table public.clients add column if not exists company_no_old    text;   -- the pre-2019 format
alter table public.clients add column if not exists tin               text;
alter table public.clients add column if not exists bill_contact      text;   -- superseded by bill_contact_id
alter table public.clients add column if not exists bill_contact_email text;
alter table public.clients add column if not exists bill_contact_phone text;
alter table public.clients add column if not exists finance_email     text;
alter table public.clients add column if not exists phone             text;
/* Superseded by `handle_*` above. The brand profile and Content Review's
   client settings were two sets of fields over one client, so a handle
   corrected on the record left the one printed on the client's own mockup
   untouched. The console edits `handle_*` in both places now; these columns
   keep what they held and are no longer written. */
alter table public.clients add column if not exists social_ig         text;
alter table public.clients add column if not exists social_fb         text;
alter table public.clients add column if not exists social_tiktok     text;
alter table public.clients add column if not exists social_xhs        text;

/* What a brand field was holding. A bare handle is taken as typed. A pasted
   profile URL gives up its last path segment, but only when that segment
   reads like a name: `instagram.com/p/DXyz` would otherwise print a route
   fragment on a client's post, which is worse than printing nothing. */
create or replace function public.handle_of(p_value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v     text := btrim(coalesce(p_value, ''));
  parts text[];
  last  text;
  ROUTE_WORDS constant text[] := array['p', 'profile', 'profiles', 'pages', 'page',
                    'user', 'users', 'home', 'reel', 'video', 'explore', 'share'];
begin
  if v = '' then return null; end if;
  if v !~* '^https?://' then return v; end if;

  v := rtrim(split_part(split_part(v, '?', 1), '#', 1), '/');
  parts := regexp_split_to_array(v, '/');
  last := parts[array_length(parts, 1)];
  if last is null or btrim(last) = '' then return null; end if;
  last := ltrim(btrim(last), '@');

  /* A route, not a person — either as the last segment, or as the one before
     it, which makes the last an id: `instagram.com/p/DXyz123` is a post and
     printing `DXyz123` on a client's own mockup is worse than printing
     nothing and being asked for the handle. */
  if lower(last) = any (ROUTE_WORDS) then return null; end if;
  if array_length(parts, 1) > 1
     and lower(ltrim(btrim(parts[array_length(parts, 1) - 1]), '@')) = any (ROUTE_WORDS)
  then return null; end if;
  if last !~ '^[A-Za-z0-9._-]{1,40}$' then return null; end if;
  return last;
end $$;

-- One-time, and only where the handle is still empty, so a correction made in
-- the console is never overwritten by a re-run.
update public.clients set handle_ig = public.handle_of(social_ig)
 where coalesce(btrim(handle_ig), '') = '' and public.handle_of(social_ig) is not null;
update public.clients set handle_fb = public.handle_of(social_fb)
 where coalesce(btrim(handle_fb), '') = '' and public.handle_of(social_fb) is not null;
update public.clients set handle_tiktok = public.handle_of(social_tiktok)
 where coalesce(btrim(handle_tiktok), '') = '' and public.handle_of(social_tiktok) is not null;
update public.clients set handle_xhs = public.handle_of(social_xhs)
 where coalesce(btrim(handle_xhs), '') = '' and public.handle_of(social_xhs) is not null;
-- Removed from Content Review without being removed from the company list.
alter table public.clients add column if not exists review_hidden boolean not null default false;

-- Every call, visit, meeting and message with a client, in order. A sales
-- person writes what was discussed and what happens next; the next action
-- and its date are what the list surfaces so nothing is left to memory.
create table if not exists public.client_touches (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references public.clients(id) on delete cascade,
  kind         text not null default 'call',   -- call | visit | meeting | whatsapp | email | note
  happened_at  date not null default current_date,
  by_whom      text,
  contact_name text,                            -- who on their side
  summary      text not null,
  next_action  text,
  next_at      date,
  created_at   timestamptz not null default now()
);
create index if not exists client_touches_client_idx on public.client_touches(client_id, happened_at desc);
alter table public.client_touches enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies
                 where tablename = 'client_touches' and policyname = 'touches staff') then
    create policy "touches staff" on public.client_touches
      for all to authenticated using (true) with check (true);
  end if;
end $$;

-- Nothing in the CRM is deleted by a click. A contact or a log entry that is
-- removed is hidden with a timestamp and can be put back; a next action that
-- is dealt with is marked done rather than erased. Reversible, every time.
alter table public.client_contacts add column if not exists archived_at timestamptz;
alter table public.client_touches  add column if not exists archived_at timestamptz;
alter table public.client_touches  add column if not exists done_at     timestamptz;
alter table public.client_touches  add column if not exists updated_at  timestamptz;

-- A lead is worth something before it is a client. The number the pipeline
-- adds up, in the client's currency.
alter table public.clients add column if not exists deal_value numeric(12,2);
alter table public.clients add column if not exists deal_note  text;

-- A client is a company; the people in it change. The campaign lock sheet and
-- the review page can pick a person from here instead of a free text box.
create table if not exists public.client_contacts (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.clients(id) on delete cascade,
  name        text not null,
  role        text,
  phone       text,
  email       text,
  whatsapp    text,
  lang        text default 'en',          -- en | zh | ms, how we write to them
  is_primary  boolean not null default false,
  notes       text,
  created_at  timestamptz not null default now()
);
create index if not exists client_contacts_client_idx on public.client_contacts(client_id);
-- One primary per client, enforced rather than merely intended.
create unique index if not exists client_contacts_one_primary
  on public.client_contacts(client_id) where is_primary;

-- The people who can be an owner. A fixed list makes "my clients" a filter;
-- anyone not on it can still be typed in, which is why owner above is text.
create table if not exists public.team_members (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  email      text,
  role       text not null default 'sales',   -- sales | account | admin
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists team_members_name_idx on public.team_members(lower(name));

alter table public.client_contacts enable row level security;
alter table public.team_members enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies
                 where tablename = 'client_contacts' and policyname = 'contacts staff') then
    create policy "contacts staff" on public.client_contacts
      for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies
                 where tablename = 'team_members' and policyname = 'team staff') then
    create policy "team staff" on public.team_members
      for all to authenticated using (true) with check (true);
  end if;
end $$;

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
-- direct table access at all. The redirector reads one row at a time through
-- link_resolve() below, never through this policy.
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
         coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), '')
    from public.posts p
    join public.batches b on b.id = p.batch_id
    join public.clients c on c.id = b.client_id
   where p.id = p_post_id;

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

-- ===========================================================================
-- CREATOR CAMPAIGNS  (Package II, custom pricing)
--
-- Sales agrees the package and rate and raises the invoice. The KOC team
-- takes over from the invoice number: sources creators, offers them as
-- options, shares one link, and runs the engagement to completion.
--
-- Package I never reaches the portal. It is a fixed set with nothing to
-- choose, so there is nothing here for it to do.
-- ===========================================================================

-- The roster. A creator exists once and is reused across every campaign,
-- which is what makes "the same creator twice" impossible rather than merely
-- detectable.
create table if not exists public.creators (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  client_rate  numeric(10,2),          -- default offer price
  notes        text,
  active       boolean not null default true,
  created_by   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table public.creators enable row level security;
create index if not exists creators_name_idx on public.creators(name);

-- One row per profile link. A creator may hold several: rednote, Instagram,
-- TikTok, Facebook, or two accounts on one platform.
--
-- `handle` is the canonical identity pulled out of the URL: the id after
-- /user/profile/ on rednote, the handle elsewhere. A xhslink.com short link
-- carries no identity, so it is stored with handle null and simply cannot
-- take part in matching.
create table if not exists public.creator_profiles (
  id          uuid primary key default gen_random_uuid(),
  creator_id  uuid not null references public.creators(id) on delete cascade,
  platform    text not null,            -- xhs | instagram | tiktok | facebook
  url         text not null,
  handle      text,
  created_at  timestamptz not null default now()
);
alter table public.creator_profiles enable row level security;
create index if not exists creator_profiles_owner on public.creator_profiles(creator_id);
-- Two creators cannot claim one identity. Short links (handle null) are exempt
-- because they identify nothing.
create unique index if not exists creator_profiles_identity
  on public.creator_profiles(platform, lower(handle)) where handle is not null;

-- One engagement for one client. It is a proposal first: the client chooses
-- from quoted rates and sees the total, and only then is an invoice raised
-- and attached here for them to open. The slot count is the number agreed
-- with sales, not something an invoice authorised.
create table if not exists public.campaigns (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.clients(id) on delete cascade,
  title         text not null,                 -- the campaign's name
  title_zh      text,
  invoice_no    text,                          -- issued after confirmation
  slots         integer not null default 10,   -- the number agreed; the cap
  deadline      date,
  owner         text,                          -- KOC team member running it
  push_format   text default 'site_visit',
  deliverable   text not null default 'video', -- video | graphic. Exactly one.
  brief         text,
  brief_zh      text,
  state         text not null default 'draft', -- draft|open|production|completed
  access_token  text unique not null,
  passcode      text,
  created_by    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table public.campaigns enable row level security;
create index if not exists campaigns_client_idx on public.campaigns(client_id, created_at desc);
-- The official invoice, as a file the client can open. Uploaded once the
-- selection is confirmed, through the same signed S3 path media uses.
alter table public.campaigns add column if not exists invoice_url         text;
alter table public.campaigns add column if not exists invoice_uploaded_at timestamptz;
-- What the campaign is for, under its name. The name is the handle the team
-- uses; the purpose is what the client reads.
/* Backups are the team's to offer, not the page's to assume. A client who has
   filled every slot was still shown every creator nobody picked, each with a
   Backup button, because the page offered backups whenever there were spare
   options. Off by default: the team opens them on the campaign when it wants
   names in reserve, and otherwise the choosing is over when the slots are. */
alter table public.campaigns add column if not exists backups_open boolean not null default false;
-- When the client wants to start. A lead that needs to commence this month is
-- worked before one that is looking at next year, and the stage clock cannot
-- say that: it measures how long we have taken, not how long they will wait.
alter table public.clients add column if not exists commence text;   -- 1_3 | 3_6 | 6_plus
alter table public.campaigns add column if not exists purpose    text;
alter table public.campaigns add column if not exists purpose_zh text;

-- A creator offered inside a campaign. The rate and the placements are
-- snapshotted here, so a roster edit can never reprice a live offer.
--
-- The unique constraint is the whole duplicate story: one creator can appear
-- in a campaign once, enforced by the database rather than by a check someone
-- might forget to run.
create table if not exists public.campaign_options (
  id             uuid primary key default gen_random_uuid(),
  campaign_id    uuid not null references public.campaigns(id) on delete cascade,
  creator_id     uuid not null references public.creators(id) on delete restrict,
  rate           numeric(10,2) not null,
  platforms      text not null,               -- comma separated placements offered
  position       integer not null default 0,
  is_replacement boolean not null default false,
  -- option → shortlisted → backup → confirmed → … → completed
  -- withdrawn (creator pulled out) and replaced (client swapped) are terminal
  -- and are never deleted, because the invoice has to reconcile against them.
  state          text not null default 'option',
  drop_reason    text,
  goodwill       boolean not null default false,
  added_at       timestamptz not null default now(),
  unique (campaign_id, creator_id)
);
alter table public.campaign_options enable row level security;
create index if not exists campaign_options_camp on public.campaign_options(campaign_id, position);

-- Who confirmed, when, and whether they did it themselves or we keyed it in
-- from a WhatsApp reply. Both are honest; pretending every client clicks
-- Confirm is how an audit trail ends up lying.
create table if not exists public.campaign_confirmations (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references public.campaigns(id) on delete cascade,
  kind         text not null,          -- client | keyed_in
  person       text not null,
  source       text,                   -- portal | whatsapp | email
  note         text,
  created_at   timestamptz not null default now()
);
alter table public.campaign_confirmations enable row level security;
create index if not exists campaign_conf_camp on public.campaign_confirmations(campaign_id, created_at desc);

-- Team only. Clients reach campaigns through the token-checked functions
-- below and never touch these tables directly.
drop policy if exists creators_team on public.creators;
create policy creators_team on public.creators
  for all to authenticated using (true) with check (true);
drop policy if exists creator_profiles_team on public.creator_profiles;
create policy creator_profiles_team on public.creator_profiles
  for all to authenticated using (true) with check (true);
drop policy if exists campaigns_team on public.campaigns;
create policy campaigns_team on public.campaigns
  for all to authenticated using (true) with check (true);
drop policy if exists campaign_options_team on public.campaign_options;
create policy campaign_options_team on public.campaign_options
  for all to authenticated using (true) with check (true);
drop policy if exists campaign_conf_team on public.campaign_confirmations;
create policy campaign_conf_team on public.campaign_confirmations
  for all to authenticated using (true) with check (true);

drop trigger if exists creators_touch on public.creators;
create trigger creators_touch before update on public.creators
  for each row execute function public.touch_updated_at();
drop trigger if exists campaigns_touch on public.campaigns;
create trigger campaigns_touch before update on public.campaigns
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Client-facing API. Same shape as the review portal: the token is the key,
-- the function is the only door, and cost_rate is never in the result.
-- ---------------------------------------------------------------------------
create or replace function public.get_campaign(p_token text, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
  cl clients%rowtype;
  billable boolean;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into cl from clients where id = c.client_id;

  -- An invoice belongs to an accepted booking. Until the client has chosen and
  -- the team has confirmed at least one creator, the number and the PDF stay
  -- off the client's page, and reverting the last confirmation takes them off
  -- it again. The gate is here rather than on the page so nothing the client
  -- can open carries what it should not show.
  select exists (
    select 1 from campaign_options o
     where o.campaign_id = c.id
       and o.state in ('confirmed', 'pending_visit', 'pending_draft', 'submitted',
                       'reviewing', 'changes', 'scheduled', 'posted', 'completed')
  ) into billable;

  if c.passcode is not null and c.passcode <> '' then
    if p_passcode is null or p_passcode <> c.passcode then
      return jsonb_build_object('error', 'passcode', 'client', cl.name);
    end if;
  end if;

  return jsonb_build_object(
    'campaign', jsonb_build_object(
      'title', c.title, 'title_zh', c.title_zh,
      'purpose', c.purpose, 'purpose_zh', c.purpose_zh, 'slots', c.slots,
      'backups_open', coalesce(c.backups_open, false),
      'deadline', c.deadline, 'state', c.state, 'deliverable', c.deliverable,
      'push_format', c.push_format, 'brief', c.brief, 'brief_zh', c.brief_zh,
      'invoice_no', case when billable then c.invoice_no end,
      'invoice_url', case when billable then c.invoice_url end),
    -- Currency and tax travel with the campaign, because the client's page
    -- prints both and must not assume Malaysia.
    'client', jsonb_build_object('name', cl.name, 'logo_url', cl.logo_url,
      'market', coalesce(cl.market, 'MY'), 'sst_applies', coalesce(cl.sst_applies, true)),
    /* A draft reaches the client when the team releases it, and not a moment
       before. `submitted` is the team's own step, so it is reported as
       `pending_draft`: the client is not asked to approve something they
       cannot open, and does not learn that a round exists. A `changes` the
       team raised is the same round going back to the creator, so it is
       withheld the same way; a `changes` the client raised is their own and
       is reported as it is. The mapping is here and not on the page, because
       what a client may not see is withheld by this function. */
    'options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'name', cr.name,
        'rate', o.rate, 'platforms', o.platforms, 'state', s.shown,
        'is_replacement', o.is_replacement, 'added_at', o.added_at,
        -- Production. Present once a creator is locked; null before that, so
        -- the page can tell "not started" from "nothing to say".
        'visit_date', o.visit_date, 'visit_time', o.visit_time,
        'visit_location', o.visit_location, 'visit_pic', o.visit_pic,
        'visit_pic_phone', o.visit_pic_phone, 'tracking_no', o.tracking_no,
        'draft_url', case when s.released then o.draft_url end,
        'revision_round', o.revision_round,
        'planned_publish', o.planned_publish,
        /* What the creator uploaded, once it has been released: the newest
           round handed in, which at `changes` is the one the client turned
           down and wants to refer back to. Never the round sitting with the
           team. */
        'files', case when s.released then coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', d.id, 'url', d.url, 'name', d.name, 'kind', d.kind,
              'bytes', d.bytes) order by d.uploaded_at)
            from campaign_deliverables d
            where d.option_id = o.id and d.removed_at is null
              and d.round = (select max(d2.round) from campaign_deliverables d2
                             where d2.option_id = o.id and d2.removed_at is null)
          ), '[]'::jsonb) else '[]'::jsonb end,
        -- The caption is part of what is being approved, so it travels with
        -- the files and is withheld with them.
        'caption', case when s.released then o.draft_caption end,
        'profiles', coalesce((
          select jsonb_agg(jsonb_build_object('platform', p.platform, 'url', p.url))
          from creator_profiles p where p.creator_id = cr.id), '[]'::jsonb),
        -- One row per platform posted on, so two placements stay two numbers.
        'posts', coalesce((
          select jsonb_agg(jsonb_build_object(
            'platform', pp.platform, 'post_url', pp.post_url,
            'published_at', pp.published_at, 'window_days', pp.window_days,
            'impressions', pp.impressions, 'engagements', pp.engagements,
            'views', pp.views, 'measured_at', pp.measured_at) order by pp.platform)
          from option_posts pp where pp.option_id = o.id), '[]'::jsonb),
        /* What the client last decided, so the card can say who approved it
           and when rather than jumping to the next step with nothing to show
           for the decision. Withheld with the draft it is about. */
        'review', case when s.released then (
            select jsonb_build_object('decision', r.decision, 'reviewer', r.reviewer,
                                      'note', r.note, 'at', r.created_at)
            from option_reviews r where r.option_id = o.id
            order by r.created_at desc limit 1) end)
        order by o.position, o.added_at)
      from campaign_options o
      join creators cr on cr.id = o.creator_id
      cross join lateral (
        select sh.shown,
               sh.shown in ('reviewing', 'changes', 'scheduled', 'posted', 'completed')
                 as released
        from (select case
                       when o.state = 'submitted' then 'pending_draft'
                       when o.state = 'changes'
                            and coalesce(o.changes_by, 'client') = 'team' then 'pending_draft'
                       else o.state
                     end as shown) sh
      ) s
      where o.campaign_id = c.id and o.state <> 'replaced'), '[]'::jsonb)
  );
end $$;

-- A client's verdict on one draft. The round is counted here rather than
-- trusted to the caller, so the tally cannot be talked down later.
create or replace function public.review_draft(
  p_token text, p_option uuid, p_decision text, p_note text default null,
  p_reviewer text default null, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
  o campaign_options%rowtype;
  n integer;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad-decision');
  end if;

  select * into o from campaign_options
   where id = p_option and campaign_id = c.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;

  -- Only a draft that is actually with the client can be ruled on.
  if o.state not in ('reviewing', 'changes') then
    return jsonb_build_object('error', 'not-reviewing');
  end if;

  n := coalesce(o.revision_round, 0);

  insert into option_reviews (option_id, round, decision, note, reviewer)
  values (p_option, greatest(n, 1), p_decision, nullif(trim(coalesce(p_note, '')), ''), p_reviewer);

  if p_decision = 'approved' then
    update campaign_options set state = 'scheduled' where id = p_option;
  else
    update campaign_options
       set state = 'changes', revision_round = greatest(n, 1) + 1,
           changes_by = 'client'
     where id = p_option;
  end if;

  /* The client's decision is the one event on a campaign that nobody on the
     team witnesses, and it was the only one the activity record never held:
     a draft went to Reviewing and appeared as Scheduled with nothing in
     between saying who had said yes. The reviewer's own name is the actor,
     because a person decided it. */
  insert into activity_log (actor, action, subject, detail)
  select coalesce(nullif(trim(coalesce(p_reviewer, '')), ''), 'Client'),
         'campaign.review', c.title,
         cr.name || ' · ' ||
         case when p_decision = 'approved' then 'Approved' else 'Changes requested' end ||
         coalesce(': ' || nullif(trim(coalesce(p_note, '')), ''), '')
    from creators cr where cr.id = o.creator_id;

  return jsonb_build_object('ok', true, 'decision', p_decision);
end $$;

revoke all on function public.review_draft(text, uuid, text, text, text, text) from public;
grant execute on function public.review_draft(text, uuid, text, text, text, text) to anon, authenticated;

-- Selection. Rewrites only the rows this campaign owns, refuses to exceed the
-- invoiced slot count, and never touches a row that has moved past confirmed.
create or replace function public.save_selection(
  p_token text, p_selected uuid[], p_backup uuid[], p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
  n integer;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;

  n := coalesce(array_length(p_selected, 1), 0);
  if n > c.slots then
    return jsonb_build_object('error', 'over-slots', 'slots', c.slots);
  end if;

  -- Anything already confirmed or further along is the team's to change.
  update campaign_options set state = 'option'
   where campaign_id = c.id and state in ('shortlisted', 'backup');

  if n > 0 then
    update campaign_options set state = 'shortlisted'
     where campaign_id = c.id and id = any(p_selected) and state = 'option';
  end if;
  -- Only where the team opened them: the page hides the control, and this is
  -- what makes that a fact rather than a courtesy.
  if coalesce(c.backups_open, false) and coalesce(array_length(p_backup, 1), 0) > 0 then
    update campaign_options set state = 'backup'
     where campaign_id = c.id and id = any(p_backup) and state = 'option';
  end if;

  return jsonb_build_object('ok', true, 'selected', n);
end $$;

create or replace function public.confirm_selection(
  p_token text, p_person text, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;

  insert into campaign_confirmations (campaign_id, kind, person, source)
  values (c.id, 'client', trim(p_person), 'portal');

  /* Logged here and not in `save_selection`: that one fires on every tick as
     an autosave, and a record full of half-made selections is a record nobody
     can read. This is the commitment, and it is the one that carries a name. */
  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          (select count(*)::text || ' creator' || case when count(*) = 1 then '' else 's' end
             from campaign_options
            where campaign_id = c.id and state = 'shortlisted') || ' confirmed');

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.get_campaign(text, text) from public;
revoke all on function public.save_selection(text, uuid[], uuid[], text) from public;
revoke all on function public.confirm_selection(text, text, text) from public;
grant execute on function public.get_campaign(text, text) to anon, authenticated;
grant execute on function public.save_selection(text, uuid[], uuid[], text) to anon, authenticated;
grant execute on function public.confirm_selection(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- QR codes for short links
--
-- A QR code cannot be revoked. It is a picture of a URL, and a printed one
-- keeps decoding to that URL forever. What can be revoked is what the URL
-- resolves to, which is why each code carries its own identity rather than
-- pointing at the bare slug:
--
--     https://go.adspace.me/<slug>?q=<code>
--
-- The redirector turns away a scan carrying a revoked code while the typed
-- link keeps working, and one slug can carry several codes so a single
-- placement can be pulled without taking the rest down with it.
--
-- The encoded text never changes for a given code, so the image is permanent:
-- regenerate it in a year and it is the same picture.
-- ---------------------------------------------------------------------------
create table if not exists public.link_qrs (
  code        text primary key,
  slug        text not null references public.links(slug) on delete cascade,
  label       text,
  active      boolean not null default true,
  revoked_at  timestamptz,
  created_by  text,
  created_at  timestamptz not null default now()
);
alter table public.link_qrs drop constraint if exists link_qrs_code_shape;
alter table public.link_qrs add constraint link_qrs_code_shape
  check (code ~ '^[a-z0-9]{6,16}$');
alter table public.link_qrs enable row level security;
create index if not exists link_qrs_slug_idx on public.link_qrs(slug, created_at);

drop policy if exists link_qrs_team on public.link_qrs;
create policy link_qrs_team on public.link_qrs
  for all to authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- The redirector's one read
--
-- hi.adspace.me is a Cloudflare Worker; its source is workers/links/ in this
-- repository. It was going to read these two tables with the service role,
-- which would have meant putting a key that can read and write every table in
-- the database into a Cloudflare secret so that a redirector could look up one
-- column. This function is the narrower thing that does the same job: one
-- exact slug in, one destination out. No listing, no search, no prefix match
-- and no second column, so the anon key is enough and nothing that can write
-- ever leaves Supabase.
--
-- What it gives away is what a short link gives away by definition: hold the
-- slug, learn where it goes. That is the redirect itself.
--
-- The state comes back beside the address because the four answers are four
-- different pages. A slug nobody has entered is not a slug the team has
-- paused, and neither is a revoked QR code: the code is turned away while the
-- typed link keeps working, which is the whole reason link_qrs carries its
-- own identity rather than pointing at the bare slug.
--
-- The out parameters are named url and state, not target_url: a declared name
-- that matches a column resolves against the column at run time, and PL/pgSQL
-- does not say so until the function is called.
-- ---------------------------------------------------------------------------
create or replace function public.link_resolve(p_slug text, p_qr text default null)
returns table (url text, state text)
language plpgsql security definer stable set search_path = public as $$
declare
  v_slug   text := lower(btrim(coalesce(p_slug, '')));
  v_code   text := lower(btrim(coalesce(p_qr, '')));
  v_target text;
  v_live   boolean;
begin
  if v_slug = '' then
    return query select null::text, 'missing'::text;
    return;
  end if;

  select l.target_url, l.active into v_target, v_live
    from public.links l
   where l.slug = v_slug;

  if v_target is null then
    return query select null::text, 'missing'::text;
    return;
  end if;
  if not v_live then
    return query select null::text, 'paused'::text;
    return;
  end if;

  -- A scan carries its code; a typed link does not, and is never turned away
  -- by one. A code that belongs to another slug is as revoked as a dead one.
  if v_code <> '' and not exists (
       select 1 from public.link_qrs q
        where q.code = v_code and q.slug = v_slug and q.active) then
    return query select null::text, 'revoked'::text;
    return;
  end if;

  return query select v_target, 'ok'::text;
end $$;

revoke all on function public.link_resolve(text, text) from public;
grant execute on function public.link_resolve(text, text) to anon, authenticated;

-- ===========================================================================
-- CREATOR CAMPAIGNS, PHASES 2 AND 3
-- Production, drafts and results.
--
-- The campaign has four states; the work has one state per creator, because
-- they move at different speeds. Creator three can be Posted while creator
-- seven is still waiting to film, and a single campaign status cannot say so.
--
-- The pipeline, in order:
--   confirmed       locked by us, with a name and a time against it
--                   (the invoice is raised and attached at this point)
--   pending_visit   logistics set, waiting on the shoot
--                   (pending_delivery instead, when the format is seeding)
--   pending_draft   filmed, waiting on content
--   reviewing       draft link with the client
--   changes         client asked for edits. Round N of 2
--   scheduled       approved, publish date set
--   posted          live, post link captured
--   completed       results in, creator closed
--
-- And two that end it early, neither of which is ever deleted, because the
-- invoice has to reconcile against them:
--   withdrawn       the creator pulled out
--   replaced        the client swapped them
-- ===========================================================================

-- Logistics. A visit and a delivery are the same shape of thing; which one is
-- asked for depends on the campaign's push format, so both live here rather
-- than in two near-identical tables.
alter table public.campaign_options add column if not exists visit_date      date;
alter table public.campaign_options add column if not exists visit_time      text;
alter table public.campaign_options add column if not exists visit_location  text;
alter table public.campaign_options add column if not exists visit_pic       text;
alter table public.campaign_options add column if not exists visit_pic_phone text;
alter table public.campaign_options add column if not exists tracking_no     text;
-- Seven days after a shoot by default. Delivery and no-visit campaigns can
-- set the same deadline directly without inventing a shoot date.
alter table public.campaign_options add column if not exists submission_due  date;

-- Content. One deliverable per creator, so one draft link. It is a Drive URL
-- pasted in, deliberately not an import: the content already lives in Drive
-- and copying it here would only make a second place for it to be wrong.
alter table public.campaign_options add column if not exists draft_url       text;
alter table public.campaign_options add column if not exists revision_round  integer not null default 0;

-- Planned against actual, kept apart. The status says a post is scheduled;
-- only the dates say whether the date was met, which is what gets asked about.
alter table public.campaign_options add column if not exists planned_publish date;
alter table public.campaign_options add column if not exists confirmed_at    timestamptz;
alter table public.campaign_options add column if not exists confirmed_by    text;
alter table public.campaign_options add column if not exists notes           text;

-- One row per platform the creator posts on. "XHS sync IG" is one video
-- published twice, so it is one draft, two post links and two sets of numbers.
-- Averaging them would hide exactly the thing worth knowing.
create table if not exists public.option_posts (
  id           uuid primary key default gen_random_uuid(),
  option_id    uuid not null references public.campaign_options(id) on delete cascade,
  platform     text not null,
  post_url     text,
  published_at date,
  window_days  integer not null default 7,
  impressions  bigint,
  engagements  bigint,
  views        bigint,
  measured_at  date,
  created_at   timestamptz not null default now(),
  unique (option_id, platform)
);
alter table public.option_posts enable row level security;
create index if not exists option_posts_owner on public.option_posts(option_id);

-- Every decision a client makes on a draft, kept as a list rather than a flag,
-- because "how many rounds has this had" is a commercial question. Two rounds
-- are included; a third is chargeable, and nobody can bill for what was never
-- written down.
create table if not exists public.option_reviews (
  id          uuid primary key default gen_random_uuid(),
  option_id   uuid not null references public.campaign_options(id) on delete cascade,
  round       integer not null default 1,
  decision    text not null check (decision in ('approved', 'changes')),
  note        text,
  reviewer    text,
  created_at  timestamptz not null default now()
);
alter table public.option_reviews enable row level security;
create index if not exists option_reviews_owner on public.option_reviews(option_id, created_at desc);

drop policy if exists option_posts_team on public.option_posts;
create policy option_posts_team on public.option_posts
  for all to authenticated using (true) with check (true);
drop policy if exists option_reviews_team on public.option_reviews;
create policy option_reviews_team on public.option_reviews
  for all to authenticated using (true) with check (true);

-- ===========================================================================
-- ACCESS
-- Who may do what, decided by the database and not by which buttons a page
-- chooses to draw. Every signed-in person has a row in team_members; the row
-- says which sections they see, whether they see the activity record and the
-- billing fields, and whether they may remove things. An admin manages the
-- rows from the Team page. Someone with a login but no row sees nothing.
-- ===========================================================================
alter table public.team_members add column if not exists can_clients   boolean not null default true;
alter table public.team_members add column if not exists can_review    boolean not null default true;
alter table public.team_members add column if not exists can_campaigns boolean not null default true;
alter table public.team_members add column if not exists can_links     boolean not null default true;
alter table public.team_members add column if not exists can_activity  boolean not null default false;
alter table public.team_members add column if not exists can_billing   boolean not null default true;
alter table public.team_members add column if not exists can_remove    boolean not null default false;
alter table public.team_members add column if not exists updated_at    timestamptz;
/* Moved up from the user groups block below so `allowed()` can be written
   once. It used to be declared after `team_roles`, which is after the first
   definition of `allowed()`, so a second copy of that function existed
   further down purely to reach `is_admin` — and the second copy had dropped
   `doc_void` from its case list, so the capability answered false for every
   non-admin group however the switch was set. One definition, one place. */
alter table public.team_members add column if not exists is_admin     boolean not null default false;
alter table public.team_members add column if not exists can_doc_void boolean not null default false;

/* ACCESS IS A LEVEL PER SECTION, NOT A SWITCH PER VERB.
   `{"clients":"work","review":"manage", …}` over the seven console sections,
   with four levels ranked none < view < work < manage.

   The old model was six section booleans plus one global `can_remove`, so the
   authority to permanently delete could not be granted for one section
   without granting it for all of them: turning it on so a group could delete
   a content set also let them delete a client, a letter, a contact and a rate
   card line. It is per section now.

   The levels are drawn on **reversibility**, not on add/edit/delete/share.
   Add and edit are reversible; so is publishing, because Unpublish exists.
   Permanent deletion is not. A matrix of sections against verbs would have
   been twenty eight switches of which about sixteen name nothing this portal
   does — and this console already removed one permission matrix for exactly
   that reason. */
alter table public.team_members add column if not exists access jsonb not null default '{}'::jsonb;
create unique index if not exists team_members_email_idx
  on public.team_members(lower(email)) where email is not null;

/* The cutover, and only the cutover: when this file first ran, everyone who
   could already sign in became an Account so nobody was locked out.

   It must never run again. Clients have logins now, so auth.users is no
   longer a list of colleagues: granting a contact portal access creates their
   login, and a sweep of auth.users would hand that contact an active team row
   with can_clients, can_review, can_campaigns, can_links and can_billing on
   it, which is read and write over every client in the console. Hence two
   guards that cannot both be got round: the sweep runs only while the team
   list is empty, and it never takes an address that belongs to a client
   contact. A login that should be on the team is added from the Team page,
   where a person decides it. */
do $$ begin
  if not exists (select 1 from public.team_members) then
    insert into public.team_members (name, email, role)
      select coalesce(u.raw_user_meta_data ->> 'name', split_part(u.email, '@', 1)),
             u.email, 'account'
      from auth.users u
      where u.email is not null
        and not exists (select 1 from public.client_contacts c
                         where lower(c.email) = lower(u.email));
  end if;
end $$;

-- The first admin. Change the address if the owner's login is a different one.
update public.team_members
  set role = 'admin', can_activity = true, can_remove = true,
      can_clients = true, can_review = true, can_campaigns = true, can_links = true, can_billing = true
  where lower(email) = 'adspacestudios@gmail.com';

-- A role sets sensible defaults when it is chosen; the switches can then be
-- adjusted per person. Sales sees Clients only. Account sees the work but not
-- the record and cannot remove. Admin sees and may do everything.
create or replace function public.team_role_defaults()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' or new.role is distinct from old.role then
    if new.role = 'admin' then
      new.can_clients := true;  new.can_review := true; new.can_campaigns := true;
      new.can_links := true;    new.can_activity := true; new.can_billing := true; new.can_remove := true;
    elsif new.role = 'sales' then
      new.can_clients := true;  new.can_review := false; new.can_campaigns := false;
      new.can_links := false;   new.can_activity := false; new.can_billing := true; new.can_remove := false;
    else
      new.role := 'account';
      new.can_clients := true;  new.can_review := true; new.can_campaigns := true;
      new.can_links := true;    new.can_activity := false; new.can_billing := true; new.can_remove := false;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists team_role_defaults on public.team_members;
create trigger team_role_defaults before insert or update on public.team_members
  for each row execute function public.team_role_defaults();

-- Nobody removes their own admin role or deactivates themselves, so the team
-- can never be left with no admin by accident.
create or replace function public.team_keep_one_admin()
returns trigger language plpgsql as $$
begin
  if lower(old.email) = lower(auth.jwt() ->> 'email')
     and old.role = 'admin'
     and (tg_op = 'DELETE' or new.role <> 'admin' or new.active = false) then
    raise exception 'You cannot remove your own admin access. Ask another admin.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists team_keep_one_admin on public.team_members;
create trigger team_keep_one_admin before update or delete on public.team_members
  for each row execute function public.team_keep_one_admin();

-- The signed-in person's own row. What the console reads once at sign-in to
-- decide what to draw; the policies below decide what actually works.
create or replace function public.me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members
  where lower(email) = lower(auth.jwt() ->> 'email') and active
  limit 1
$$;
grant execute on function public.me() to authenticated;

-- The four levels, ranked. Anything unknown is nothing, so a section a group
-- has never been given is a section it cannot reach.
create or replace function public.level_rank(p_level text)
returns int language sql immutable as $$
  select case lower(coalesce(p_level, ''))
    when 'view' then 1 when 'work' then 2 when 'manage' then 3 else 0 end;
$$;

/* The predicate every policy asks: does this person reach this level in this
   section, or in this part of it? `view` reads, `work` adds, edits and
   publishes, `manage` also destroys. An admin reaches everything.

   A PART IS A KEY UNDER ITS SECTION. The access map holds a level per
   section (`clients`) and, where a group needs one, a level per part of a
   section (`clients.billing`): a part answers with its own level where one is
   set and with its section's where none is, so a group that has never set a
   part is exactly where it was. The parts are the panes and lists a section
   is made of, and nothing finer:

     clients    contacts · billing · services · documents · requests · calls
     review     sets · settings
     campaigns  campaigns · creators · finance
     register   documents · hr

   HR letters were a section of their own (`hr`) until this went in; they are
   `register.hr` now, and the backfill below moves the level across once. */
create or replace function public.allowed(p_section text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members;
  k text := lower(coalesce(p_section, ''));
  lv text;
begin
  select * into t from public.team_members
    where lower(email) = lower(auth.jwt() ->> 'email') and active limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  lv := t.access ->> k;
  if lv is null and position('.' in k) > 0 then
    lv := t.access ->> split_part(k, '.', 1);
  end if;
  return public.level_rank(lv) >= public.level_rank(p_level);
end $$;
grant execute on function public.allowed(text, text) to authenticated;

/* The one-argument form stays for `admin`, the flag that opens everything,
   and as the everyday form: a section or part name passed here means
   **work**, not view, so a call site missed when the levels went in refuses
   rather than quietly granting a write to somebody who was only given
   reading. Every read policy names `view` explicitly. `remove` is
   deliberately gone — that was the global flag this model exists to break
   up, so any call still asking for it fails loudly.

   `billing` was a capability here, a switch beside the ladder, because a
   pane inside the client record is not a section. It went on 2026-09-22 at
   the user's request: the letters in Documents print the registered name
   and the billing address anyway, so the switch hid a pane and not the
   facts, and a group that could open Clients without Billing read as a
   mistake nobody had made. Billing is `clients.billing` now, a part with the
   same four levels as everything else; the `can_billing` columns stay,
   unread, as `can_doc_void` does. `allowed('billing')` therefore refuses,
   which is what a retired switch should do. */
create or replace function public.allowed(flag text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  if flag = 'admin' then
    select * into t from public.team_members
      where lower(email) = lower(auth.jwt() ->> 'email') and active limit 1;
    if t.id is null then return false; end if;
    return t.is_admin or t.role = 'admin';
  end if;
  return public.allowed(flag, 'work');
end $$;
grant execute on function public.allowed(text) to authenticated;

-- The section tables, each gated by the part of its section it belongs to,
-- with removal gated twice. Policies are additive, so the old blanket ones
-- have to go first.
do $$
declare
  spec text[][] := array[
    ['client_contacts',        'clients.contacts'],
    ['client_touches',         'clients.calls'],
    ['batches',                'review.sets'],
    ['posts',                  'review.sets'],
    ['reviews',                'review.sets'],
    ['drive_assets',           'review.sets'],
    ['links',                  'links'],
    ['link_qrs',               'links'],
    ['creators',               'campaigns.creators'],
    ['creator_profiles',       'campaigns.creators'],
    ['campaigns',              'campaigns.campaigns'],
    ['campaign_options',       'campaigns.campaigns'],
    ['campaign_confirmations', 'campaigns.campaigns'],
    ['option_posts',           'campaigns.campaigns'],
    ['option_reviews',         'campaigns.campaigns']
  ];
  i int; t text; f text; p record;
begin
  for i in 1 .. array_length(spec, 1) loop
    t := spec[i][1]; f := spec[i][2];
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy if exists %I on public.%I', p.policyname, t);
    end loop;
    /* The four statements are the four levels, which is what the level model
       buys: reading is `view`, writing is `work`, and deleting is `manage` in
       that section rather than one global remove flag shared by all of them. */
    execute format('create policy %I on public.%I for select to authenticated using (public.allowed(%L, ''view''))', t || '_read', t, f);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.allowed(%L, ''work''))', t || '_write', t, f);
    execute format('create policy %I on public.%I for update to authenticated using (public.allowed(%L, ''work'')) with check (public.allowed(%L, ''work''))', t || '_edit', t, f, f);
    execute format('create policy %I on public.%I for delete to authenticated using (public.allowed(%L, ''manage''))', t || '_del', t, f);
  end loop;
end $$;

-- Clients are read by every section that hangs off them, and written by the
-- CRM and by Content Review (handles, logo, passcode, the review flag).
drop policy if exists team_all       on public.clients;
drop policy if exists clients_read   on public.clients;
drop policy if exists clients_write  on public.clients;
drop policy if exists clients_update on public.clients;
create policy clients_read on public.clients for select to authenticated
  using (public.allowed('clients', 'view') or public.allowed('review', 'view')
      or public.allowed('campaigns', 'view'));
create policy clients_write on public.clients for insert to authenticated
  with check (public.allowed('clients'));
create policy clients_update on public.clients for update to authenticated
  using (public.allowed('clients') or public.allowed('review.settings'))
  with check (public.allowed('clients') or public.allowed('review.settings'));

/* Two parts live in columns of a row other parts also write, so a policy
   cannot separate them: the billing details on `clients` and the invoice on
   `campaigns`. A trigger asks the part's own level for exactly those columns
   and lets the rest of the row through on the section's, so hiding the
   Billing pane from a group is a refusal in the database and not only a tab
   the page does not draw. */
create or replace function public.clients_billing_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- A billing contact deleted from Contacts nulls bill_contact_id by the
  -- foreign key, which is a cascade and not a person editing Billing.
  if pg_trigger_depth() > 1 then return new; end if;
  if (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.sst_applies,
      new.bill_contact_id, new.finance_email, new.billing_address)
     is distinct from
     (old.legal_name, old.company_no, old.company_no_old, old.tin, old.sst_no, old.sst_applies,
      old.bill_contact_id, old.finance_email, old.billing_address)
     and not public.allowed('clients.billing', 'work') then
    raise exception 'Billing details need Clients: Billing at Work.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists clients_billing_guard on public.clients;
create trigger clients_billing_guard before update on public.clients
  for each row execute function public.clients_billing_guard();

create or replace function public.campaigns_finance_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.invoice_no, new.invoice_url, new.invoice_uploaded_at)
     is distinct from (old.invoice_no, old.invoice_url, old.invoice_uploaded_at)
     and not public.allowed('campaigns.finance', 'work') then
    raise exception 'The invoice needs Creator Campaigns: Finance at Work.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists campaigns_finance_guard on public.campaigns;
create trigger campaigns_finance_guard before update on public.campaigns
  for each row execute function public.campaigns_finance_guard();

-- The activity record is written by anyone and read by those allowed to.
-- activity_viewers is no longer consulted; the switch lives on the team row.
drop policy if exists activity_read on public.activity_log;
create policy activity_read on public.activity_log
  for select to authenticated using (public.allowed('activity', 'view'));

-- The team list is read by everyone signed in (the owner dropdown, and me())
-- and changed only by an admin. The admin test goes through allowed(), which
-- is security definer: a policy on team_members that queried team_members
-- directly would re-enter itself and Postgres refuses with "infinite
-- recursion detected".
drop policy if exists "team staff" on public.team_members;
drop policy if exists team_read    on public.team_members;
drop policy if exists team_admin   on public.team_members;
create policy team_read on public.team_members for select to authenticated using (true);
create policy team_admin on public.team_members for all to authenticated
  using (public.allowed('team', 'manage'))
  with check (public.allowed('team', 'manage'));

-- ===========================================================================
-- USER GROUPS
-- A person belongs to one group; the group says what its members may do.
-- Admin, Account and Sales come built in; an admin can add more from the
-- Team page. A member's can_* columns are a copy of the group's, kept in
-- step by trigger, so every policy above keeps reading the member row.
-- ===========================================================================
create table if not exists public.team_roles (
  slug          text primary key,
  name          text not null,
  is_admin      boolean not null default false,
  can_clients   boolean not null default true,
  can_review    boolean not null default true,
  can_campaigns boolean not null default true,
  can_links     boolean not null default true,
  can_activity  boolean not null default false,
  can_billing   boolean not null default true,
  can_remove    boolean not null default false,
  can_doc_void  boolean not null default false,
  position      integer not null default 0,
  created_at    timestamptz not null default now()
);
alter table public.team_roles enable row level security;
insert into public.team_roles
  (slug, name, is_admin, can_clients, can_review, can_campaigns, can_links, can_activity, can_billing, can_remove, can_doc_void, position)
values
  ('admin',   'Admin',   true,  true, true,  true,  true,  true,  true, true,  true,  0),
  ('account', 'Marketing', false, true, true,  true,  true,  false, true, false, false, 1),
  ('sales',   'Sales',   false, true, false, false, false, false, true, false, false, 2)
on conflict (slug) do nothing;

-- `is_admin` and `can_doc_void` are declared in the ACCESS block above now,
-- so one definition of allowed() can reach them.
alter table public.team_roles add column if not exists access jsonb not null default '{}'::jsonb;

/* The levels, backfilled once from the switches each group already carried,
   so this file changes what a permission *can* say without changing what any
   existing group is allowed to do on the day it runs.

   A section the group could open becomes `work`, or `manage` where it also
   held the old global remove flag. Activity is a log, so it is `view` or
   nothing. Services is read by everyone who is signed in and edited by an
   admin, and Team is an admin's alone, so both start where they already were.
   Guarded on emptiness: the levels are edited on the Team page after this,
   and a backfill that ran on every re-run would put a group's corrections
   back to whatever its old booleans said. */
update public.team_roles set access = jsonb_build_object(
    'clients',   case when can_clients   then (case when can_remove then 'manage' else 'work' end) else 'none' end,
    'review',    case when can_review    then (case when can_remove then 'manage' else 'work' end) else 'none' end,
    'campaigns', case when can_campaigns then (case when can_remove then 'manage' else 'work' end) else 'none' end,
    'links',     case when can_links     then (case when can_remove then 'manage' else 'work' end) else 'none' end,
    'activity',  case when can_activity  then 'view' else 'none' end,
    'services',  case when is_admin      then 'manage' else 'view' end,
    'team',      case when is_admin      then 'manage' else 'none' end)
  where access = '{}'::jsonb;

/* HR letters were their own section (`hr`) and are a part of the Register
   (`register.hr`) now. The level moves across once, `none` included, because
   a part with no level of its own falls back to its section's and a group
   given the Register but not HR must stay that way. Guarded on the old key,
   which the move removes, so a re-run finds nothing to move. */
update public.team_roles
   set access = (access - 'hr') || jsonb_build_object('register.hr', coalesce(access ->> 'hr', 'none'))
 where access ? 'hr';

update public.team_members set role = 'account'
  where role is null or role not in (select slug from public.team_roles);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'team_members_role_fkey') then
    alter table public.team_members
      add constraint team_members_role_fkey foreign key (role) references public.team_roles(slug);
  end if;
end $$;

-- A member carries their group's switches. Runs on every write, so a group
-- change and a member's group change both land here.
create or replace function public.team_role_defaults()
returns trigger language plpgsql as $$
declare r public.team_roles;
begin
  select * into r from public.team_roles where slug = new.role;
  if r.slug is null then
    select * into r from public.team_roles where slug = 'account';
    new.role := 'account';
  end if;
  new.is_admin      := r.is_admin;
  new.can_clients   := r.can_clients;   new.can_review   := r.can_review;
  new.can_campaigns := r.can_campaigns; new.can_links    := r.can_links;
  new.can_activity  := r.can_activity;  new.can_billing  := r.can_billing;
  new.can_remove    := r.can_remove;    new.can_doc_void := r.can_doc_void;
  new.access        := coalesce(r.access, '{}'::jsonb);
  new.updated_at    := now();
  return new;
end $$;

-- Changing a group re-stamps everyone in it.
create or replace function public.team_role_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.team_members set role = new.slug where role = new.slug;
  return new;
end $$;
drop trigger if exists team_role_sync on public.team_roles;
create trigger team_role_sync after update on public.team_roles
  for each row execute function public.team_role_sync();

-- The Admin group cannot be narrowed or removed, and a group with members
-- cannot be deleted.
create or replace function public.team_roles_guard()
returns trigger language plpgsql as $$
begin
  if old.slug = 'admin' then
    if tg_op = 'DELETE' or not (new.is_admin and new.can_clients and new.can_review and new.can_campaigns
       and new.can_links and new.can_activity and new.can_billing and new.can_remove) then
      raise exception 'The Admin group cannot be changed.';
    end if;
  end if;
  if tg_op = 'DELETE' and exists (select 1 from public.team_members where role = old.slug) then
    raise exception 'Move its members to another group first.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists team_roles_guard on public.team_roles;
create trigger team_roles_guard before update or delete on public.team_roles
  for each row execute function public.team_roles_guard();

-- Nobody removes their own admin access, so the team always keeps one.
create or replace function public.team_keep_one_admin()
returns trigger language plpgsql as $$
begin
  if lower(old.email) = lower(auth.jwt() ->> 'email') and old.is_admin
     and (tg_op = 'DELETE' or new.active = false
          or not coalesce((select is_admin from public.team_roles where slug = new.role), false)) then
    raise exception 'You cannot remove your own admin access. Ask another admin.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

/* `allowed()` used to be defined a second time here, to reach `is_admin`,
   which was declared below the first copy. That second copy had quietly
   dropped `doc_void` from its case list, so the capability answered false for
   every non-admin group however the Team page set it. The columns move up to
   the ACCESS block instead and there is one definition. */

-- Re-stamp every member from their group once, so rows written before this
-- block carry the right switches.
update public.team_members set role = role;

drop policy if exists roles_read  on public.team_roles;
drop policy if exists roles_admin on public.team_roles;
create policy roles_read  on public.team_roles for select to authenticated using (true);
create policy roles_admin on public.team_roles for all to authenticated
  using (public.allowed('team', 'manage')) with check (public.allowed('team', 'manage'));

-- ============================================================================
-- SERVICES: the rate card, and what each client has asked for.
-- ============================================================================
-- One row per line on the rate card. Admins edit prices here; every section
-- that quotes reads from here. Seeded from Rate Card v2.0.2; a re-run never
-- overwrites a price an admin has changed (on conflict do nothing).
create table if not exists public.services (
  slug      text primary key,
  category  text not null,
  name      text not null,
  rate      numeric(12,2),                 -- null: quoted case by case
  unit      text,
  position  int not null default 0,
  active    boolean not null default true,
  note      text
);
alter table public.services enable row level security;
drop policy if exists services_read  on public.services;
drop policy if exists services_admin on public.services;
create policy services_read  on public.services for select to authenticated using (true);
create policy services_admin on public.services for all to authenticated
  using (public.allowed('services', 'manage')) with check (public.allowed('services', 'manage'));

-- The rate card is seeded once, on a database that has none, and never again.
-- The people who own it edit it in the console, deletions included, and a seed
-- that ran on every re-run would put a deleted line back the next time a schema
-- change shipped. Same reason `detail` below seeds only where it is null.
-- So a line added to the list here reaches an existing database not at all: a
-- new service is added on the Services page, by the person whose card it is.
do $seed$
begin
  if exists (select 1 from public.services) then return; end if;
  insert into public.services (slug, category, name, rate, unit, position) values
  ('static-graphic',   'Content',            'Static graphic',                       360,  'Per post',                          10),
  ('gif',              'Content',            'GIF',                                  450,  'Per GIF',                           11),
  ('carousel',         'Content',            'Carousel',                             600,  'Per set',                           12),
  ('reels-30',         'Content',            'Reels, up to 30 seconds',              550,  'Per video',                         13),
  ('reels-60',         'Content',            'Reels, up to 60 seconds',              800,  'Per video',                         14),
  ('short-video-120',  'Content',            'Short video, up to 120 seconds',       1200, 'Per video',                         15),
  ('mgmt-meta',        'Account management', 'Meta (Facebook and Instagram)',        500,  'Per post',                          20),
  ('mgmt-tiktok',      'Account management', 'TikTok / Douyin',                      500,  'Per GIF',                           21),
  ('mgmt-xhs',         'Account management', 'rednote (XHS)',                        600,  'Per set',                           22),
  ('mgmt-linkedin',    'Account management', 'LinkedIn',                             700,  'Per video, up to 30 seconds',       23),
  ('verify-meta',      'Verification',       'Meta Verified (blue tick)',            200,  'Per account, plus Meta subscription', 30),
  ('verify-xhs',       'Verification',       'rednote Professional (blue tick)',     1299, 'Per account, RM 450 platform fee included', 31),
  ('pkg-a',            'Monthly packages',   'Package A · 1 platform · 2 contents',  1310, 'Per month, 6 month minimum',        40),
  ('pkg-b',            'Monthly packages',   'Package B · 2 platforms · 4 contents', 2830, 'Per month, 6 month minimum',        41),
  ('pkg-c',            'Monthly packages',   'Package C · 3 platforms · 8 contents', 5300, 'Per month, 6 month minimum',        42),
  ('pkg-d',            'Monthly packages',   'Package D · 1 platform · 4 contents · ads', 2690, 'Per month, 6 month minimum',   43),
  ('pkg-e',            'Monthly packages',   'Package E · 2 platforms · 6 contents · ads', 3980, 'Per month, 6 month minimum',  44),
  ('pkg-f',            'Monthly packages',   'Package F · 3 platforms · 10 contents · ads', 5830, 'Per month, 6 month minimum', 45),
  ('ads-8k',           'Monthly packages',   'Ad budget cover, up to RM 8,000',      400,  'Per month',                         46),
  ('ads-14k',          'Monthly packages',   'Ad budget cover, up to RM 14,000',     800,  'Per month',                         47),
  ('ads-20k',          'Monthly packages',   'Ad budget cover, up to RM 20,000',     1200, 'Per month',                         48),
  ('koc-10',           'KOC programmes',     'KOC package · 10 creators',            4500, 'Per campaign',                      50),
  ('koc-15',           'KOC programmes',     'KOC package · 15 creators',            6500, 'Per campaign',                      51),
  ('koc-20',           'KOC programmes',     'KOC package · 20 creators',            8200, 'Per campaign',                      52),
  ('koc-custom',       'KOC programmes',     'KOC custom list',                      null, 'Costed list per creator',           53),
  ('kol-mgmt',         'KOL programmes',     'KOL management fee',                   null, '12% to 18% of talent fee, per talent', 60),
  ('rev-minor',        'Add-ons',            'Minor revision',                       200,  'Per asset, per round',              70),
  ('rev-major',        'Add-ons',            'Major revision',                       350,  'Per asset, per round',              71),
  ('urgent',           'Add-ons',            'Urgent fee',                           150,  'Per affected asset, per round',     72),
  ('translation',      'Add-ons',            'Translation',                          200,  'Per asset, per language',           73),
  ('resize',           'Add-ons',            'Adaptation / resizing',                100,  'Per asset',                         74),
  ('shoot',            'Add-ons',            'Ad hoc on-site shoot',                 450,  'Per trip, from',                    75),
  ('working-files',    'Add-ons',            'Working files',                        250,  'Per asset',                         76),
  ('raw-footage',      'Add-ons',            'Raw footage',                          350,  'Per shoot',                         77)
  on conflict (slug) do nothing;
end $seed$;

-- What a client asked for, was quoted, or confirmed. A line keeps its own
-- label and rate, so a later price change does not rewrite history.
create table if not exists public.client_services (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references public.clients(id) on delete cascade,
  service_slug text references public.services(slug) on delete set null,
  label        text not null,
  qty          numeric(10,2) not null default 1,
  rate         numeric(12,2) not null default 0,
  unit         text,
  state        text not null default 'enquired',   -- enquired | quoted | confirmed
  note         text,
  created_at   timestamptz not null default now(),
  archived_at  timestamptz
);
create index if not exists client_services_client_idx on public.client_services(client_id);
alter table public.client_services enable row level security;
drop policy if exists client_services_rw on public.client_services;
create policy client_services_rw on public.client_services for all to authenticated
  using (public.allowed('clients.services', 'view')) with check (public.allowed('clients.services', 'work'));

-- ============================================================================
-- DOCUMENTS: quotations and invoices, kept as issued.
-- ============================================================================
-- A snapshot of the deal at the moment of issue, so the PDF can be drawn
-- again later exactly as issued. The Letter of Offer is numbered
-- AQT/INT/YYMMXXX; the sequence restarts each month. bill_to holds the
-- client, contact and deal facts as they stood.
create table if not exists public.client_documents (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.clients(id) on delete cascade,
  kind       text not null,                       -- offer (earlier rows: intent | cover | quotation | invoice)
  number     text not null unique,
  issued_at  date not null default current_date,
  market     text not null default 'MY',
  subtotal   numeric(12,2) not null default 0,
  tax        numeric(12,2) not null default 0,
  total      numeric(12,2) not null default 0,
  bill_to    jsonb,
  lines      jsonb not null default '[]'::jsonb,
  issued_by  text,
  created_at timestamptz not null default now(),
  voided_at  timestamptz
);
create index if not exists client_documents_client_idx on public.client_documents(client_id);
alter table public.client_documents enable row level security;
drop policy if exists client_documents_rw on public.client_documents;
create policy client_documents_rw on public.client_documents for all to authenticated
  using (public.allowed('clients.documents', 'view')) with check (public.allowed('clients.documents', 'work'));

-- A line can run for a term: qty × rate × months, from a start month.
alter table public.client_services add column if not exists tenure   int  not null default 1;
alter table public.client_services add column if not exists start_on text;   -- YYYY-MM-DD (older lines YYYY-MM)

-- The term adjustment is asked for, never applied by itself. A line priced at
-- RM 400 over three months printed RM 444.44 because the factor was applied to
-- every line that had a term, so the rate somebody typed was not the rate on
-- the screen. Off means the rate is billed as typed; on means the term's own
-- factor applies. The one-time backfill is in
-- supabase/migrations/2026-09-21-the-term-adjustment-is-asked-for.sql, guarded
-- on the column being new, so lines quoted before the tick existed keep the
-- figures they were quoted at.
alter table public.client_services add column if not exists term_adjust boolean not null default false;

-- The billing contact is one of the client's contacts; the main contact
-- stands in when none is chosen.
alter table public.clients add column if not exists bill_contact_id uuid references public.client_contacts(id) on delete set null;

-- ===========================================================================
-- CLIENT PORTAL
-- A client signs in with an email link to /client/ and sees one client: the
-- company as registered, the people, the confirmed and quoted services, the
-- letters issued, the Content Review and Creator Campaign pages, and the
-- requests they have raised. Nothing on the portal writes to a client's
-- record directly: a request is a row the team acts on in the console.
--
-- Access is one switch on a contact (portal_access); the contact's email is
-- the sign-in address. The portal reads and writes only through the three
-- security definer functions below, which check the signed-in email against
-- client_contacts on every call. A client account never touches a table.
-- ===========================================================================
alter table public.client_contacts add column if not exists portal_access boolean not null default false;

/* Access is the team's decision; the login is what makes it usable, and they
   are not the same fact. Sign-ups are closed on the project, so a client whose
   login was never created reaches the sign-in page and is refused by Supabase
   itself: the console has to be able to say that access is on but the person
   still cannot get in, rather than showing a green chip over a dead end.

   Added and backfilled together, once: rows that predate the column were
   always invited by the console, so they carry a login. Doing the backfill as
   a plain re-runnable update would instead mark every pending contact ready
   the next time this file runs. */
do $$ begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'client_contacts'
                    and column_name = 'portal_login_at') then
    alter table public.client_contacts add column portal_login_at timestamptz;
    update public.client_contacts set portal_login_at = now() where portal_access;
  end if;
end $$;

-- Is the signed-in person on the team at all? Clients now have logins too,
-- so "authenticated" no longer means "one of us". Every policy that used to
-- say using (true) for authenticated says is_team() instead.
create or replace function public.is_team()
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.team_members t
    where t.active and lower(t.email) = lower(auth.jwt() ->> 'email'))
$$;
grant execute on function public.is_team() to authenticated;

drop policy if exists team_read on public.team_members;
create policy team_read on public.team_members for select to authenticated using (public.is_team());
drop policy if exists roles_read on public.team_roles;
create policy roles_read on public.team_roles for select to authenticated using (public.is_team());
drop policy if exists services_read on public.services;
create policy services_read on public.services for select to authenticated using (public.is_team());
drop policy if exists activity_write on public.activity_log;
create policy activity_write on public.activity_log for insert to authenticated with check (public.is_team());
drop policy if exists viewers_read on public.activity_viewers;
create policy viewers_read on public.activity_viewers for select to authenticated using (public.is_team());
do $$
begin
  if exists (select 1 from storage.buckets where id = 'content') then
    drop policy if exists content_team_write on storage.objects;
    create policy content_team_write on storage.objects
      for all to authenticated
      using (bucket_id = 'content' and public.is_team())
      with check (bucket_id = 'content' and public.is_team());
  end if;
end $$;

/* Deleting a client is the team's alone, whatever the code says, and within
   the team it is the same authority that hard-deletes a contact, a rate card
   line or a letter. Hiding the menu item is not access control, so the
   capability is checked again here: a permission taken away while the sheet
   was open is a refusal, not a deletion that already happened. */
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
  if not public.is_team() then
    raise exception 'Not allowed';
  end if;
  -- Deleting a client is `manage` on Clients, not a global remove flag.
  if not public.allowed('clients', 'manage') then
    raise exception 'Not allowed';
  end if;
  select value into want from public.app_secrets where key = 'delete_code';
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

-- What a client asks for from the portal. The team moves it through
-- Requested → Reviewing → Approved or Declined → Applied and may set a fee
-- and a reply the client reads. Approval never changes a service line by
-- itself; a person applies it in the console. A client withdraws only while
-- the request is still Requested.
create table if not exists public.client_requests (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.clients(id) on delete cascade,
  contact_id    uuid references public.client_contacts(id) on delete set null,
  contact_name  text,
  kind          text not null,                    -- upgrade | downgrade | cancel | details
  service_id    uuid references public.client_services(id) on delete set null,
  service_label text,
  note          text,
  state         text not null default 'requested', -- requested | reviewing | approved | declined | applied
  fee           numeric(12,2),
  reply         text,
  decided_by    text,
  withdrawn_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists client_requests_client_idx on public.client_requests(client_id, created_at desc);
alter table public.client_requests enable row level security;
drop policy if exists client_requests_team on public.client_requests;
create policy client_requests_team on public.client_requests for all to authenticated
  using (public.allowed('clients.requests', 'view')) with check (public.allowed('clients.requests', 'work'));
drop trigger if exists client_requests_touch on public.client_requests;
create trigger client_requests_touch before update on public.client_requests
  for each row execute function public.touch_updated_at();

-- The clients the signed-in email may open.
create or replace function public.portal_clients()
returns setof uuid
language sql security definer stable set search_path = public as $$
  select distinct c.client_id from public.client_contacts c
  where c.portal_access and c.archived_at is null and c.email is not null
    and lower(c.email) = lower(auth.jwt() ->> 'email')
$$;
revoke all on function public.portal_clients() from public;
grant execute on function public.portal_clients() to authenticated;

-- Everything the portal shows, for one client, in one call.
create or replace function public.get_portal(p_client uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  cid uuid;
  cl  public.clients%rowtype;
  me  public.client_contacts%rowtype;
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select p into cid from public.portal_clients() p
    order by (p = p_client) desc nulls last limit 1;
  if cid is null then return jsonb_build_object('error', 'no-access'); end if;
  select * into cl from public.clients where id = cid;
  select * into me from public.client_contacts
    where client_id = cid and portal_access and archived_at is null and lower(email) = who
    order by is_primary desc limit 1;

  return jsonb_build_object(
    'clients', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
      from public.clients c where c.id in (select public.portal_clients())), '[]'::jsonb),
    'client', jsonb_build_object(
      'id', cl.id, 'name', cl.name, 'legal_name', cl.legal_name, 'company_no', cl.company_no,
      'billing_address', cl.billing_address, 'market', coalesce(cl.market, 'MY'),
      'sst_applies', coalesce(cl.sst_applies, true), 'stage', cl.stage, 'owner', cl.owner,
      'industry', cl.industry, 'website', cl.website, 'logo_url', cl.logo_url),
    'me', jsonb_build_object('id', me.id, 'name', me.name, 'email', me.email),
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'role', k.role, 'phone', k.phone,
        'email', k.email, 'is_primary', k.is_primary, 'portal_access', k.portal_access)
        order by k.is_primary desc, k.name)
      from public.client_contacts k where k.client_id = cid and k.archived_at is null), '[]'::jsonb),
    'services', coalesce((
      -- `term_adjust` travels with the line, because the client's page works
      -- the figure out the same way the console and the letter do and must
      -- never print a different one.
      select jsonb_agg(jsonb_build_object('id', s.id, 'label', s.label, 'unit', s.unit, 'qty', s.qty,
        'rate', s.rate, 'tenure', s.tenure, 'start_on', s.start_on, 'state', s.state, 'note', s.note,
        'term_adjust', coalesce(s.term_adjust, false))
        order by s.created_at)
      from public.client_services s
      where s.client_id = cid and s.archived_at is null and s.state in ('quoted', 'confirmed')), '[]'::jsonb),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'number', d.number,
        'issued_at', d.issued_at, 'market', d.market, 'subtotal', d.subtotal, 'tax', d.tax,
        'total', d.total, 'bill_to', d.bill_to, 'lines', d.lines, 'issued_by', d.issued_by)
        order by d.created_at desc)
      from public.client_documents d where d.client_id = cid and d.voided_at is null), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'service_label', r.service_label,
        'note', r.note, 'state', r.state, 'fee', r.fee, 'reply', r.reply,
        'created_at', r.created_at, 'withdrawn_at', r.withdrawn_at)
        order by r.created_at desc)
      from public.client_requests r where r.client_id = cid), '[]'::jsonb),
    'review', case
      when cl.review_hidden is not true
       and exists (select 1 from public.batches b where b.client_id = cid and b.published)
      then jsonb_build_object('token', cl.access_token) end,
    'campaigns', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'title_zh', m.title_zh,
        'state', m.state, 'deadline', m.deadline, 'token', m.access_token)
        order by m.created_at desc)
      from public.campaigns m where m.client_id = cid and m.state <> 'draft'), '[]'::jsonb),
    'access', coalesce((
      select jsonb_agg(jsonb_build_object('name', k.name, 'email', k.email) order by k.is_primary desc, k.name)
      from public.client_contacts k
      where k.client_id = cid and k.archived_at is null and k.portal_access), '[]'::jsonb)
  );
end $$;

-- A request from the portal. The service must be one of this client's
-- confirmed lines; a change of details carries no line.
create or replace function public.portal_request(
  p_client uuid, p_kind text, p_service uuid default null, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  cl  public.clients%rowtype;
  me  public.client_contacts%rowtype;
  sv  public.client_services%rowtype;
  rid uuid;
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  if p_kind not in ('upgrade', 'downgrade', 'cancel', 'details') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  select * into cl from public.clients where id = p_client;
  select * into me from public.client_contacts
    where client_id = p_client and portal_access and archived_at is null and lower(email) = who
    order by is_primary desc limit 1;
  if p_kind <> 'details' then
    select * into sv from public.client_services
      where id = p_service and client_id = p_client and archived_at is null and state = 'confirmed';
    if sv.id is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if p_kind <> 'cancel' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note-required');
  end if;
  insert into public.client_requests (client_id, contact_id, contact_name, kind, service_id, service_label, note)
  values (p_client, me.id, me.name, p_kind, sv.id, sv.label, nullif(btrim(p_note), ''))
  returning id into rid;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'request.raised', cl.name, p_kind || coalesce(' · ' || sv.label, ''));
  return jsonb_build_object('ok', true, 'id', rid);
end $$;

-- Withdraw while still Requested; p_undo puts it back within the same state.
create or replace function public.portal_withdraw(p_id uuid, p_undo boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  n int;
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  update public.client_requests
     set withdrawn_at = case when p_undo then null else now() end
   where id = p_id and client_id in (select public.portal_clients())
     and state = 'requested'
     and (withdrawn_at is null) = (not p_undo);
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error', 'not-found'); end if;

  insert into public.activity_log (actor, action, subject, detail)
  select who, case when p_undo then 'request.reinstated' else 'request.withdrawn' end,
         c.name, r.kind
    from public.client_requests r
    join public.clients c on c.id = r.client_id
   where r.id = p_id;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.get_portal(uuid) from public;
revoke all on function public.portal_request(uuid, text, uuid, text) from public;
revoke all on function public.portal_withdraw(uuid, boolean) from public;
grant execute on function public.get_portal(uuid) to authenticated;
grant execute on function public.portal_request(uuid, text, uuid, text) to authenticated;
grant execute on function public.portal_withdraw(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- What a package actually includes, and how long it runs.
--
-- A rate card line carried a name and a unit and nothing else, so the Letter
-- of Offer could only print "Package C · 3 platforms · 8 contents". The
-- detail is what the client is buying and belongs on the letter; the minimum
-- term is what makes the monthly rate honest, because a monthly figure with
-- no term beside it understates what the client is committing to.
--
-- detail is plain text, one item per line. It is copied onto a service line
-- when the line is added and stays editable there, so a later rate card edit
-- never rewrites a letter already issued.
-- ---------------------------------------------------------------------------
alter table public.services         add column if not exists detail     text;
alter table public.services         add column if not exists min_months int not null default 1;
alter table public.client_services  add column if not exists detail     text;

-- The rate card already prints "6 month minimum" against every monthly
-- package. This states it as data so a line prefills with the right term.
update public.services set min_months = 6
  where category = 'Monthly packages' and slug like 'pkg-%' and min_months = 1;

-- ---------------------------------------------------------------------------
-- A readable address for a client.
--
-- The console carried the record in the address as a UUID
-- (/admin/?s=clients&client=8f3a1b2c-...), which nobody can read, recognise
-- or paste into a message and have a colleague know where it goes. A slug
-- taken from the name does all three: /admin/?s=clients&client=hkl-lim-team.
--
-- It is set once, from the name, and does not follow a rename: an address
-- that changes under the people who have it is worse than one that reads a
-- little out of date. A UUID in an older link still resolves.
-- ---------------------------------------------------------------------------
alter table public.clients add column if not exists slug text;
create unique index if not exists clients_slug_idx
  on public.clients(lower(slug)) where slug is not null and slug <> '';

-- Backfill from the name, numbering a clash rather than failing on it. A name
-- with no latin letters (a Chinese trading name) leaves an empty base, so it
-- falls back to "client".
with base as (
  select id, created_at,
         coalesce(nullif(btrim(regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'), '-'), ''), 'client') as b
  from public.clients
  where slug is null or slug = ''
), numbered as (
  select id, b, row_number() over (partition by b order by created_at, id) as n from base
)
update public.clients c
   set slug = numbered.b || case when numbered.n > 1 then '-' || numbered.n else '' end
  from numbered
 where c.id = numbered.id
   and not exists (select 1 from public.clients o
                   where lower(o.slug) = lower(numbered.b || case when numbered.n > 1 then '-' || numbered.n else '' end));

-- ============================================================================
-- RATE CARD: what each service includes, from Rate Card & Packages v2.0.2.
-- Seeds the inclusions once and never again. `detail` is one item per line:
-- the client record shows it under the line and the Letter of Offer prints it
-- under the name. Rows the rate card gives no inclusions for are left alone
-- rather than filled with invented text.
--
-- It writes only where the row has none. The rate card is edited in the
-- console by the people who own it, and an update that ran on every re-run
-- would throw their corrections away the next time a schema change shipped:
-- a migration seeds a value, it does not keep overruling the person who
-- changed it afterwards.
-- ============================================================================
update public.services set detail = v.detail from (values
  -- Content. The page 2 note applies to every ala carte deliverable; a graphic
  -- carries only the revision terms, a video carries the shoot and the export.
  ('static-graphic',  E'Two revision rounds per deliverable\nCorrections, captions, tagging, trims and sequence adjustments'),
  ('gif',             E'Two revision rounds per deliverable\nCorrections, captions, tagging, trims and sequence adjustments'),
  ('carousel',        E'Two revision rounds per deliverable\nCorrections, captions, tagging, trims and sequence adjustments'),
  ('reels-30',        E'One on-site shoot included\nEditing and brand styling to your tone of voice\nFinal export ready to post\nTwo revision rounds per deliverable\nRaw footage on request at an additional charge'),
  ('reels-60',        E'One on-site shoot included\nEditing and brand styling to your tone of voice\nFinal export ready to post\nTwo revision rounds per deliverable\nRaw footage on request at an additional charge'),
  ('short-video-120', E'One on-site shoot included\nEditing and brand styling to your tone of voice\nFinal export ready to post\nTwo revision rounds per deliverable\nRaw footage on request at an additional charge'),

  ('verify-meta',     E'Meta subscription fee billed separately'),
  ('verify-xhs',      E'RM 450 platform fee included'),

  -- Monthly packages without ads.
  ('pkg-a', E'1 platform\n2 contents each month: 1 graphic and 1 reels up to 60s\nDedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nBasic accounts analytics report'),
  ('pkg-b', E'Up to 2 platforms\n4 contents each month: 1 graphic and 3 reels up to 60s, or 4 reels up to 60s\nDedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nBasic accounts analytics report'),
  ('pkg-c', E'Up to 3 platforms\n8 contents each month: 3 graphics and 4 reels up to 60s, or 8 reels up to 60s\nDedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nBasic accounts analytics report'),

  -- Monthly packages with ads. Each carries the advertising budget its service
  -- fee covers; going past it is an add-on line, not a push up to the next
  -- package, so a client on D who wants to spend RM 6,000 adds the cover tier
  -- rather than being moved to F.
  ('pkg-d', E'1 platform\n4 contents each month: 2 graphics and 2 reels up to 60s\nAdvertising budget up to RM 4,000 each month\nDedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nFull advertising campaign setup and ongoing management\nWeekly advertising performance snapshot\nComprehensive monthly performance report'),
  ('pkg-e', E'Up to 2 platforms\n6 contents each month: 2 graphics and 4 reels up to 60s\nAdvertising budget up to RM 8,000 each month\nDedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nFull advertising campaign setup and ongoing management\nWeekly advertising performance snapshot\nComprehensive monthly performance report'),
  ('pkg-f', E'Up to 3 platforms\n10 contents each month: 4 graphics and 6 reels up to 60s\nDedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nFull advertising campaign setup and ongoing management\nWeekly advertising performance snapshot\nComprehensive monthly performance report'),

  -- Added on top of the cover a package already carries, never instead of it.
  ('ads-8k',  E'Raises the covered advertising budget to RM 8,000 each month\nAdded on top of a monthly package with ads\nAdvertising budget is billed separately from the service fee\nPlatform charges, platform SST and withholding taxes are borne by the client'),
  ('ads-14k', E'Raises the covered advertising budget to RM 14,000 each month\nAdded on top of a monthly package with ads\nAdvertising budget is billed separately from the service fee\nPlatform charges, platform SST and withholding taxes are borne by the client'),
  ('ads-20k', E'Raises the covered advertising budget to RM 20,000 each month\nAdded on top of a monthly package with ads\nAdvertising budget is billed separately from the service fee\nPlatform charges, platform SST and withholding taxes are borne by the client'),

  -- KOC. The pool is ours and the rate is fixed, which is what separates the
  -- package from the costed list.
  ('koc-10', E'Average RM 450 per creator\nSourced and booked from the ADspace KOC pool at a fixed rate\nMatched to your industry and campaign goal\nMinimum 2,000 followers per creator\nTwo revision rounds per deliverable\nLead time 3 to 4 weeks'),
  ('koc-15', E'Average RM 430 per creator\nSourced and booked from the ADspace KOC pool at a fixed rate\nMatched to your industry and campaign goal\nMinimum 2,000 followers per creator\nTwo revision rounds per deliverable\nLead time 3 to 4 weeks'),
  ('koc-20', E'Average RM 410 per creator\nSourced and booked from the ADspace KOC pool at a fixed rate\nMatched to your industry and campaign goal\nMinimum 2,000 followers per creator\nTwo revision rounds per deliverable\nLead time 3 to 4 weeks'),
  ('koc-custom', E'You select the creators you want to engage\nA costed list of available KOCs is issued\nProfile and individual rate shown for each\nTwo revision rounds per deliverable\nLead time 4 to 5 weeks'),

  ('kol-mgmt', E'Talent fee passed through at the creator''s own rate, no markup\nCreator sourcing and shortlisting\nRate negotiation and quotation handling\nCampaign briefing and content direction\nScheduling and posting coordination\nContent review and revision cycles\nPublication verification and reporting'),

  ('shoot', E'Additional shoots are quoted by location')
) as v(slug, detail)
where public.services.slug = v.slug and public.services.detail is null;

-- ============================================================================
-- STAGE TIMING: how long a client has sat where it is, and how it got there.
-- Speed to first contact is the number that moves conversion, and a deal that
-- stalls stalls in a stage, so the stage a client is in needs a clock on it.
--
-- Maintained by a trigger, not by the page: a value derived from a change
-- belongs with the change, and four call sites that each have to remember to
-- stamp it is three chances to forget. Nothing client-side writes these.
-- ============================================================================
alter table public.clients add column if not exists stage_since timestamptz;
alter table public.clients add column if not exists stage_log   jsonb not null default '[]'::jsonb;

create or replace function public.clients_stage_clock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.stage_since := coalesce(new.stage_since, coalesce(new.created_at, now()));
    if new.stage_log is null or jsonb_array_length(new.stage_log) = 0 then
      new.stage_log := jsonb_build_array(
        jsonb_build_object('stage', new.stage, 'at', new.stage_since));
    end if;
    return new;
  end if;
  -- Only a real move restarts the clock. An update that does not mention the
  -- stage already arrives with the old values on every other column, which is
  -- what keeps a plain save from making a stalled lead look freshly worked;
  -- forcing them back here as well also overwrote the backfill below in this
  -- same file, so the clock never started on any row that already existed.
  if new.stage is distinct from old.stage then
    new.stage_since := now();
    new.stage_log := coalesce(old.stage_log, '[]'::jsonb) ||
      jsonb_build_array(jsonb_build_object('stage', new.stage, 'at', now()));
  end if;
  return new;
end $$;

drop trigger if exists clients_stage_clock on public.clients;
create trigger clients_stage_clock before insert or update on public.clients
  for each row execute function public.clients_stage_clock();

-- Rows that existed before the clock: they have been in their stage at least
-- since they were created, which is the honest floor rather than "just now".
update public.clients set stage_since = created_at where stage_since is null;
update public.clients
   set stage_log = jsonb_build_array(jsonb_build_object('stage', stage, 'at', created_at))
 where stage_log is null or jsonb_array_length(stage_log) = 0;

-- A row whose history starts at the migration rather than at its creation: the
-- client existed from created_at, as a lead, which is the column default and
-- how every record reaches the portal. Where the first entry already is the
-- lead stage, it is the timestamp on that entry that is wrong rather than an
-- entry being missing, so it moves back instead of being duplicated.
update public.clients c
   set stage_log = case
         when c.stage_log->0->>'stage' = 'lead'
           then jsonb_set(c.stage_log, '{0,at}', to_jsonb(c.created_at))
         else jsonb_build_array(jsonb_build_object('stage', 'lead', 'at', c.created_at)) || c.stage_log
       end
 where jsonb_array_length(coalesce(c.stage_log, '[]'::jsonb)) > 0
   and c.created_at < (c.stage_log->0->>'at')::timestamptz;

-- And a row still sitting in the stage it was created in has been there since
-- it was created, not since the migration ran.
update public.clients
   set stage_since = created_at
 where stage_since > created_at
   and jsonb_array_length(coalesce(stage_log, '[]'::jsonb)) = 1;

-- ============================================================================
-- TEAM LIST REPAIR: a client's contact is not a colleague.
-- ============================================================================
-- The cutover sweep above used to take every address in auth.users. Once a
-- client contact was granted portal access their login existed, so the next
-- run of this file added them to the team as an active Account: read and
-- write over every client, and a name in the Person in charge list. The sweep
-- is guarded now; this clears up what it already did.
--
-- Deactivated rather than deleted. Standing the row down is what closes the
-- hole, because is_team(), allowed() and the Person in charge list all ask
-- whether the row is active; leaving it on the Team page as Inactive shows
-- the person who re-runs this file exactly what changed and lets them put
-- anyone back with one click, which a delete would not. Never an admin and
-- never one of our own addresses, so a colleague who is also recorded as a
-- contact somewhere is only ever stood down, never lost.
update public.team_members t
   set active = false
 where t.active
   and t.email is not null
   and coalesce(t.is_admin, false) = false
   and t.role <> 'admin'
   and t.email not ilike '%@adspacestudios.com'
   and exists (select 1 from public.client_contacts c
                where lower(c.email) = lower(t.email)
                  and c.archived_at is null);

-- ============================================================================
-- ONE PERSON, ONE SIDE: the team or a client's portal, never both.
-- ============================================================================
-- Nothing in the portal reads auth.users to decide anything, so one address
-- can sit in both lists without either knowing. That is how a client contact
-- became an Account with read and write over every client: the two lists
-- answer two different questions and neither asked the other.
--
-- So the database refuses the overlap outright. It fires only where a row is
-- moving into it (granted portal access, made active, or the address changed),
-- which leaves any legacy row editable rather than frozen; the repair above is
-- what clears those.
create or replace function public.no_team_client_overlap()
returns trigger language plpgsql as $$
declare clash text;
begin
  if tg_table_name = 'client_contacts' then
    if tg_op = 'UPDATE'
       and old.portal_access is not distinct from new.portal_access
       and lower(coalesce(old.email, '')) = lower(coalesce(new.email, '')) then
      return new;
    end if;
    if new.portal_access is not true or new.email is null or new.archived_at is not null then
      return new;
    end if;
    select t.name into clash from public.team_members t
      where t.active and t.email is not null and lower(t.email) = lower(new.email) limit 1;
    if clash is not null then
      raise exception 'That address is on the team (%). A colleague cannot also hold a client portal sign-in.', clash;
    end if;
  else
    if tg_op = 'UPDATE'
       and old.active is not distinct from new.active
       and lower(coalesce(old.email, '')) = lower(coalesce(new.email, '')) then
      return new;
    end if;
    if new.active is not true or new.email is null then return new; end if;
    select c.name into clash from public.client_contacts c
      where c.portal_access and c.archived_at is null and c.email is not null
        and lower(c.email) = lower(new.email) limit 1;
    if clash is not null then
      raise exception 'That address holds a client portal sign-in (%). A client contact cannot also be on the team.', clash;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists client_contacts_no_overlap on public.client_contacts;
create trigger client_contacts_no_overlap before insert or update on public.client_contacts
  for each row execute function public.no_team_client_overlap();

drop trigger if exists team_members_no_overlap on public.team_members;
create trigger team_members_no_overlap before insert or update on public.team_members
  for each row execute function public.no_team_client_overlap();

-- And if an overlap ever exists anyway, the client portal is the side that
-- yields: a colleague losing a client's own page costs them nothing they
-- cannot see in the console, where a client reaching the console costs every
-- other client. So the guarantee holds whatever is in the tables.
create or replace function public.portal_clients()
returns setof uuid
language sql security definer stable set search_path = public as $$
  select distinct c.client_id from public.client_contacts c
  where c.portal_access and c.archived_at is null and c.email is not null
    and lower(c.email) = lower(auth.jwt() ->> 'email')
    and not exists (
      select 1 from public.team_members t
      where t.active and t.email is not null
        and lower(t.email) = lower(auth.jwt() ->> 'email'))
$$;

-- The group that handles clients is Marketing, not Account: "Account" is the
-- word for a login, and the Team page had a group named after one. The slug is
-- what `team_members.role` points at, so it does not move; only the name a
-- person reads does. Guarded on the old name, so it fires once and never
-- overwrites a name somebody has since chosen themselves.
update public.team_roles set name = 'Marketing'
 where slug = 'account' and name = 'Account';

-- =========================================================================
-- CREATOR ACCESS AND DELIVERY
--
-- Creators were the one party in this operation with no page of their own.
-- Drafts arrived in a Google Drive folder somebody had to find, paste a link
-- to, and chase; a creator asking "when am I shooting" asked on WhatsApp.
--
-- A creator is not a client and not a colleague, so neither sign-in fits. An
-- SMS one time code costs money on every message, for ever, to let somebody
-- open a page four times a campaign, and we hold phone numbers rather than
-- addresses anyway. The key is therefore a code they keep: eight characters
-- from an alphabet with no 0/O/1/I/L in it, readable down a phone line,
-- carried in the link we send so one tap is enough, and stored by the browser
-- so it is asked for once. 31^8 is 852 billion, which is six orders of
-- magnitude past the six digit code a bank is content to send by SMS.
-- =========================================================================

alter table public.creators add column if not exists access_code    text;
alter table public.creators add column if not exists code_issued_at timestamptz;
create unique index if not exists creators_code_idx
  on public.creators(access_code) where access_code is not null;

create or replace function public.new_creator_code()
returns text language plpgsql volatile set search_path = public as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  out text;
  i integer;
begin
  loop
    out := '';
    for i in 1..8 loop
      out := out || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from creators where access_code = out);
  end loop;
  return out;
end $$;

-- Every creator carries one from now on, including the ones already keyed in.
update public.creators
   set access_code = public.new_creator_code(), code_issued_at = now()
 where access_code is null;

create or replace function public.creators_code_default()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.access_code is null then
    new.access_code := public.new_creator_code();
    new.code_issued_at := now();
  end if;
  return new;
end $$;
drop trigger if exists creators_code on public.creators;
create trigger creators_code before insert on public.creators
  for each row execute function public.creators_code_default();

-- What a creator hands in. Several files per booking, because one post is a
-- cover and four slides, and a revision is a new round rather than an
-- overwrite: the team has to be able to see what changed.
create table if not exists public.campaign_deliverables (
  id          uuid primary key default gen_random_uuid(),
  option_id   uuid not null references public.campaign_options(id) on delete cascade,
  url         text not null,
  name        text not null,
  kind        text not null default 'file',    -- image | video | file
  bytes       bigint,
  round       integer not null default 1,
  uploaded_at timestamptz not null default now(),
  removed_at  timestamptz
);
alter table public.campaign_deliverables enable row level security;
create index if not exists campaign_deliverables_option
  on public.campaign_deliverables(option_id, uploaded_at);
drop policy if exists campaign_deliverables_team on public.campaign_deliverables;
create policy campaign_deliverables_team on public.campaign_deliverables
  for all to authenticated using (public.is_team()) with check (public.is_team());

-- The caption the creator wrote is part of the draft: it is what the client
-- approves alongside the visual, and retyping it into a content set by hand is
-- how a caption comes to differ from the one that was agreed.
alter table public.campaign_options add column if not exists draft_caption text;
alter table public.campaign_options add column if not exists submitted_at  timestamptz;

/* Who asked for the changes. `changes` serves two rounds that look alike from
   the row and are opposite from the client's seat: one the client raised on a
   draft they were shown, and one the team raised on a draft the client has
   never seen. Without this column the second leaks the first's chip onto their
   page, and with it `get_campaign` reports an internal round as
   `pending_draft`. Rows that predate the column can only have come from the
   client, because the team had no way to raise one. */
alter table public.campaign_options add column if not exists changes_by text;
update public.campaign_options set changes_by = 'client'
 where state = 'changes' and changes_by is null;

/* How the job went, in the creator's own words, asked once the booking is
   finished and never before: a rating taken while the work is still being
   judged is a rating given under pressure. One to five, theirs to change
   while the booking stays completed, and never shown to the client. */
alter table public.campaign_options add column if not exists creator_rating smallint;
do $$ begin
  alter table public.campaign_options
    add constraint campaign_options_creator_rating_range
    check (creator_rating is null or creator_rating between 1 and 5);
exception when duplicate_object then null; end $$;

-- A creator may upload only while we are actually waiting for their draft.
/* A creator may add to a hand-in until the team releases it: `submitted` is
   ours to review, not yet the client's, and a creator who pressed Submit
   after one file found the box gone with the second still on their phone
   (reported by the user on 2026-09-22). Taking a file back off stays open
   while we are still waiting for the draft and shuts at `submitted`, so a
   submission under review cannot be emptied from the creator's side. */
create or replace function public.creator_can_deliver(p_state text)
returns boolean language sql immutable as $$
  select p_state in ('pending_draft', 'changes', 'submitted')
$$;
create or replace function public.creator_can_retract(p_state text)
returns boolean language sql immutable as $$
  select p_state in ('pending_draft', 'changes')
$$;

-- What the creator is shown.
--
-- Deliberately not everything the console holds. A creator never sees the
-- client's stage, the campaign's commercial state, what the client is paying,
-- who else was offered the campaign, or the team's own notes on the row: a
-- creator reading that we are still waiting on a client is being handed our
-- position in somebody else's negotiation. They see their own booking, which
-- is the brand, the brief, their platforms, their fee, the dates and where
-- their own work has got to.
create or replace function public.get_creator(p_code text)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  cr creators%rowtype;
begin
  if p_code is null or length(trim(p_code)) < 8 then
    return jsonb_build_object('error', 'not-found');
  end if;
  select * into cr from creators
   where access_code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;

  return jsonb_build_object(
    'creator', jsonb_build_object('name', cr.name, 'code', cr.access_code),
    'bookings', coalesce((
      select jsonb_agg(b order by b->>'sort')
      from (
        select jsonb_build_object(
          'id', o.id,
          'sort', coalesce(o.visit_date::text, '9999') || c.title,
          'campaign', c.title,
          'campaign_zh', c.title_zh,
          'brand', cl.name,
          'brief', c.brief,
          'brief_zh', c.brief_zh,
          'deliverable', c.deliverable,
          'push_format', c.push_format,
          'platforms', o.platforms,
          /* NO RATE, AND NO CURRENCY. `campaign_options.rate` is what the
             client is quoted for this booking and carries our markup, so it
             is not the creator's to read and is certainly not "their fee";
             what a creator is paid is agreed with them and claimed on AP01,
             which the page links to once the work is approved. `currency`
             existed only to format that one figure and names the client's
             market, which is a fact about the client. */
          'state', o.state,
          'visit_date', o.visit_date,
          'visit_time', o.visit_time,
          'visit_location', o.visit_location,
          'visit_pic', o.visit_pic,
          'visit_pic_phone', o.visit_pic_phone,
          'tracking_no', o.tracking_no,
          'submission_due', o.submission_due,
          'planned_publish', o.planned_publish,
          'revision_round', o.revision_round,
          'change_note', case when o.state = 'changes' then o.drop_reason end,
          'caption', o.draft_caption,
          'submitted_at', o.submitted_at,
          'rating', o.creator_rating,
          'can_deliver', public.creator_can_deliver(o.state),
          'files', coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', d.id, 'url', d.url, 'name', d.name, 'kind', d.kind,
              'bytes', d.bytes, 'round', d.round)
              order by d.uploaded_at)
            from campaign_deliverables d
             where d.option_id = o.id and d.removed_at is null), '[]'::jsonb)
        ) as b
        from campaign_options o
        join campaigns c on c.id = o.campaign_id
        join clients cl on cl.id = c.client_id
        where o.creator_id = cr.id
          and c.state <> 'draft'
          and o.state in ('confirmed', 'pending_visit', 'pending_delivery',
                          'pending_draft', 'submitted', 'reviewing', 'changes',
                          'scheduled', 'posted', 'completed', 'withdrawn', 'replaced')
      ) rows), '[]'::jsonb));
end $$;

-- The creator's own writes. Each one re-checks the code and that the booking
-- is theirs, because a page anyone can open is not allowed to take the page's
-- word for whose booking it is.
create or replace function public.creator_add_file(
  p_code text, p_option uuid, p_url text, p_name text, p_kind text, p_bytes bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr     creators%rowtype;
  o      campaign_options%rowtype;
  new_id uuid;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  /* Qualified, and the variable is not called `id`. A declared `id` against an
     unqualified `where id = p_option` is ambiguous, which PL/pgSQL raises at
     run time rather than at create time: every upload failed in production
     while the schema applied cleanly and every browser suite stayed green. */
  select * into o from campaign_options co
   where co.id = p_option and co.creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  insert into campaign_deliverables (option_id, url, name, kind, bytes, round)
  values (p_option, p_url, p_name, coalesce(p_kind, 'file'), p_bytes,
          greatest(o.revision_round, 1))
  returning campaign_deliverables.id into new_id;
  return jsonb_build_object('id', new_id);
end $$;

create or replace function public.creator_remove_file(p_code text, p_file uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr creators%rowtype;
  n  integer;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  update campaign_deliverables d set removed_at = now()
   where d.id = p_file and d.removed_at is null
     and exists (select 1 from campaign_options o
                  where o.id = d.option_id and o.creator_id = cr.id
                    and public.creator_can_retract(o.state));
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Handing it in is what moves the step, so nobody has to notice that files
-- appeared. Reviewing is the team's word for "ours now", which is exactly
-- what has happened.
create or replace function public.creator_submit(p_code text, p_option uuid, p_caption text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr creators%rowtype;
  o  campaign_options%rowtype;
  n  integer;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options where id = p_option and creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  select count(*) into n from campaign_deliverables
   where option_id = p_option and removed_at is null;
  if n = 0 then return jsonb_build_object('error', 'empty'); end if;

  /* `submitted` is ours, not the client's. It used to move straight to
     `reviewing`, which on the client's page reads "Your approval": the chip
     asked them to act the moment a creator uploaded, while the files are
     team-only, so there was nothing there for them to open. The team reviews
     it and releases it. */
  update campaign_options
     set state = 'submitted', draft_caption = p_caption, submitted_at = now(),
         changes_by = null          -- that round is over, whoever raised it
   where id = p_option;

  -- A creator is a party to this too, and when they handed in is exactly the
  -- fact a late delivery turns on.
  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.submitted', c.title,
         n::text || ' file' || case when n = 1 then '' else 's' end || ' handed in'
         || case when o.state = 'submitted' then ' · updated' else '' end
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'files', n);
end $$;

/* How the job went. Asked only once the booking is completed, so nobody is
   rating us while we still hold their payment, and changeable afterwards
   because a first answer given in a hurry is not a better one. */
create or replace function public.creator_rate(p_code text, p_option uuid, p_stars integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr creators%rowtype;
  o  campaign_options%rowtype;
begin
  if p_stars is not null and (p_stars < 1 or p_stars > 5) then
    return jsonb_build_object('error', 'range');
  end if;
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options where id = p_option and creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if o.state <> 'completed' then return jsonb_build_object('error', 'closed'); end if;

  update campaign_options set creator_rating = p_stars where id = p_option;

  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.rated', c.title,
         coalesce(p_stars::text || ' of 5', 'rating cleared')
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'rating', p_stars);
end $$;

-- Asked by the sign-upload edge function before it signs anything: this code,
-- this booking, and a step we are actually waiting on a draft for. The
-- function builds the S3 key from the option id it checked here, so a real
-- code cannot be pointed at somebody else's folder.
create or replace function public.creator_may_upload(p_code text, p_option uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from campaign_options o
    join creators cr on cr.id = o.creator_id
    where o.id = p_option and cr.active
      and cr.access_code = upper(p_code)
      and public.creator_can_deliver(o.state))
$$;

grant execute on function public.get_creator(text) to anon, authenticated;
grant execute on function public.creator_add_file(text, uuid, text, text, text, bigint) to anon, authenticated;
grant execute on function public.creator_remove_file(text, uuid) to anon, authenticated;
grant execute on function public.creator_submit(text, uuid, text) to anon, authenticated;
grant execute on function public.creator_rate(text, uuid, integer) to anon, authenticated;
grant execute on function public.creator_may_upload(text, uuid) to anon, authenticated;

-- Taking a code back. A link forwarded to the wrong person is the only way one
-- leaks, so the answer is a new code rather than a lecture: the old link stops
-- working the moment this runs. Team only, like every other write.
create or replace function public.reset_creator_code(p_creator uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  fresh text;
begin
  if not public.is_team() then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  fresh := public.new_creator_code();
  update creators set access_code = fresh, code_issued_at = now() where id = p_creator;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('code', fresh);
end $$;
grant execute on function public.reset_creator_code(uuid) to authenticated;

-- The brand sets its name in lower case: rednote. The rate card seeds only
-- into an empty database, so a card that already exists is corrected here
-- instead. Guarded on the old spelling, so it fires once and never overwrites
-- a name somebody has since chosen themselves.
update public.services set name = replace(name, 'RedNote', 'rednote')
 where name like '%RedNote%';


-- ===========================================================================
-- THE LETTER AND THE SERVICE ARE TWO LIFECYCLES
--
-- A letter is issued for the services somebody chose, and only a verified
-- signature confirms them. Before this, client_services.state was both the
-- commercial state of the service and the selection set for the next letter,
-- so a line already sent to a client on one letter was silently carried into
-- the next: issuing correctly confirms nothing, which is exactly what left it
-- at `quoted` for the following letter to pick up.
--
-- client_documents.lines stays the immutable human readable snapshot. The
-- mapping table below carries identity, the sequence table carries the serial,
-- and the five functions are the only things that move either lifecycle.
-- Mirrored from supabase/migrations/2026-09-17-letter-service-lifecycle.sql,
-- which is what a live database runs; this copy is for a fresh one.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The Client ID
--    A business code staff own, separate from the row's uuid. Uppercase
--    letters and digits only: it goes into a serial number, so a slash or a
--    space would break the format it is part of. Two to twelve characters,
--    which is loose enough for whatever operations already write down.
-- ---------------------------------------------------------------------------
alter table public.clients add column if not exists client_code text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clients_client_code_fmt') then
    alter table public.clients add constraint clients_client_code_fmt
      check (client_code is null or client_code ~ '^[A-Z0-9]{2,12}$');
  end if;
end $$;

-- Unique where set. A partial index, so any number of clients may have none.
create unique index if not exists clients_client_code_uidx
  on public.clients (client_code) where client_code is not null;

-- ---------------------------------------------------------------------------
-- 2. The letter's own lifecycle
--    Issued -> Signed, awaiting verification -> Verified. voided_at is reused
--    as it stands. superseded_by names the letter that replaced this one, for
--    the explicit replacement path.
-- ---------------------------------------------------------------------------
alter table public.client_documents add column if not exists signed_at     timestamptz;
alter table public.client_documents add column if not exists verified_at   timestamptz;
alter table public.client_documents add column if not exists verified_by   text;
alter table public.client_documents add column if not exists superseded_by uuid;
alter table public.client_documents add column if not exists client_code   text;
alter table public.client_documents add column if not exists idem_key      text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_documents_superseded_fk') then
    alter table public.client_documents add constraint client_documents_superseded_fk
      foreign key (superseded_by) references public.client_documents(id) on delete set null;
  end if;
end $$;

-- One submission, one letter. A double click carries the same key and the
-- second insert loses to this index, which issue_letter then reads back.
create unique index if not exists client_documents_idem_uidx
  on public.client_documents (client_id, idem_key) where idem_key is not null;

-- ---------------------------------------------------------------------------
-- 3. Which services a letter captured
--    The primary key is the "one service once per document" rule. The service
--    reference is `restrict`, not `cascade`: a line that has been quoted to a
--    client on paper is not a row anybody may delete out from under the
--    letter. Services are archived, never deleted, so nothing legitimate is
--    blocked by it.
-- ---------------------------------------------------------------------------
create table if not exists public.client_document_services (
  document_id uuid not null references public.client_documents(id) on delete cascade,
  service_id  uuid not null references public.client_services(id)  on delete restrict,
  created_at  timestamptz not null default now(),
  primary key (document_id, service_id)
);
create index if not exists cds_service_idx on public.client_document_services(service_id);

alter table public.client_document_services enable row level security;
-- Read only from the client side of the wire. Every write goes through the
-- security definer functions below, so nobody can attach a line to a letter by
-- calling PostgREST.
drop policy if exists cds_read on public.client_document_services;
create policy cds_read on public.client_document_services for select to authenticated
  using (public.allowed('clients.documents', 'view'));

-- ---------------------------------------------------------------------------
-- 4. The serial, per client, per Malaysian calendar month
--    Reserved by an upsert, which takes a row lock, so two people pressing
--    Issue letter in the same second get consecutive numbers and neither
--    retries. A number handed out is spent: voiding, superseding or a later
--    failure never returns it to the pool.
-- ---------------------------------------------------------------------------
create table if not exists public.client_document_seq (
  client_id uuid not null references public.clients(id) on delete cascade,
  ym        text not null,                       -- 'YYMM' in Asia/Kuala_Lumpur
  next_val  int  not null default 1,
  primary key (client_id, ym)
);
alter table public.client_document_seq enable row level security;
drop policy if exists cdseq_read on public.client_document_seq;
create policy cdseq_read on public.client_document_seq for select to authenticated
  using (public.allowed('clients.documents', 'view'));

-- ---------------------------------------------------------------------------
-- 5. Issuing
-- ---------------------------------------------------------------------------
-- A letter is signed by a person, never by a permission. issued_by is the
-- team row's name, so a row named "Superadmin" put that word under ADSPACE PLT
-- on a client's letterhead. Defined before issue_letter, which calls it.
create or replace function public.issuer_name_ok(p_name text)
returns boolean
language sql immutable set search_path = public as $$
  select coalesce(btrim(p_name), '') <> ''
     and position('@' in p_name) = 0
     and lower(btrim(p_name)) not in (
       'superadmin', 'super admin', 'admin', 'administrator', 'team member',
       'team', 'marketing', 'sales', 'account', 'user', 'root', 'owner',
       'staff', 'system', 'support', 'test');
$$;
grant execute on function public.issuer_name_ok(text) to authenticated;

create or replace function public.issue_letter(
  p_client    uuid,
  p_services  uuid[],
  p_idem      text,
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false,
  /* A reference somebody typed. Blank is the ordinary case and the counter
     below makes the number; where one is typed it is checked against every
     document that stands and the counter is not advanced, so filling a gap
     by hand never costs the next letter its place in the sequence. */
  p_serial    text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  ct     public.client_contacts%rowtype;
  me     public.team_members%rowtype;
  v_ym   text;
  v_seq  int;
  v_try  int;
  v_no   text;
  v_id   uuid;
  v_lines jsonb;
  v_n    int;
  v_bad  int;
  v_old  public.client_documents%rowtype;
begin
  if not public.allowed('clients.documents') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if p_client is null or p_services is null or array_length(p_services, 1) is null then
    return jsonb_build_object('error', 'no-lines');
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;

  -- The Client ID is what the serial is built from, so there is no letter
  -- without one. Staff enter it on the record; nothing invents it. A typed
  -- reference needs no code, because nothing is being built.
  v_no := nullif(btrim(coalesce(p_serial, '')), '');
  if v_no is null and coalesce(btrim(cl.client_code), '') = '' then
    return jsonb_build_object('error', 'no-client-code');
  end if;

  -- The same submission, pressed twice, is one letter. Answered before any
  -- number is reserved, so a double click cannot spend a serial either.
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.client_documents
      where client_id = p_client and idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
    end if;
  end if;

  -- A typed reference is checked before anything is written: the same shape
  -- the Register accepts, and refused where a document still holds it.
  if v_no is not null then
    if v_no !~ '^[A-Za-z0-9/._-]{3,40}$' then
      return jsonb_build_object('error', 'serial-shape');
    end if;
    if public.serial_taken(v_no) then
      return jsonb_build_object('error', 'serial-taken');
    end if;
  end if;

  -- Every id must be this client's own live line, and in a state this letter
  -- may carry: To quote always, Confirmed only on a deliberate renewal.
  select count(*) into v_bad from unnest(p_services) s(id)
    left join public.client_services cs
      on cs.id = s.id and cs.client_id = p_client and cs.archived_at is null
    where cs.id is null
       or (cs.state = 'confirmed' and not p_renewal)
       or cs.state not in ('quoted', 'confirmed');
  if v_bad > 0 then return jsonb_build_object('error', 'bad-lines'); end if;

  -- A line already on a live letter is not offered again by accident. The way
  -- through is to void that letter, or to name it as the one being replaced.
  select count(*) into v_bad
    from public.client_document_services m
    join public.client_documents d on d.id = m.document_id
   where m.service_id = any(p_services)
     and d.voided_at is null
     and d.superseded_by is null
     and d.verified_at is null
     and (p_replaces is null or d.id <> p_replaces);
  if v_bad > 0 then return jsonb_build_object('error', 'already-quoted'); end if;

  if p_replaces is not null then
    select * into v_old from public.client_documents
      where id = p_replaces and client_id = p_client;
    if v_old.id is null then return jsonb_build_object('error', 'no-replaces'); end if;
    if v_old.verified_at is not null then return jsonb_build_object('error', 'replaces-verified'); end if;
  end if;

  select * into ct from public.client_contacts
    where client_id = p_client and archived_at is null
    order by (id = cl.bill_contact_id) desc, is_primary desc, name limit 1;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  -- A letter is signed by a person. issued_by is this row's name, so a team
  -- row named "Superadmin" printed that word under ADSPACE PLT on a client's
  -- letterhead. Refuse rather than draw a permission as a signatory.
  if not public.issuer_name_ok(me.name) then
    return jsonb_build_object('error', 'issuer-name', 'name', coalesce(me.name, ''));
  end if;

  -- The snapshot is built from the stored rows, never from what the browser
  -- sent: the words on a letter are the words the record held at that moment.
  select jsonb_agg(jsonb_build_object(
           'label', cs.label, 'unit', coalesce(cs.unit, ''), 'note', coalesce(cs.note, ''),
           'detail', coalesce(cs.detail, ''), 'state', cs.state,
           'qty', cs.qty, 'rate', cs.rate,
           'tenure', greatest(1, coalesce(cs.tenure, 1)),
           'start_on', coalesce(cs.start_on, ''),
           -- The line's own answer to whether its term prices it. Written into
           -- the snapshot because the letter is redrawn from it, and a letter
           -- must print the same figure every time it is drawn. A snapshot
           -- taken before this key existed carries none, which money.js reads
           -- as on, so those letters redraw as they were issued.
           'term_adjust', coalesce(cs.term_adjust, false),
           'tax', cl.sst_applies is not false,
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;

  -- A typed reference spends no sequence number: the counter is the office's
  -- record of how many letters it has issued this month, and a person filling
  -- a gap by hand has not issued one more.
  if v_no is null then
    -- The month is Malaysian, because the office that numbers the letter is.
    v_ym := to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');

    -- The counter still advances on every automatic issue, and the upsert's
    -- row lock is what makes the scan below safe: a second issuer blocks here
    -- until the first has committed its letter, so the two never read the same
    -- gap as free. What the counter gives is a bound to scan within, not the
    -- number itself.
    insert into public.client_document_seq (client_id, ym, next_val)
         values (p_client, v_ym, 2)
    on conflict (client_id, ym)
      do update set next_val = public.client_document_seq.next_val + 1
      returning next_val - 1 into v_seq;

    -- The lowest free slot, not the counter's own value. A deleted letter
    -- releases its reference (serial_taken stopped counting deletions on
    -- 2026-09-20), and without this the automatic path still counted upward
    -- past the gap: a client whose first two letters were issued in testing
    -- and deleted started at 03 for ever. The counter is at least the number
    -- of letters issued this month, so a free slot exists at or below it
    -- unless somebody has typed references over the same range by hand; the
    -- cap covers that and refuses rather than looping.
    --
    -- Two digits is the floor, not the ceiling: the hundredth letter of a month
    -- widens to three rather than wrapping. Not lpad(): Postgres pads AND
    -- truncates to the width it is given, so lpad('100', 2, '0') is '10' and the
    -- hundredth letter would collide with the tenth.
    v_try := 1;
    loop
      v_no := 'AQL/' || cl.client_code || '/' || v_ym ||
              case when v_try < 100 then lpad(v_try::text, 2, '0') else v_try::text end;
      exit when not public.serial_taken(v_no);
      v_try := v_try + 1;
      if v_try > greatest(v_seq, 1) + 200 then
        return jsonb_build_object('error', 'no-serial');
      end if;
    end loop;
  end if;

  insert into public.client_documents
    (client_id, kind, number, issued_at, market, subtotal, tax, total,
     bill_to, lines, issued_by, client_code, idem_key)
  values
    (p_client, 'offer', v_no, (timezone('Asia/Kuala_Lumpur', now()))::date,
     coalesce(cl.market, 'MY'),
     round(coalesce(p_subtotal, 0), 2), round(coalesce(p_tax, 0), 2), round(coalesce(p_total, 0), 2),
     jsonb_build_object(
       'name', coalesce(cl.name, ''), 'legal_name', coalesce(cl.legal_name, ''),
       'address', coalesce(cl.billing_address, ''), 'regno', coalesce(cl.company_no, ''),
       'regno_old', coalesce(cl.company_no_old, ''), 'tin', coalesce(cl.tin, ''),
       'sst_no', coalesce(cl.sst_no, ''), 'sst_applies', cl.sst_applies is not false,
       'contact', coalesce(ct.name, ''), 'contact_role', coalesce(ct.role, ''),
       'phone', coalesce(ct.phone, ''), 'email', coalesce(ct.email, ''),
       'finance_email', coalesce(cl.finance_email, ''),
       'client_code', cl.client_code,
       'owner', coalesce(p_deal ->> 'owner', ''), 'source', coalesce(p_deal ->> 'source', ''),
       'industry', coalesce(p_deal ->> 'industry', ''), 'stage', coalesce(p_deal ->> 'stage', ''),
       'enquiry', coalesce(p_deal ->> 'enquiry', '')),
     v_lines, coalesce(me.name, who), cl.client_code, nullif(btrim(p_idem), ''))
  returning id into v_id;

  insert into public.client_document_services (document_id, service_id)
    select v_id, s.id from unnest(p_services) s(id)
    on conflict do nothing;

  if p_replaces is not null then
    update public.client_documents set superseded_by = v_id where id = p_replaces;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.superseded', cl.name, v_old.number || ' replaced by ' || v_no);
  end if;

  select count(*) into v_n from public.client_document_services where document_id = v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.issued', cl.name, v_no || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end);

  return jsonb_build_object('ok', true, 'id', v_id, 'number', v_no);
exception
  when unique_violation then
    -- Two presses that raced past the idempotency read: the loser reads the
    -- winner's letter back rather than making a second one.
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.client_documents
        where client_id = p_client and idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
      end if;
    end if;
    -- A typed reference two people sent at once: the loser is told the
    -- reference is spent rather than that "two letters were issued at once",
    -- which names a cause they cannot act on.
    if nullif(btrim(coalesce(p_serial, '')), '') is not null then
      return jsonb_build_object('error', 'serial-taken');
    end if;
    return jsonb_build_object('error', 'clash');
end $$;

/* PostgREST resolves an RPC by the argument names it is sent, so the older
   nine-argument form would be a second candidate for a call that omits
   p_serial and the request would be refused as ambiguous. */
drop function if exists public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean);
grant execute on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The client signed it. That is a fact about the letter and nothing else.
-- ---------------------------------------------------------------------------
create or replace function public.letter_set_signed(p_doc uuid, p_on boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
begin
  if not public.allowed('clients.documents') then return jsonb_build_object('error', 'not-allowed'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('error', 'voided'); end if;
  if d.verified_at is not null then return jsonb_build_object('error', 'verified'); end if;
  -- Already where it is asked to be: say so and change nothing.
  if (d.signed_at is not null) = coalesce(p_on, true) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  update public.client_documents
     set signed_at = case when coalesce(p_on, true) then now() else null end
   where id = p_doc;
  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, case when coalesce(p_on, true) then 'document.signed' else 'document.unsigned' end,
          cl.name, d.number);
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.letter_set_signed(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Verification. The only thing in this portal that confirms a service.
--    It confirms the services mapped to THIS letter and reads no others.
-- ---------------------------------------------------------------------------
create or replace function public.verify_letter(p_doc uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.client_documents%rowtype;
  cl    public.clients%rowtype;
  me    public.team_members%rowtype;
  v_map int;
  v_n   int;
begin
  if not public.allowed('clients.documents') then return jsonb_build_object('error', 'not-allowed'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('error', 'voided'); end if;
  if d.superseded_by is not null then return jsonb_build_object('error', 'superseded'); end if;
  if d.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;

  -- Verifying twice is verifying once.
  if d.verified_at is not null then
    return jsonb_build_object('ok', true, 'repeat', true, 'confirmed', 0);
  end if;

  -- A letter issued before this change has no mappings, so there is nothing
  -- to confirm and no guess is made. It stays history.
  select count(*) into v_map from public.client_document_services where document_id = p_doc;
  if v_map = 0 or v_map <> coalesce(jsonb_array_length(d.lines), -1) then
    return jsonb_build_object('error', 'no-mapping');
  end if;

  update public.client_services cs
     set state = 'confirmed'
    from public.client_document_services m
   where m.document_id = p_doc and cs.id = m.service_id
     and cs.archived_at is null and cs.state <> 'confirmed';
  get diagnostics v_n = row_count;

  select * into me from public.team_members where lower(email) = who and active limit 1;
  update public.client_documents
     set verified_at = now(), verified_by = coalesce(me.name, who)
   where id = p_doc;

  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.verified', cl.name,
          d.number || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end || ' confirmed');
  return jsonb_build_object('ok', true, 'confirmed', v_n);
end $$;

grant execute on function public.verify_letter(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Void. It never touches a service, and it refuses a verified letter:
--    that one is the record of something the client signed and we accepted.
-- ---------------------------------------------------------------------------
create or replace function public.letter_set_void(p_doc uuid, p_on boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
begin
  if not public.allowed('clients.documents') then return jsonb_build_object('error', 'not-allowed'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.verified_at is not null then return jsonb_build_object('error', 'verified'); end if;
  if (d.voided_at is not null) = coalesce(p_on, true) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  update public.client_documents
     set voided_at = case when coalesce(p_on, true) then now() else null end
   where id = p_doc;
  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, case when coalesce(p_on, true) then 'document.voided' else 'document.restored' end,
          cl.name, d.number);
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.letter_set_void(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. The escape hatch. An admin may still set a service state by hand, for a
--    legacy line or an exception, and must say why. It is written to the
--    activity record with the reason, so it is never a silent edit.
-- ---------------------------------------------------------------------------
create or replace function public.override_service_state(p_service uuid, p_state text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  cs  public.client_services%rowtype;
  cl  public.clients%rowtype;
  adm boolean;
begin
  select coalesce(t.is_admin, t.role = 'admin', false) into adm
    from public.team_members t where lower(t.email) = who and t.active limit 1;
  if not coalesce(adm, false) then return jsonb_build_object('error', 'not-allowed'); end if;
  if p_state not in ('enquired', 'quoted', 'confirmed') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into cs from public.client_services where id = p_service and archived_at is null;
  if cs.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if cs.state = p_state then return jsonb_build_object('ok', true, 'repeat', true); end if;
  update public.client_services set state = p_state where id = p_service;
  select * into cl from public.clients where id = cs.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'service.override', cl.name,
          cs.label || ' · ' || cs.state || ' to ' || p_state || ' · ' || btrim(p_reason));
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.override_service_state(uuid, text, text) to authenticated;

-- ===========================================================================
-- VOIDING AND DELETING A LETTER
--
-- Two different authorities. A void reverses a confirmation, so it applies to
-- a verified letter, needs a reason, and puts back only the service lines this
-- letter alone was holding confirmed. A permanent deletion is the portal's
-- existing hard-delete authority (can_remove) and takes the serial typed back
-- plus a reason. There is no stored PDF and no signed upload for a letter, so
-- a deletion has no storage side and nothing to quarantine: the row is the
-- letter, and the console says the deletion is irreversible.
-- ===========================================================================

alter table public.client_documents add column if not exists voided_by   text;
alter table public.client_documents add column if not exists void_reason text;

-- What a permanent deletion leaves behind: enough to answer "what happened to
-- AQL/AC173/260902", and none of the client's document content.
create table if not exists public.client_document_deletions (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null,
  number      text not null,
  client_id   uuid,
  actor       text,
  reason      text not null,
  service_ids uuid[] not null default '{}',
  deleted_at  timestamptz not null default now()
);
create index if not exists client_document_deletions_client_idx
  on public.client_document_deletions (client_id);

alter table public.client_document_deletions enable row level security;
drop policy if exists client_document_deletions_read on public.client_document_deletions;
create policy client_document_deletions_read on public.client_document_deletions
  for select to authenticated using (public.allowed('clients.documents'));
-- No write policy: the audit row is written by letter_delete and nothing else.

-- Which lines this letter alone is holding confirmed. A line mapped to a
-- second verified, unvoided letter stays confirmed: that letter still says so.
create or replace function public.letter_sole_services(p_doc uuid)
returns uuid[]
language sql security definer stable set search_path = public as $$
  select coalesce(array_agg(m.service_id), '{}')
    from public.client_document_services m
    join public.client_services s on s.id = m.service_id
   where m.document_id = p_doc
     and s.state = 'confirmed'
     and not exists (
       select 1
         from public.client_document_services m2
         join public.client_documents d2 on d2.id = m2.document_id
        where m2.service_id = m.service_id
          and m2.document_id <> p_doc
          and d2.verified_at is not null
          and d2.voided_at is null);
$$;
grant execute on function public.letter_sole_services(uuid) to authenticated;

drop function if exists public.letter_set_void(uuid, boolean);
create or replace function public.letter_set_void(p_doc uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
  ids uuid[];
begin
  -- Voiding is the Clients section's Manage level, the same authority that
  -- deletes a letter: one level of trust, one switch.
  if not public.allowed('clients.documents', 'manage') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('ok', true, 'repeat', true); end if;
  if d.verified_at is null then return jsonb_build_object('error', 'not-verified'); end if;

  ids := public.letter_sole_services(p_doc);

  update public.client_documents
     set voided_at = now(), voided_by = who, void_reason = btrim(p_reason)
   where id = p_doc;
  update public.client_services set state = 'quoted' where id = any(ids);

  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.voided', cl.name,
          d.number || ' · ' || btrim(p_reason) || ' · ' ||
          coalesce(array_length(ids, 1), 0) || ' service lines reverted');
  return jsonb_build_object('ok', true, 'reverted', coalesce(array_length(ids, 1), 0));
end $$;
grant execute on function public.letter_set_void(uuid, text) to authenticated;

create or replace function public.letter_delete(p_doc uuid, p_confirm text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
  ids uuid[];
begin
  -- A letter lives inside the client record, so deleting one is `manage`
  -- on Clients. Voiding stays its own capability: two authorities, two acts.
  if not public.allowed('clients.documents', 'manage') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if btrim(coalesce(p_confirm, '')) <> d.number then
    return jsonb_build_object('error', 'confirm-mismatch');
  end if;

  ids := public.letter_sole_services(p_doc);
  update public.client_services set state = 'quoted' where id = any(ids);
  update public.client_documents set superseded_by = null where superseded_by = p_doc;

  insert into public.client_document_deletions
    (document_id, number, client_id, actor, reason, service_ids)
  values (d.id, d.number, d.client_id, who, btrim(p_reason), coalesce(ids, '{}'));

  select * into cl from public.clients where id = d.client_id;
  delete from public.client_documents where id = p_doc;

  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.deleted', cl.name,
          d.number || ' · ' || btrim(p_reason) || ' · ' ||
          coalesce(array_length(ids, 1), 0) || ' service lines reverted');
  return jsonb_build_object('ok', true, 'number', d.number,
                            'reverted', coalesce(array_length(ids, 1), 0));
end $$;
grant execute on function public.letter_delete(uuid, text, text) to authenticated;

-- ===========================================================================
-- THE DOCUMENTS REGISTER
--
-- Every letter the portal issues, and every serial it is told about, in one
-- place: the quotation cover that accompanies the accounting portal's
-- quotation, the letters to clients, the HR letters to colleagues, and the
-- rows added by hand for documents made elsewhere. The Letter of Offer keeps
-- its own table above; the Register reads both.
--
-- Three rules carry the whole design.
--   1. The serial is the database's to make, per family, and the person may
--      overwrite it where the number comes from outside (the accounting
--      portal's quotation serial). A serial is never reused: a deleted one is
--      remembered.
--   2. HR is its own part of the access ladder (`register.hr`). An HR row is
--      unreadable without it, its serial carries a staff code, and the
--      activity record is told that an HR letter was issued and nothing
--      about whom.
--   3. Verification answers an exact serial with the kind, the date and
--      whether it stands, and never the recipient. It is granted to anon,
--      because the footer of every letter names a public page.
-- ===========================================================================

-- 1. The people who are written to, and who sign. A colleague carries a staff
--    code (the HR serial is built from it) and a designation (printed under
--    the signature). Both are typed on the Team page.
alter table public.team_members add column if not exists staff_code text;
alter table public.team_members add column if not exists designation text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'team_members_staff_code_shape') then
    alter table public.team_members add constraint team_members_staff_code_shape
      check (staff_code is null or staff_code ~ '^[A-Z0-9]{3,8}$');
  end if;
end $$;
create unique index if not exists team_members_staff_code_idx
  on public.team_members (upper(staff_code)) where staff_code is not null and staff_code <> '';

-- 2. The kinds. One row per letter type: which family it belongs to, the
--    segment it puts in the serial, and the words it starts with. The seed is
--    a first run into an empty table, as the rate card's is: the wording is
--    the team's to edit and a seed that ran every time would put it back.
create table if not exists public.doc_types (
  id         text primary key,
  family     text not null check (family in ('quote_cover', 'client', 'hr')),
  code       text,
  name       text not null,
  title      text not null default '',
  salutation text not null default 'Dear Sir/Madam,',
  closing    text not null default 'Yours sincerely,',
  body_en    text not null default '',
  body_zh    text not null default '',
  body_ms    text not null default '',
  signed     boolean not null default true,
  position   int not null default 0,
  active     boolean not null default true
);
alter table public.doc_types enable row level security;
drop policy if exists doc_types_read on public.doc_types;
create policy doc_types_read on public.doc_types for select to authenticated using (public.is_team());

insert into public.doc_types (id, family, code, name, title, salutation, closing, body_en, body_zh, body_ms, signed, position)
select v.* from (values
  ('quote_cover', 'quote_cover', null, 'Quotation Cover', 'QUOTATION FOR DIGITAL MARKETING SERVICES',
   'Dear Sir/Madam,', 'Yours sincerely,',
   E'We are pleased to submit our quotation for your consideration. It has been prepared based on the scope and requirements discussed, with full details set out in the attached quotation.\n\nShould you need any clarification or additional information, please do not hesitate to reach out. We are happy to provide further materials to support your evaluation.\n\nThank you for the opportunity. We look forward to working with you and your team.',
   E'我們很榮幸能為貴司提呈本次報價。此報價乃根據貴司需求擬定，詳細內容請見附件報價單。\n\n若在審閱過程中有任何疑問或需要補充資料，歡迎隨時與我們聯繫。\n\n感謝貴司給予此次機會，期待有幸與貴司團隊展開合作。',
   E'Dengan sukacitanya kami mengemukakan sebut harga ini untuk pertimbangan pihak tuan/puan. Sebut harga ini telah disediakan berdasarkan skop dan keperluan yang telah dibincangkan, dengan butiran lengkap disertakan dalam dokumen yang dilampirkan.\n\nSekiranya pihak tuan/puan memerlukan sebarang penjelasan atau maklumat lanjut, sila hubungi kami. Kami dengan senang hati akan membantu dan menyediakan maklumat tambahan yang diperlukan untuk penilaian pihak tuan/puan.\n\nTerima kasih atas peluang yang diberikan. Kami menantikan peluang untuk bekerjasama dengan pihak tuan/puan dan pasukan anda.',
   false, 10),
  ('thanks', 'client', 'SC', 'Thank You Letter', 'WITH APPRECIATION',
   'Dear Sir/Madam,', 'Yours sincerely,',
   E'On behalf of the team, we would like to extend our sincere appreciation for the opportunity to serve as your marketing partner throughout this engagement. It has been a privilege to support your brand and contribute to your business objectives.\n\nWe place high importance on the feedback of our clients, as it enables us to refine and enhance the quality of our services. At your convenience, we would be grateful if you could share your experience with us through the following link: https://go.adspace.me/review. Your input will be invaluable to our continuous improvement efforts.\n\nWhile this engagement is drawing to a close, we wish to emphasise that our doors remain open for future collaboration opportunities. Should there be any new initiatives or campaigns where our expertise may be of value, we would be delighted to support your brand once again.\n\nThank you once more for the trust and confidence you have placed in us. We look forward to the possibility of building upon this relationship in the future.',
   '', '', true, 20),
  ('client_letter', 'client', 'GL', 'Letter to Client', '',
   'Dear Sir/Madam,', 'Yours sincerely,', '', '', '', true, 30),
  ('hr_confirm', 'hr', 'E', 'Confirmation of Employment', 'CONFIRMATION OF EMPLOYMENT',
   'Dear {first name},', 'Warm regards,',
   E'We are pleased to officially confirm your position as {role} with us, effective {effective date}. This follows a successful completion of your probationary period which commenced on {start date}.\n\nFollowing your confirmation, the terms of your employment outlined in your initial employment contract will remain in effect, with the following additions or modifications:\n\nSalary: RM {salary}/month (subject to statutory deductions)\n\nWe trust that you will continue to work with dedication and commitment, and we encourage you to further develop your skills and grow professionally within our organisation.\n\nShould you have any questions regarding your confirmation or any other matters, please do not hesitate to contact your Direct Manager.\n\nCongratulations on your confirmation! We look forward to your continued contributions and a successful journey ahead with ADSPACE PLT.',
   '', '', true, 40),
  ('hr_letter', 'hr', 'GL', 'HR Letter', '',
   'Dear {first name},', 'Warm regards,', '', '', '', true, 50)
) as v(id, family, code, name, title, salutation, closing, body_en, body_zh, body_ms, signed, position)
where not exists (select 1 from public.doc_types);

-- 3. The documents. A portal row holds the whole snapshot the PDF is drawn
--    from, so it is redrawn exactly as issued; a manual row holds the serial
--    and what is known about it. The serial is unique across the register
--    and, through serial_taken(), across the Letters of Offer and the
--    deletions as well.
create table if not exists public.documents (
  id          uuid primary key default gen_random_uuid(),
  type_id     text references public.doc_types(id) on delete set null,
  family      text not null check (family in ('quote_cover', 'client', 'hr', 'other')),
  kind        text not null,
  serial      text not null,
  client_id   uuid references public.clients(id) on delete set null,
  member_id   uuid references public.team_members(id) on delete set null,
  issued_at   date default current_date,
  title       text not null default '',
  salutation  text not null default '',
  closing     text not null default '',
  recipient   jsonb not null default '{}'::jsonb,
  body        jsonb not null default '{}'::jsonb,
  languages   text[] not null default '{en}',
  signatory   jsonb,
  signed      boolean not null default true,
  source      text not null default 'portal' check (source in ('portal', 'manual')),
  file_url    text,
  note        text,
  issued_by   text,
  idem_key    text,
  created_at  timestamptz not null default now(),
  voided_at   timestamptz,
  voided_by   text,
  void_reason text
);
/* A reissue keeps the serial: the earlier version is voided and stays on the
   record, the new one is the document that stands. So a serial is unique
   among the documents that stand, and serial_taken() below still refuses it
   to anything else, because both versions hold it. */
drop index if exists documents_serial_idx;
create unique index if not exists documents_serial_live_idx
  on public.documents (upper(serial)) where voided_at is null;
alter table public.documents add column if not exists replaces uuid references public.documents(id) on delete set null;
create index if not exists documents_client_idx on public.documents (client_id);
create index if not exists documents_member_idx on public.documents (member_id);
create index if not exists documents_created_idx on public.documents (created_at desc);

create table if not exists public.document_deletions (
  id         uuid primary key default gen_random_uuid(),
  serial     text not null,
  family     text not null,
  kind       text,
  actor      text,
  reason     text,
  deleted_at timestamptz not null default now()
);
alter table public.document_deletions enable row level security;

-- Who may do what, by family. A client's documents belong to the client
-- record as much as to the Register, so either's Documents part opens them;
-- an HR letter answers to the Register's HR part and to nothing else.
create or replace function public.register_may(p_family text, p_level text)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when p_family = 'hr'    then public.allowed('register.hr', p_level)
    when p_family = 'other' then public.allowed('register.documents', p_level)
    else public.allowed('register.documents', p_level) or public.allowed('clients.documents', p_level)
  end
$$;
grant execute on function public.register_may(text, text) to authenticated;

alter table public.documents enable row level security;
drop policy if exists documents_read on public.documents;
create policy documents_read on public.documents for select to authenticated
  using (public.register_may(family, 'view'));
-- Every write goes through a function below; there is no insert, update or
-- delete policy on the table, and PostgREST refuses them all.

-- A serial is spent by a document that STANDS: on the register, or as a
-- Letter of Offer. A deletion is deliberately not counted (2026-09-20): a
-- document issued by mistake and deleted used to take its reference out of
-- circulation for ever, so testing a client's first two letters and deleting
-- both left that client starting at 03. The deletion row is still the only
-- record that an earlier document held the reference, which is the cost of
-- this and is stated rather than hidden.
create or replace function public.serial_taken(p_serial text)
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.documents where upper(serial) = upper(btrim(p_serial)))
      or exists (select 1 from public.client_documents where upper(number) = upper(btrim(p_serial)))
$$;
grant execute on function public.serial_taken(text) to authenticated;

-- 4. Issuing. The serial rules, per family:
--      quote cover  typed, from the accounting portal (AQT2607003)
--      client       AD/[SA/]{client code}/{type}, SA where the client has
--                   engaged a service (any confirmed line, or a client that
--                   has been Active)
--      hr           ADHR/{staff code}/{type}{YYMM}
--    A typed serial is accepted for any family; a built one takes a numeric
--    suffix where the same client already holds the same type.
create or replace function public.issue_document(
  p_type      text,
  p_client    uuid,
  p_member    uuid,
  p_serial    text,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_idem      text,
  p_salutation text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who     text := lower(auth.jwt() ->> 'email');
  t       public.doc_types%rowtype;
  cl      public.clients%rowtype;
  mb      public.team_members%rowtype;
  me      public.team_members%rowtype;
  v_old   public.documents%rowtype;
  v_serial text;
  v_base  text;
  v_n     int;
  v_id    uuid;
  v_engaged boolean;
  v_langs text[];
begin
  select * into t from public.doc_types where id = p_type and active;
  if t.id is null then return jsonb_build_object('error', 'no-type'); end if;
  if not public.register_may(t.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;

  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;

  if t.family in ('quote_cover', 'client') then
    if p_client is null then return jsonb_build_object('error', 'no-client'); end if;
    select * into cl from public.clients where id = p_client;
    if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;
  end if;
  if t.family = 'hr' then
    if p_member is null then return jsonb_build_object('error', 'no-member'); end if;
    select * into mb from public.team_members where id = p_member;
    if mb.id is null then return jsonb_build_object('error', 'no-member'); end if;
    if coalesce(btrim(mb.staff_code), '') = '' then return jsonb_build_object('error', 'no-staff-code'); end if;
  end if;

  -- A signed kind is signed by a person, never by a permission.
  if t.signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;

  v_serial := nullif(btrim(coalesce(p_serial, '')), '');
  if v_serial is null then
    if t.family = 'quote_cover' then return jsonb_build_object('error', 'serial-required'); end if;
    if t.family = 'client' then
      if coalesce(btrim(cl.client_code), '') = '' then return jsonb_build_object('error', 'no-client-code'); end if;
      v_engaged := cl.stage in ('active', 'paused', 'past')
                or exists (select 1 from public.client_services s where s.client_id = cl.id and s.state = 'confirmed');
      v_base := 'AD/' || case when v_engaged then 'SA/' else '' end || cl.client_code || '/' || coalesce(t.code, 'GL');
    else
      v_base := 'ADHR/' || upper(mb.staff_code) || '/' || coalesce(t.code, 'GL') ||
                to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');
    end if;
    v_serial := v_base; v_n := 1;
    while public.serial_taken(v_serial) loop
      v_n := v_n + 1; v_serial := v_base || '-' || v_n;
    end loop;
  else
    if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
    if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  end if;

  v_langs := coalesce(p_languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;

  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key)
  values
    (t.id, t.family, t.name, v_serial,
     case when t.family = 'hr' then null else p_client end,
     case when t.family = 'hr' then p_member else null end,
     coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), t.title),
     coalesce(nullif(btrim(p_salutation), ''), t.salutation), t.closing,
     coalesce(p_recipient, '{}'::jsonb), coalesce(p_body, '{}'::jsonb), v_langs,
     case when t.signed then p_signatory else null end, t.signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''))
  returning id into v_id;

  -- The record is told an HR letter was issued and nothing about whom: the
  -- Activity record is read by more people than HR is.
  if t.family = 'hr' then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', 'HR', t.name);
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', cl.name, v_serial || ' · ' || t.name);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
      end if;
    end if;
    return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.issue_document(text, uuid, uuid, text, date, text, jsonb, jsonb, jsonb, text[], text, text) to authenticated;

-- 5. A serial added by hand: a document made elsewhere (the accounting
--    portal, an older Word letter) that the verify page should still answer.
create or replace function public.register_add(
  p_serial    text,
  p_family    text,
  p_kind      text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  me    public.team_members%rowtype;
  v_serial text := nullif(btrim(coalesce(p_serial, '')), '');
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  v_id  uuid;
  cl    public.clients%rowtype;
begin
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(v_fam, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  if v_serial is null then return jsonb_build_object('error', 'serial-required'); end if;
  if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
  if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if p_client is not null then select * into cl from public.clients where id = p_client; end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (family, kind, serial, client_id, issued_at, recipient, signed, source, file_url, note, issued_by)
  values
    (v_fam, btrim(p_kind), v_serial, cl.id, coalesce(p_issued_at, current_date),
     jsonb_build_object('name', coalesce(btrim(p_recipient), '')), false, 'manual',
     nullif(btrim(p_file_url), ''), nullif(btrim(p_note), ''), coalesce(me.name, who))
  returning id into v_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.added',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else v_serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.register_add(text, text, text, date, text, uuid, text, text) to authenticated;
-- A serial imported or added by hand is known before its details are, so
-- the date may be blank and the row is edited afterwards; a portal row is a
-- snapshot and is never edited.
alter table public.documents alter column issued_at drop not null;

-- 5a. Editing a hand-added row: the kind, the family, the date, the recipient,
--     the client, the note and the file link. The serial never changes; a
--     wrong serial is deleted and added again, so the deletions remember it.
create or replace function public.register_update(
  p_doc       uuid,
  p_kind      text,
  p_family    text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.documents%rowtype;
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  cl    public.clients%rowtype;
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'manual' then return jsonb_build_object('error', 'not-manual'); end if;
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(d.family, 'work') or not public.register_may(v_fam, 'work') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if p_client is not null then select * into cl from public.clients where id = p_client; end if;
  update public.documents set
    kind = btrim(p_kind), family = v_fam, issued_at = p_issued_at,
    recipient = jsonb_build_object('name', coalesce(btrim(p_recipient), '')),
    client_id = cl.id, note = nullif(btrim(p_note), ''), file_url = nullif(btrim(p_file_url), '')
  where id = p_doc;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.edited',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else d.serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'serial', d.serial);
end $$;
grant execute on function public.register_update(uuid, text, text, date, text, uuid, text, text) to authenticated;

-- 5b. Reissue: a portal document corrected after it went out. The earlier
--     version is voided with the reason `Reissued` and kept, the new version
--     takes the same serial, the same kind and the same client or colleague,
--     and points back at the one it replaces. Work level, because correcting
--     what you issued is everyday work and the earlier version stays on the
--     record where anybody can read it. The verify page answers the version
--     that stands and says nothing about a reissue: the reference on the
--     paper in somebody's hand is the reference of the document that stands.
create or replace function public.document_reissue(
  p_doc       uuid,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_salutation text,
  p_idem      text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  d      public.documents%rowtype;
  v_old  public.documents%rowtype;
  me     public.team_members%rowtype;
  cl     public.clients%rowtype;
  v_id   uuid;
  v_langs text[];
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'portal' then return jsonb_build_object('error', 'not-portal'); end if;
  if not public.register_may(d.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  -- The same press twice is one reissue, and is answered before the check
  -- below, because the first press is exactly what made a later version stand.
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;
  -- Only the version that stands is reissued; an earlier one already has a successor.
  if exists (select 1 from public.documents
              where upper(serial) = upper(d.serial) and voided_at is null and id <> d.id) then
    return jsonb_build_object('error', 'not-current');
  end if;
  if d.signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;
  v_langs := coalesce(p_languages, d.languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  -- The version that stood stops standing first, so the serial is free for
  -- the one that replaces it; a version already voided keeps its own reason.
  if d.voided_at is null then
    update public.documents set voided_at = now(), voided_by = who, void_reason = 'Reissued' where id = d.id;
  end if;
  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key, replaces)
  values
    (d.type_id, d.family, d.kind, d.serial, d.client_id, d.member_id,
     coalesce(p_issued_at, d.issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), d.title),
     coalesce(nullif(btrim(p_salutation), ''), d.salutation), d.closing,
     coalesce(p_recipient, d.recipient), coalesce(p_body, d.body), v_langs,
     case when d.signed then p_signatory else null end, d.signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''), d.id)
  returning id into v_id;

  if d.client_id is not null then select * into cl from public.clients where id = d.client_id; end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.reissued',
          case when d.family = 'hr' then 'HR' else coalesce(cl.name, d.recipient ->> 'name', '') end,
          case when d.family = 'hr' then d.kind else d.serial || ' · ' || d.kind end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', d.serial);
exception
  when unique_violation then
    return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.document_reissue(uuid, date, text, jsonb, jsonb, jsonb, text[], text, text) to authenticated;

-- 6. Void: the row and the serial stay, the document no longer stands. The
--    verify page answers "voided" from then on.
create or replace function public.document_set_void(p_doc uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.documents%rowtype;
  cl  public.clients%rowtype;
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.register_may(d.family, 'manage') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if d.voided_at is not null then return jsonb_build_object('ok', true, 'repeat', true); end if;
  update public.documents set voided_at = now(), voided_by = who, void_reason = btrim(p_reason) where id = p_doc;
  if d.client_id is not null then select * into cl from public.clients where id = d.client_id; end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.voided',
          case when d.family = 'hr' then 'HR' else coalesce(cl.name, d.recipient ->> 'name', '') end,
          case when d.family = 'hr' then d.kind else d.serial || ' · ' || btrim(p_reason) end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.document_set_void(uuid, text) to authenticated;

-- 7. Delete: permanent, the serial typed back, and remembered so it is never
--    handed out again.
create or replace function public.document_delete(p_doc uuid, p_confirm text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.documents%rowtype;
  cl  public.clients%rowtype;
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.register_may(d.family, 'manage') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if upper(btrim(coalesce(p_confirm, ''))) <> upper(d.serial) then return jsonb_build_object('error', 'confirm-mismatch'); end if;
  insert into public.document_deletions (serial, family, kind, actor, reason)
  values (d.serial, d.family, d.kind, who, btrim(p_reason));
  delete from public.documents where id = p_doc;
  if d.client_id is not null then select * into cl from public.clients where id = d.client_id; end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.deleted',
          case when d.family = 'hr' then 'HR' else coalesce(cl.name, d.recipient ->> 'name', '') end,
          case when d.family = 'hr' then d.kind else d.serial || ' · ' || btrim(p_reason) end);
  return jsonb_build_object('ok', true, 'serial', d.serial);
end $$;
grant execute on function public.document_delete(uuid, text, text) to authenticated;

-- 8. Verification, public. One exact serial in, the kind, the date and
--    whether it stands out. Never the recipient, never the content, no
--    listing and no partial match: what this gives away is what the footer
--    of the letter already printed. An HR serial is answered as "HR letter".
--    A reissued serial is answered by the version that stands, as Valid, and
--    only reads Void once no version of it stands.
create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  d public.documents%rowtype;
  l public.client_documents%rowtype;
begin
  if length(s) < 3 or length(s) > 40 then return jsonb_build_object('found', false); end if;
  select * into d from public.documents where upper(serial) = s
    order by (voided_at is null) desc, created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('found', true, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued_at', d.issued_at,
      'state', case when d.voided_at is null then 'valid' else 'voided' end);
  end if;
  select * into l from public.client_documents where upper(number) = s limit 1;
  if l.id is not null then
    return jsonb_build_object('found', true, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued_at', l.issued_at,
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end);
  end if;
  return jsonb_build_object('found', false);
end $$;
grant execute on function public.verify_serial(text) to anon, authenticated;


-- ===========================================================================
-- THE OPERATIONS SYSTEM
--
-- The internal task, workflow, time and audit model behind /admin/ Work.
-- Everything here is prefixed `ops_`.
--
-- THIS SECTION AND supabase/migrations/2026-09-19-operations-system.sql ARE
-- THE SAME TEXT. The migration is what a live database is given, because a
-- re-run of this whole file to add one table is exposure with no benefit;
-- this copy is the canonical schema a fresh database is built from.
-- `tests/ops.js` compares the two byte for byte, so they cannot drift.
--
-- Permissions are levels in the access ladder, not a second set of switches:
-- the note at the head of the migration says which level each of the brief's
-- seven capabilities is, and why the four that widen a section are granted
-- rather than inherited.
-- ===========================================================================
-- ---------------------------------------------------------------------------
-- 0. Planning figures on a colleague. Capacity is guidance for planning, not
--    attendance: nothing in this system records when somebody is at a desk.
-- ---------------------------------------------------------------------------
alter table public.team_members add column if not exists capacity_minutes_week integer;
alter table public.team_members add column if not exists wip_guidance integer;

-- ---------------------------------------------------------------------------
-- 1. Helpers.
-- ---------------------------------------------------------------------------

/* A PART THAT WIDENS IS GRANTED, NEVER INHERITED.
   `allowed()` falls back from a part to its section, which is right for every
   part this portal had before today: Billing is inside the Clients job, so a
   group that works Clients works Billing unless somebody says otherwise, and
   only the exception is stored. The operations parts are the other direction.
   The team-wide queue, the reports, the templates and another person's hours
   are not inside "work my own tasks" — they are more than it. Inherited, a
   group given `{"ops":"work"}` would read every colleague's queue and every
   report until an admin remembered to opt them out, and a group added next
   year would start there again. So these four are asked for with this
   predicate, which reads the exact key and does not fall back. Same map, same
   four levels, same `level_rank`: what changes is that silence means no. */
create or replace function public.ops_granted(p_key text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
   where active and lower(email) = lower(auth.jwt() ->> 'email') limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  return public.level_rank(t.access ->> p_key) >= public.level_rank(p_level);
end $$;
grant execute on function public.ops_granted(text, text) to authenticated;

/* The signed-in colleague, or nothing. Every function below starts here, so
   a client contact holding an auth account reaches no operations row: they
   have no active `team_members` row and the first check fails. */
create or replace function public.ops_me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members
   where active and lower(email) = lower(auth.jwt() ->> 'email')
   limit 1
$$;
grant execute on function public.ops_me() to authenticated;

/* Business days forward or backward from a timestamp, skipping Saturday and
   Sunday. Public holidays are a later setting; the function takes them from
   nothing today and the offset is documented as working days. */
create or replace function public.ops_add_business_days(p_from timestamptz, p_days integer)
returns timestamptz
language plpgsql immutable set search_path = public as $$
declare
  d   timestamptz := p_from;
  n   integer := abs(coalesce(p_days, 0));
  dir integer := case when coalesce(p_days, 0) < 0 then -1 else 1 end;
begin
  if p_from is null then return null; end if;
  while n > 0 loop
    d := d + (dir || ' day')::interval;
    -- 0 is Sunday, 6 is Saturday in Postgres `dow`.
    if extract(dow from d at time zone 'Asia/Kuala_Lumpur') not in (0, 6) then
      n := n - 1;
    end if;
  end loop;
  return d;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Workflows and their stages.
-- ---------------------------------------------------------------------------

create table if not exists public.ops_workflows (
  id          uuid primary key default gen_random_uuid(),
  key         text unique not null,
  name        text not null,
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.ops_workflow_stages (
  id              uuid primary key default gen_random_uuid(),
  workflow_id     uuid not null references public.ops_workflows(id) on delete cascade,
  key             text not null,
  label           text not null,
  position        integer not null,
  stage_group     text not null,
  is_active_work  boolean not null default false,
  is_waiting      boolean not null default false,
  is_review       boolean not null default false,
  is_terminal     boolean not null default false,
  wip_guidance    integer,
  next_stage_keys text[] not null default '{}'
);
create unique index if not exists ops_stage_key_idx on public.ops_workflow_stages(workflow_id, key);
create unique index if not exists ops_stage_pos_idx on public.ops_workflow_stages(workflow_id, position);

create table if not exists public.ops_task_templates (
  id                               uuid primary key default gen_random_uuid(),
  name                             text not null,
  deliverable_type                 text not null,
  workflow_id                      uuid not null references public.ops_workflows(id),
  default_complexity               text,
  first_draft_offset_business_days integer,
  final_offset_business_days       integer,
  default_estimate_minutes         integer,
  required_fields                  jsonb not null default '{}'::jsonb,
  checklist                        jsonb not null default '[]'::jsonb,
  active                           boolean not null default true,
  created_at                       timestamptz not null default now(),
  updated_at                       timestamptz not null default now()
);
create unique index if not exists ops_template_name_idx on public.ops_task_templates(lower(name));

-- ---------------------------------------------------------------------------
-- 3. The task, and everything hanging off it.
-- ---------------------------------------------------------------------------

create sequence if not exists public.ops_task_no_seq start 1001;

create table if not exists public.ops_tasks (
  id            uuid primary key default gen_random_uuid(),
  task_no       bigint not null default nextval('public.ops_task_no_seq'),
  scope         text not null check (scope in ('client', 'internal')),
  client_id     uuid references public.clients(id) on delete set null,
  campaign_id   uuid references public.campaigns(id) on delete set null,
  batch_id      uuid references public.batches(id) on delete set null,
  source_type   text,
  source_id     uuid,
  parent_task_id uuid references public.ops_tasks(id) on delete set null,
  template_id   uuid references public.ops_task_templates(id),
  workflow_id   uuid not null references public.ops_workflows(id),
  stage_key     text not null,
  title         text not null,
  description   text,
  remarks       text,
  deliverable_type text not null,
  language_codes text[] not null default '{}',
  priority_level smallint not null default 3 check (priority_level between 1 and 5),
  complexity    text check (complexity in ('simple', 'standard', 'complex')),
  estimate_minutes integer,
  publish_at    timestamptz,
  /* The promise first made. Never written again after creation: a report
     that can only measure the latest replan cannot see replanning at all. */
  original_first_draft_due_at timestamptz,
  current_first_draft_due_at  timestamptz,
  first_draft_submitted_at    timestamptz,
  original_final_due_at       timestamptz,
  current_final_due_at        timestamptz,
  delivered_at  timestamptz,
  completed_at  timestamptz,
  blocked_category text,
  blocked_note  text,
  blocked_at    timestamptz,
  created_by    uuid references public.team_members(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  archived_at   timestamptz,
  cancelled_at  timestamptz,
  version       integer not null default 1,
  legacy_source text,
  legacy_key    text,
  data_quality  text not null default 'complete',
  idem_key      text,
  constraint ops_tasks_client_scope check (scope <> 'client' or client_id is not null)
);
create unique index if not exists ops_tasks_no_idx on public.ops_tasks(task_no);
create unique index if not exists ops_tasks_legacy_idx
  on public.ops_tasks(legacy_source, legacy_key) where legacy_key is not null;
create unique index if not exists ops_tasks_idem_idx
  on public.ops_tasks(idem_key) where idem_key is not null;

create table if not exists public.ops_task_assignees (
  id             uuid primary key default gen_random_uuid(),
  task_id        uuid not null references public.ops_tasks(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id),
  responsibility text not null check (responsibility in ('owner', 'contributor', 'reviewer')),
  assigned_by    uuid references public.team_members(id),
  assigned_at    timestamptz not null default now(),
  ended_at       timestamptz
);
/* One accountable owner at a time, and one live row per person per role: an
   ended assignment stays for the history, which is why these are partial. */
create unique index if not exists ops_one_owner_idx on public.ops_task_assignees(task_id)
  where responsibility = 'owner' and ended_at is null;
create unique index if not exists ops_one_role_idx
  on public.ops_task_assignees(task_id, team_member_id, responsibility) where ended_at is null;
create index if not exists ops_assignee_live_idx
  on public.ops_task_assignees(team_member_id, responsibility) where ended_at is null;

create table if not exists public.ops_task_events (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.ops_tasks(id) on delete cascade,
  event_type  text not null,
  actor_id    uuid references public.team_members(id),
  actor_email text,
  from_value  jsonb,
  to_value    jsonb,
  detail      jsonb not null default '{}'::jsonb,
  source      text not null default 'portal',
  created_at  timestamptz not null default now()
);
create index if not exists ops_events_task_idx on public.ops_task_events(task_id, created_at desc);
create index if not exists ops_events_type_idx on public.ops_task_events(event_type, created_at desc);

create table if not exists public.ops_work_sessions (
  id             uuid primary key default gen_random_uuid(),
  task_id        uuid not null references public.ops_tasks(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id),
  started_at     timestamptz not null,
  ended_at       timestamptz,
  minutes        integer,
  note           text,
  source         text not null default 'timer',
  corrected_at   timestamptz,
  corrected_by   uuid references public.team_members(id),
  correction_reason text,
  created_at     timestamptz not null default now(),
  constraint ops_session_order check (ended_at is null or ended_at >= started_at)
);
/* One open session a person, across every task. */
create unique index if not exists ops_one_open_session_idx
  on public.ops_work_sessions(team_member_id) where ended_at is null;
create index if not exists ops_sessions_member_idx
  on public.ops_work_sessions(team_member_id, started_at desc);
create index if not exists ops_sessions_task_idx on public.ops_work_sessions(task_id);

create table if not exists public.ops_revisions (
  id                uuid primary key default gen_random_uuid(),
  task_id           uuid not null references public.ops_tasks(id) on delete cascade,
  round_no          integer not null,
  requested_by_type text not null check (requested_by_type in ('internal', 'client', 'platform', 'other')),
  reason_category   text not null,
  summary           text,
  requested_by      uuid references public.team_members(id),
  assigned_to       uuid references public.team_members(id),
  requested_at      timestamptz not null default now(),
  completed_at      timestamptz,
  source_review_id  uuid,
  idem_key          text
);
create unique index if not exists ops_revision_round_idx on public.ops_revisions(task_id, round_no);
create unique index if not exists ops_revision_idem_idx
  on public.ops_revisions(idem_key) where idem_key is not null;
/* A review version decides once. A second delivery of the same decision is
   the same decision, so it finds this row rather than opening a round. */
create unique index if not exists ops_revision_source_idx
  on public.ops_revisions(task_id, source_review_id) where source_review_id is not null;

create table if not exists public.ops_task_checklist_items (
  id           uuid primary key default gen_random_uuid(),
  task_id      uuid not null references public.ops_tasks(id) on delete cascade,
  label        text not null,
  position     integer not null,
  required     boolean not null default false,
  completed_at timestamptz,
  completed_by uuid references public.team_members(id),
  created_at   timestamptz not null default now()
);
create index if not exists ops_checklist_task_idx on public.ops_task_checklist_items(task_id, position);

create table if not exists public.ops_task_links (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.ops_tasks(id) on delete cascade,
  kind        text not null,
  label       text not null,
  url         text not null,
  created_by  uuid references public.team_members(id),
  created_at  timestamptz not null default now(),
  archived_at timestamptz
);
create index if not exists ops_links_task_idx on public.ops_task_links(task_id) where archived_at is null;

create table if not exists public.ops_video_details (
  task_id                  uuid primary key references public.ops_tasks(id) on delete cascade,
  output_duration_seconds  integer,
  footage_duration_seconds integer,
  subtitle_required        boolean not null default false,
  motion_graphics_required boolean not null default false,
  aspect_ratios            text[] not null default '{}',
  script_ready             boolean,
  footage_ready            boolean,
  shoot_required           boolean not null default false,
  shoot_at                 timestamptz,
  variant_count            integer not null default 1
);

create table if not exists public.ops_notifications (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  task_id        uuid references public.ops_tasks(id) on delete cascade,
  kind           text not null,
  title          text not null,
  body           text,
  read_at        timestamptz,
  created_at     timestamptz not null default now(),
  dedupe_key     text unique
);
create index if not exists ops_notif_member_idx
  on public.ops_notifications(team_member_id, created_at desc) where read_at is null;

create table if not exists public.ops_recurring_rules (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  client_id             uuid references public.clients(id) on delete cascade,
  template_id           uuid not null references public.ops_task_templates(id),
  owner_id              uuid references public.team_members(id),
  frequency             text not null default 'monthly',
  day_of_month          integer,
  publish_rule          jsonb,
  active                boolean not null default true,
  last_generated_period text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table if not exists public.ops_kpi_targets (
  id             uuid primary key default gen_random_uuid(),
  metric_key     text not null,
  scope_type     text not null check (scope_type in ('company', 'client', 'workflow', 'deliverable')),
  scope_id       text,
  target_value   numeric not null,
  comparison     text not null check (comparison in ('gte', 'lte', 'between')),
  target_max     numeric,
  effective_from date not null,
  effective_to   date,
  created_by     uuid references public.team_members(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists ops_target_metric_idx
  on public.ops_kpi_targets(metric_key, effective_from desc);

-- Reporting and list indexes. Measured against the filters the views actually
-- carry rather than one per column.
create index if not exists ops_tasks_open_idx on public.ops_tasks(current_final_due_at)
  where completed_at is null and cancelled_at is null and archived_at is null;
create index if not exists ops_tasks_client_idx on public.ops_tasks(client_id, created_at desc);
create index if not exists ops_tasks_stage_idx on public.ops_tasks(workflow_id, stage_key);
create index if not exists ops_tasks_done_idx on public.ops_tasks(completed_at desc)
  where completed_at is not null;
create index if not exists ops_tasks_delivered_idx on public.ops_tasks(delivered_at desc)
  where delivered_at is not null;

-- ---------------------------------------------------------------------------
-- 4. Who may read what.
--
--    Reads are policies. Writes are not: every table below carries a select
--    policy and nothing else, so the only way a row changes is through one of
--    the security-definer functions in section 6, which check the permission
--    and write the audit event in the same transaction. A browser holding the
--    anon key cannot set a stage, move a date, assign a person or file an
--    event, whatever it sends.
-- ---------------------------------------------------------------------------

/* May the signed-in colleague read this task? Their own work always: owner,
   contributor, reviewer or the person who asked for it. The whole team's
   work only with `ops.all`. */
create or replace function public.ops_may_see_task(p_task uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when not public.allowed('ops', 'view') then false
    when public.ops_granted('ops.all', 'view') then true
    else exists (
      select 1 from public.ops_tasks t
       where t.id = p_task
         and (t.created_by = (select id from public.ops_me())
              or exists (select 1 from public.ops_task_assignees a
                          where a.task_id = t.id and a.ended_at is null
                            and a.team_member_id = (select id from public.ops_me()))))
  end
$$;
grant execute on function public.ops_may_see_task(uuid) to authenticated;

-- Row level security is stated one table at a time, never in the loop below.
-- The Supabase SQL editor scans a script for exactly these lines and offers to
-- append its own where it cannot find them: an `execute format(...)` inside a
-- `do $$` block is invisible to it, so a file that enabled RLS correctly still
-- prompted on every run. A security posture a reader cannot see in the file is
-- one nobody can check, the editor included.
alter table public.ops_workflows enable row level security;
alter table public.ops_workflow_stages enable row level security;
alter table public.ops_task_templates enable row level security;
alter table public.ops_tasks enable row level security;
alter table public.ops_task_assignees enable row level security;
alter table public.ops_task_events enable row level security;
alter table public.ops_work_sessions enable row level security;
alter table public.ops_revisions enable row level security;
alter table public.ops_task_checklist_items enable row level security;
alter table public.ops_task_links enable row level security;
alter table public.ops_video_details enable row level security;
alter table public.ops_notifications enable row level security;
alter table public.ops_recurring_rules enable row level security;
alter table public.ops_kpi_targets enable row level security;

do $$
declare
  t text;
  tables text[] := array[
    'ops_workflows', 'ops_workflow_stages', 'ops_task_templates', 'ops_tasks',
    'ops_task_assignees', 'ops_task_events', 'ops_work_sessions', 'ops_revisions',
    'ops_task_checklist_items', 'ops_task_links', 'ops_video_details',
    'ops_notifications', 'ops_recurring_rules', 'ops_kpi_targets'];
begin
  foreach t in array tables loop
    /* Policies are additive, so every one this file owns goes before the new
       one lands. Named from the catalogue rather than from a list kept here,
       because a list is a second place to remember a policy and this file
       already had one it forgot. */
    declare p text;
    begin
      for p in select policyname from pg_policies
                where schemaname = 'public' and tablename = t loop
        execute format('drop policy if exists %I on public.%I', p, t);
      end loop;
    end;
  end loop;
end $$;

-- The catalogue: anybody who can open the section reads it.
create policy ops_workflows_read on public.ops_workflows
  for select to authenticated using (public.allowed('ops', 'view'));
create policy ops_workflow_stages_read on public.ops_workflow_stages
  for select to authenticated using (public.allowed('ops', 'view'));
create policy ops_task_templates_read on public.ops_task_templates
  for select to authenticated using (public.allowed('ops', 'view'));
create policy ops_kpi_targets_read on public.ops_kpi_targets
  for select to authenticated using (public.ops_granted('ops.reports', 'view'));
create policy ops_recurring_rules_read on public.ops_recurring_rules
  for select to authenticated using (public.ops_granted('ops.workflows', 'view'));

-- The work: own tasks, or the whole queue with `ops.all`.
create policy ops_tasks_read on public.ops_tasks
  for select to authenticated using (public.ops_may_see_task(id));
create policy ops_task_assignees_read on public.ops_task_assignees
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_task_events_read on public.ops_task_events
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_revisions_read on public.ops_revisions
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_task_checklist_items_read on public.ops_task_checklist_items
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_task_links_read on public.ops_task_links
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_video_details_read on public.ops_video_details
  for select to authenticated using (public.ops_may_see_task(task_id));

/* A person's own hours are their own to read; a manager reads the team's.
   Neither reads a session on a task they cannot see. */
create policy ops_work_sessions_read on public.ops_work_sessions
  for select to authenticated using (
    public.ops_may_see_task(task_id)
    and (team_member_id = (select id from public.ops_me())
         or public.ops_granted('ops.all', 'view')
         or public.ops_granted('ops.time', 'manage')));

-- A notification is addressed to one person and read by that person.
create policy ops_notifications_read on public.ops_notifications
  for select to authenticated using (team_member_id = (select id from public.ops_me()));
/* Marking one read is the single write a browser may make directly, and it
   can only reach its own row and can only set `read_at`. */
create policy ops_notifications_mark on public.ops_notifications
  for update to authenticated
  using (team_member_id = (select id from public.ops_me()))
  with check (team_member_id = (select id from public.ops_me()));

-- ---------------------------------------------------------------------------
-- 5. The workflows the portal ships with. Seeded once, into a database that
--    has none: the stages are the team's to edit afterwards, and a seed that
--    ran on every pass would put back a stage somebody had removed.
-- ---------------------------------------------------------------------------
do $$
declare
  w_general uuid;
  w_video   uuid;
begin
  if exists (select 1 from public.ops_workflows) then return; end if;

  insert into public.ops_workflows (key, name, description)
  values ('general', 'General deliverable',
          'Design, copy, reports and everything that is not a shoot.')
  returning id into w_general;

  insert into public.ops_workflows (key, name, description)
  values ('video', 'Video production',
          'Work that is shot and edited before it reaches a client.')
  returning id into w_video;

  insert into public.ops_workflow_stages
    (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
     is_review, is_terminal, wip_guidance, next_stage_keys) values
    (w_general, 'intake',    'Intake',          1, 'intake',        false, false, false, false, null, array['ready','cancelled','kiv']),
    (w_general, 'ready',     'Ready',           2, 'ready',         false, false, false, false, null, array['in_progress','blocked','cancelled','kiv','intake']),
    (w_general, 'in_progress','In progress',    3, 'active',        true,  false, false, false, 5,    array['internal_review','blocked','waiting_client','ready','cancelled']),
    (w_general, 'internal_review','Internal review', 4, 'internal_review', false, true, true, false, 8, array['client_review','revision','in_progress','blocked']),
    (w_general, 'client_review','Client review', 5, 'client_review', false, true,  true,  false, null, array['approved','revision','blocked','waiting_client']),
    (w_general, 'revision',  'Revision',        6, 'revision',      true,  false, false, false, null, array['internal_review','client_review','approved','blocked']),
    (w_general, 'approved',  'Approved',        7, 'approved',      false, false, false, false, null, array['delivered','revision']),
    (w_general, 'delivered', 'Delivered',       8, 'delivered',     false, false, false, false, null, array['done','revision']),
    (w_general, 'done',      'Done',            9, 'done',          false, false, false, true,  null, array['revision','in_progress']),
    (w_general, 'blocked',   'Blocked',        10, 'blocked',       false, true,  false, false, null, array['ready','in_progress','internal_review','client_review','revision','cancelled']),
    (w_general, 'waiting_client','Waiting for client', 11, 'waiting', false, true, false, false, null, array['in_progress','client_review','revision','cancelled']),
    (w_general, 'kiv',       'KIV',            12, 'kiv',           false, true,  false, false, null, array['ready','intake','cancelled']),
    (w_general, 'cancelled', 'Cancelled',      13, 'cancelled',     false, false, false, true,  null, array['intake']);

  insert into public.ops_workflow_stages
    (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
     is_review, is_terminal, wip_guidance, next_stage_keys) values
    (w_video, 'intake',    'Intake',            1, 'intake',        false, false, false, false, null, array['ready','cancelled','kiv']),
    (w_video, 'ready',     'Ready',             2, 'ready',         false, false, false, false, null, array['shooting','editing','blocked','cancelled','kiv','intake']),
    (w_video, 'shooting',  'Shooting',          3, 'active',        true,  false, false, false, 3,    array['editing','blocked','ready','cancelled']),
    (w_video, 'editing',   'Editing',           4, 'active',        true,  false, false, false, 4,    array['internal_review','blocked','shooting','waiting_client']),
    (w_video, 'internal_review','Internal review', 5, 'internal_review', false, true, true, false, 6, array['client_review','revision','editing','blocked']),
    (w_video, 'client_review','Client review',   6, 'client_review', false, true,  true,  false, null, array['approved','revision','blocked','waiting_client']),
    (w_video, 'revision',  'Revision',          7, 'revision',      true,  false, false, false, null, array['internal_review','client_review','approved','blocked']),
    (w_video, 'approved',  'Approved',          8, 'approved',      false, false, false, false, null, array['delivered','revision']),
    (w_video, 'delivered', 'Delivered',         9, 'delivered',     false, false, false, false, null, array['done','revision']),
    (w_video, 'done',      'Done',             10, 'done',          false, false, false, true,  null, array['revision','editing']),
    (w_video, 'blocked',   'Blocked',          11, 'blocked',       false, true,  false, false, null, array['ready','shooting','editing','internal_review','client_review','revision','cancelled']),
    (w_video, 'waiting_client','Waiting for client', 12, 'waiting', false, true,  false, false, null, array['editing','client_review','revision','cancelled']),
    (w_video, 'kiv',       'KIV',              13, 'kiv',           false, true,  false, false, null, array['ready','intake','cancelled']),
    (w_video, 'cancelled', 'Cancelled',        14, 'cancelled',     false, false, false, true,  null, array['intake']);

  /* Offsets count backward from the publish date where there is one, and
     forward from today where there is not. They are the template's opening
     bid: the person naming the commitment can type over them, with a reason
     where the change departs from the template. */
  insert into public.ops_task_templates
    (name, deliverable_type, workflow_id, default_complexity,
     first_draft_offset_business_days, final_offset_business_days,
     default_estimate_minutes, required_fields, checklist) values
    ('Static post',   'static',  w_general, 'simple',   5, 2, 90,
      '{"language":true}'::jsonb,
      '["Brief read", "Copy approved internally", "Artwork exported"]'::jsonb),
    ('Carousel',      'carousel', w_general, 'standard', 6, 2, 180,
      '{"language":true}'::jsonb,
      '["Brief read", "Copy approved internally", "All frames exported"]'::jsonb),
    ('Report',        'report',  w_general, 'standard', 4, 1, 120,
      '{}'::jsonb, '["Figures checked", "Period stated"]'::jsonb),
    ('Short video',   'video',   w_video,   'standard', 7, 3, 300,
      '{"language":true,"complexity":true}'::jsonb,
      '["Script approved", "Footage backed up", "Subtitles checked", "Export settings checked"]'::jsonb),
    ('Reel',          'reel',    w_video,   'simple',   5, 2, 180,
      '{"language":true,"complexity":true}'::jsonb,
      '["Footage backed up", "Aspect ratio checked"]'::jsonb),
    ('Ad-hoc request','adhoc',   w_general, 'simple',   2, 1, 60,
      '{}'::jsonb, '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- 6. Every important write, server side.
--
--    Each one: confirms an active colleague, checks the one permission that
--    governs it, validates the transition against the workflow, refuses a
--    stale write, changes the row and files the event in one transaction,
--    and returns the task. A repeated call that plausibly happens twice is
--    answered with the first call's result rather than a second row.
-- ---------------------------------------------------------------------------

/* One place writes an event, so an event cannot arrive without its actor. */
create or replace function public.ops_log(
  p_task uuid, p_type text, p_from jsonb, p_to jsonb, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  insert into public.ops_task_events (task_id, event_type, actor_id, actor_email,
                                      from_value, to_value, detail)
  values (p_task, p_type, m.id, m.email, p_from, p_to, coalesce(p_detail, '{}'::jsonb));
end $$;

create or replace function public.ops_stage(p_workflow uuid, p_key text)
returns public.ops_workflow_stages
language sql stable security definer set search_path = public as $$
  select * from public.ops_workflow_stages
   where workflow_id = p_workflow and key = p_key limit 1
$$;

/* The task as the page reads it back: the row, its live assignees and the
   stage it is on, so a caller never has to make a second request to find out
   what its own write produced. */
create or replace function public.ops_task_json(p_task uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(t) || jsonb_build_object(
    'stage', to_jsonb(public.ops_stage(t.workflow_id, t.stage_key)),
    'assignees', coalesce((
      select jsonb_agg(jsonb_build_object(
               'team_member_id', a.team_member_id, 'name', tm.name,
               'responsibility', a.responsibility))
        from public.ops_task_assignees a
        join public.team_members tm on tm.id = a.team_member_id
       where a.task_id = t.id and a.ended_at is null), '[]'::jsonb))
  from public.ops_tasks t where t.id = p_task
$$;
grant execute on function public.ops_task_json(uuid) to authenticated;

-- 6.1 Create ------------------------------------------------------------------
create or replace function public.ops_create_task(p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  tpl   public.ops_task_templates;
  wf    uuid;
  tid   uuid;
  owner uuid;
  publish timestamptz;
  fd    timestamptz;
  fin   timestamptz;
  item  jsonb;
  i     integer := 0;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  if coalesce(p_payload ->> 'title', '') = '' then
    return jsonb_build_object('error', 'title-required');
  end if;
  if coalesce(p_payload ->> 'scope', 'client') = 'client'
     and (p_payload ->> 'client_id') is null then
    return jsonb_build_object('error', 'client-required');
  end if;

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
  end if;
  wf := coalesce((p_payload ->> 'workflow_id')::uuid, tpl.workflow_id,
                 (select id from public.ops_workflows where key = 'general'));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;

  publish := (p_payload ->> 'publish_at')::timestamptz;
  /* Backward from the publish date where the client has one, forward from
     today where they do not: a service with no publish date still owes an
     answer by the template's own target. */
  fd := coalesce((p_payload ->> 'first_draft_due_at')::timestamptz,
        case when publish is not null and tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.first_draft_offset_business_days)
             when tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.first_draft_offset_business_days)
        end);
  fin := coalesce((p_payload ->> 'final_due_at')::timestamptz,
        case when publish is not null and tpl.final_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.final_offset_business_days)
             when tpl.final_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.final_offset_business_days)
        end);

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality)
  values (
    coalesce(p_payload ->> 'scope', 'client'),
    (p_payload ->> 'client_id')::uuid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, 'intake',
    p_payload ->> 'title', p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'adhoc'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'))
  returning id into tid;

  owner := (p_payload ->> 'owner_id')::uuid;
  if owner is not null then
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (tid, owner, 'owner', m.id);
    perform public.ops_log(tid, 'assignment_changed', null,
      jsonb_build_object('owner_id', owner), '{}'::jsonb);
  end if;
  if (p_payload ->> 'reviewer_id') is not null then
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (tid, (p_payload ->> 'reviewer_id')::uuid, 'reviewer', m.id);
  end if;

  -- The template's checklist, in the order it states.
  if tpl.checklist is not null then
    for item in select * from jsonb_array_elements(tpl.checklist) loop
      i := i + 1;
      insert into public.ops_task_checklist_items (task_id, label, position)
      values (tid, item #>> '{}', i);
    end loop;
  end if;

  if (p_payload -> 'video') is not null then
    insert into public.ops_video_details (
      task_id, output_duration_seconds, footage_duration_seconds,
      subtitle_required, motion_graphics_required, aspect_ratios,
      script_ready, footage_ready, shoot_required, shoot_at, variant_count)
    values (tid,
      ((p_payload -> 'video') ->> 'output_duration_seconds')::integer,
      ((p_payload -> 'video') ->> 'footage_duration_seconds')::integer,
      coalesce(((p_payload -> 'video') ->> 'subtitle_required')::boolean, false),
      coalesce(((p_payload -> 'video') ->> 'motion_graphics_required')::boolean, false),
      coalesce((select array_agg(x) from jsonb_array_elements_text(
                 coalesce((p_payload -> 'video') -> 'aspect_ratios', '[]'::jsonb)) x), '{}'),
      ((p_payload -> 'video') ->> 'script_ready')::boolean,
      ((p_payload -> 'video') ->> 'footage_ready')::boolean,
      coalesce(((p_payload -> 'video') ->> 'shoot_required')::boolean, false),
      ((p_payload -> 'video') ->> 'shoot_at')::timestamptz,
      coalesce(((p_payload -> 'video') ->> 'variant_count')::integer, 1));
  end if;

  perform public.ops_log(tid, 'task_created', null,
    jsonb_build_object('title', p_payload ->> 'title',
                       'first_draft_due_at', fd, 'final_due_at', fin), '{}'::jsonb);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

-- 6.2 Move a stage -------------------------------------------------------------
create or replace function public.ops_transition_task(
  p_task uuid, p_next text, p_version integer default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cur public.ops_workflow_stages;
  nxt public.ops_workflow_stages;
  has_owner boolean;
  has_draft boolean;
  has_final boolean;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* A write made against a version somebody has already replaced is a write
     made from a stale screen. It is refused with the current row, so the
     page can say what changed rather than overwriting it. */
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if t.stage_key = p_next then return public.ops_task_json(p_task); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  if not (p_next = any (cur.next_stage_keys)) then
    return jsonb_build_object('error', 'bad-transition',
      'allowed', to_jsonb(cur.next_stage_keys));
  end if;

  -- What each gate needs before it opens.
  has_owner := exists (select 1 from public.ops_task_assignees
                        where task_id = p_task and responsibility = 'owner' and ended_at is null);
  has_draft := exists (select 1 from public.ops_task_links
                        where task_id = p_task and archived_at is null
                          and kind in ('draft', 'review'));
  has_final := exists (select 1 from public.ops_task_links
                        where task_id = p_task and archived_at is null and kind = 'final');

  if p_next = 'ready' and (not has_owner or t.current_final_due_at is null) then
    return jsonb_build_object('error', 'ready-needs-owner-and-due');
  end if;
  if p_next = 'editing' and exists (
       select 1 from public.ops_video_details v
        where v.task_id = p_task and v.footage_ready is false) then
    return jsonb_build_object('error', 'footage-not-ready');
  end if;
  if p_next = 'client_review' and not has_draft then
    return jsonb_build_object('error', 'needs-draft');
  end if;
  if p_next = 'delivered' and not has_final then
    return jsonb_build_object('error', 'needs-final-link');
  end if;
  if p_next = 'done' and t.delivered_at is null
     and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-delivery-or-reason');
  end if;

  update public.ops_tasks set
    stage_key = p_next,
    version = version + 1,
    updated_at = now(),
    first_draft_submitted_at = case
      when first_draft_submitted_at is null and nxt.is_review then now()
      else first_draft_submitted_at end,
    delivered_at = case when p_next = 'delivered' then coalesce(delivered_at, now())
                        else delivered_at end,
    completed_at = case when nxt.is_terminal and p_next <> 'cancelled' then coalesce(completed_at, now())
                        when not nxt.is_terminal then null
                        else completed_at end,
    cancelled_at = case when p_next = 'cancelled' then coalesce(cancelled_at, now())
                        else cancelled_at end,
    blocked_at = case when p_next = 'blocked' then blocked_at else null end,
    blocked_category = case when p_next = 'blocked' then blocked_category else null end
  where id = p_task;

  perform public.ops_log(p_task, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', p_next),
    case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end);
  if p_next = 'delivered' then
    perform public.ops_log(p_task, 'delivered', null, null, '{}'::jsonb);
  end if;
  if nxt.is_terminal and p_next <> 'cancelled' then
    perform public.ops_log(p_task, 'completed', null, null, '{}'::jsonb);
  end if;
  if p_next = 'cancelled' then
    perform public.ops_log(p_task, 'cancelled', null, null,
      jsonb_build_object('reason', p_note));
  end if;
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_transition_task(uuid, text, integer, text) to authenticated;

-- 6.3 Move a date ---------------------------------------------------------------
-- The order of the pair, stated once. Calendar days, not an interval: a person
-- reads "the day before", and comparing timestamps would refuse a draft set
-- for the morning of the day before a midnight final, which works perfectly.
create or replace function public.ops_due_order_ok(
  p_draft timestamptz, p_final timestamptz)
returns boolean
language sql immutable set search_path = public as $$
  select p_draft is null
      or p_final is null
      or p_draft::date <= (p_final::date - 1)
$$;
grant execute on function public.ops_due_order_ok(timestamptz, timestamptz) to authenticated;

create or replace function public.ops_change_due_date(
  p_task uuid, p_kind text, p_value timestamptz, p_reason text,
  p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_kind not in ('first_draft', 'final') then return jsonb_build_object('error', 'bad-kind'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  /* The pair as it would stand after this move, whichever end moved. Checked
     here and not only on the asking path, because `ops_decide_due_change`
     reaches this function directly once an extension is approved: a gate that
     lives only where the ask is raised is one an approval walks straight
     past. */
  if not public.ops_due_order_ok(
       case when p_kind = 'first_draft' then p_value else t.current_first_draft_due_at end,
       case when p_kind = 'final'       then p_value else t.current_final_due_at end) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  was := case when p_kind = 'final' then t.current_final_due_at
              else t.current_first_draft_due_at end;

  /* The original is written once, when the task is created, and never here.
     A report that can only measure the latest replan cannot see replanning. */
  update public.ops_tasks set
    current_final_due_at = case when p_kind = 'final' then p_value else current_final_due_at end,
    current_first_draft_due_at = case when p_kind = 'first_draft' then p_value else current_first_draft_due_at end,
    version = version + 1, updated_at = now()
  where id = p_task;

  perform public.ops_log(p_task, 'due_changed',
    jsonb_build_object('kind', p_kind, 'value', was),
    jsonb_build_object('kind', p_kind, 'value', p_value),
    jsonb_build_object('reason', p_reason, 'note', p_note));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_change_due_date(uuid, text, timestamptz, text, text, integer) to authenticated;

-- 6.4 Assign --------------------------------------------------------------------
create or replace function public.ops_assign_task(
  p_task uuid, p_owner uuid, p_contributors uuid[] default null,
  p_reviewer uuid default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was uuid;
  c   uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  /* Accountable ownership is the one assignment a member cannot hand
     themselves: it is what the whole queue is ordered by. */
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  select team_member_id into was from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null;

  if p_owner is not null and p_owner is distinct from was then
    /* The former owner stops seeing it as live work and keeps their place in
       its history: the row is ended, never deleted. */
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (p_task, p_owner, 'owner', m.id);
    perform public.ops_log(p_task, 'assignment_changed',
      jsonb_build_object('owner_id', was), jsonb_build_object('owner_id', p_owner), '{}'::jsonb);
  end if;

  if p_contributors is not null then
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'contributor' and ended_at is null
       and not (team_member_id = any (p_contributors));
    foreach c in array p_contributors loop
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, c, 'contributor', m.id)
      on conflict do nothing;
    end loop;
    perform public.ops_log(p_task, 'contributor_changed', null,
      jsonb_build_object('contributors', to_jsonb(p_contributors)), '{}'::jsonb);
  end if;

  if p_reviewer is not null then
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'reviewer' and ended_at is null
       and team_member_id <> p_reviewer;
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (p_task, p_reviewer, 'reviewer', m.id)
    on conflict do nothing;
    perform public.ops_log(p_task, 'reviewer_changed', null,
      jsonb_build_object('reviewer_id', p_reviewer), '{}'::jsonb);
  end if;

  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_assign_task(uuid, uuid, uuid[], uuid, integer) to authenticated;

-- 6.5 Blocked ---------------------------------------------------------------------
create or replace function public.ops_set_blocked(
  p_task uuid, p_category text, p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.ops_tasks;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_category, '') = '' then return jsonb_build_object('error', 'category-required'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  update public.ops_tasks set
    stage_key = 'blocked', blocked_category = p_category, blocked_note = p_note,
    blocked_at = now(), version = version + 1, updated_at = now()
  where id = p_task;
  perform public.ops_log(p_task, 'blocked',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', 'blocked'),
    jsonb_build_object('category', p_category, 'note', p_note));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_set_blocked(uuid, text, text, integer) to authenticated;

create or replace function public.ops_clear_blocked(
  p_task uuid, p_next text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.ops_tasks; res jsonb;
begin
  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.stage_key <> 'blocked' then return jsonb_build_object('error', 'not-blocked'); end if;
  res := public.ops_transition_task(p_task, p_next, p_version, null);
  if res ? 'error' then return res; end if;
  perform public.ops_log(p_task, 'unblocked',
    jsonb_build_object('category', t.blocked_category),
    jsonb_build_object('stage_key', p_next), '{}'::jsonb);
  return res;
end $$;
grant execute on function public.ops_clear_blocked(uuid, text, integer) to authenticated;

-- 6.6 Work sessions -----------------------------------------------------------------
create or replace function public.ops_start_work(p_task uuid, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  open_id uuid;
  sid  uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'view') then return jsonb_build_object('error', 'denied'); end if;

  /* One open session a person, across every task. A second start on the same
     task is the same start; a start on another task closes the first and
     says so, rather than leaving two clocks running. */
  select id into open_id from public.ops_work_sessions
   where team_member_id = m.id and ended_at is null;
  if open_id is not null then
    if exists (select 1 from public.ops_work_sessions
                where id = open_id and task_id = p_task) then
      return jsonb_build_object('session_id', open_id, 'already_open', true);
    end if;
    perform public.ops_stop_work(open_id, 'Stopped by starting another task');
  end if;

  insert into public.ops_work_sessions (task_id, team_member_id, started_at)
  values (p_task, m.id, now()) returning id into sid;
  perform public.ops_log(p_task, 'work_started', null,
    jsonb_build_object('session_id', sid), '{}'::jsonb);
  return jsonb_build_object('session_id', sid, 'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_start_work(uuid, text) to authenticated;

create or replace function public.ops_stop_work(p_session uuid, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  s public.ops_work_sessions;
  mins integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into s from public.ops_work_sessions where id = p_session for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* A session belongs to the person who did the work, not to the task's
     owner, so only they or a corrector may close it. */
  if s.team_member_id <> m.id and not public.ops_granted('ops.time', 'manage') then
    return jsonb_build_object('error', 'denied');
  end if;
  if s.ended_at is not null then return jsonb_build_object('session_id', s.id, 'minutes', s.minutes); end if;

  mins := greatest(0, (extract(epoch from (now() - s.started_at)) / 60)::integer);
  update public.ops_work_sessions
     set ended_at = now(), minutes = mins, note = coalesce(p_note, note)
   where id = p_session;
  perform public.ops_log(s.task_id, 'work_stopped', null,
    jsonb_build_object('session_id', s.id, 'minutes', mins),
    case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end);
  return jsonb_build_object('session_id', s.id, 'minutes', mins);
end $$;
grant execute on function public.ops_stop_work(uuid, text) to authenticated;

create or replace function public.ops_correct_work_session(
  p_session uuid, p_started timestamptz, p_ended timestamptz, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  s public.ops_work_sessions;
  mins integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into s from public.ops_work_sessions where id = p_session for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if s.team_member_id <> m.id and not public.ops_granted('ops.time', 'manage') then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_ended is not null and p_ended < p_started then
    return jsonb_build_object('error', 'ends-before-it-starts');
  end if;

  mins := case when p_ended is null then null
               else greatest(0, (extract(epoch from (p_ended - p_started)) / 60)::integer) end;
  update public.ops_work_sessions set
    started_at = p_started, ended_at = p_ended, minutes = mins,
    corrected_at = now(), corrected_by = m.id, correction_reason = p_reason,
    source = 'corrected'
  where id = p_session;
  /* The value before the correction stays in the event, so a corrected hour
     is a change somebody made and not a number that was always so. */
  perform public.ops_log(s.task_id, 'work_corrected',
    jsonb_build_object('started_at', s.started_at, 'ended_at', s.ended_at, 'minutes', s.minutes),
    jsonb_build_object('started_at', p_started, 'ended_at', p_ended, 'minutes', mins),
    jsonb_build_object('reason', p_reason, 'session_id', s.id));
  return jsonb_build_object('session_id', s.id, 'minutes', mins);
end $$;
grant execute on function public.ops_correct_work_session(uuid, timestamptz, timestamptz, text) to authenticated;

create or replace function public.ops_add_work_session(
  p_task uuid, p_started timestamptz, p_ended timestamptz, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; sid uuid; mins integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if p_ended < p_started then return jsonb_build_object('error', 'ends-before-it-starts'); end if;
  mins := greatest(0, (extract(epoch from (p_ended - p_started)) / 60)::integer);
  insert into public.ops_work_sessions (task_id, team_member_id, started_at, ended_at, minutes, note, source)
  values (p_task, m.id, p_started, p_ended, mins, p_note, 'manual') returning id into sid;
  perform public.ops_log(p_task, 'work_stopped', null,
    jsonb_build_object('session_id', sid, 'minutes', mins, 'manual', true), '{}'::jsonb);
  return jsonb_build_object('session_id', sid, 'minutes', mins);
end $$;
grant execute on function public.ops_add_work_session(uuid, timestamptz, timestamptz, text) to authenticated;

-- 6.7 Revisions -----------------------------------------------------------------------
create or replace function public.ops_request_revision(
  p_task uuid, p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  rid uuid;
  rnd integer;
  src uuid := (p_payload ->> 'source_review_id')::uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_payload ->> 'reason_category', '') = '' then
    return jsonb_build_object('error', 'reason-required');
  end if;

  -- Retry safe on both keys: the caller's own, and the review version, since
  -- one client decision must never open two rounds.
  if p_idem is not null then
    select id into rid from public.ops_revisions where idem_key = p_idem;
    if rid is not null then return jsonb_build_object('revision_id', rid, 'task', public.ops_task_json(p_task)); end if;
  end if;
  if src is not null then
    select id into rid from public.ops_revisions where task_id = p_task and source_review_id = src;
    if rid is not null then return jsonb_build_object('revision_id', rid, 'task', public.ops_task_json(p_task)); end if;
  end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select coalesce(max(round_no), 0) + 1 into rnd from public.ops_revisions where task_id = p_task;

  insert into public.ops_revisions (
    task_id, round_no, requested_by_type, reason_category, summary,
    requested_by, assigned_to, source_review_id, idem_key)
  values (p_task, rnd,
    coalesce(p_payload ->> 'requested_by_type', 'internal'),
    p_payload ->> 'reason_category', p_payload ->> 'summary', m.id,
    coalesce((p_payload ->> 'assigned_to')::uuid,
             (select team_member_id from public.ops_task_assignees
               where task_id = p_task and responsibility = 'owner' and ended_at is null)),
    src, p_idem)
  returning id into rid;

  if 'revision' = any ((public.ops_stage(t.workflow_id, t.stage_key)).next_stage_keys) then
    update public.ops_tasks set stage_key = 'revision', version = version + 1, updated_at = now()
     where id = p_task;
    perform public.ops_log(p_task, 'stage_changed',
      jsonb_build_object('stage_key', t.stage_key),
      jsonb_build_object('stage_key', 'revision'), '{}'::jsonb);
  end if;
  perform public.ops_log(p_task, 'revision_requested', null,
    jsonb_build_object('revision_id', rid, 'round_no', rnd),
    jsonb_build_object('reason', p_payload ->> 'reason_category',
                       'by', coalesce(p_payload ->> 'requested_by_type', 'internal')));
  return jsonb_build_object('revision_id', rid, 'round_no', rnd, 'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_request_revision(uuid, jsonb, text) to authenticated;

create or replace function public.ops_complete_revision(p_revision uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.ops_revisions;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.ops_revisions where id = p_revision for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(r.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if r.completed_at is not null then return jsonb_build_object('revision_id', r.id); end if;
  update public.ops_revisions set completed_at = now() where id = p_revision;
  perform public.ops_log(r.task_id, 'revision_completed', null,
    jsonb_build_object('revision_id', r.id, 'round_no', r.round_no), '{}'::jsonb);
  return jsonb_build_object('revision_id', r.id);
end $$;
grant execute on function public.ops_complete_revision(uuid) to authenticated;

/* The client's own decision, arriving from Content Review. Version specific
   and retry safe: the same review version delivered twice records one
   approval or one revision round, never two. */
create or replace function public.ops_record_review_decision(
  p_task uuid, p_review uuid, p_approved boolean, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.ops_tasks;
begin
  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_approved then
    if exists (select 1 from public.ops_task_events
                where task_id = p_task and event_type = 'approval_recorded'
                  and (to_value ->> 'review_id')::uuid = p_review) then
      return public.ops_task_json(p_task);
    end if;
    perform public.ops_log(p_task, 'approval_recorded', null,
      jsonb_build_object('review_id', p_review), jsonb_build_object('note', p_note));
    if t.stage_key = 'client_review' then
      update public.ops_tasks set stage_key = 'approved', version = version + 1, updated_at = now()
       where id = p_task;
      perform public.ops_log(p_task, 'stage_changed',
        jsonb_build_object('stage_key', 'client_review'),
        jsonb_build_object('stage_key', 'approved'), '{}'::jsonb);
    end if;
    return public.ops_task_json(p_task);
  end if;
  return public.ops_request_revision(p_task, jsonb_build_object(
    'requested_by_type', 'client', 'reason_category', 'client_preference',
    'summary', p_note, 'source_review_id', p_review), null);
end $$;

-- 6.8 Finish, reopen, tidy -------------------------------------------------------------
create or replace function public.ops_complete_task(
  p_task uuid, p_final_link text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; t public.ops_tasks; missing integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  select count(*) into missing from public.ops_task_checklist_items
   where task_id = p_task and required and completed_at is null;
  if missing > 0 then
    return jsonb_build_object('error', 'checklist-incomplete', 'missing', missing);
  end if;

  if p_final_link is not null and p_final_link <> '' then
    insert into public.ops_task_links (task_id, kind, label, url, created_by)
    values (p_task, 'final', 'Final deliverable', p_final_link, m.id);
    perform public.ops_log(p_task, 'file_added', null,
      jsonb_build_object('kind', 'final', 'url', p_final_link), '{}'::jsonb);
  end if;

  update public.ops_tasks set
    stage_key = 'done', delivered_at = coalesce(delivered_at, now()),
    completed_at = coalesce(completed_at, now()),
    version = version + 1, updated_at = now()
  where id = p_task;
  perform public.ops_log(p_task, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', 'done'), '{}'::jsonb);
  perform public.ops_log(p_task, 'completed', null, null, '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_complete_task(uuid, text, integer) to authenticated;

create or replace function public.ops_reopen_task(
  p_task uuid, p_reason text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.ops_tasks;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  update public.ops_tasks set
    stage_key = 'revision', completed_at = null,
    version = version + 1, updated_at = now()
  where id = p_task;
  perform public.ops_log(p_task, 'reopened',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', 'revision'), jsonb_build_object('reason', p_reason));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_reopen_task(uuid, text, integer) to authenticated;

/* Archive is list hygiene and reverses. Cancel is a business outcome and is
   a stage. Neither is a deletion: a task is never removed from this table by
   the console. */
create or replace function public.ops_archive_task(p_task uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  update public.ops_tasks set archived_at = case when p_on then now() else null end,
                              version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, case when p_on then 'archived' else 'restored' end,
    null, null, '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_archive_task(uuid, boolean) to authenticated;

-- 6.9 Recurring ----------------------------------------------------------------------
create or replace function public.ops_generate_recurring(
  p_period text, p_rules uuid[] default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  r     public.ops_recurring_rules;
  made  integer := 0;
  skip  integer := 0;
  key   text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('ops.workflows', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;

  for r in select * from public.ops_recurring_rules
            where active and (p_rules is null or id = any (p_rules)) loop
    /* A rule makes one task a period, whoever presses the button and however
       many times. The key is the rule and the period, so a second press is
       counted as skipped rather than filed as a second task. */
    key := 'recur:' || r.id::text || ':' || p_period;
    if exists (select 1 from public.ops_tasks where idem_key = key) then
      skip := skip + 1;
      continue;
    end if;
    perform public.ops_create_task(jsonb_build_object(
      'scope', case when r.client_id is null then 'internal' else 'client' end,
      'client_id', r.client_id,
      'template_id', r.template_id,
      'title', r.name || ' — ' || p_period,
      'owner_id', r.owner_id,
      'publish_at', case when r.day_of_month is null then null
        else ((p_period || '-' || lpad(r.day_of_month::text, 2, '0'))::date)::timestamptz end
    ), key);
    made := made + 1;
    update public.ops_recurring_rules set last_generated_period = p_period, updated_at = now()
     where id = r.id;
  end loop;
  return jsonb_build_object('created', made, 'skipped', skip, 'period', p_period);
end $$;
grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;

/* Functions this migration adds, for the rollback at the head of the file:
     ops_granted, ops_me, ops_add_business_days, ops_may_see_task, ops_log, ops_stage,
     ops_task_json, ops_create_task, ops_transition_task, ops_change_due_date,
     ops_assign_task, ops_set_blocked, ops_clear_blocked, ops_start_work,
     ops_stop_work, ops_correct_work_session, ops_add_work_session,
     ops_request_revision, ops_complete_revision, ops_record_review_decision,
     ops_complete_task, ops_reopen_task, ops_archive_task,
     ops_generate_recurring. */

-- ===========================================================================
-- THE OPERATIONS SYSTEM, PHASE 2 — the writes the console needs to drive the
-- stage machine from a page.
--
-- Phase 1 shipped the data model, the read policies and every write that
-- moves a task. Three of its gates are data the page had no way to set:
--
--   Client review is refused without a draft or review link.
--   Delivered is refused without a final link.
--   Editing is refused while the footage is marked not ready.
--
-- There was no function that adds a link, ticks a checklist item, or records
-- that footage is ready, so a task created in the console could reach Ready
-- and stop. These four are that, and nothing else: no table, column, policy
-- or permission changes, and every one asks the same questions every other
-- write in section 6 asks — an active colleague, the one permission that
-- governs it, the task is theirs to see, the version is not stale — and
-- files its event in the same transaction.
--
-- Safe to run twice. Nothing here is a data migration.
--
-- Rollback:
--   drop function if exists public.ops_add_link(uuid, text, text, text, integer);
--   drop function if exists public.ops_set_link_archived(uuid, boolean);
--   drop function if exists public.ops_set_checklist(uuid, boolean);
--   drop function if exists public.ops_set_video(uuid, jsonb);
-- ===========================================================================

-- 7.1 Links ------------------------------------------------------------------
/* A link is the evidence a stage gate asks for, so adding one is a write the
   database owns like any other: the page cannot insert a row that says a
   draft exists. `kind` is closed, because `ops_transition_task` reads exactly
   these words and a typo would be a draft nobody can find. */
create or replace function public.ops_add_link(
  p_task uuid, p_kind text, p_label text, p_url text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  lid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind not in ('brief', 'draft', 'review', 'final', 'asset', 'other') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if coalesce(trim(p_url), '') = '' then return jsonb_build_object('error', 'url-required'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  insert into public.ops_task_links (task_id, kind, label, url, created_by)
  values (p_task, p_kind,
          coalesce(nullif(trim(p_label), ''), initcap(p_kind) || ' link'),
          trim(p_url), m.id)
  returning id into lid;

  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'file_added', null,
    jsonb_build_object('link_id', lid, 'kind', p_kind, 'url', trim(p_url)), '{}'::jsonb);
  return jsonb_build_object('link_id', lid, 'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_add_link(uuid, text, text, text, integer) to authenticated;

/* Taking a link off is a soft remove with a way back, which is this portal's
   law for anything a person can attach, so it is one function and `p_on`
   false is the Undo. Removing the draft link shuts the Client review gate
   again, which is the point: the gate reads the live rows. */
create or replace function public.ops_set_link_archived(p_link uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.ops_task_links;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into l from public.ops_task_links where id = p_link for update;
  if l.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(l.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  update public.ops_task_links
     set archived_at = case when p_on then now() else null end
   where id = p_link;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = l.task_id;
  perform public.ops_log(l.task_id,
    case when p_on then 'file_removed' else 'file_restored' end, null,
    jsonb_build_object('link_id', l.id, 'kind', l.kind, 'label', l.label), '{}'::jsonb);
  return jsonb_build_object('link_id', l.id, 'archived', p_on,
                            'task', public.ops_task_json(l.task_id));
end $$;
grant execute on function public.ops_set_link_archived(uuid, boolean) to authenticated;

-- 7.2 Checklist ----------------------------------------------------------------
/* A tick is a statement that something was done, so it records who made it
   and when, and untickings are kept in the events rather than erased: a
   checklist that can be cleared with no trace is one nobody can rely on. */
create or replace function public.ops_set_checklist(p_item uuid, p_done boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; c public.ops_task_checklist_items;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into c from public.ops_task_checklist_items where id = p_item for update;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(c.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  update public.ops_task_checklist_items set
    completed_at = case when p_done then coalesce(completed_at, now()) else null end,
    completed_by = case when p_done then coalesce(completed_by, m.id) else null end
  where id = p_item;

  perform public.ops_log(c.task_id, 'checklist_changed',
    jsonb_build_object('label', c.label, 'done', c.completed_at is not null),
    jsonb_build_object('label', c.label, 'done', p_done), '{}'::jsonb);
  return (select to_jsonb(x) from public.ops_task_checklist_items x where x.id = p_item);
end $$;
grant execute on function public.ops_set_checklist(uuid, boolean) to authenticated;

-- 7.3 Video readiness ------------------------------------------------------------
/* Editing is refused while footage is marked not ready, and the mark had no
   control. The row is created on demand, because a task can be moved onto
   the video workflow after it was made and then has no `ops_video_details`
   row at all; a key the payload does not carry is left as it stands, so
   ticking footage cannot blank a duration somebody typed. */
create or replace function public.ops_set_video(p_task uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; v public.ops_video_details;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.ops_tasks where id = p_task) then
    return jsonb_build_object('error', 'not-found');
  end if;

  insert into public.ops_video_details (task_id) values (p_task)
  on conflict (task_id) do nothing;
  select * into v from public.ops_video_details where task_id = p_task for update;

  update public.ops_video_details set
    output_duration_seconds  = coalesce((p_payload ->> 'output_duration_seconds')::integer, output_duration_seconds),
    footage_duration_seconds = coalesce((p_payload ->> 'footage_duration_seconds')::integer, footage_duration_seconds),
    subtitle_required        = coalesce((p_payload ->> 'subtitle_required')::boolean, subtitle_required),
    motion_graphics_required = coalesce((p_payload ->> 'motion_graphics_required')::boolean, motion_graphics_required),
    script_ready             = coalesce((p_payload ->> 'script_ready')::boolean, script_ready),
    footage_ready            = coalesce((p_payload ->> 'footage_ready')::boolean, footage_ready),
    shoot_required           = coalesce((p_payload ->> 'shoot_required')::boolean, shoot_required),
    shoot_at                 = coalesce((p_payload ->> 'shoot_at')::timestamptz, shoot_at),
    variant_count            = coalesce((p_payload ->> 'variant_count')::integer, variant_count)
  where task_id = p_task;

  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'video_changed',
    jsonb_build_object('script_ready', v.script_ready, 'footage_ready', v.footage_ready),
    p_payload, '{}'::jsonb);
  return (select to_jsonb(x) from public.ops_video_details x where x.task_id = p_task);
end $$;
grant execute on function public.ops_set_video(uuid, jsonb) to authenticated;

-- ===========================================================================
-- THE OPERATIONS SYSTEM, PHASE 3 — the record tells the person it concerns.
--
-- Phase 1 made `ops_notifications`, a select policy on it and the one direct
-- write a browser may make (marking its own row read), and nothing ever wrote
-- a row. Phase 3 puts the console's board, calendar and bell on the page, so
-- the rows have to exist.
--
-- They are written where every event is already written. `ops_log` is the one
-- function every write in section 6 files its event through, so it is the one
-- place that knows the task, the kind of change and who made it; a second
-- call beside each `ops_log` in fourteen functions would be fourteen chances
-- to forget one, and the day somebody added a fifteenth write it would notify
-- nobody. The rule is stated once here:
--
--   The accountable owner is told about a change to their task that somebody
--   else made. A person is never told about their own act, and a change to
--   a task with no owner tells nobody, because there is nobody to tell.
--   A new owner is told they were assigned, whoever assigned them.
--
-- Nothing else changes. No table, column, policy or permission is added; the
-- events themselves are written exactly as before, and a notification is one
-- row beside the event, keyed so that the same change filed twice inside a
-- minute is one row and not two.
--
-- Safe to run twice. Nothing here is a data migration.
--
-- Rollback (restores phase 1's `ops_log`, which files the event and nothing else):
--   drop function if exists public.ops_notify(uuid, uuid, text, text, text, text);
--   create or replace function public.ops_log(
--     p_task uuid, p_type text, p_from jsonb, p_to jsonb, p_detail jsonb default '{}'::jsonb)
--   returns void language plpgsql security definer set search_path = public as $$
--   declare m public.team_members;
--   begin
--     m := public.ops_me();
--     insert into public.ops_task_events (task_id, event_type, actor_id, actor_email,
--                                         from_value, to_value, detail)
--     values (p_task, p_type, m.id, m.email, p_from, p_to, coalesce(p_detail, '{}'::jsonb));
--   end $$;
-- ===========================================================================

-- 8.1 One row, addressed to one person --------------------------------------------
/* A notification is written by the database and read by the person it names.
   The dedupe key is what makes a double press one row: the browser retries a
   write, or a person moves a stage and moves it back inside a minute, and the
   owner is told once. */
create or replace function public.ops_notify(
  p_member uuid, p_task uuid, p_kind text, p_title text, p_body text, p_dedupe text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_member is null then return; end if;
  insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
  values (p_member, p_task, p_kind, p_title, p_body, p_dedupe)
  on conflict (dedupe_key) do nothing;
end $$;

-- 8.2 The event, and the person it concerns ---------------------------------------
create or replace function public.ops_log(
  p_task uuid, p_type text, p_from jsonb, p_to jsonb, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  t      public.ops_tasks;
  owner  uuid;
  who    text;
  body   text;
  st     public.ops_workflow_stages;
begin
  m := public.ops_me();
  insert into public.ops_task_events (task_id, event_type, actor_id, actor_email,
                                      from_value, to_value, detail)
  values (p_task, p_type, m.id, m.email, p_from, p_to, coalesce(p_detail, '{}'::jsonb));

  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return; end if;
  who := coalesce(nullif(m.name, ''), m.email, 'Somebody');

  /* Assignment tells the new owner, whoever made it, except where the new
     owner is the person assigning: somebody taking a task for themselves
     already knows. */
  if p_type = 'assignment_changed' then
    owner := (p_to ->> 'owner_id')::uuid;
    if owner is not null and owner is distinct from m.id then
      perform public.ops_notify(owner, p_task, 'assigned',
        'T' || t.task_no || ' · ' || t.title,
        'Assigned to you by ' || who || '.',
        'assigned:' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
    end if;
    return;
  end if;

  /* Every other change tells the accountable owner, and only where somebody
     else made it. What is said is the change in the team's words, never the
     event's key. */
  select team_member_id into owner from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null
   limit 1;
  if owner is null or owner = m.id then return; end if;

  if p_type = 'stage_changed' then
    st := public.ops_stage(t.workflow_id, p_to ->> 'stage_key');
    body := 'Moved to ' || coalesce(st.label, p_to ->> 'stage_key') || ' by ' || who || '.';
  elsif p_type = 'due_changed' then
    body := 'The ' || case when p_to ->> 'kind' = 'final' then 'final' else 'first draft' end
      || ' date moved to ' || to_char((p_to ->> 'value')::timestamptz, 'DD Mon YYYY')
      || ' by ' || who || '.';
  elsif p_type = 'blocked' then
    body := 'Marked blocked by ' || who || ': '
      || coalesce(p_detail ->> 'category', 'reason not given') || '.';
  elsif p_type = 'unblocked' then
    body := 'Unblocked by ' || who || '.';
  elsif p_type = 'revision_requested' then
    body := 'A revision was requested by ' || who || '.';
  elsif p_type = 'approval_recorded' then
    body := 'A review decision was recorded by ' || who || '.';
  elsif p_type = 'reopened' then
    body := 'Reopened by ' || who || '.';
  elsif p_type = 'cancelled' then
    body := 'Cancelled by ' || who || '.';
  else
    return;
  end if;

  perform public.ops_notify(owner, p_task, p_type,
    'T' || t.task_no || ' · ' || t.title, body,
    p_type || ':' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
end $$;

-- ==========================================================================
-- MY WORK: DELETING A TASK
-- 2026-09-22. Safe to run twice. Rollback at the foot.
--
-- Archive is list hygiene and reverses; Cancel is a business outcome and is a
-- stage. Neither removes a row, and until now nothing did: a task keyed in
-- twice, or against the wrong client, stayed in the database for ever and the
-- console offered no way out of it. That is the same case a client record has
-- (`delete_client`, "for the lead keyed in twice"), so it takes the same
-- shape: the section's Manage level, the thing's own identifier typed back,
-- a reason, no restore, and a row in the activity record naming what went —
-- because the task's own events go with it.
--
-- Everything hanging off a task already cascades (checklist, links, events,
-- assignees, work sessions, video details, revisions, notifications), and a
-- task generated from this one as a parent is set null rather than removed,
-- so a series survives the removal of one of its members.
-- ==========================================================================

create or replace function public.ops_delete_task(
  p_task uuid, p_confirm text, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cl  text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  /* A permission can be taken away while the sheet is open, so the level is
     asked again when the button is pressed and not only when it was drawn. */
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  /* The number typed back, because a deletion with no way back is agreed to
     and never merely clicked. */
  if coalesce(p_confirm, '') <> 'T' || t.task_no::text then
    return jsonb_build_object('error', 'confirm-required');
  end if;

  select c.name into cl from public.clients c where c.id = t.client_id;

  /* The record outlives the row, and it is the only place this deletion can
     be read afterwards: the task's own events are about to be cascaded. */
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.deleted',
          'T' || t.task_no::text,
          t.title ||
          coalesce(' · ' || cl, case when t.scope = 'internal' then ' · Internal' else '' end) ||
          coalesce(' · ' || nullif(btrim(p_reason), ''), ''));

  delete from public.ops_tasks where id = p_task;
  return jsonb_build_object('deleted', true, 'task_no', t.task_no);
end $$;
grant execute on function public.ops_delete_task(uuid, text, text) to authenticated;

-- Rollback:
--   drop function if exists public.ops_delete_task(uuid, text, text);

-- ==========================================================================
-- THE ACTIVITY RECORD, SECTION BY SECTION
-- 2026-09-22. Safe to run twice. Rollback at the foot.
--
-- The Activity record is already read section by section on the page — the
-- tab strip is Clients, My Work, Team, Content Review, Creator Campaigns,
-- Short Links, Documents, Services — but its access was one switch over all
-- of them, so opening Creator Campaigns' log to the team meant opening every
-- client's billing change and every letter with it. Asked for by the user on
-- 2026-09-22.
--
-- The ladder already has the shape for this: a part is an exception to its
-- section, and answers with its section's level where none is set. So
-- `activity.campaigns` at View over `activity` at No access is a group that
-- reads one log and no other, and a group that never opened the fold is
-- exactly where it was.
--
-- What the policy needs, and did not have, is the map from a tag to the
-- section the console files it under. That map lives in `ACTION_LABEL` in
-- `js/admin.js`, and about thirty of its entries do not follow their tag's
-- prefix (`client.handles` is Content Review, `service.override` is Clients),
-- so it cannot be derived. It is restated here, and `tests/sql.js` reads both
-- copies and fails on any difference — the same guard the operations schema
-- and its migration are held to, because two copies of a map drift the way
-- two copies of a colour do.
--
-- A tag with no entry answers `other`, which has no part, so it falls back to
-- the section: a row written by something added next year is read by whoever
-- can read the record, never silently hidden from everybody.
-- ==========================================================================

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.withdrawn', 'creator.added',
                    'creator.off', 'creator.on', 'creator.removed', 'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.stage', 'client.touch',
                    'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored', 'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'set.created', 'set.deleted', 'set.published', 'set.renamed',
                    'set.withdrawn') then 'review'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

-- The record is read a section at a time. `allowed()` answers a part with its
-- own level where one is set and its section's where none is, so a group with
-- `{"activity":"view"}` and nothing else reads exactly what it read before.
drop policy if exists activity_read on public.activity_log;
create policy activity_read on public.activity_log
  for select to authenticated
  using (public.allowed('activity.' || public.activity_section(action), 'view'));

-- Rollback:
--   drop policy if exists activity_read on public.activity_log;
--   create policy activity_read on public.activity_log
--     for select to authenticated using (public.allowed('activity', 'view'));
--   drop function if exists public.activity_section(text);

-- ==========================================================================
-- AN EXTENSION IS ASKED FOR, NOT TAKEN
-- 2026-09-20. Safe to run twice. Rollback at the foot.
--
-- `ops_change_due_date` moved a commitment the moment somebody pressed it, so
-- the person who created the task and put the date on it found out afterwards,
-- from a notification, about a deadline that had already moved. The user asked
-- for the round that was missing: A creates the task and assigns it to B; B
-- asking to move the date raises a request back to A, and the date moves when
-- A approves it and not before.
--
-- WHAT IS DELIBERATELY NOT CHANGED
--   * A person moving a date on a task THEY created still moves it at once.
--     An approval round with one name on both ends is a form, not a control.
--   * The first draft date is not gated. It is the team's own internal
--     milestone; the commitment a client is owed is the final due date, and
--     that is the one an extension is about.
--   * `ops_change_due_date` keeps its signature and its behaviour, so every
--     existing caller, the original-commitment rule and the event it files
--     are untouched. The approval path calls it once A has said yes.
--
-- The request carries the reason category the date sheet already asks for, so
-- nothing new is asked of the person raising it.
-- ==========================================================================

create table if not exists public.ops_due_requests (
  id            uuid primary key default gen_random_uuid(),
  task_id       uuid not null references public.ops_tasks(id) on delete cascade,
  kind          text not null check (kind in ('first_draft', 'final')),
  -- What the date is now, kept so the decision can be read long afterwards
  -- without replaying the task's events.
  was_at        timestamptz,
  wants_at      timestamptz not null,
  reason        text not null,
  note          text,
  asked_by      uuid not null references public.team_members(id),
  asked_at      timestamptz not null default now(),
  -- Who it went to. Stored rather than derived, because a task's creator can
  -- be stood down and the request still has to say who was asked.
  decider_id    uuid references public.team_members(id),
  state         text not null default 'asked' check (state in ('asked', 'approved', 'declined', 'withdrawn')),
  decided_by    uuid references public.team_members(id),
  decided_at    timestamptz,
  decide_note   text
);
create index if not exists ops_due_requests_task_idx on public.ops_due_requests(task_id);
create index if not exists ops_due_requests_decider_idx on public.ops_due_requests(decider_id) where state = 'asked';
/* One open request a task and a kind: a second press is the same ask, and two
   open requests over one date is a question with two answers. */
create unique index if not exists ops_due_requests_open_uidx
  on public.ops_due_requests(task_id, kind) where state = 'asked';

alter table public.ops_due_requests enable row level security;
drop policy if exists ops_due_requests_read on public.ops_due_requests;
/* Read only, like every other ops table: the two writes below are functions,
   so a browser cannot approve its own extension whatever it sends. Visible to
   whoever may already see the task. */
create policy ops_due_requests_read on public.ops_due_requests
  for select to authenticated using (public.ops_may_see_task(task_id));

-- Who an extension on this task is asked of: the person who created it.
-- Who decides, per kind. The first draft date is the team's own milestone and
-- has no decider, so it falls through to the move; the final date is the
-- client's commitment and keeps the round. One argument was not enough to say
-- that, and two candidates for one name is how `issue_letter` came to have two
-- signatures for one call, so the old form is dropped rather than kept.
drop function if exists public.ops_due_decider(uuid);
create or replace function public.ops_due_decider(p_task uuid, p_kind text)
returns uuid
language sql security definer stable set search_path = public as $$
  select case when p_kind = 'first_draft' then null
              else (select t.created_by from public.ops_tasks t where t.id = p_task)
         end
$$;
grant execute on function public.ops_due_decider(uuid, text) to authenticated;

-- 1. Asking.
create or replace function public.ops_request_due_change(
  p_task uuid, p_kind text, p_value timestamptz, p_reason text,
  p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  t     public.ops_tasks;
  who   uuid;
  was   timestamptz;
  v_id  uuid;
  nm    text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_kind not in ('first_draft', 'final') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_value is null then return jsonb_build_object('error', 'no-date'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  /* Refused before an ask is raised as well as before a move is made: an ask
     nobody could approve without breaking the plan is one to turn away at the
     door, with the word the move itself would have used. */
  if not public.ops_due_order_ok(
       case when p_kind = 'first_draft' then p_value else t.current_first_draft_due_at end,
       case when p_kind = 'final'       then p_value else t.current_final_due_at end) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  who := public.ops_due_decider(p_task, p_kind);
  /* Nobody to ask — the team's own first draft milestone, or a task whose
     creator is the person asking — so the move is theirs to make and the
     round would be a form with one name on both ends. */
  if who is null or who = m.id then
    return public.ops_change_due_date(p_task, p_kind, p_value, p_reason, p_note, p_version);
  end if;

  was := case when p_kind = 'final' then t.current_final_due_at
              else t.current_first_draft_due_at end;

  insert into public.ops_due_requests
    (task_id, kind, was_at, wants_at, reason, note, asked_by, decider_id)
  values (p_task, p_kind, was, p_value, p_reason, nullif(btrim(p_note), ''), m.id, who)
  on conflict (task_id, kind) where state = 'asked' do nothing
  returning id into v_id;

  /* The same press twice is the same ask. The open one is handed back so the
     page can say it is already with somebody. */
  if v_id is null then
    select id into v_id from public.ops_due_requests
      where task_id = p_task and kind = p_kind and state = 'asked';
    return jsonb_build_object('ok', true, 'repeat', true, 'request', v_id,
                              'task', public.ops_task_json(p_task));
  end if;

  select name into nm from public.team_members where id = m.id;
  perform public.ops_notify(who, p_task, 'due_requested',
    'Extension requested',
    coalesce(nm, 'Somebody') || ' asked to move ' ||
      case when p_kind = 'final' then 'the due date' else 'the first draft date' end ||
      ' to ' || to_char(timezone('Asia/Kuala_Lumpur', p_value), 'DD Mon YYYY'),
    'due_req:' || v_id::text);

  perform public.ops_log(p_task, 'due_requested',
    jsonb_build_object('kind', p_kind, 'value', was),
    jsonb_build_object('kind', p_kind, 'value', p_value),
    jsonb_build_object('reason', p_reason, 'note', p_note, 'request', v_id));

  return jsonb_build_object('ok', true, 'request', v_id, 'asked', true,
                            'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_request_due_change(uuid, text, timestamptz, text, text, integer) to authenticated;

-- 2. Deciding. The date moves here and nowhere else on this path.
create or replace function public.ops_decide_due_change(
  p_request uuid, p_approve boolean, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  r   public.ops_due_requests;
  out jsonb;
  nm  text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;

  select * into r from public.ops_due_requests where id = p_request for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.state <> 'asked' then return jsonb_build_object('error', 'decided'); end if;

  /* The person it was asked of decides it. An ops Manage may also, because
     somebody has to when the creator has left; nobody else, and never the
     person who asked. */
  if m.id <> coalesce(r.decider_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and not public.allowed('ops', 'manage') then
    return jsonb_build_object('error', 'not-yours');
  end if;
  if m.id = r.asked_by and m.id <> r.decider_id then
    return jsonb_build_object('error', 'not-yours');
  end if;

  update public.ops_due_requests set
    state = case when p_approve then 'approved' else 'declined' end,
    decided_by = m.id, decided_at = now(), decide_note = nullif(btrim(p_note), '')
  where id = p_request;

  select name into nm from public.team_members where id = m.id;

  if p_approve then
    /* One path to a moved date, so the original-commitment rule and the event
       it files are the same whether or not an approval was needed. */
    out := public.ops_change_due_date(r.task_id, r.kind, r.wants_at,
                                      r.reason, r.note, null);
    if out ? 'error' then
      /* The gate refused after the approval, so the decision is put back
         rather than left recorded against a date that never moved. */
      update public.ops_due_requests set
        state = 'asked', decided_by = null, decided_at = null, decide_note = null
      where id = p_request;
      return out;
    end if;
  end if;

  perform public.ops_notify(r.asked_by, r.task_id,
    case when p_approve then 'due_approved' else 'due_declined' end,
    case when p_approve then 'Extension approved' else 'Extension declined' end,
    coalesce(nm, 'The task owner') ||
      case when p_approve then ' approved the new date' else ' declined the new date' end,
    'due_dec:' || p_request::text);

  perform public.ops_log(r.task_id,
    case when p_approve then 'due_approved' else 'due_declined' end,
    jsonb_build_object('kind', r.kind, 'value', r.was_at),
    jsonb_build_object('kind', r.kind, 'value', r.wants_at),
    jsonb_build_object('request', p_request, 'note', p_note));

  return jsonb_build_object('ok', true, 'approved', p_approve,
                            'task', public.ops_task_json(r.task_id));
end $$;
grant execute on function public.ops_decide_due_change(uuid, boolean, text) to authenticated;

-- 3. Taking it back. The person who asked may withdraw while it is open.
create or replace function public.ops_withdraw_due_change(p_request uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.ops_due_requests;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.ops_due_requests where id = p_request for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.state <> 'asked' then return jsonb_build_object('error', 'decided'); end if;
  if m.id <> r.asked_by and not public.allowed('ops', 'manage') then
    return jsonb_build_object('error', 'not-yours');
  end if;
  update public.ops_due_requests set state = 'withdrawn', decided_by = m.id, decided_at = now()
    where id = p_request;
  return jsonb_build_object('ok', true, 'task', public.ops_task_json(r.task_id));
end $$;
grant execute on function public.ops_withdraw_due_change(uuid) to authenticated;

-- Rollback:
--   drop function if exists public.ops_withdraw_due_change(uuid);
--   drop function if exists public.ops_decide_due_change(uuid, boolean, text);
--   drop function if exists public.ops_request_due_change(uuid, text, timestamptz, text, text, integer);
--   drop function if exists public.ops_due_decider(uuid, text);
--   drop function if exists public.ops_due_order_ok(timestamptz, timestamptz);
--   drop table if exists public.ops_due_requests;
-- ops_change_due_date is unchanged by this file and needs no rollback.

-- ==========================================================================
-- THE OPERATIONS REPORT
-- Mirrored from supabase/migrations/2026-09-21-operations-report.sql.
--
-- One function, one read, five answers: what is running, what is late, how
-- long each stage takes, whether the work was there on time, and the same per
-- person. It adds no table, column, policy or permission — every figure is
-- derived from rows the system has written since phase 1, which is the whole
-- reason the events are append-only.
--
-- `ops.reports` governs it, granted and never inherited, so a group given
-- `ops: work` does not silently gain the team's numbers.
--
-- MEDIAN, NOT MEAN, and never a bare figure: one task stuck in Editing for
-- three months moves a mean enough to make it say nothing about the ordinary
-- case, so the median carries its 90th percentile and the count it was taken
-- over. Replanning is reported beside the on-time rate and never folded into
-- it: an extension would otherwise erase the miss it was granted for.
--
-- Nothing here measures idle time, keystrokes, screens or location, and the
-- three durations stay three and are never summed.
-- ==========================================================================

create or replace function public.ops_report(
  p_from timestamptz default (now() - interval '90 days'),
  p_to   timestamptz default now())
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  out jsonb;
begin
  if not public.ops_granted('ops.reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;

  with
  /* Where client review begins in each workflow. The final due date is the
     day the work is owed AT that stage, so everything below that position is
     "has not reached the client yet". Read from `stage_group` and never from
     a stage key: the two seeded workflows name that stage differently. */
  floors as (
    select workflow_id, min(position) as at
      from public.ops_workflow_stages
     where stage_group = 'client_review'
     group by workflow_id
  ),
  live as (
    select t.*, s.label as stage_label, s.position as stage_position,
           s.stage_group, f.at as review_at
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.workflow_id = t.workflow_id and s.key = t.stage_key
      left join floors f on f.workflow_id = t.workflow_id
     where t.completed_at is null and t.cancelled_at is null
       and t.archived_at is null
  ),

  /* 1. WHAT IS RUNNING, by the words on the screen. Grouped by the stage's
        own label rather than by its group, because "what is on shooting" is
        the question and Shooting is a label, not a group. */
  running as (
    select jsonb_agg(x order by x ->> 'position', x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key, 'label', stage_label,
               'position', stage_position, 'stage_group', stage_group,
               'count', count(*)) as x
        from live
       group by stage_key, stage_label, stage_position, stage_group
    ) q
  ),

  /* 2. WHAT IS LATE. Past the commitment and still short of client review.
        The same rule the queue row draws, stated once more here because a
        report a page computes for itself is a second definition. */
  late as (
    select jsonb_agg(x order by x ->> 'due_at') as j from (
      select jsonb_build_object(
               'task_id', l.id, 'task_no', l.task_no, 'title', l.title,
               'client', c.name, 'stage', l.stage_label,
               'due_at', l.current_final_due_at,
               'days_over', (current_date - l.current_final_due_at::date),
               'owner', (select tm.name
                           from public.ops_task_assignees a
                           join public.team_members tm on tm.id = a.team_member_id
                          where a.task_id = l.id and a.responsibility = 'owner'
                            and a.ended_at is null
                          limit 1)) as x
        from live l
        left join public.clients c on c.id = l.client_id
       where l.current_final_due_at is not null
         and l.current_final_due_at::date < current_date
         and (l.review_at is null or l.stage_position < l.review_at)
    ) q
  ),

  /* 3. HOW LONG EACH STAGE TAKES. A task enters a stage at the event that
        names it and leaves at the next event, or at its own ending, or now.
        Only spans that were ENTERED inside the period are counted, so the
        window means what it says and a task that sat in Editing since March
        does not land in every report for ever. */
  spans as (
    select e.task_id,
           e.to_value ->> 'stage_key' as stage_key,
           e.created_at as from_at,
           coalesce(
             lead(e.created_at) over (partition by e.task_id order by e.created_at),
             t.completed_at, t.cancelled_at, now()) as to_at
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
     where e.event_type in ('task_created', 'stage_changed')
       and e.to_value ->> 'stage_key' is not null
  ),
  /* One row per span and no grouping: an earlier draft grouped by the span's
     own timestamps, which silently collapsed two tasks that entered the same
     stage in the same instant into one measurement. The label is looked up
     once per stage below instead of aggregated here. */
  span_mins as (
    select s.stage_key,
           extract(epoch from (s.to_at - s.from_at)) / 60 as mins
      from spans s
     where s.from_at >= p_from and s.from_at < p_to
       and s.to_at > s.from_at
  ),
  stage_time as (
    select jsonb_agg(x order by x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key,
               'label', coalesce((select w.label from public.ops_workflow_stages w
                                   where w.key = sm.stage_key limit 1), stage_key),
               'n', count(*),
               'median_minutes', round(percentile_cont(0.5) within group (order by mins))::int,
               'p90_minutes', round(percentile_cont(0.9) within group (order by mins))::int) as x
        from span_mins sm
       group by stage_key
    ) q
  ),

  /* 4. WAS IT THERE ON TIME. Of the tasks that reached client review inside
        the period, how many got there on or before the date they were owed.
        Replanning is counted beside it and never folded into it: an extension
        that moves the date would otherwise erase the miss it was granted for,
        and a rate that cannot be missed is not a measurement. */
  reached as (
    select distinct on (e.task_id)
           e.task_id, e.created_at as at, t.current_final_due_at as due,
           (t.original_final_due_at is distinct from t.current_final_due_at) as replanned
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
      join public.ops_workflow_stages w
        on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
     where e.event_type = 'stage_changed'
       and w.stage_group = 'client_review'
       and e.created_at >= p_from and e.created_at < p_to
     order by e.task_id, e.created_at
  ),
  on_time as (
    select jsonb_build_object(
             'reached', count(*),
             'met', count(*) filter (where due is null or at::date <= due::date),
             'missed', count(*) filter (where due is not null and at::date > due::date),
             'replanned', count(*) filter (where replanned)) as j
      from reached
  ),

  /* 5. BY PERSON. The foundation of a KPI and not a KPI: what somebody
        finished in the window, how much of it was on time, and how long their
        work took end to end. No ranking and no score — a number a person can
        check is worth more than a league table nobody trusts. */
  done as (
    select t.id, t.created_at, coalesce(t.completed_at, t.delivered_at) as ended,
           t.current_final_due_at as due,
           (select a.team_member_id
              from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc
             limit 1) as owner_id
      from public.ops_tasks t
     where t.completed_at is not null
       and t.completed_at >= p_from and t.completed_at < p_to
  ),
  by_person as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', d.owner_id,
               'name', coalesce(tm.name, 'Nobody'),
               'completed', count(*),
               'on_time', count(*) filter (where d.due is null or d.ended::date <= d.due::date),
               'median_cycle_minutes',
                 round(percentile_cont(0.5) within group (
                   order by extract(epoch from (d.ended - d.created_at)) / 60))::int) as x
        from done d
        left join public.team_members tm on tm.id = d.owner_id
       group by d.owner_id, tm.name
    ) q
  )

  select jsonb_build_object(
           'from', p_from, 'to', p_to,
           'running',    coalesce((select j from running), '[]'::jsonb),
           'late',       coalesce((select j from late), '[]'::jsonb),
           'stage_time', coalesce((select j from stage_time), '[]'::jsonb),
           'on_time',    coalesce((select j from on_time), '{}'::jsonb),
           'by_person',  coalesce((select j from by_person), '[]'::jsonb))
    into out;

  return out;
end $$;
grant execute on function public.ops_report(timestamptz, timestamptz) to authenticated;


-- =============================================================================
-- THE QUALITY CHECK IS A GATE
-- 2026-09-21
--
-- Asked for by the user on 2026-09-21: "qc should actually be a gate, despite
-- one person two person … if unsure always pull in another person to review
-- too", and "anyone can login and review, anyone can push, just that there is
-- a record of whose actually performed the actions".
--
-- WHAT WAS WRONG. Release to client moved the booking with a direct table
-- write from the browser (`db.from('campaign_options').update({state:
-- 'reviewing'})`). The nine-check sheet was therefore a speed bump on one
-- page and not a gate: nothing in the database knew a check had been made,
-- and a second reviewer could not be required at all, because "the second may
-- not be the first" is a rule only the server can hold.
--
-- WHAT THIS ADDS. One column, one table, one function and one trigger.
--
--   campaign_options.qc_second_wanted  the first checker asked for a second
--   option_qc                          who checked, when, for which round
--   campaign_qc_pass()                 the only way to reach `reviewing`
--   campaign_options_qc_gate           refuses the move whatever is sent
--
-- THE RULE, IN ONE SENTENCE. A booking reaches Client review when at least
-- one team member has completed the check, and at least two distinct ones
-- have where somebody asked for a second.
--
-- NOBODY IS ASSIGNED. The user chose this deliberately: the second reviewer
-- is anyone on the team who is not the person who asked. So a colleague who
-- leaves, or is on a shoot, can never strand a booking behind their own
-- account, and an admin or a manager clears it like anybody else. Telling the
-- second person is verbal; there is no notification and no queue, because the
-- campaign section is already carrying more than a new person can hold.
--
-- WHAT IS RECORDED IS THE PERSON, NOT THE NINE TICKS. Every check is
-- required, so one row per person is the evidence that all nine were made;
-- storing nine booleans a person would be nine times the data for the same
-- fact. The ticks stay on the page while somebody works through them.
--
-- A SENT-BACK BOOKING IS CHECKED FROM THE TOP. The rows key on
-- `revision_round`, which Request changes already increments, so a different
-- file is a different check and last week's sign-off cannot release it.
--
-- SAFE TO RUN TWICE. `create table if not exists`, `add column if not
-- exists`, `create or replace`, and the trigger is dropped before it is made.
--
-- ROLLBACK:
--   drop trigger if exists campaign_options_qc_gate on public.campaign_options;
--   drop function if exists public.campaign_options_qc_gate();
--   drop function if exists public.campaign_qc_pass(uuid, boolean);
--   drop table if exists public.option_qc;
--   alter table public.campaign_options drop column if exists qc_second_wanted;
-- =============================================================================

alter table public.campaign_options
  add column if not exists qc_second_wanted boolean not null default false;

-- Who checked a booking, when, and for which revision round. One row a person
-- a round: pressing the check twice is the same check, which is what stops a
-- single person satisfying a two-person gate by trying again.
create table if not exists public.option_qc (
  id             uuid primary key default gen_random_uuid(),
  option_id      uuid not null references public.campaign_options(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id) on delete restrict,
  round          integer not null default 0,
  checked_at     timestamptz not null default now(),
  unique (option_id, team_member_id, round)
);
alter table public.option_qc enable row level security;
create index if not exists option_qc_option on public.option_qc(option_id, round);

-- Read-only to a browser, like every other table whose writes are a function.
-- There is exactly one foreign key from here to `team_members`, so a
-- `team_members(name)` embed is unambiguous and PostgREST will answer it.
drop policy if exists option_qc_read on public.option_qc;
create policy option_qc_read on public.option_qc
  for select to authenticated using (public.is_team());

-- How many distinct people have completed the check for the round a booking
-- is on. Its own function because the page, the gate and the trigger all ask
-- the same question, and three copies of one rule drift.
create or replace function public.option_qc_count(p_option uuid)
returns integer
language sql security definer stable set search_path = public as $$
  select count(distinct q.team_member_id)::int
    from public.option_qc q
    join public.campaign_options o on o.id = q.option_id
   where q.option_id = p_option
     and q.round = coalesce(o.revision_round, 0)
$$;
grant execute on function public.option_qc_count(uuid) to authenticated;

-- Whether this booking may be released as it stands.
create or replace function public.option_qc_ok(p_option uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
           when coalesce(o.qc_second_wanted, false)
             then public.option_qc_count(p_option) >= 2
           else public.option_qc_count(p_option) >= 1
         end
    from public.campaign_options o where o.id = p_option
$$;
grant execute on function public.option_qc_ok(uuid) to authenticated;

-- The one way a booking reaches Client review.
--
--   p_want_second  true  record my check and hold it for somebody else
--                  false record my check and release it if the gate allows
--
-- Pressing it a second time as the same person is the same check: the insert
-- conflicts, the count does not move, and a booking held for a second
-- reviewer stays held. That is the whole of the no-self-approval rule, and it
-- is here rather than on the page because a rule a browser enforces is a rule
-- a browser can skip.
create or replace function public.campaign_qc_pass(
  p_option uuid, p_want_second boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members;
  o    public.campaign_options;
  n    integer;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;

  select * into o from public.campaign_options where id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'no-booking'); end if;
  if o.state <> 'submitted' then
    return jsonb_build_object('error', 'not-submitted');
  end if;

  insert into public.option_qc (option_id, team_member_id, round)
  values (p_option, me.id, coalesce(o.revision_round, 0))
  on conflict (option_id, team_member_id, round) do nothing;

  if p_want_second and not coalesce(o.qc_second_wanted, false) then
    update public.campaign_options set qc_second_wanted = true where id = p_option;
    o.qc_second_wanted := true;
  end if;

  n := public.option_qc_count(p_option);
  if coalesce(o.qc_second_wanted, false) and n < 2 then
    return jsonb_build_object('state', 'waiting', 'checks', n, 'second', true);
  end if;

  update public.campaign_options
     set state = 'reviewing', changes_by = null
   where id = p_option;
  return jsonb_build_object('state', 'reviewing', 'checks', n,
                            'second', coalesce(o.qc_second_wanted, false));
end $$;
grant execute on function public.campaign_qc_pass(uuid, boolean) to authenticated;

-- And the gate itself. Row level security on this table is still the
-- permissive one the repository carries as an open finding, so without this
-- the rule above would hold only for callers who chose to use the function.
-- It fires on the move INTO Client review and on nothing else, so every other
-- step on a creator's card is untouched and a booking already there is left
-- exactly as it stands.
create or replace function public.campaign_options_qc_gate()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.state = 'reviewing' and coalesce(old.state, '') is distinct from 'reviewing'
     and not public.option_qc_ok(new.id) then
    raise exception 'qc-required'
      using hint = 'Release to client needs the quality check completed.';
  end if;
  return new;
end $$;

drop trigger if exists campaign_options_qc_gate on public.campaign_options;
create trigger campaign_options_qc_gate
  before update on public.campaign_options
  for each row execute function public.campaign_options_qc_gate();

-- A booking sent back to the creator starts its check again: the round moves,
-- so the rows above no longer count, and whether a second reviewer was wanted
-- is a judgement about the file that just changed.
create or replace function public.campaign_qc_reset(p_option uuid)
returns void
language sql security definer set search_path = public as $$
  update public.campaign_options set qc_second_wanted = false where id = p_option
$$;
grant execute on function public.campaign_qc_reset(uuid) to authenticated;
