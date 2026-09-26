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
/* The groups are seeded once, into a database that has none. A group deleted
   on the Team page is a decision, and `on conflict do nothing` does not keep
   a deleted row deleted: a row that is gone raises no conflict, so every
   re-run of this file put Sales back after it had been removed (the rate
   card's lesson). Admin alone is ensured on every run, because the console
   cannot be administered without it and its guard refuses its deletion. */
insert into public.team_roles
  (slug, name, is_admin, can_clients, can_review, can_campaigns, can_links, can_activity, can_billing, can_remove, can_doc_void, position)
select * from (values
  ('account', 'Marketing', false, true, true,  true,  true,  false, true, false, false, 1),
  ('sales',   'Sales',   false, true, false, false, false, false, true, false, false, 2)
) as seed
where not exists (select 1 from public.team_roles);
insert into public.team_roles
  (slug, name, is_admin, can_clients, can_review, can_campaigns, can_links, can_activity, can_billing, can_remove, can_doc_void, position)
values
  ('admin',   'Admin',   true,  true, true,  true,  true,  true,  true, true,  true,  0)
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
        'term_adjust', coalesce(s.term_adjust, false), 'term_pct', s.term_pct)
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
    /* Who they are to us: the name the team keyed, since when, and the
       profile links the client's selection page opens, which they may keep
       up to date themselves. Never `client_rate`: that is the client's
       price, not theirs to read. */
    'creator', jsonb_build_object('name', cr.name, 'code', cr.access_code,
      'since', cr.created_at,
      'profiles', coalesce((
        select jsonb_agg(jsonb_build_object('platform', p.platform, 'handle', p.handle, 'url', p.url)
                         order by p.platform, p.url)
          from creator_profiles p where p.creator_id = cr.id), '[]'::jsonb)),
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
           -- And the percentage that tick applies, so a later rate card can
           -- never move a figure this letter printed. Null on a line quoted
           -- before the column existed, which money.js reads as that card.
           'term_pct', cs.term_pct,
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
--    An HR row names its colleague (p_member) and no client; every other row
--    its client and no colleague (2026-09-26, the nine-argument shape).
drop function if exists public.register_add(text, text, text, date, text, uuid, text, text);
create or replace function public.register_add(
  p_serial    text,
  p_family    text,
  p_kind      text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null
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
  tm    public.team_members%rowtype;
begin
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(v_fam, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  if v_serial is null then return jsonb_build_object('error', 'serial-required'); end if;
  if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
  if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (family, kind, serial, client_id, member_id, issued_at, recipient, signed, source, file_url, note, issued_by)
  values
    (v_fam, btrim(p_kind), v_serial, cl.id, tm.id, coalesce(p_issued_at, current_date),
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
grant execute on function public.register_add(text, text, text, date, text, uuid, text, text, uuid) to authenticated;
-- A serial imported or added by hand is known before its details are, so
-- the date may be blank and the row is edited afterwards; a portal row is a
-- snapshot and is never edited.
alter table public.documents alter column issued_at drop not null;

-- 5a. Editing a hand-added row: the kind, the family, the date, the recipient,
--     the client, the note and the file link. The serial never changes; a
--     wrong serial is deleted and added again, so the deletions remember it.
drop function if exists public.register_update(uuid, text, text, date, text, uuid, text, text);
create or replace function public.register_update(
  p_doc       uuid,
  p_kind      text,
  p_family    text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.documents%rowtype;
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  cl    public.clients%rowtype;
  tm    public.team_members%rowtype;
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'manual' then return jsonb_build_object('error', 'not-manual'); end if;
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(d.family, 'work') or not public.register_may(v_fam, 'work') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  update public.documents set
    kind = btrim(p_kind), family = v_fam, issued_at = p_issued_at,
    recipient = jsonb_build_object('name', coalesce(btrim(p_recipient), '')),
    client_id = cl.id, member_id = tm.id,
    note = nullif(btrim(p_note), ''), file_url = nullif(btrim(p_file_url), '')
  where id = p_doc;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.edited',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else d.serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'serial', d.serial);
end $$;
grant execute on function public.register_update(uuid, text, text, date, text, uuid, text, text, uuid) to authenticated;

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
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.stage', 'client.touch',
                    'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored', 'report.confirmed', 'report.created',
                    'report.deleted', 'report.published', 'report.returned',
                    'report.revised', 'report.submitted', 'report.unpublished',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
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

-- ===========================================================================
-- THE OPERATIONS SYSTEM, PHASE 4 — the monthly engagement, the task's name,
-- who the work is for, and the hand from one person to the next.
-- 2026-09-23. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS ADDS, AND WHAT IT LEAVES ALONE.
--
--   A task is for a client, a lead or nobody (`scope`), and the link is the
--   permanent record id: a client that later becomes a past client keeps
--   every task it ever had, because nothing here reads the client's current
--   stage to decide whose a task is. The stage is checked ONCE, when the task
--   is created, and never again.
--
--   A task keeps its serial (`T1001`) as its identity. Its NAME is a code and
--   an editable description: `2609W103 Raya carousel`, where 2609 is the
--   content month, W1 the planned publishing week and 03 the running number
--   for that client for the whole month. The code is generated under a lock
--   and never changes; the description is the team's to edit; the serial is
--   what history and references point at.
--
--   An engagement is one client's work for one month: the manager, how many
--   deliverables were agreed (typed, never derived from the contract, because
--   contract quantities change between renewals), the onboarding checklist,
--   the content meeting, and the tasks generated under it.
--
--   Existing tasks are not rewritten. They gain a description equal to their
--   old title, a task type of ad hoc, and no code; their workflow, stage,
--   events and assignments are untouched. The two seeded workflows are
--   retired for NEW tasks only and every task already on them carries on.
--
-- Rollback (in this order; the data in the new columns and tables is lost,
-- nothing that existed before is touched):
--   drop function if exists public.ops_engagement_set_status(uuid, text, integer);
--   drop function if exists public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean);
--   drop function if exists public.ops_engagement_set_check(uuid, text, text, uuid, text);
--   drop function if exists public.ops_engagement_upsert(jsonb);
--   drop function if exists public.ops_engagement_json(uuid);
--   drop function if exists public.ops_may_see_engagement(uuid);
--   drop function if exists public.ops_generate_month(jsonb, boolean, text);
--   drop function if exists public.ops_set_recurring(uuid, jsonb);
--   drop function if exists public.ops_duplicate_task(uuid, jsonb, text);
--   drop function if exists public.ops_set_content_desc(uuid, text, integer);
--   drop function if exists public.ops_transition_task(uuid, text, integer, text, uuid, text);
--   drop function if exists public.ops_next_seq(uuid, text);
--   drop function if exists public.ops_code_of(text, integer, integer);
--   drop function if exists public.ops_scope_error(text, uuid);
--   drop function if exists public.ops_title(public.ops_tasks);
--   drop table if exists public.ops_engagement_events;
--   drop table if exists public.ops_engagement_checks;
--   alter table public.ops_tasks drop column if exists engagement_id;
--   drop table if exists public.ops_engagements;
--   alter table public.ops_tasks drop column if exists task_type, drop column if exists code,
--     drop column if exists code_period, drop column if exists code_week,
--     drop column if exists code_seq, drop column if exists content_desc,
--     drop column if exists manager_id;
--   alter table public.ops_recurring_rules drop column if exists source_task_id,
--     drop column if exists interval_days, drop column if exists ends_on,
--     drop column if exists max_count, drop column if exists generated_count,
--     drop column if exists code_week, drop column if exists created_by;
--   alter table public.client_services drop column if exists term_pct;
--   then re-apply supabase/migrations/2026-09-19-operations-system.sql for
--   ops_create_task, ops_transition_task and ops_generate_recurring, the
--   phase 3 file for ops_log, the delete file for ops_delete_task, and the
--   term adjustment file for issue_letter and get_portal.
-- ===========================================================================

-- 9.1 The term adjustment carries its own percentage ----------------------------
/* The tick stays (`term_adjust`); beside it the percentage that tick applies,
   prefilled from the rate card for the term and editable on the line. Stored
   on the line and copied into the letter's snapshot, so a later rate card
   never moves a figure a client was already quoted. A line ticked before this
   column existed carries null, which money.js reads as the card the line was
   quoted under. */
alter table public.client_services add column if not exists term_pct numeric(6,2);

-- 9.2 The task: scope, type, name, engagement, manager ---------------------------
alter table public.ops_tasks drop constraint if exists ops_tasks_scope_check;
alter table public.ops_tasks add constraint ops_tasks_scope_check
  check (scope in ('client', 'lead', 'internal'));
alter table public.ops_tasks drop constraint if exists ops_tasks_client_scope;
alter table public.ops_tasks add constraint ops_tasks_client_scope
  check (scope = 'internal' or client_id is not null);

alter table public.ops_tasks add column if not exists task_type text not null default 'adhoc';
alter table public.ops_tasks drop constraint if exists ops_tasks_type_check;
alter table public.ops_tasks add constraint ops_tasks_type_check
  check (task_type in ('engagement', 'adhoc', 'goodwill', 'special'));
alter table public.ops_tasks add column if not exists code         text;
alter table public.ops_tasks add column if not exists code_period  text;
alter table public.ops_tasks add column if not exists code_week    smallint;
alter table public.ops_tasks add column if not exists code_seq     smallint;
alter table public.ops_tasks add column if not exists content_desc text;
alter table public.ops_tasks add column if not exists manager_id   uuid references public.team_members(id);

/* One code a client a month, whatever two sessions try at once: the lock in
   ops_next_seq is what stops them both reading 04 as free, and this index is
   what refuses the second one if anything ever bypasses the lock. Internal
   tasks carry no code. */
create unique index if not exists ops_tasks_code_idx
  on public.ops_tasks (coalesce(client_id, '00000000-0000-0000-0000-000000000000'::uuid), code_period, code_seq)
  where code_seq is not null;
create index if not exists ops_tasks_client_period_idx on public.ops_tasks (client_id, code_period);

/* Existing tasks keep their title as the editable description and their
   creator as their manager. No code is invented for them: a sequence nobody
   planned is not a plan. Guarded on the column being empty, so a second run
   cannot overwrite a description somebody has since edited. */
update public.ops_tasks set content_desc = title
 where content_desc is null and code is null;
update public.ops_tasks set manager_id = created_by
 where manager_id is null and created_by is not null;

-- 9.3 The engagement: one client's work for one month --------------------------
create table if not exists public.ops_engagements (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references public.clients(id) on delete cascade,
  period           text not null,
  manager_id       uuid references public.team_members(id),
  planned_count    integer not null default 0,
  drive_url        text,
  status           text not null default 'planning',
  meeting_at       timestamptz,
  meeting_channel  text,
  meeting_owner_id uuid references public.team_members(id),
  meeting_note     text,
  meeting_na       boolean not null default false,
  created_by       uuid references public.team_members(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  version          integer not null default 1,
  constraint ops_engagements_period_check check (period ~ '^\d{4}-\d{2}$'),
  constraint ops_engagements_status_check
    check (status in ('planning', 'ready', 'in_production', 'completed', 'cancelled')),
  constraint ops_engagements_channel_check
    check (meeting_channel is null or meeting_channel in ('onsite', 'google_meet', 'zoom', 'other'))
);
create unique index if not exists ops_engagements_client_period_idx
  on public.ops_engagements (client_id, period);

alter table public.ops_tasks add column if not exists engagement_id
  uuid references public.ops_engagements(id) on delete set null;
create index if not exists ops_tasks_engagement_idx on public.ops_tasks (engagement_id);

/* The onboarding and readiness list belongs to the engagement, not to every
   task: thirteen questions asked once a month, each with an owner and a state
   a person can act on. */
create table if not exists public.ops_engagement_checks (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.ops_engagements(id) on delete cascade,
  key           text not null,
  state         text not null default 'not_started',
  owner_id      uuid references public.team_members(id),
  note          text,
  updated_by    uuid references public.team_members(id),
  updated_at    timestamptz not null default now(),
  constraint ops_engagement_checks_state_check
    check (state in ('not_started', 'waiting_client', 'in_progress', 'ready', 'na'))
);
create unique index if not exists ops_engagement_checks_key_idx
  on public.ops_engagement_checks (engagement_id, key);

/* Append only, like the task's own events: who changed what on the
   engagement, and when. */
create table if not exists public.ops_engagement_events (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.ops_engagements(id) on delete cascade,
  event_type    text not null,
  actor_id      uuid references public.team_members(id),
  actor_email   text,
  detail        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists ops_engagement_events_idx
  on public.ops_engagement_events (engagement_id, created_at desc);

-- 9.4 A recurring rule can start from any task ----------------------------------
alter table public.ops_recurring_rules alter column template_id drop not null;
alter table public.ops_recurring_rules add column if not exists source_task_id
  uuid references public.ops_tasks(id) on delete set null;
alter table public.ops_recurring_rules add column if not exists interval_days   integer;
alter table public.ops_recurring_rules add column if not exists ends_on         date;
alter table public.ops_recurring_rules add column if not exists max_count       integer;
alter table public.ops_recurring_rules add column if not exists generated_count integer not null default 0;
alter table public.ops_recurring_rules add column if not exists code_week       smallint;
alter table public.ops_recurring_rules add column if not exists created_by      uuid references public.team_members(id);
alter table public.ops_recurring_rules drop constraint if exists ops_recurring_rules_freq_check;
alter table public.ops_recurring_rules add constraint ops_recurring_rules_freq_check
  check (frequency in ('weekly', 'monthly', 'custom'));
/* One live rule a source task, so setting it twice edits the one rule. */
create unique index if not exists ops_recurring_source_idx
  on public.ops_recurring_rules (source_task_id) where source_task_id is not null and active;

-- 9.5 The content workflow, and the two seeded ones retired for new work ---------
/* Seeded once, on a database that has none. The stages are the brief's:
   nine on the line and three beside it. Skipping a step the deliverable does
   not need is allowed and recorded (see ops_transition_task), so the
   adjacency here is the ordinary path, not the only one. */
do $$
declare w uuid;
begin
  if exists (select 1 from public.ops_workflows where key = 'content') then return; end if;
  insert into public.ops_workflows (key, name, description)
  values ('content', 'Content deliverable',
          'Planning, the content meeting, production, review and publishing.')
  returning id into w;
  insert into public.ops_workflow_stages
    (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
     is_review, is_terminal, wip_guidance, next_stage_keys) values
    (w, 'planning',          'Planning',                  1, 'intake',          false, false, false, false, null, array['meeting_scheduled','ready','on_hold','cancelled']),
    (w, 'meeting_scheduled', 'Content meeting scheduled', 2, 'intake',          false, true,  false, false, null, array['ready','planning','on_hold','cancelled']),
    (w, 'ready',             'Ready for production',      3, 'ready',           false, false, false, false, null, array['in_production','planning','blocked','on_hold','cancelled']),
    (w, 'in_production',     'In production',             4, 'active',          true,  false, false, false, 6,    array['internal_review','ready','blocked','on_hold','cancelled']),
    (w, 'internal_review',   'Internal quality review',   5, 'internal_review', false, true,  true,  false, 8,    array['client_review','changes_requested','in_production','blocked']),
    (w, 'client_review',     'Client review',             6, 'client_review',   false, true,  true,  false, null, array['approved','changes_requested','blocked','on_hold']),
    (w, 'changes_requested', 'Changes requested',         7, 'revision',        true,  false, false, false, null, array['in_production','internal_review','client_review','approved','blocked']),
    (w, 'approved',          'Approved',                  8, 'approved',        false, false, false, false, null, array['published','changes_requested']),
    (w, 'published',         'Published',                 9, 'done',            false, false, false, true,  null, array['changes_requested']),
    (w, 'blocked',           'Blocked',                  10, 'blocked',         false, true,  false, false, null, array['ready','in_production','internal_review','client_review','changes_requested','cancelled']),
    (w, 'on_hold',           'On hold',                  11, 'waiting',         false, true,  false, false, null, array['planning','ready','in_production','client_review','cancelled']),
    (w, 'cancelled',         'Cancelled',                12, 'cancelled',       false, false, false, true,  null, array['planning']);
end $$;

/* Retired for new tasks (decided with the user, 2026-09-23). A task already
   on either carries on exactly as it was: its stages, gates and events are
   untouched, and nothing reads `active` when moving it. */
update public.ops_workflows set active = false, updated_at = now()
 where key in ('general', 'video') and active;

-- 9.6 Reading the new tables ----------------------------------------------------
alter table public.ops_engagements enable row level security;
alter table public.ops_engagement_checks enable row level security;
alter table public.ops_engagement_events enable row level security;

/* An engagement is read by whoever manages it or created it, by anybody who
   may see a task inside it, and by the team queue. Select and nothing else:
   every write below is a function. */
create or replace function public.ops_may_see_engagement(p_engagement uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when not public.allowed('ops', 'view') then false
    when public.ops_granted('ops.all', 'view') then true
    else exists (
      select 1 from public.ops_engagements e
       where e.id = p_engagement
         and (e.manager_id = (select id from public.ops_me())
              or e.created_by = (select id from public.ops_me())
              or exists (select 1 from public.ops_tasks t
                          where t.engagement_id = e.id and public.ops_may_see_task(t.id))))
  end
$$;
grant execute on function public.ops_may_see_engagement(uuid) to authenticated;

drop policy if exists ops_engagements_read on public.ops_engagements;
create policy ops_engagements_read on public.ops_engagements
  for select to authenticated using (public.ops_may_see_engagement(id));
drop policy if exists ops_engagement_checks_read on public.ops_engagement_checks;
create policy ops_engagement_checks_read on public.ops_engagement_checks
  for select to authenticated using (public.ops_may_see_engagement(engagement_id));
drop policy if exists ops_engagement_events_read on public.ops_engagement_events;
create policy ops_engagement_events_read on public.ops_engagement_events
  for select to authenticated using (public.ops_may_see_engagement(engagement_id));
grant select on public.ops_engagements, public.ops_engagement_checks,
                public.ops_engagement_events to authenticated;
/* A rule is read by whoever may see the task it was set on, as well as by
   the templates part it always answered to. */
drop policy if exists ops_recurring_rules_read on public.ops_recurring_rules;
create policy ops_recurring_rules_read on public.ops_recurring_rules
  for select to authenticated using (
    public.ops_granted('ops.workflows', 'view')
    or (source_task_id is not null and public.ops_may_see_task(source_task_id)));

-- 9.7 The name ----------------------------------------------------------------
/* What a task is called on every screen and in every notification: the code
   and the description where it has a code, the old title where it does not.
   One definition, so the page, the bell and the activity record cannot name
   the same task three ways. */
create or replace function public.ops_title(t public.ops_tasks)
returns text
language sql immutable as $$
  select case
    when coalesce(t.code, '') = '' then coalesce(nullif(t.content_desc, ''), t.title, '')
    else btrim(t.code || ' ' || coalesce(t.content_desc, ''))
  end
$$;

/* YYMM + W + week + the running number, two digits. */
create or replace function public.ops_code_of(p_period text, p_week integer, p_seq integer)
returns text
language sql immutable as $$
  select substr(p_period, 3, 2) || substr(p_period, 6, 2) || 'W' || p_week::text || lpad(p_seq::text, 2, '0')
$$;

/* The next running number for a client and a month. The advisory lock is
   what makes two sessions generating for the same client and month queue
   behind each other rather than both reading the same gap as free; the
   unique index on the table is the backstop. Internal tasks carry no code,
   so the null client key is never reached from ops_create_task. */
create or replace function public.ops_next_seq(p_client uuid, p_period text)
returns integer
language plpgsql as $$
declare n integer;
begin
  perform pg_advisory_xact_lock(hashtext('ops_code:' || coalesce(p_client::text, 'internal') || ':' || p_period));
  select coalesce(max(code_seq), 0) + 1 into n from public.ops_tasks
   where coalesce(client_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = coalesce(p_client, '00000000-0000-0000-0000-000000000000'::uuid)
     and code_period = p_period;
  return n;
end $$;

/* Whose the task may be, checked ONCE at creation and never again: a client
   that later becomes a past client keeps its tasks. Client means a client
   that is engaged now (active, or paused); lead means a record that has not
   yet become one. */
create or replace function public.ops_scope_error(p_scope text, p_client uuid)
returns text
language plpgsql stable as $$
declare st text;
begin
  if p_scope = 'internal' then return null; end if;
  if p_scope not in ('client', 'lead') then return 'bad-scope'; end if;
  if p_client is null then return 'client-required'; end if;
  select stage into st from public.clients where id = p_client;
  if st is null then return 'client-required'; end if;
  if p_scope = 'client' and st not in ('active', 'paused') then return 'client-not-active'; end if;
  if p_scope = 'lead' and st not in ('lead', 'contacted', 'proposal') then return 'not-a-lead'; end if;
  return null;
end $$;

-- 9.8 Create --------------------------------------------------------------------
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
  scope text;
  ttype text;
  cid   uuid;
  bad   text;
  descr text;
  period text;
  week  integer;
  seq   integer;
  code  text;
  title text;
  first_stage text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  scope := coalesce(p_payload ->> 'scope', 'client');
  cid := (p_payload ->> 'client_id')::uuid;
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;

  ttype := coalesce(p_payload ->> 'task_type', 'adhoc');
  if ttype not in ('engagement', 'adhoc', 'goodwill', 'special') then
    return jsonb_build_object('error', 'bad-task-type');
  end if;

  /* The description is the team's to edit and may start blank on a task that
     carries a code; a task with no code is named by its description alone, so
     there it is required. `title` is accepted from older callers as the
     description. */
  descr := nullif(btrim(coalesce(p_payload ->> 'content_desc', p_payload ->> 'title', '')), '');

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
  end if;
  /* New work goes on the content workflow. A caller may still name another
     (a template's own, or one somebody adds), and a task already on a retired
     workflow is never moved. */
  wf := coalesce((p_payload ->> 'workflow_id')::uuid, tpl.workflow_id,
                 (select id from public.ops_workflows where key = 'content' and active),
                 (select id from public.ops_workflows where active order by created_at limit 1));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  select key into first_stage from public.ops_workflow_stages
   where workflow_id = wf order by position limit 1;

  publish := (p_payload ->> 'publish_at')::timestamptz;
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
  if fd is not null and fin is not null and not public.ops_due_order_ok(fd, fin) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  /* The name. The month is the content month (the scheduled publish date's,
     else the one the caller names, else this one); the week is the planned
     publishing week, chosen by the caller and prefilled by the page from the
     date; the running number is the client's for the month. Generated once,
     under the lock, and never rewritten: a publish date that moves later
     leaves the name as it was, because the name is a label and not a fact
     about the date. */
  if scope <> 'internal' then
    period := coalesce(nullif(p_payload ->> 'code_period', ''),
                       case when publish is not null then to_char(publish, 'YYYY-MM') end,
                       to_char(now(), 'YYYY-MM'));
    if period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
    week := coalesce((p_payload ->> 'code_week')::integer,
                     case when publish is not null
                          then least(5, ((extract(day from publish)::integer - 1) / 7) + 1) end,
                     1);
    if week < 1 or week > 5 then return jsonb_build_object('error', 'bad-week'); end if;
    seq := public.ops_next_seq(cid, period);
    code := public.ops_code_of(period, week, seq);
    title := btrim(code || ' ' || coalesce(descr, ''));
  else
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
  end if;

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality,
    task_type, code, code_period, code_week, code_seq, content_desc,
    engagement_id, manager_id, parent_task_id)
  values (
    scope, cid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, coalesce(first_stage, 'intake'),
    title, p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'other'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'),
    ttype, code, period, week, seq, descr,
    (p_payload ->> 'engagement_id')::uuid,
    coalesce((p_payload ->> 'manager_id')::uuid, m.id),
    (p_payload ->> 'parent_task_id')::uuid)
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

  -- The template's checklist, or the one the caller hands over (a duplicate
  -- carries its source's labels, unticked), in the order stated.
  for item in select * from jsonb_array_elements(
      coalesce(p_payload -> 'checklist', tpl.checklist, '[]'::jsonb)) loop
    i := i + 1;
    insert into public.ops_task_checklist_items (task_id, label, position)
    values (tid, item #>> '{}', i);
  end loop;

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
    jsonb_build_object('title', title, 'code', code,
                       'first_draft_due_at', fd, 'final_due_at', fin),
    case when (p_payload ->> 'duplicated_from') is null then '{}'::jsonb
         else jsonb_build_object('duplicated_from', p_payload ->> 'duplicated_from') end);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

-- 9.9 The description is edited; the code and the serial never are --------------
create or replace function public.ops_set_content_desc(
  p_task uuid, p_desc text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
  d text;
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
  d := nullif(btrim(coalesce(p_desc, '')), '');
  if d is null and coalesce(t.code, '') = '' then
    return jsonb_build_object('error', 'title-required');
  end if;
  if d is not distinct from t.content_desc then return public.ops_task_json(p_task); end if;
  update public.ops_tasks
     set content_desc = d,
         title = case when coalesce(code, '') = '' then d else btrim(code || ' ' || coalesce(d, '')) end,
         version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'renamed',
    jsonb_build_object('content_desc', t.content_desc),
    jsonb_build_object('content_desc', d), '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_set_content_desc(uuid, text, integer) to authenticated;

-- 9.10 Move a stage, hand it on, and skip what the deliverable does not need ------
/* The signature grows by two, so the four-argument one goes first: with both
   present PostgREST cannot tell a call that names four arguments from one
   that names four and leaves two to their defaults. */
drop function if exists public.ops_transition_task(uuid, text, integer, text);
create or replace function public.ops_transition_task(
  p_task uuid, p_next text, p_version integer default null, p_note text default null,
  p_assignee uuid default null, p_skip_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cur public.ops_workflow_stages;
  nxt public.ops_workflow_stages;
  sk  public.ops_workflow_stages;
  eng public.ops_engagements;
  has_owner boolean;
  has_draft boolean;
  has_final boolean;
  was_owner uuid;
  side text[] := array['blocked', 'waiting', 'kiv', 'cancelled'];
  skipping boolean := false;
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
  if t.stage_key = p_next then return public.ops_task_json(p_task); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  if not (p_next = any (cur.next_stage_keys)) then
    /* A step the deliverable does not need is skipped, forward along the
       line, with a reason on the record: who skipped it and why is written
       against every stage that was passed over. Nothing beside the line can
       be skipped into or out of, and nothing is skipped backwards. */
    if not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.position > cur.position then
      if nullif(btrim(coalesce(p_skip_reason, '')), '') is null then
        return jsonb_build_object('error', 'skip-reason-required');
      end if;
      skipping := true;
    else
      return jsonb_build_object('error', 'bad-transition',
        'allowed', to_jsonb(cur.next_stage_keys));
    end if;
  end if;

  -- What each gate needs before it opens.
  has_owner := exists (select 1 from public.ops_task_assignees
                        where task_id = p_task and responsibility = 'owner' and ended_at is null)
               or p_assignee is not null;
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
  /* Production waits on the engagement: planning marked complete, and the
     content meeting held or marked not applicable. A task with no engagement
     (ad hoc, internal) has nothing to wait on. */
  if p_next = 'in_production' and t.engagement_id is not null then
    select * into eng from public.ops_engagements where id = t.engagement_id;
    if eng.status = 'planning' then return jsonb_build_object('error', 'planning-incomplete'); end if;
    if not (eng.meeting_na or (eng.meeting_at is not null and eng.meeting_at <= now())) then
      return jsonb_build_object('error', 'meeting-required');
    end if;
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
  if p_next = 'published' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;

  /* The hand to the next person, recorded on the move: the previous owner
     ends, the new one begins, and the event names both with the stage it
     happened at. Work level, because handing the work on is part of doing
     it; reassigning a task without moving it stays Manage. */
  if p_assignee is not null then
    select team_member_id into was_owner from public.ops_task_assignees
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    if p_assignee is distinct from was_owner then
      if not exists (select 1 from public.team_members where id = p_assignee and active) then
        return jsonb_build_object('error', 'no-such-person');
      end if;
      update public.ops_task_assignees set ended_at = now()
       where task_id = p_task and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, p_assignee, 'owner', m.id);
      perform public.ops_log(p_task, 'assignment_changed',
        jsonb_build_object('owner_id', was_owner),
        jsonb_build_object('owner_id', p_assignee),
        jsonb_build_object('handover', true, 'stage_key', p_next, 'from_stage_key', t.stage_key));
    end if;
  end if;

  if skipping then
    for sk in select * from public.ops_workflow_stages
               where workflow_id = t.workflow_id
                 and position > cur.position and position < nxt.position
                 and not (stage_group = any (side))
               order by position loop
      perform public.ops_log(p_task, 'stage_skipped',
        jsonb_build_object('stage_key', sk.key), jsonb_build_object('stage_key', p_next),
        jsonb_build_object('reason', btrim(p_skip_reason)));
    end loop;
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
    (case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end)
    || (case when skipping then jsonb_build_object('skip_reason', btrim(p_skip_reason)) else '{}'::jsonb end));
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
grant execute on function public.ops_transition_task(uuid, text, integer, text, uuid, text) to authenticated;

-- 9.11 Duplicate ----------------------------------------------------------------
/* A copy is a new task with a new code: the planning fields travel, the
   history does not. Dates and assignees travel only where the caller says
   so; the description travels only where the caller says so; comments,
   events, sessions and review records never travel. */
create or replace function public.ops_duplicate_task(
  p_task uuid, p_opts jsonb default '{}'::jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  s   public.ops_tasks;
  owner uuid;
  payload jsonb;
  made jsonb;
  c   uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.ops_tasks where id = p_task;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce((p_opts ->> 'copy_assignees')::boolean, false) then
    select team_member_id into owner from public.ops_task_assignees
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
  end if;

  payload := jsonb_build_object(
    'scope', s.scope, 'client_id', s.client_id, 'campaign_id', s.campaign_id,
    'template_id', s.template_id, 'workflow_id', s.workflow_id,
    'task_type', s.task_type, 'deliverable_type', s.deliverable_type,
    'engagement_id', coalesce((p_opts ->> 'engagement_id')::uuid, s.engagement_id),
    'manager_id', s.manager_id,
    'priority_level', s.priority_level, 'complexity', s.complexity,
    'estimate_minutes', s.estimate_minutes,
    'description', s.description, 'remarks', s.remarks,
    'language_codes', to_jsonb(s.language_codes),
    'content_desc', case when coalesce((p_opts ->> 'keep_desc')::boolean, false) then s.content_desc else null end,
    'code_period', coalesce(nullif(p_opts ->> 'code_period', ''), s.code_period),
    'code_week', coalesce((p_opts ->> 'code_week')::integer, s.code_week),
    'owner_id', owner,
    'parent_task_id', s.id,
    'duplicated_from', s.id,
    'checklist', coalesce((select jsonb_agg(label order by position)
                             from public.ops_task_checklist_items where task_id = p_task), '[]'::jsonb));
  if coalesce((p_opts ->> 'copy_dates')::boolean, false) then
    payload := payload || jsonb_build_object(
      'publish_at', coalesce((p_opts ->> 'publish_at')::timestamptz, s.publish_at),
      'first_draft_due_at', s.current_first_draft_due_at,
      'final_due_at', s.current_final_due_at);
  elsif (p_opts ->> 'publish_at') is not null then
    payload := payload || jsonb_build_object('publish_at', (p_opts ->> 'publish_at')::timestamptz);
  end if;
  /* A copy of a task on a retired workflow starts on the live one: the
     retired pair is for the tasks already on them and nothing new. */
  if not exists (select 1 from public.ops_workflows where id = s.workflow_id and active) then
    payload := payload - 'workflow_id' - 'template_id';
  end if;

  made := public.ops_create_task(payload, p_idem);
  if made ? 'error' then return made; end if;

  if coalesce((p_opts ->> 'copy_assignees')::boolean, false) then
    for c in select team_member_id from public.ops_task_assignees
              where task_id = p_task and responsibility = 'contributor' and ended_at is null loop
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values ((made ->> 'id')::uuid, c, 'contributor', m.id) on conflict do nothing;
    end loop;
  end if;
  return made;
end $$;
grant execute on function public.ops_duplicate_task(uuid, jsonb, text) to authenticated;

-- 9.12 A month of content at once ------------------------------------------------
/* The operator types the count; nothing is read off the service contract,
   because contract quantities change between renewals and a number nobody
   confirmed is a number nobody planned. `weeks` is how many go in each
   publishing week (four or five figures); with none given the count is spread
   over four. The running numbers are the client's for the month, so twelve
   tasks over four weeks are 01 to 12 whatever week each lands in. A dry run
   answers with the codes that would be made and writes nothing. */
create or replace function public.ops_generate_month(
  p_payload jsonb, p_dry_run boolean default false, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  cid    uuid;
  per    text;
  n      integer;
  weeks  integer[];
  bad    text;
  eng    uuid;
  k      integer;
  w      integer;
  seq    integer;
  seqs   integer;
  made   jsonb := '[]'::jsonb;
  one    jsonb;
  key    text;
  scope  text;
  first_day date;
  publish timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  n := coalesce((p_payload ->> 'count')::integer, 0);
  scope := coalesce(p_payload ->> 'scope', 'client');
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  if n < 1 or n > 60 then return jsonb_build_object('error', 'bad-count'); end if;

  if (p_payload -> 'weeks') is not null and jsonb_typeof(p_payload -> 'weeks') = 'array' then
    select array_agg(x::integer) into weeks from jsonb_array_elements_text(p_payload -> 'weeks') x;
    if array_length(weeks, 1) < 1 or array_length(weeks, 1) > 5 then
      return jsonb_build_object('error', 'bad-weeks');
    end if;
    if (select sum(v) from unnest(weeks) v) <> n then return jsonb_build_object('error', 'weeks-do-not-add-up'); end if;
  else
    weeks := array[n / 4, n / 4, n / 4, n - 3 * (n / 4)];
  end if;

  /* The same press twice is one month, not two. */
  if not p_dry_run and p_idem is not null then
    if exists (select 1 from public.ops_tasks where idem_key = 'month:' || p_idem || ':1') then
      return jsonb_build_object('error', 'already-generated');
    end if;
  end if;

  first_day := (per || '-01')::date;
  /* One lock for the whole run, taken before anything is read: two operators
     generating the same month queue here, so the second sees the first's
     engagement and the first's numbers rather than racing both. */
  perform pg_advisory_xact_lock(hashtext('ops_code:' || cid::text || ':' || per));
  if not p_dry_run then
    eng := coalesce((p_payload ->> 'engagement_id')::uuid,
                    (select e.id from public.ops_engagements e where e.client_id = cid and e.period = per));
    if eng is null then
      eng := (public.ops_engagement_upsert(jsonb_build_object(
                'client_id', cid, 'period', per, 'planned_count', n,
                'manager_id', coalesce((p_payload ->> 'manager_id')::uuid, m.id))) ->> 'id')::uuid;
    else
      update public.ops_engagements set planned_count = greatest(planned_count, n), updated_at = now()
       where id = eng and planned_count < n;
    end if;
  end if;

  /* One lock for the whole month, so the preview and the run see the same
     next number and two operators generating for one client queue. */
  seq := public.ops_next_seq(cid, per) - 1;
  seqs := 0;
  for w in 1 .. array_length(weeks, 1) loop
    for k in 1 .. coalesce(weeks[w], 0) loop
      seq := seq + 1;
      seqs := seqs + 1;
      /* A tentative date on the Monday of the week, so the calendar has
         somewhere to put it; the meeting fixes the real one. */
      publish := (first_day + ((w - 1) * 7))::timestamptz;
      if p_dry_run then
        made := made || jsonb_build_object('code', public.ops_code_of(per, w, seq), 'week', w, 'seq', seq);
      else
        key := case when p_idem is null then null else 'month:' || p_idem || ':' || seqs::text end;
        one := public.ops_create_task(jsonb_build_object(
          'scope', scope, 'client_id', cid, 'engagement_id', eng,
          'task_type', coalesce(p_payload ->> 'task_type', 'engagement'),
          'deliverable_type', p_payload ->> 'deliverable_type',
          'priority_level', (p_payload ->> 'priority_level')::integer,
          'complexity', p_payload ->> 'complexity',
          'owner_id', (p_payload ->> 'owner_id')::uuid,
          'manager_id', (p_payload ->> 'manager_id')::uuid,
          'code_period', per, 'code_week', w,
          'publish_at', publish), key);
        if one ? 'error' then return one; end if;
        made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'week', w, 'seq', seq);
      end if;
    end loop;
  end loop;
  return jsonb_build_object('engagement_id', eng, 'period', per, 'count', seqs,
                            'tasks', made, 'dry_run', p_dry_run);
end $$;
grant execute on function public.ops_generate_month(jsonb, boolean, text) to authenticated;

-- 9.13 Recurring, from any task ------------------------------------------------
/* Setting the rule is the task owner's act (Work). One live rule a task. */
create or replace function public.ops_set_recurring(p_task uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
  r public.ops_recurring_rules;
  freq text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  select * into r from public.ops_recurring_rules where source_task_id = p_task and active;
  if coalesce((p_payload ->> 'active')::boolean, true) = false then
    if r.id is not null then
      update public.ops_recurring_rules set active = false, updated_at = now() where id = r.id;
      perform public.ops_log(p_task, 'recurrence_off', null, null, '{}'::jsonb);
    end if;
    return jsonb_build_object('ok', true, 'active', false);
  end if;

  freq := coalesce(p_payload ->> 'frequency', 'monthly');
  if freq not in ('weekly', 'monthly', 'custom') then return jsonb_build_object('error', 'bad-frequency'); end if;
  if freq = 'custom' and coalesce((p_payload ->> 'interval_days')::integer, 0) < 1 then
    return jsonb_build_object('error', 'interval-required');
  end if;

  if r.id is null then
    insert into public.ops_recurring_rules
      (name, client_id, template_id, owner_id, frequency, day_of_month, source_task_id,
       interval_days, ends_on, max_count, code_week, created_by)
    values (public.ops_title(t), t.client_id, t.template_id,
            (select team_member_id from public.ops_task_assignees
              where task_id = p_task and responsibility = 'owner' and ended_at is null),
            freq, (p_payload ->> 'day_of_month')::integer, p_task,
            (p_payload ->> 'interval_days')::integer, (p_payload ->> 'ends_on')::date,
            (p_payload ->> 'max_count')::integer, coalesce((p_payload ->> 'code_week')::integer, t.code_week),
            m.id)
    returning * into r;
    perform public.ops_log(p_task, 'recurrence_set', null, to_jsonb(r) - 'id', '{}'::jsonb);
  else
    update public.ops_recurring_rules set
      frequency = freq, day_of_month = (p_payload ->> 'day_of_month')::integer,
      interval_days = (p_payload ->> 'interval_days')::integer,
      ends_on = (p_payload ->> 'ends_on')::date, max_count = (p_payload ->> 'max_count')::integer,
      code_week = coalesce((p_payload ->> 'code_week')::integer, r.code_week),
      updated_at = now()
    where id = r.id returning * into r;
    perform public.ops_log(p_task, 'recurrence_set', null, to_jsonb(r) - 'id', '{}'::jsonb);
  end if;
  return to_jsonb(r);
end $$;
grant execute on function public.ops_set_recurring(uuid, jsonb) to authenticated;

/* Every occurrence due in a month, once. The key is the rule and the
   occurrence date, so a run pressed twice — or by two people — files the
   same occurrence once, and the unique index on `idem_key` is what says so
   if two runs race. A rule set on a task copies that task; an older rule set
   on a template creates from the template as it always did. */
create or replace function public.ops_generate_recurring(
  p_period text, p_rules uuid[] default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  r     public.ops_recurring_rules;
  src   public.ops_tasks;
  made  integer := 0;
  skip  integer := 0;
  key   text;
  first_day date;
  last_day date;
  anchor date;
  d     date;
  stepd integer;
  one   jsonb;
  wk    integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  first_day := (p_period || '-01')::date;
  last_day := (first_day + interval '1 month' - interval '1 day')::date;

  for r in select * from public.ops_recurring_rules
            where active and (p_rules is null or id = any (p_rules))
              and (source_task_id is null or public.ops_may_see_task(source_task_id)) loop
    if r.source_task_id is not null then
      select * into src from public.ops_tasks where id = r.source_task_id;
    else
      src := null;
    end if;

    /* The dates this rule falls on inside the month. */
    if r.frequency = 'monthly' then
      d := first_day + (least(coalesce(r.day_of_month,
              case when src.publish_at is not null then extract(day from src.publish_at)::integer else 1 end),
              extract(day from last_day)::integer) - 1);
      stepd := null;
    else
      stepd := case when r.frequency = 'weekly' then 7 else greatest(1, coalesce(r.interval_days, 7)) end;
      anchor := coalesce(src.publish_at::date, r.created_at::date, first_day);
      if anchor > first_day then d := anchor;
      else d := anchor + ((((first_day - anchor) + stepd - 1) / stepd) * stepd); end if;
    end if;

    while d is not null and d <= last_day loop
      if d >= first_day
         and (r.ends_on is null or d <= r.ends_on)
         and (r.max_count is null or r.generated_count < r.max_count) then
        key := 'recur:' || r.id::text || ':' || to_char(d, 'YYYY-MM-DD');
        if exists (select 1 from public.ops_tasks where idem_key = key) then
          skip := skip + 1;
        else
          wk := coalesce(r.code_week, least(5, ((extract(day from d)::integer - 1) / 7) + 1));
          if src.id is not null then
            one := public.ops_duplicate_task(src.id, jsonb_build_object(
              'keep_desc', true, 'copy_dates', false, 'copy_assignees', true,
              'publish_at', d::timestamptz, 'code_period', p_period, 'code_week', wk,
              'engagement_id', (select id from public.ops_engagements
                                 where client_id = src.client_id and period = p_period)), key);
          else
            one := public.ops_create_task(jsonb_build_object(
              'scope', case when r.client_id is null then 'internal' else 'client' end,
              'client_id', r.client_id, 'template_id', r.template_id,
              'title', r.name || ' — ' || p_period, 'content_desc', r.name,
              'owner_id', r.owner_id, 'publish_at', d::timestamptz,
              'code_period', p_period, 'code_week', wk), key);
          end if;
          if one ? 'error' then return one || jsonb_build_object('rule', r.id); end if;
          made := made + 1;
          update public.ops_recurring_rules
             set generated_count = generated_count + 1, last_generated_period = p_period, updated_at = now()
           where id = r.id;
          r.generated_count := r.generated_count + 1;
        end if;
      end if;
      exit when stepd is null;
      d := d + stepd;
    end loop;
  end loop;
  return jsonb_build_object('created', made, 'skipped', skip, 'period', p_period);
end $$;
grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;

-- 9.14 The engagement's own writes ----------------------------------------------
create or replace function public.ops_engagement_json(p_engagement uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(e) || jsonb_build_object(
    'checks', coalesce((select jsonb_agg(to_jsonb(c) order by c.key)
                          from public.ops_engagement_checks c where c.engagement_id = e.id), '[]'::jsonb),
    'task_count', (select count(*) from public.ops_tasks t
                    where t.engagement_id = e.id and t.archived_at is null))
  from public.ops_engagements e where e.id = p_engagement
$$;
grant execute on function public.ops_engagement_json(uuid) to authenticated;

create or replace function public.ops_engagement_log(p_engagement uuid, p_type text, p_detail jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  insert into public.ops_engagement_events (engagement_id, event_type, actor_id, actor_email, detail)
  values (p_engagement, p_type, m.id, m.email, coalesce(p_detail, '{}'::jsonb));
end $$;

/* One a client a month. A second call for the same month edits the one row
   rather than making a second; the thirteen checks are seeded on creation
   and never re-seeded. */
create or replace function public.ops_engagement_upsert(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  cid uuid;
  per text;
  eid uuid;
  k text;
  fresh boolean := false;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  if cid is null or not exists (select 1 from public.clients where id = cid) then
    return jsonb_build_object('error', 'client-required');
  end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;

  select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
  if eid is null then
    insert into public.ops_engagements (client_id, period, manager_id, planned_count, drive_url, created_by)
    values (cid, per, coalesce((p_payload ->> 'manager_id')::uuid, m.id),
            coalesce((p_payload ->> 'planned_count')::integer, 0),
            nullif(p_payload ->> 'drive_url', ''), m.id)
    on conflict (client_id, period) do nothing
    returning id into eid;
    /* Somebody else made it between the read and the write: theirs stands. */
    if eid is null then
      select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
    else
      fresh := true;
    end if;
  end if;
  if fresh then
    foreach k in array array['client_name', 'legal_name', 'brand_name', 'brand_profile',
                             'social_profiles', 'client_info', 'platform_ready',
                             'platform_setup', 'platform_create', 'partner_access_requested',
                             'partner_access_received', 'pre_ads_required', 'pre_ads_completed'] loop
      insert into public.ops_engagement_checks (engagement_id, key) values (eid, k)
      on conflict do nothing;
    end loop;
    perform public.ops_engagement_log(eid, 'created', p_payload - 'client_id');
  else
    if not public.ops_may_see_engagement(eid) then return jsonb_build_object('error', 'denied'); end if;
    update public.ops_engagements set
      manager_id = coalesce((p_payload ->> 'manager_id')::uuid, manager_id),
      planned_count = coalesce((p_payload ->> 'planned_count')::integer, planned_count),
      drive_url = case when p_payload ? 'drive_url' then nullif(p_payload ->> 'drive_url', '') else drive_url end,
      updated_at = now(), version = version + 1
    where id = eid;
    perform public.ops_engagement_log(eid, 'edited', p_payload - 'client_id' - 'period');
  end if;
  return public.ops_engagement_json(eid) || jsonb_build_object('created', fresh);
end $$;
grant execute on function public.ops_engagement_upsert(jsonb) to authenticated;

create or replace function public.ops_engagement_set_check(
  p_engagement uuid, p_key text, p_state text, p_owner uuid default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; was text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_state not in ('not_started', 'waiting_client', 'in_progress', 'ready', 'na') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  select state into was from public.ops_engagement_checks
   where engagement_id = p_engagement and key = p_key;
  if was is null then return jsonb_build_object('error', 'no-such-check'); end if;
  update public.ops_engagement_checks
     set state = p_state, owner_id = coalesce(p_owner, owner_id),
         note = case when p_note is null then note else nullif(btrim(p_note), '') end,
         updated_by = m.id, updated_at = now()
   where engagement_id = p_engagement and key = p_key;
  perform public.ops_engagement_log(p_engagement, 'check_changed',
    jsonb_build_object('key', p_key, 'from', was, 'to', p_state, 'owner_id', p_owner));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_check(uuid, text, text, uuid, text) to authenticated;

/* The content meeting. When it is first put in the diary the date is today
   or later; once it has been held the record stays as it was, because a past
   meeting is a fact and not a mistake. Not applicable is its own answer. */
create or replace function public.ops_engagement_set_meeting(
  p_engagement uuid, p_at timestamptz, p_channel text default null,
  p_owner uuid default null, p_note text default null, p_na boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce(p_na, false) then
    update public.ops_engagements set meeting_na = true, meeting_note = coalesce(p_note, meeting_note),
           updated_at = now(), version = version + 1 where id = p_engagement;
    perform public.ops_engagement_log(p_engagement, 'meeting_na', jsonb_build_object('note', p_note));
    return public.ops_engagement_json(p_engagement);
  end if;
  if p_at is null then return jsonb_build_object('error', 'no-date'); end if;
  if p_channel is not null and p_channel not in ('onsite', 'google_meet', 'zoom', 'other') then
    return jsonb_build_object('error', 'bad-channel');
  end if;
  if e.meeting_at is null and p_at::date < current_date then
    return jsonb_build_object('error', 'meeting-in-past');
  end if;
  update public.ops_engagements set
    meeting_at = p_at, meeting_channel = coalesce(p_channel, meeting_channel),
    meeting_owner_id = coalesce(p_owner, meeting_owner_id, m.id),
    meeting_note = case when p_note is null then meeting_note else nullif(btrim(p_note), '') end,
    meeting_na = false, updated_at = now(), version = version + 1
  where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'meeting_set',
    jsonb_build_object('at', p_at, 'channel', p_channel, 'owner_id', p_owner, 'was', e.meeting_at));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean) to authenticated;

/* Ready is a claim about the checklist and the meeting, so the database
   checks both before it lets the word stand. */
create or replace function public.ops_engagement_set_status(
  p_engagement uuid, p_status text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('planning', 'ready', 'in_production', 'completed', 'cancelled') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> e.version then
    return jsonb_build_object('error', 'stale', 'engagement', public.ops_engagement_json(p_engagement));
  end if;
  if p_status in ('ready', 'in_production') and e.status = 'planning' then
    if exists (select 1 from public.ops_engagement_checks
                where engagement_id = p_engagement
                  and state in ('not_started', 'waiting_client', 'in_progress')) then
      return jsonb_build_object('error', 'checklist-open');
    end if;
    if not (e.meeting_na or (e.meeting_at is not null and e.meeting_at <= now())) then
      return jsonb_build_object('error', 'meeting-required');
    end if;
  end if;
  update public.ops_engagements set status = p_status, updated_at = now(), version = version + 1
   where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'status_changed',
    jsonb_build_object('from', e.status, 'to', p_status));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_status(uuid, text, integer) to authenticated;

-- 9.15 The name everywhere the task is named ------------------------------------
/* Phase 3's ops_log, with the notification naming the task by its name and
   its serial. Nothing else in it changes. */
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

  if p_type = 'assignment_changed' then
    owner := (p_to ->> 'owner_id')::uuid;
    if owner is not null and owner is distinct from m.id then
      perform public.ops_notify(owner, p_task, 'assigned',
        'T' || t.task_no || ' · ' || public.ops_title(t),
        case when coalesce((p_detail ->> 'handover')::boolean, false)
             then 'Handed to you by ' || who || ' at ' ||
                  coalesce((public.ops_stage(t.workflow_id, p_detail ->> 'stage_key')).label, p_detail ->> 'stage_key') || '.'
             else 'Assigned to you by ' || who || '.' end,
        'assigned:' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
    end if;
    return;
  end if;

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
    'T' || t.task_no || ' · ' || public.ops_title(t), body,
    p_type || ':' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
end $$;

/* The deletion names the task the way every screen does. */
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
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce(p_confirm, '') <> 'T' || t.task_no::text then
    return jsonb_build_object('error', 'confirm-required');
  end if;

  select c.name into cl from public.clients c where c.id = t.client_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.deleted',
          'T' || t.task_no::text,
          public.ops_title(t) ||
          coalesce(' · ' || cl, case when t.scope = 'internal' then ' · Internal' else '' end) ||
          coalesce(' · ' || nullif(btrim(p_reason), ''), ''));

  delete from public.ops_tasks where id = p_task;
  return jsonb_build_object('deleted', true, 'task_no', t.task_no);
end $$;
grant execute on function public.ops_delete_task(uuid, text, text) to authenticated;

-- END OF PHASE 4 -----------------------------------------------------------

-- ===========================================================================
-- MY WORK AS A DAILY TASK TRACKER — everyday tasks, quick creation, comments,
-- checklist items, templates, and the next-step rules the task page shows.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   A task is one finishable action. Most of them do not need the content
--   workflow's nine stages and its gates, so there is a second, small
--   workflow for them: `task` — To do, In progress, Waiting, Review, Done —
--   where any stage may follow any other and nothing is gated. A content
--   deliverable stays on the content workflow with every gate it had.
--
--   1. The `task` workflow, seeded once, into a database that has none.
--
--   2. `ops_create_task` names an everyday task by what it is (no content
--      code), takes the client and the month from a linked engagement, and
--      takes a template's default title, owner and due offset in calendar
--      days from a base date.
--
--   3. `ops_transition_task`: skipping a step keeps the published rule (ops
--      Work, with a reason) and can never land on a revision stage; a task
--      reaches Client review only after AQC review, with the draft link or a
--      note saying how the draft was sent (the WhatsApp group); a revision
--      takes a note; every review and revision records its round; and a move
--      into a terminal stage closes every running timer on the task.
--
--   4. `ops_hand_over_task` (ops Manage, the note kept on the event),
--      `ops_set_publish_date` (ops Work), `ops_add_checklist_item` and
--      `ops_add_comment` (ops Work), `ops_save_template` (the granted part
--      ops.workflows, Work).
--
--   5. Three columns on `ops_task_templates` (default_title,
--      default_owner_id, due_offset_days) and one index for cancelled work.
--
--   6. The task number reads #WT00001 (`ops_serial`), in the notifications,
--      the activity record and the delete check alike; `ops_next_task_no` and
--      `ops_set_next_task_no` let an admin read and set the next number.
--
--   7. The content workflow's words, its two revision loops and what follows
--      approval: In progress, Ready to start and AQC review are relabelled
--      where they still read as seeded; Revision (Internal) (from AQC review)
--      and Revision (Client) (from Client review) are added; and after
--      Approved come Scheduled, Live, Performance review (three days after
--      going live, handed back to whoever created the task), Taken down and
--      Completed. Changes requested stays for any task already in it and is
--      no longer offered as a next step.
--
--   8. The live date and the rating: five columns on `ops_tasks` (live_at,
--      rating, rating_note, rated_by, rated_at), `ops_mark_live` (a date other
--      than the scheduled one says why) and `ops_rate_task` (one to five, a
--      finished task only, a change filed as a second event).
--
--   9. `ops_delete_tasks`: several tasks deleted in one act, ops Manage, the
--      count typed back and a reason, each one filed as its own deletion.
--
--  10. What was added can be put right: `ops_update_task` (the brief and the
--      priority), `ops_edit_checklist_item` and `ops_remove_checklist_item`
--      (never a required check), `ops_update_link`, and `ops_edit_comment` /
--      `ops_remove_comment` (the writer or ops Manage), each filed as a later
--      event so the history keeps what it was.
--
--   No existing task is rewritten, moved or renamed. No policy changes. The
--   test tasks are cleared by a separate file, 2026-09-24-clear-test-tasks.sql,
--   which is run once and on purpose.
--
-- Rollback: re-run sections 9.8 and 9.10 of 2026-09-23-operations-phase4.sql
-- (the previous ops_create_task, ops_transition_task, ops_log and
-- ops_delete_task), then
--   drop function if exists public.ops_rate_task(uuid, integer, text);
--   drop function if exists public.ops_mark_live(uuid, timestamptz, text, integer, uuid, text);
--   drop function if exists public.ops_remove_comment(uuid, boolean);
--   drop function if exists public.ops_edit_comment(uuid, text);
--   drop function if exists public.ops_update_link(uuid, text, text, text, integer);
--   drop function if exists public.ops_remove_checklist_item(uuid);
--   drop function if exists public.ops_edit_checklist_item(uuid, text);
--   drop function if exists public.ops_update_task(uuid, jsonb, integer);
--   drop function if exists public.ops_delete_tasks(uuid[], text, text);
--   drop function if exists public.ops_set_next_task_no(bigint);
--   drop function if exists public.ops_next_task_no();
--   drop function if exists public.ops_serial(bigint);
--   drop function if exists public.ops_hand_over_task(uuid, uuid, text, integer);
--   drop function if exists public.ops_set_publish_date(uuid, timestamptz, integer);
--   drop function if exists public.ops_add_checklist_item(uuid, text);
--   drop function if exists public.ops_add_comment(uuid, text);
--   drop function if exists public.ops_save_template(uuid, jsonb);
--   drop index if exists public.ops_tasks_cancelled_idx;
-- The `task` workflow, the three template columns and the five live and
-- rating columns may stay: nothing reads them once the functions are rolled
-- back. Remove them only where no task was
-- created on the workflow:
--   delete from public.ops_workflow_stages where workflow_id in
--     (select id from public.ops_workflows where key = 'task');
--   delete from public.ops_workflows where key = 'task';
-- ===========================================================================

-- 1. The everyday workflow ------------------------------------------------------
do $$
declare w uuid;
begin
  if exists (select 1 from public.ops_workflows where key = 'task') then return; end if;
  insert into public.ops_workflows (key, name, description)
  values ('task', 'Everyday task', 'To do, in progress, waiting, review and done.')
  returning id into w;
  insert into public.ops_workflow_stages
    (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
     is_review, is_terminal, wip_guidance, next_stage_keys) values
    (w, 'todo',      'To do',       1, 'intake',          false, false, false, false, null, array['doing','waiting','review','complete','cancelled']),
    (w, 'doing',     'In progress', 2, 'active',          true,  false, false, false, null, array['todo','waiting','review','complete','cancelled']),
    (w, 'waiting',   'Waiting',     3, 'waiting',         false, true,  false, false, null, array['todo','doing','review','complete','cancelled']),
    (w, 'review',    'Review',      4, 'internal_review', false, true,  true,  false, null, array['todo','doing','waiting','complete','cancelled']),
    (w, 'complete',  'Done',        5, 'done',            false, false, false, true,  null, array['todo','doing']),
    (w, 'cancelled', 'Cancelled',   6, 'cancelled',       false, false, false, true,  null, array['todo']);
end $$;

alter table public.ops_task_templates add column if not exists default_title    text;
alter table public.ops_task_templates add column if not exists default_owner_id uuid references public.team_members(id);
alter table public.ops_task_templates add column if not exists due_offset_days  integer;
create index if not exists ops_tasks_cancelled_idx on public.ops_tasks(cancelled_at desc)
  where cancelled_at is not null;

-- 2. Making a task --------------------------------------------------------------
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
  scope text;
  ttype text;
  cid   uuid;
  bad   text;
  descr text;
  period text;
  week  integer;
  seq   integer;
  code  text;
  title text;
  first_stage text;
  wkey  text;
  base  timestamptz;
  eng   public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  scope := coalesce(p_payload ->> 'scope', 'client');
  cid := (p_payload ->> 'client_id')::uuid;
  /* A task linked to a month's engagement takes the client from it: the
     person names the month once and the client comes with it. */
  if (p_payload ->> 'engagement_id') is not null then
    select * into eng from public.ops_engagements where id = (p_payload ->> 'engagement_id')::uuid;
    if eng.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if cid is null then cid := eng.client_id; scope := 'client'; end if;
  end if;
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;

  ttype := coalesce(p_payload ->> 'task_type', 'adhoc');
  if ttype not in ('engagement', 'adhoc', 'goodwill', 'special') then
    return jsonb_build_object('error', 'bad-task-type');
  end if;

  /* The description is the team's to edit and may start blank on a task that
     carries a code; a task with no code is named by its description alone, so
     there it is required. `title` is accepted from older callers as the
     description. */
  descr := nullif(btrim(coalesce(p_payload ->> 'content_desc', p_payload ->> 'title', '')), '');

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
    descr := coalesce(descr, nullif(btrim(coalesce(tpl.default_title, tpl.name, '')), ''));
  end if;
  /* New work goes on the content workflow. A caller may still name another
     (a template's own, or one somebody adds), and a task already on a retired
     workflow is never moved. */
  wf := coalesce((p_payload ->> 'workflow_id')::uuid,
                 (select id from public.ops_workflows where key = p_payload ->> 'workflow_key' and active),
                 tpl.workflow_id,
                 (select id from public.ops_workflows where key = 'content' and active),
                 (select id from public.ops_workflows where active order by created_at limit 1));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  select key into first_stage from public.ops_workflow_stages
   where workflow_id = wf order by position limit 1;
  select key into wkey from public.ops_workflows where id = wf;

  publish := (p_payload ->> 'publish_at')::timestamptz;
  fd := coalesce((p_payload ->> 'first_draft_due_at')::timestamptz,
        case when publish is not null and tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.first_draft_offset_business_days)
             when tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.first_draft_offset_business_days)
        end);
  /* A template's due date is a number of calendar days from the day the
     work is made for (the base date the caller names, else today). */
  base := coalesce((p_payload ->> 'base_date')::timestamptz, now());
  fin := coalesce((p_payload ->> 'final_due_at')::timestamptz,
        case when tpl.due_offset_days is not null
             then date_trunc('day', base) + make_interval(days => tpl.due_offset_days)
             when publish is not null and tpl.final_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.final_offset_business_days)
             when tpl.final_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.final_offset_business_days)
        end);
  if fd is not null and fin is not null and not public.ops_due_order_ok(fd, fin) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  /* The name. The month is the content month (the scheduled publish date's,
     else the one the caller names, else this one); the week is the planned
     publishing week, chosen by the caller and prefilled by the page from the
     date; the running number is the client's for the month. Generated once,
     under the lock, and never rewritten: a publish date that moves later
     leaves the name as it was, because the name is a label and not a fact
     about the date. */
  if wkey = 'task' then
    /* An everyday task is named by what it is. It carries no content code,
       because the code numbers a client's deliverables for the month and a
       task is not one; the content month is kept where it is known, so the
       task can be grouped with the month it belongs to. */
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
    period := coalesce(nullif(p_payload ->> 'code_period', ''), eng.period);
  elsif scope <> 'internal' then
    period := coalesce(nullif(p_payload ->> 'code_period', ''),
                       case when publish is not null then to_char(publish, 'YYYY-MM') end,
                       to_char(now(), 'YYYY-MM'));
    if period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
    week := coalesce((p_payload ->> 'code_week')::integer,
                     case when publish is not null
                          then least(5, ((extract(day from publish)::integer - 1) / 7) + 1) end,
                     1);
    if week < 1 or week > 5 then return jsonb_build_object('error', 'bad-week'); end if;
    seq := public.ops_next_seq(cid, period);
    code := public.ops_code_of(period, week, seq);
    title := btrim(code || ' ' || coalesce(descr, ''));
  else
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
  end if;

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality,
    task_type, code, code_period, code_week, code_seq, content_desc,
    engagement_id, manager_id, parent_task_id)
  values (
    scope, cid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, coalesce(first_stage, 'intake'),
    title, p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'other'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'),
    ttype, code, period, week, seq, descr,
    coalesce((p_payload ->> 'engagement_id')::uuid, eng.id),
    coalesce((p_payload ->> 'manager_id')::uuid, m.id),
    (p_payload ->> 'parent_task_id')::uuid)
  returning id into tid;

  owner := coalesce((p_payload ->> 'owner_id')::uuid, tpl.default_owner_id);
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

  -- The template's checklist, or the one the caller hands over (a duplicate
  -- carries its source's labels, unticked), in the order stated.
  for item in select * from jsonb_array_elements(
      coalesce(p_payload -> 'checklist', tpl.checklist, '[]'::jsonb)) loop
    i := i + 1;
    insert into public.ops_task_checklist_items (task_id, label, position)
    values (tid, item #>> '{}', i);
  end loop;

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
    jsonb_build_object('title', title, 'code', code,
                       'first_draft_due_at', fd, 'final_due_at', fin),
    case when (p_payload ->> 'duplicated_from') is null then '{}'::jsonb
         else jsonb_build_object('duplicated_from', p_payload ->> 'duplicated_from') end);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

-- 3. Moving a task --------------------------------------------------------------
/* The phase 4 move, with the rules this file adds: a skip keeps the
   published rule (ops Work, with a reason); AQC review comes before the
   client; a draft reaches the client as a link or with a note saying how;
   a revision says what changes; each review and revision counts its round;
   a finished task stops its timers; and a task that leaves Cancelled is no
   longer cancelled. */
create or replace function public.ops_transition_task(
  p_task uuid, p_next text, p_version integer default null, p_note text default null,
  p_assignee uuid default null, p_skip_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cur public.ops_workflow_stages;
  nxt public.ops_workflow_stages;
  sk  public.ops_workflow_stages;
  eng public.ops_engagements;
  has_owner boolean;
  has_draft boolean;
  has_final boolean;
  was_owner uuid;
  side text[] := array['blocked', 'waiting', 'kiv', 'cancelled'];
  skipping boolean := false;
  ws  public.ops_work_sessions;
  wmins integer;
  v_round integer;
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
  if t.stage_key = p_next then return public.ops_task_json(p_task); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  if not (p_next = any (cur.next_stage_keys)) then
    /* A step the deliverable does not need is skipped, forward along the
       line, with a reason on the record: who skipped it and why is written
       against every stage that was passed over. Nothing beside the line can
       be skipped into or out of, and nothing is skipped backwards. */
    /* A revision is where work is sent back from a review, so it is never
       a step somebody skips forward into. */
    if not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.stage_group <> 'revision'
       and nxt.position > cur.position then
      if nullif(btrim(coalesce(p_skip_reason, '')), '') is null then
        return jsonb_build_object('error', 'skip-reason-required');
      end if;
      skipping := true;
    else
      return jsonb_build_object('error', 'bad-transition',
        'allowed', to_jsonb(cur.next_stage_keys));
    end if;
  end if;

  /* A performance review goes back to whoever created the task unless the
     move names somebody else. */
  if p_next = 'performance_review' and p_assignee is null and exists (
       select 1 from public.team_members where id = t.created_by and active) then
    p_assignee := t.created_by;
  end if;

  -- What each gate needs before it opens.
  has_owner := exists (select 1 from public.ops_task_assignees
                        where task_id = p_task and responsibility = 'owner' and ended_at is null)
               or p_assignee is not null;
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
  /* Production waits on the engagement: planning marked complete, and the
     content meeting held or marked not applicable. A task with no engagement
     (ad hoc, internal) has nothing to wait on. */
  if p_next = 'in_production' and t.engagement_id is not null then
    select * into eng from public.ops_engagements where id = t.engagement_id;
    if eng.status = 'planning' then return jsonb_build_object('error', 'planning-incomplete'); end if;
    if not (eng.meeting_na or (eng.meeting_at is not null and eng.meeting_at <= now())) then
      return jsonb_build_object('error', 'meeting-required');
    end if;
  end if;
  /* AQC review comes first: the client sees the work only once it has been
     through AQC review at least once. */
  if p_next = 'client_review'
     and exists (select 1 from public.ops_workflow_stages s
                  where s.workflow_id = t.workflow_id and s.key = 'internal_review')
     and not exists (select 1 from public.ops_task_events e
                      where e.task_id = p_task and e.event_type = 'stage_changed'
                        and e.to_value ->> 'stage_key' = 'internal_review') then
    return jsonb_build_object('error', 'needs-aqc');
  end if;
  /* The draft reaches the client as a link on the task or through the
     team's WhatsApp group with the client. Either way the record says how:
     the link, or a note naming where it went. */
  if p_next = 'client_review' and not has_draft
     and nullif(btrim(coalesce(p_note, '')), '') is null then
    return jsonb_build_object('error', 'needs-draft');
  end if;
  /* A revision says what has to change, and so does taking a post down. */
  if ((nxt.stage_group = 'revision' and p_next <> 'changes_requested') or p_next = 'taken_down')
     and nullif(btrim(coalesce(p_note, '')), '') is null then
    return jsonb_build_object('error', 'note-required');
  end if;
  /* After approval: a schedule needs its date, going live is confirmed with
     its own date through ops_mark_live and needs the post's link or a note,
     and a task is completed only once its performance checklist is done. */
  if p_next = 'scheduled' and t.publish_at is null then
    return jsonb_build_object('error', 'needs-schedule');
  end if;
  if p_next = 'live' and t.live_at is null then
    return jsonb_build_object('error', 'needs-live-date');
  end if;
  if p_next = 'live' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;
  if p_next = 'completed' and exists (
       select 1 from public.ops_task_checklist_items c
        where c.task_id = p_task and c.required and c.completed_at is null) then
    return jsonb_build_object('error', 'checklist-incomplete');
  end if;
  if p_next = 'delivered' and not has_final then
    return jsonb_build_object('error', 'needs-final-link');
  end if;
  if p_next = 'done' and t.delivered_at is null
     and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-delivery-or-reason');
  end if;
  if p_next = 'published' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;

  /* The hand to the next person, recorded on the move: the previous owner
     ends, the new one begins, and the event names both with the stage it
     happened at. Work level, because handing the work on is part of doing
     it; reassigning a task without moving it stays Manage. */
  if p_assignee is not null then
    select team_member_id into was_owner from public.ops_task_assignees
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    if p_assignee is distinct from was_owner then
      if not exists (select 1 from public.team_members where id = p_assignee and active) then
        return jsonb_build_object('error', 'no-such-person');
      end if;
      update public.ops_task_assignees set ended_at = now()
       where task_id = p_task and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, p_assignee, 'owner', m.id);
      perform public.ops_log(p_task, 'assignment_changed',
        jsonb_build_object('owner_id', was_owner),
        jsonb_build_object('owner_id', p_assignee),
        jsonb_build_object('handover', true, 'stage_key', p_next, 'from_stage_key', t.stage_key));
    end if;
  end if;

  if skipping then
    for sk in select * from public.ops_workflow_stages
               where workflow_id = t.workflow_id
                 and position > cur.position and position < nxt.position
                 and not (stage_group = any (side))
               order by position loop
      perform public.ops_log(p_task, 'stage_skipped',
        jsonb_build_object('stage_key', sk.key), jsonb_build_object('stage_key', p_next),
        jsonb_build_object('reason', btrim(p_skip_reason)));
    end loop;
  end if;

  /* The round: how many times this task has now entered this review or
     this revision, counted off its own history, so nothing is stored that
     a reverted move could leave wrong. */
  if nxt.is_review or nxt.stage_group = 'revision' then
    select count(*) + 1 into v_round from public.ops_task_events e
     where e.task_id = p_task and e.event_type = 'stage_changed'
       and e.to_value ->> 'stage_key' = p_next;
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
    /* Leaving Cancelled for a live stage is a reopening, and the stamp
       leaves with it, as completed_at does; left behind, the task went on
       reading cancelled at the stage it had been reopened to. */
    cancelled_at = case when p_next = 'cancelled' then coalesce(cancelled_at, now())
                        when not nxt.is_terminal then null
                        else cancelled_at end,
    blocked_at = case when p_next = 'blocked' then blocked_at else null end,
    blocked_category = case when p_next = 'blocked' then blocked_category else null end
  where id = p_task;

  /* The performance review brings its own checklist, the same five checks
     for a brand post and a KOC post, added once however often the task
     comes back to the stage. */
  if p_next = 'performance_review' then
    insert into public.ops_task_checklist_items (task_id, label, position, required)
    select p_task, x.label,
           coalesce((select max(c.position) from public.ops_task_checklist_items c
                      where c.task_id = p_task), 0) + x.n,
           true
      from (values (1, 'Reach and views checked'),
                   (2, 'Engagement checked (likes, comments, shares, saves)'),
                   (3, 'Comments checked for brand safety'),
                   (4, 'Leads or sales checked, where tracked'),
                   (5, 'Keep live or take down decided')) as x(n, label)
     where not exists (select 1 from public.ops_task_checklist_items c
                        where c.task_id = p_task and c.label = x.label);
  end if;

  /* A finished task is not being worked on, so every timer running on it
     stops with it, each filed as the stop it is. */
  if nxt.is_terminal then
    for ws in select * from public.ops_work_sessions
               where task_id = p_task and ended_at is null loop
      wmins := greatest(0, (extract(epoch from (now() - ws.started_at)) / 60)::integer);
      update public.ops_work_sessions set ended_at = now(), minutes = wmins where id = ws.id;
      perform public.ops_log(p_task, 'work_stopped', null,
        jsonb_build_object('session_id', ws.id, 'minutes', wmins),
        jsonb_build_object('note', 'Stopped when the task finished'));
    end loop;
  end if;

  perform public.ops_log(p_task, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', p_next),
    (case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end)
    || (case when skipping then jsonb_build_object('skip_reason', btrim(p_skip_reason)) else '{}'::jsonb end)
    || (case when v_round is not null then jsonb_build_object('round', v_round) else '{}'::jsonb end));
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
grant execute on function public.ops_transition_task(uuid, text, integer, text, uuid, text) to authenticated;

/* Changing responsibility without changing the stage. The note is for the
   person taking it on, so it is kept on the event and not in a column. */
create or replace function public.ops_hand_over_task(
  p_task uuid, p_owner uuid, p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if p_owner is null then return jsonb_build_object('error', 'no-such-person'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if not exists (select 1 from public.team_members where id = p_owner and active) then
    return jsonb_build_object('error', 'no-such-person');
  end if;

  select team_member_id into was from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null;
  if p_owner is not distinct from was then return public.ops_task_json(p_task); end if;

  update public.ops_task_assignees set ended_at = now()
   where task_id = p_task and responsibility = 'owner' and ended_at is null;
  insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
  values (p_task, p_owner, 'owner', m.id);
  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'assignment_changed',
    jsonb_build_object('owner_id', was),
    jsonb_build_object('owner_id', p_owner),
    jsonb_build_object('handover', true, 'stage_key', t.stage_key)
      || case when nullif(btrim(coalesce(p_note, '')), '') is null then '{}'::jsonb
              else jsonb_build_object('note', btrim(p_note)) end);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_hand_over_task(uuid, uuid, text, integer) to authenticated;

/* The scheduled publish date: tentative until the content meeting, never
   a commitment, so it moves on the press and gates nothing. */
create or replace function public.ops_set_publish_date(
  p_task uuid, p_at timestamptz, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
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
  if t.publish_at is not distinct from p_at then return public.ops_task_json(p_task); end if;

  update public.ops_tasks set publish_at = p_at, version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'publish_changed',
    jsonb_build_object('value', t.publish_at), jsonb_build_object('value', p_at), '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_set_publish_date(uuid, timestamptz, integer) to authenticated;

-- 4. Adding to a task -----------------------------------------------------------
/* One more thing to tick, at the foot of the list. */
create or replace function public.ops_add_checklist_item(p_task uuid, p_label text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  lbl text;
  pos integer;
  iid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  lbl := nullif(btrim(coalesce(p_label, '')), '');
  if lbl is null then return jsonb_build_object('error', 'label-required'); end if;
  if length(lbl) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  select coalesce(max(position), 0) + 1 into pos from public.ops_task_checklist_items where task_id = p_task;
  insert into public.ops_task_checklist_items (task_id, label, position)
  values (p_task, lbl, pos) returning id into iid;
  perform public.ops_log(p_task, 'checklist_changed', null,
    jsonb_build_object('label', lbl, 'added', true), '{}'::jsonb);
  return (select to_jsonb(c) from public.ops_task_checklist_items c where c.id = iid);
end $$;
grant execute on function public.ops_add_checklist_item(uuid, text) to authenticated;

/* A comment is an event: it is read in the task's own history, in order,
   with who wrote it. The event itself is never rewritten; a correction or a
   removal is a later event (section 15). */
create or replace function public.ops_add_comment(p_task uuid, p_body text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  body text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  body := nullif(btrim(coalesce(p_body, '')), '');
  if body is null then return jsonb_build_object('error', 'comment-required'); end if;
  if length(body) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  perform public.ops_log(p_task, 'commented', null, null, jsonb_build_object('note', body));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_add_comment(uuid, text) to authenticated;

-- 5. Templates ------------------------------------------------------------------
/* A template is the task somebody makes every month: its title, its owner,
   when it is due relative to the day it is made for, its checklist and its
   estimate. Kept by whoever holds the granted part ops.workflows. */
create or replace function public.ops_save_template(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  nm   text;
  wf   uuid;
  tid  uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('ops.workflows', 'work') then return jsonb_build_object('error', 'denied'); end if;
  nm := nullif(btrim(coalesce(p_payload ->> 'name', '')), '');
  if nm is null then return jsonb_build_object('error', 'name-required'); end if;
  if exists (select 1 from public.ops_task_templates
              where lower(name) = lower(nm) and id is distinct from p_id) then
    return jsonb_build_object('error', 'name-taken');
  end if;
  wf := coalesce((select id from public.ops_workflows where key = coalesce(p_payload ->> 'workflow_key', 'task')),
                 (select id from public.ops_workflows where key = 'task'));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  if p_id is null then
    insert into public.ops_task_templates (name, deliverable_type, workflow_id, default_title,
      default_owner_id, due_offset_days, default_estimate_minutes, checklist, active)
    values (nm, coalesce(nullif(p_payload ->> 'deliverable_type', ''), 'other'), wf,
      nullif(btrim(coalesce(p_payload ->> 'default_title', '')), ''),
      (p_payload ->> 'default_owner_id')::uuid,
      (p_payload ->> 'due_offset_days')::integer,
      (p_payload ->> 'default_estimate_minutes')::integer,
      coalesce(p_payload -> 'checklist', '[]'::jsonb),
      coalesce((p_payload ->> 'active')::boolean, true))
    returning id into tid;
  else
    update public.ops_task_templates set
      name = nm,
      deliverable_type = coalesce(nullif(p_payload ->> 'deliverable_type', ''), deliverable_type),
      workflow_id = wf,
      default_title = nullif(btrim(coalesce(p_payload ->> 'default_title', '')), ''),
      default_owner_id = (p_payload ->> 'default_owner_id')::uuid,
      due_offset_days = (p_payload ->> 'due_offset_days')::integer,
      default_estimate_minutes = (p_payload ->> 'default_estimate_minutes')::integer,
      checklist = coalesce(p_payload -> 'checklist', '[]'::jsonb),
      active = coalesce((p_payload ->> 'active')::boolean, active),
      updated_at = now()
    where id = p_id
    returning id into tid;
    if tid is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  return (select to_jsonb(x) from public.ops_task_templates x where x.id = tid);
end $$;
grant execute on function public.ops_save_template(uuid, jsonb) to authenticated;

-- 10. The task number reads #WT00001 ---------------------------------------------
/* One running number for every task, written with a fixed prefix and five
   digits. The number is the same column it always was; how it is written
   lives here and nowhere else in the database. */
create or replace function public.ops_serial(p_no bigint)
returns text
language sql immutable set search_path = public as $$
  select '#WT' || lpad(p_no::text, 5, '0')
$$;
grant execute on function public.ops_serial(bigint) to authenticated;

/* ops_log as phase 4 left it, with the number written by ops_serial and the
   round named when work comes back for a review or a revision. */
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

  if p_type = 'assignment_changed' then
    owner := (p_to ->> 'owner_id')::uuid;
    if owner is not null and owner is distinct from m.id then
      perform public.ops_notify(owner, p_task, 'assigned',
        public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
        case when coalesce((p_detail ->> 'handover')::boolean, false)
             then 'Handed to you by ' || who || ' at ' ||
                  coalesce((public.ops_stage(t.workflow_id, p_detail ->> 'stage_key')).label, p_detail ->> 'stage_key') || '.'
             else 'Assigned to you by ' || who || '.' end,
        'assigned:' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
    end if;
    return;
  end if;

  select team_member_id into owner from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null
   limit 1;
  if owner is null or owner = m.id then return; end if;

  if p_type = 'stage_changed' then
    st := public.ops_stage(t.workflow_id, p_to ->> 'stage_key');
    body := 'Moved to ' || coalesce(st.label, p_to ->> 'stage_key')
      || coalesce(', round ' || (p_detail ->> 'round'), '') || ' by ' || who || '.';
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
    public.ops_serial(t.task_no) || ' · ' || public.ops_title(t), body,
    p_type || ':' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
end $$;

/* The deletion names the task the way every screen does, and the number is
   typed back with or without the # and in any case. */
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
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if upper(regexp_replace(coalesce(p_confirm, ''), '[^A-Za-z0-9]', '', 'g'))
     <> upper(regexp_replace(public.ops_serial(t.task_no), '[^A-Za-z0-9]', '', 'g')) then
    return jsonb_build_object('error', 'confirm-required');
  end if;

  select c.name into cl from public.clients c where c.id = t.client_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.deleted',
          public.ops_serial(t.task_no),
          public.ops_title(t) ||
          coalesce(' · ' || cl, case when t.scope = 'internal' then ' · Internal' else '' end) ||
          coalesce(' · ' || nullif(btrim(p_reason), ''), ''));

  delete from public.ops_tasks where id = p_task;
  return jsonb_build_object('deleted', true, 'task_no', t.task_no);
end $$;
grant execute on function public.ops_delete_task(uuid, text, text) to authenticated;

-- 11. The content workflow: its words, AQC review, and what follows approval ----
/* In progress, Ready to start and AQC review are the team's words, applied
   only where a stage still reads as seeded, so a label somebody changed is
   left alone. Two revision loops replace the one: Revision (Internal) is
   reached from AQC review only and Revision (Client) from Client review
   only, each back to the review it came from. After approval the work is
   Scheduled, goes Live on a confirmed date, has its Performance review, and
   ends Completed or Taken down. Changes requested and Published stay for any
   task already in them and are no longer offered as next steps. Positions
   are appended after the last one, so nothing already placed moves. */
do $$
declare
  w uuid;
  p integer;
begin
  select id into w from public.ops_workflows where key = 'content';
  if w is null then return; end if;

  update public.ops_workflow_stages set label = 'In progress'
   where workflow_id = w and key = 'in_production' and label = 'In production';
  update public.ops_workflow_stages set label = 'Ready to start'
   where workflow_id = w and key = 'ready' and label = 'Ready for production';
  update public.ops_workflow_stages set label = 'AQC review'
   where workflow_id = w and key = 'internal_review' and label = 'Internal quality review';

  if not exists (select 1 from public.ops_workflow_stages
                  where workflow_id = w and key = 'revision_internal') then
    select coalesce(max(position), 0) into p from public.ops_workflow_stages where workflow_id = w;
    insert into public.ops_workflow_stages
      (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
       is_review, is_terminal, wip_guidance, next_stage_keys) values
      (w, 'revision_internal',  'Revision (Internal)', p + 1, 'revision',    true,  false, false, false, null,
          array['internal_review', 'blocked', 'on_hold']),
      (w, 'revision_client',    'Revision (Client)',   p + 2, 'revision',    true,  false, false, false, null,
          array['client_review', 'internal_review', 'blocked', 'on_hold']),
      (w, 'scheduled',          'Scheduled',           p + 3, 'scheduled',   false, true,  false, false, null,
          array['live', 'revision_client', 'on_hold', 'cancelled']),
      (w, 'live',               'Live',                p + 4, 'live',        false, true,  false, false, null,
          array['performance_review', 'taken_down']),
      (w, 'performance_review', 'Performance review',  p + 5, 'performance', false, false, true,  false, null,
          array['completed', 'taken_down', 'live']),
      (w, 'taken_down',         'Taken down',          p + 6, 'taken_down',  false, false, false, true,  null,
          array['live']),
      (w, 'completed',          'Completed',           p + 7, 'done',        false, false, false, true,  null,
          array['performance_review']);

    update public.ops_workflow_stages set next_stage_keys =
      array['client_review', 'revision_internal', 'in_production', 'blocked']
     where workflow_id = w and key = 'internal_review';
    update public.ops_workflow_stages set next_stage_keys =
      array['approved', 'revision_client', 'blocked', 'on_hold']
     where workflow_id = w and key = 'client_review';
    update public.ops_workflow_stages set next_stage_keys =
      array['scheduled', 'live', 'revision_client']
     where workflow_id = w and key = 'approved';
    update public.ops_workflow_stages set next_stage_keys =
      array['ready', 'in_production', 'internal_review', 'revision_internal', 'client_review',
            'revision_client', 'scheduled', 'cancelled']
     where workflow_id = w and key = 'blocked';
    update public.ops_workflow_stages set next_stage_keys =
      array['planning', 'ready', 'in_production', 'internal_review', 'revision_internal',
            'client_review', 'revision_client', 'scheduled', 'cancelled']
     where workflow_id = w and key = 'on_hold';
  end if;
end $$;

-- 12. The live date and the rating -------------------------------------------------
/* When the work actually went live, and what the team made of the task once
   it was finished. A column each, added, never a rewrite. */
alter table public.ops_tasks add column if not exists live_at     timestamptz;
alter table public.ops_tasks add column if not exists rating      smallint;
alter table public.ops_tasks add column if not exists rating_note text;
alter table public.ops_tasks add column if not exists rated_by    uuid references public.team_members(id);
alter table public.ops_tasks add column if not exists rated_at    timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ops_tasks_rating_range') then
    alter table public.ops_tasks add constraint ops_tasks_rating_range
      check (rating is null or rating between 1 and 5);
  end if;
end $$;

/* Going live. The date is today unless somebody says otherwise; a date that
   differs from the scheduled one says why, and both dates and the reason are
   on the record. The move itself is ops_transition_task, with every gate it
   has, and the date is put back if the move is refused. */
create or replace function public.ops_mark_live(
  p_task uuid, p_live_at timestamptz, p_reason text default null,
  p_version integer default null, p_assignee uuid default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  t    public.ops_tasks;
  res  jsonb;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if p_live_at is null then return jsonb_build_object('error', 'no-date'); end if;
  if (p_live_at at time zone 'Asia/Kuala_Lumpur')::date
     > (now() at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'live-in-future');
  end if;
  if t.publish_at is not null
     and (p_live_at at time zone 'Asia/Kuala_Lumpur')::date
         <> (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date
     and nullif(btrim(coalesce(p_reason, '')), '') is null then
    return jsonb_build_object('error', 'live-reason-required');
  end if;

  update public.ops_tasks set live_at = p_live_at where id = p_task;
  res := public.ops_transition_task(p_task, 'live', p_version, p_note, p_assignee, null);
  if res ? 'error' then
    update public.ops_tasks set live_at = t.live_at where id = p_task;
    return res;
  end if;
  perform public.ops_log(p_task, 'live_confirmed',
    jsonb_build_object('scheduled', t.publish_at),
    jsonb_build_object('live_at', p_live_at),
    case when nullif(btrim(coalesce(p_reason, '')), '') is null then '{}'::jsonb
         else jsonb_build_object('reason', btrim(p_reason)) end);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_mark_live(uuid, timestamptz, text, integer, uuid, text) to authenticated;

/* A finished task is rated one to five, with a line if there is one to say.
   Changing the rating is a second event, never an overwrite of the first. */
create or replace function public.ops_rate_task(p_task uuid, p_rating integer, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.completed_at is null then return jsonb_build_object('error', 'not-finished'); end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    return jsonb_build_object('error', 'bad-rating');
  end if;
  update public.ops_tasks set
    rating = p_rating,
    rating_note = nullif(btrim(coalesce(p_note, '')), ''),
    rated_by = m.id,
    rated_at = now()
  where id = p_task;
  perform public.ops_log(p_task, 'rated',
    case when t.rating is null then null else jsonb_build_object('rating', t.rating) end,
    jsonb_build_object('rating', p_rating),
    case when nullif(btrim(coalesce(p_note, '')), '') is null then '{}'::jsonb
         else jsonb_build_object('note', btrim(p_note)) end);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_rate_task(uuid, integer, text) to authenticated;

-- 13. Several tasks deleted at once --------------------------------------------------
/* The same act as ops_delete_task, for a selection: ops Manage, every task in
   it one the person may see or none is deleted, the count typed back, a
   reason, and a row in the activity record for each task, because the task's
   own history goes with it. At most 500 in one act. */
create or replace function public.ops_delete_tasks(p_tasks uuid[], p_confirm text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  t     public.ops_tasks;
  want  integer := coalesce(array_length(p_tasks, 1), 0);
  n     integer := 0;
  cl    text;
  why   text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if want = 0 then return jsonb_build_object('error', 'none-selected'); end if;
  if want > 500 then return jsonb_build_object('error', 'too-many'); end if;
  if btrim(coalesce(p_confirm, '')) <> want::text then
    return jsonb_build_object('error', 'confirm-required');
  end if;
  if why is null then return jsonb_build_object('error', 'reason-required'); end if;
  if exists (select 1 from unnest(p_tasks) x where not public.ops_may_see_task(x)) then
    return jsonb_build_object('error', 'denied');
  end if;

  for t in select * from public.ops_tasks where id = any (p_tasks) order by task_no for update loop
    select c.name into cl from public.clients c where c.id = t.client_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(m.name, m.email), 'ops.deleted', public.ops_serial(t.task_no),
            public.ops_title(t) ||
            coalesce(' · ' || cl, case when t.scope = 'internal' then ' · Internal' else '' end) ||
            ' · ' || why);
    delete from public.ops_tasks where id = t.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('deleted', n);
end $$;
grant execute on function public.ops_delete_tasks(uuid[], text, text) to authenticated;

-- 14. The next number, for an admin -------------------------------------------------
/* What the next task will be numbered, and the place to set it: an admin
   only, never below or on a number a task already holds, and filed in the
   activity record. */
create or replace function public.ops_next_task_no()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  lv   bigint;
  ic   boolean;
  nxt  bigint;
  top  bigint;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  select last_value, is_called into lv, ic from public.ops_task_no_seq;
  nxt := case when ic then lv + 1 else lv end;
  select max(task_no) into top from public.ops_tasks;
  return jsonb_build_object('next', nxt, 'serial', public.ops_serial(nxt),
    'highest', top, 'highest_serial', case when top is null then null else public.ops_serial(top) end);
end $$;
grant execute on function public.ops_next_task_no() to authenticated;

create or replace function public.ops_set_next_task_no(p_next bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  top  bigint;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  if p_next is null or p_next < 1 or p_next > 9999999 then
    return jsonb_build_object('error', 'bad-number');
  end if;
  select max(task_no) into top from public.ops_tasks;
  if top is not null and p_next <= top then
    return jsonb_build_object('error', 'number-taken', 'highest', public.ops_serial(top));
  end if;
  perform setval('public.ops_task_no_seq', p_next, false);
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.numbering', 'My Work',
          'Next task number set to ' || public.ops_serial(p_next));
  return public.ops_next_task_no();
end $$;
grant execute on function public.ops_set_next_task_no(bigint) to authenticated;

-- 15. Changing and taking back what was added ------------------------------------
/* Everything a person adds to a task can be put right afterwards: the brief
   and the priority, a checklist item, a link, a comment. Each change is an
   event beside the others, so the record shows what it was and what it
   became. A required check is the review's own gate and is neither renamed
   nor removed. A comment is never rewritten: a correction or a removal is a
   later event, and the history keeps what was said and when. */
create or replace function public.ops_update_task(
  p_task uuid, p_payload jsonb, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  t     public.ops_tasks;
  d     text;
  pr    integer;
  was   jsonb := '{}'::jsonb;
  now_  jsonb := '{}'::jsonb;
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
  d := t.description;
  pr := t.priority_level;
  if p_payload ? 'description' then
    d := nullif(btrim(coalesce(p_payload ->> 'description', '')), '');
    if length(coalesce(d, '')) > 4000 then return jsonb_build_object('error', 'too-long'); end if;
  end if;
  if p_payload ? 'priority_level' then
    pr := (p_payload ->> 'priority_level')::integer;
    if pr is null or pr < 1 or pr > 4 then return jsonb_build_object('error', 'bad-priority'); end if;
  end if;
  if d is not distinct from t.description and pr is not distinct from t.priority_level then
    return public.ops_task_json(p_task);
  end if;
  if d is distinct from t.description then
    was := was || jsonb_build_object('description', t.description);
    now_ := now_ || jsonb_build_object('description', d);
  end if;
  if pr is distinct from t.priority_level then
    was := was || jsonb_build_object('priority_level', t.priority_level);
    now_ := now_ || jsonb_build_object('priority_level', pr);
  end if;
  update public.ops_tasks set description = d, priority_level = pr,
         version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'details_changed', was, now_, '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_update_task(uuid, jsonb, integer) to authenticated;

create or replace function public.ops_edit_checklist_item(p_item uuid, p_label text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  c   public.ops_task_checklist_items;
  lbl text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into c from public.ops_task_checklist_items where id = p_item for update;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(c.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if c.required then return jsonb_build_object('error', 'item-required'); end if;
  lbl := nullif(btrim(coalesce(p_label, '')), '');
  if lbl is null then return jsonb_build_object('error', 'label-required'); end if;
  if length(lbl) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  if lbl = c.label then return to_jsonb(c); end if;
  update public.ops_task_checklist_items set label = lbl where id = p_item;
  perform public.ops_log(c.task_id, 'checklist_changed',
    jsonb_build_object('label', c.label),
    jsonb_build_object('label', lbl, 'renamed', true), '{}'::jsonb);
  return (select to_jsonb(x) from public.ops_task_checklist_items x where x.id = p_item);
end $$;
grant execute on function public.ops_edit_checklist_item(uuid, text) to authenticated;

create or replace function public.ops_remove_checklist_item(p_item uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  c   public.ops_task_checklist_items;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into c from public.ops_task_checklist_items where id = p_item for update;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(c.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if c.required then return jsonb_build_object('error', 'item-required'); end if;
  delete from public.ops_task_checklist_items where id = p_item;
  perform public.ops_log(c.task_id, 'checklist_changed',
    jsonb_build_object('label', c.label, 'done', c.completed_at is not null),
    jsonb_build_object('label', c.label, 'removed', true), '{}'::jsonb);
  return jsonb_build_object('removed', to_jsonb(c));
end $$;
grant execute on function public.ops_remove_checklist_item(uuid) to authenticated;

create or replace function public.ops_update_link(
  p_link uuid, p_label text, p_url text, p_kind text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  l   public.ops_task_links;
  t   public.ops_tasks;
  lbl text;
  u   text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into l from public.ops_task_links where id = p_link for update;
  if l.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(l.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind not in ('brief', 'asset', 'draft', 'review', 'final', 'other') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  u := nullif(btrim(coalesce(p_url, '')), '');
  if u is null then return jsonb_build_object('error', 'url-required'); end if;
  select * into t from public.ops_tasks where id = l.task_id for update;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(l.task_id));
  end if;
  lbl := coalesce(nullif(btrim(coalesce(p_label, '')), ''), initcap(p_kind) || ' link');
  if lbl = l.label and u = l.url and p_kind = l.kind then
    return jsonb_build_object('link_id', l.id, 'task', public.ops_task_json(l.task_id));
  end if;
  update public.ops_task_links set label = lbl, url = u, kind = p_kind where id = p_link;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = l.task_id;
  perform public.ops_log(l.task_id, 'file_changed',
    jsonb_build_object('link_id', l.id, 'label', l.label, 'url', l.url, 'kind', l.kind),
    jsonb_build_object('link_id', l.id, 'label', lbl, 'url', u, 'kind', p_kind), '{}'::jsonb);
  return jsonb_build_object('link_id', l.id, 'task', public.ops_task_json(l.task_id));
end $$;
grant execute on function public.ops_update_link(uuid, text, text, text, integer) to authenticated;

/* A comment is corrected or removed by the person who wrote it, or by ops
   Manage, through a later event that names it. */
create or replace function public.ops_edit_comment(p_event uuid, p_body text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  e    public.ops_task_events;
  body text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into e from public.ops_task_events where id = p_event;
  if e.id is null or e.event_type <> 'commented' then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(e.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if e.actor_id is distinct from m.id and not public.allowed('ops', 'manage') then
    return jsonb_build_object('error', 'not-yours');
  end if;
  body := nullif(btrim(coalesce(p_body, '')), '');
  if body is null then return jsonb_build_object('error', 'comment-required'); end if;
  if length(body) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  perform public.ops_log(e.task_id, 'comment_edited',
    jsonb_build_object('event_id', e.id), jsonb_build_object('event_id', e.id),
    jsonb_build_object('note', body));
  return public.ops_task_json(e.task_id);
end $$;
grant execute on function public.ops_edit_comment(uuid, text) to authenticated;

create or replace function public.ops_remove_comment(p_event uuid, p_on boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  e public.ops_task_events;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into e from public.ops_task_events where id = p_event;
  if e.id is null or e.event_type <> 'commented' then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(e.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if e.actor_id is distinct from m.id and not public.allowed('ops', 'manage') then
    return jsonb_build_object('error', 'not-yours');
  end if;
  perform public.ops_log(e.task_id, case when p_on then 'comment_removed' else 'comment_restored' end,
    jsonb_build_object('event_id', e.id), jsonb_build_object('event_id', e.id), '{}'::jsonb);
  return public.ops_task_json(e.task_id);
end $$;
grant execute on function public.ops_remove_comment(uuid, boolean) to authenticated;

-- END OF MY WORK AS A DAILY TASK TRACKER -----------------------------------

-- ===========================================================================
-- THE MONTH IN TWO TICKS — the readiness list is two checklists, who ticked
-- is recorded by the database, and a month can be deleted.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   1. A month's readiness is two ticks, Onboarding checklist and
--      Pre-advertising checklist, in place of thirteen questions with a state
--      and an owner each. The detailed checklists are the team's own forms;
--      the portal records that each is done. Every existing month takes the
--      two rows once: Onboarding is ticked where every onboarding question
--      was Ready or Not applicable, Pre-advertising where its checklist was
--      completed (Not applicable where it was not required), and the
--      thirteen rows then go.
--
--   2. `ops_engagement_upsert` seeds the two rows on a new month.
--
--   3. `ops_engagement_set_check` records the person who made the change as
--      the check's owner. The owner is no longer chosen by hand.
--
--   4. `ops_delete_engagement` (ops Manage): a month is deleted with a reason.
--      Its tasks stay and leave the month; its checks and its own history go
--      with it; the activity record keeps `ops.month_deleted` naming the
--      client, the month and how many tasks it held.
--
--   5. `activity_section` files `ops.month_deleted` under My Work. It is at
--      the foot, after the end marker, like every copy of that function.
--
--   The gate is unchanged: Ready and In production still need every check
--   Ready or Not applicable, and the meeting held or marked not applicable.
--
-- ROLLBACK
--   drop function if exists public.ops_delete_engagement(uuid, text);
--   Then re-run 2026-09-23-operations-phase4.sql for the thirteen-question
--   ops_engagement_upsert and ops_engagement_set_check. The thirteen rows
--   removed from existing months are not restored: their answers were folded
--   into the two ticks and the fold is not reversible.
-- ===========================================================================

-- 1. Two ticks on every month that exists ------------------------------------
insert into public.ops_engagement_checks (engagement_id, key, state, updated_at)
select e.id, 'onboarding',
       case when exists (select 1 from public.ops_engagement_checks c
                          where c.engagement_id = e.id
                            and c.key in ('client_name', 'legal_name', 'brand_name', 'brand_profile',
                                          'social_profiles', 'client_info', 'platform_ready',
                                          'platform_setup', 'platform_create',
                                          'partner_access_requested', 'partner_access_received'))
             and not exists (select 1 from public.ops_engagement_checks c
                              where c.engagement_id = e.id
                                and c.key in ('client_name', 'legal_name', 'brand_name', 'brand_profile',
                                              'social_profiles', 'client_info', 'platform_ready',
                                              'platform_setup', 'platform_create',
                                              'partner_access_requested', 'partner_access_received')
                                and c.state not in ('ready', 'na'))
            then 'ready' else 'not_started' end,
       now()
  from public.ops_engagements e
on conflict (engagement_id, key) do nothing;

insert into public.ops_engagement_checks (engagement_id, key, state, updated_at)
select e.id, 'pre_ads',
       case when exists (select 1 from public.ops_engagement_checks c
                          where c.engagement_id = e.id and c.key = 'pre_ads_completed' and c.state = 'ready')
            then 'ready'
            when exists (select 1 from public.ops_engagement_checks c
                          where c.engagement_id = e.id and c.key in ('pre_ads_required', 'pre_ads_completed')
                            and c.state = 'na')
            then 'na'
            else 'not_started' end,
       now()
  from public.ops_engagements e
on conflict (engagement_id, key) do nothing;

delete from public.ops_engagement_checks where key not in ('onboarding', 'pre_ads');

-- 2. A new month is seeded with the two ------------------------------------------
/* One a client a month. A second call for the same month edits the one row
   rather than making a second; the two checks are seeded on creation and
   never re-seeded. */
create or replace function public.ops_engagement_upsert(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  cid uuid;
  per text;
  eid uuid;
  k text;
  fresh boolean := false;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  if cid is null or not exists (select 1 from public.clients where id = cid) then
    return jsonb_build_object('error', 'client-required');
  end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;

  select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
  if eid is null then
    insert into public.ops_engagements (client_id, period, manager_id, planned_count, drive_url, created_by)
    values (cid, per, coalesce((p_payload ->> 'manager_id')::uuid, m.id),
            coalesce((p_payload ->> 'planned_count')::integer, 0),
            nullif(p_payload ->> 'drive_url', ''), m.id)
    on conflict (client_id, period) do nothing
    returning id into eid;
    /* Somebody else made it between the read and the write: theirs stands. */
    if eid is null then
      select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
    else
      fresh := true;
    end if;
  end if;
  if fresh then
    foreach k in array array['onboarding', 'pre_ads'] loop
      insert into public.ops_engagement_checks (engagement_id, key) values (eid, k)
      on conflict do nothing;
    end loop;
    perform public.ops_engagement_log(eid, 'created', p_payload - 'client_id');
  else
    if not public.ops_may_see_engagement(eid) then return jsonb_build_object('error', 'denied'); end if;
    /* Asked for with nothing to change, the month is answered as it stands:
       a task made for a month joins it without editing it. */
    if (p_payload - 'client_id' - 'period') = '{}'::jsonb then
      return public.ops_engagement_json(eid) || jsonb_build_object('created', false);
    end if;
    update public.ops_engagements set
      manager_id = coalesce((p_payload ->> 'manager_id')::uuid, manager_id),
      planned_count = coalesce((p_payload ->> 'planned_count')::integer, planned_count),
      drive_url = case when p_payload ? 'drive_url' then nullif(p_payload ->> 'drive_url', '') else drive_url end,
      updated_at = now(), version = version + 1
    where id = eid;
    perform public.ops_engagement_log(eid, 'edited', p_payload - 'client_id' - 'period');
  end if;
  return public.ops_engagement_json(eid) || jsonb_build_object('created', fresh);
end $$;
grant execute on function public.ops_engagement_upsert(jsonb) to authenticated;

-- 3. Who ticked it is who is recorded --------------------------------------------
/* The owner of a check is the person who last changed it, stamped here and
   never chosen on the page. `p_owner` is kept so a caller written for the
   older shape is not refused; it is not read. */
create or replace function public.ops_engagement_set_check(
  p_engagement uuid, p_key text, p_state text, p_owner uuid default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; was text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_state not in ('not_started', 'waiting_client', 'in_progress', 'ready', 'na') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  select state into was from public.ops_engagement_checks
   where engagement_id = p_engagement and key = p_key;
  if was is null then return jsonb_build_object('error', 'no-such-check'); end if;
  if was = p_state and p_note is null then return public.ops_engagement_json(p_engagement); end if;
  update public.ops_engagement_checks
     set state = p_state, owner_id = m.id,
         note = case when p_note is null then note else nullif(btrim(p_note), '') end,
         updated_by = m.id, updated_at = now()
   where engagement_id = p_engagement and key = p_key;
  perform public.ops_engagement_log(p_engagement, 'check_changed',
    jsonb_build_object('key', p_key, 'from', was, 'to', p_state));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_check(uuid, text, text, uuid, text) to authenticated;

-- 4. A month is deleted -----------------------------------------------------------
/* A month keyed in for the wrong client or the wrong period has to be able
   to go. ops Manage, a reason, and a row in the activity record, because the
   month's own history goes with it. Its tasks are not deleted: they stay, with
   their codes, and simply leave the month. */
create or replace function public.ops_delete_engagement(p_engagement uuid, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m  public.team_members;
  e  public.ops_engagements;
  cl text;
  n  integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return jsonb_build_object('error', 'reason-required');
  end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select c.name into cl from public.clients c where c.id = e.client_id;
  select count(*) into n from public.ops_tasks t where t.engagement_id = e.id;

  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.month_deleted', coalesce(cl, 'Client'),
          to_char(to_date(e.period || '-01', 'YYYY-MM-DD'), 'Mon YYYY') ||
          case when n = 1 then ' · 1 task left the month'
               when n > 1 then ' · ' || n || ' tasks left the month' else '' end ||
          ' · ' || btrim(p_reason));

  delete from public.ops_engagements where id = e.id;
  return jsonb_build_object('deleted', true, 'period', e.period, 'tasks', n);
end $$;
grant execute on function public.ops_delete_engagement(uuid, text) to authenticated;

-- END OF THE MONTH IN TWO TICKS --------------------------------------------

-- ===========================================================================
-- THE CONTENT MEETING ON GOOGLE MEET — a length, a link, and the calendar
-- event it lives on.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   1. Three columns on `ops_engagements`: `meeting_minutes` (how long, 15 to
--      240, 30 by default, so the message to the client can say when it
--      ends), `meeting_link` (the Meet link, generated or pasted), and
--      `meeting_event_id` (the event on the shared Google calendar, so a
--      moved meeting moves the event and a cancelled one removes it).
--
--   2. `ops_engagement_set_meeting` takes the length and a pasted link. Its
--      older six-argument shape is dropped first, because PostgREST cannot
--      tell a call that names six arguments from one that names six and
--      leaves two to their defaults. Marking the month as having no meeting
--      clears the link; the calendar event is removed by the page through
--      the meet-create function.
--
--   3. `ops_engagement_meet_prepare` and `ops_engagement_set_meet`, the two
--      calls the meet-create edge function makes as the signed-in person: the
--      first answers what the calendar needs (and refuses a person who may
--      not work the month), the second records the link and the event. Both
--      ask what every write on the month asks: ops Work, and a month the
--      person may see.
--
--   4. `ops_log` tells a task's owner when somebody else comments on it, with
--      the first 140 characters of the comment. Every other rule is as the
--      daily tracker left it: nobody is told about their own act.
--
-- ROLLBACK
--   drop function if exists public.ops_engagement_meet_prepare(uuid);
--   drop function if exists public.ops_engagement_set_meet(uuid, text, text);
--   drop function if exists public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean, integer, text);
--   Re-run 2026-09-23-operations-phase4.sql for the six-argument
--   ops_engagement_set_meeting and 2026-09-24-my-work-daily-tasks.sql for
--   ops_log, then:
--   alter table public.ops_engagements drop column if exists meeting_minutes,
--     drop column if exists meeting_link, drop column if exists meeting_event_id;
-- ===========================================================================

-- 1. The length, the link and the event --------------------------------------
alter table public.ops_engagements add column if not exists meeting_minutes integer not null default 30;
alter table public.ops_engagements add column if not exists meeting_link text;
alter table public.ops_engagements add column if not exists meeting_event_id text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ops_engagements_minutes_check') then
    alter table public.ops_engagements add constraint ops_engagements_minutes_check
      check (meeting_minutes between 15 and 240);
  end if;
end $$;

-- 2. The meeting takes its length and a pasted link ------------------------------
drop function if exists public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean);
/* The content meeting. When it is first put in the diary the date is today
   or later; once it has been held the record stays as it was, because a past
   meeting is a fact and not a mistake. Not applicable is its own answer, and
   clears the link. A link is Google Meet's, Zoom's or Teams', never anything
   else, because it is sent to a client as it stands. */
create or replace function public.ops_engagement_set_meeting(
  p_engagement uuid, p_at timestamptz, p_channel text default null,
  p_owner uuid default null, p_note text default null, p_na boolean default false,
  p_minutes integer default null, p_link text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements; lk text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce(p_na, false) then
    update public.ops_engagements set meeting_na = true, meeting_note = coalesce(p_note, meeting_note),
           meeting_link = null, updated_at = now(), version = version + 1 where id = p_engagement;
    perform public.ops_engagement_log(p_engagement, 'meeting_na', jsonb_build_object('note', p_note));
    return public.ops_engagement_json(p_engagement);
  end if;
  if p_at is null then return jsonb_build_object('error', 'no-date'); end if;
  if p_channel is not null and p_channel not in ('onsite', 'google_meet', 'zoom', 'other') then
    return jsonb_build_object('error', 'bad-channel');
  end if;
  if e.meeting_at is null and p_at::date < current_date then
    return jsonb_build_object('error', 'meeting-in-past');
  end if;
  if p_minutes is not null and (p_minutes < 15 or p_minutes > 240) then
    return jsonb_build_object('error', 'bad-minutes');
  end if;
  lk := nullif(btrim(coalesce(p_link, '')), '');
  if lk is not null and lk !~* '^https://([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com)/' then
    return jsonb_build_object('error', 'bad-meeting-link');
  end if;
  update public.ops_engagements set
    meeting_at = p_at, meeting_channel = coalesce(p_channel, meeting_channel),
    meeting_owner_id = coalesce(p_owner, meeting_owner_id, m.id),
    meeting_note = case when p_note is null then meeting_note else nullif(btrim(p_note), '') end,
    meeting_minutes = coalesce(p_minutes, meeting_minutes),
    meeting_link = case when p_link is null then meeting_link else lk end,
    meeting_na = false, updated_at = now(), version = version + 1
  where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'meeting_set',
    jsonb_build_object('at', p_at, 'channel', p_channel, 'owner_id', p_owner, 'was', e.meeting_at,
                       'minutes', p_minutes));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean, integer, text) to authenticated;

-- 3. The two calls the calendar function makes ------------------------------------
/* What the shared calendar needs to book the month's meeting, asked as the
   person pressing the button: a person who may not work the month is refused
   here, before Google is asked anything. */
create or replace function public.ops_engagement_meet_prepare(p_engagement uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements; cl text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  select * into e from public.ops_engagements where id = p_engagement;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select c.name into cl from public.clients c where c.id = e.client_id;
  return jsonb_build_object(
    'id', e.id, 'client_name', coalesce(cl, 'Client'),
    'month_word', to_char(to_date(e.period || '-01', 'YYYY-MM-DD'), 'Mon YYYY'),
    'meeting_at', e.meeting_at, 'meeting_minutes', e.meeting_minutes,
    'meeting_channel', e.meeting_channel, 'meeting_na', e.meeting_na,
    'meeting_link', e.meeting_link, 'meeting_event_id', e.meeting_event_id);
end $$;
grant execute on function public.ops_engagement_meet_prepare(uuid) to authenticated;

/* The link and the event the calendar made, recorded on the month. A null
   pair is the event removed, and takes the Meet link with it; a Zoom or
   Teams link somebody typed is theirs and stays. */
create or replace function public.ops_engagement_set_meet(p_engagement uuid, p_link text, p_event text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_link is not null and p_link !~* '^https://meet\.google\.com/' then
    return jsonb_build_object('error', 'bad-meeting-link');
  end if;
  update public.ops_engagements set meeting_link = case
           when p_link is not null then p_link
           when p_event is null and meeting_link ~* '^https://meet\.google\.com/' then null
           else meeting_link end,
         meeting_event_id = p_event, meeting_channel = case when p_link is not null then 'google_meet' else meeting_channel end,
         updated_at = now(), version = version + 1
   where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, case when p_event is null then 'meet_removed' else 'meet_booked' end,
    jsonb_build_object('link', p_link, 'event', p_event));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meet(uuid, text, text) to authenticated;


-- 4. A comment tells the task's owner ------------------------------------------------
/* ops_log as the daily tracker left it, and a comment somebody else made on
   a task tells its owner what was said. */
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

  if p_type = 'assignment_changed' then
    owner := (p_to ->> 'owner_id')::uuid;
    if owner is not null and owner is distinct from m.id then
      perform public.ops_notify(owner, p_task, 'assigned',
        public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
        case when coalesce((p_detail ->> 'handover')::boolean, false)
             then 'Handed to you by ' || who || ' at ' ||
                  coalesce((public.ops_stage(t.workflow_id, p_detail ->> 'stage_key')).label, p_detail ->> 'stage_key') || '.'
             else 'Assigned to you by ' || who || '.' end,
        'assigned:' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
    end if;
    return;
  end if;

  select team_member_id into owner from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null
   limit 1;
  if owner is null or owner = m.id then return; end if;

  if p_type = 'stage_changed' then
    st := public.ops_stage(t.workflow_id, p_to ->> 'stage_key');
    body := 'Moved to ' || coalesce(st.label, p_to ->> 'stage_key')
      || coalesce(', round ' || (p_detail ->> 'round'), '') || ' by ' || who || '.';
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
  elsif p_type = 'commented' then
    body := who || ' commented: ' ||
      case when length(coalesce(p_detail ->> 'note', '')) > 140
           then left(p_detail ->> 'note', 139) || '…' else coalesce(p_detail ->> 'note', '') end;
  else
    return;
  end if;

  perform public.ops_notify(owner, p_task, p_type,
    public.ops_serial(t.task_no) || ' · ' || public.ops_title(t), body,
    p_type || ':' || p_task::text || ':' || owner::text || ':' ||
      /* Two comments in one minute are two things said; the same change
         twice in a minute is one. */
      case when p_type = 'commented' then md5(body) else to_char(now(), 'YYYYMMDDHH24MI') end);
end $$;


-- END OF THE CONTENT MEETING ON GOOGLE MEET --------------------------------

-- ===========================================================================
-- READINESS IS THE FIRST MONTH'S — onboarding is done once a client, not
-- every month.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   The Onboarding and Pre-advertising checklists are what happens when a
--   client starts, so they belong to the client's first month and to no
--   later one (the user, 2026-09-24: "the readiness is only when its the
--   first engagement with clients, not every single month"). A later month
--   carries no checks at all, so its gate to Ready is the content meeting
--   alone: `ops_engagement_set_status` already refuses only while a check
--   row is open, and a month with none has none open. Nothing about the gate
--   itself is rewritten.
--
--   1. Existing months: each client's first month (the earliest period)
--      takes the furthest state either check reached on any of the client's
--      months, with who ticked it and when, so a tick somebody made on the
--      second month is not lost; then the rows on every later month go.
--   2. `ops_engagement_upsert` seeds the two checks only when the client has
--      no other month.
--   3. Deleting a client's first month hands its checks to the earliest month
--      left, by trigger, so onboarding that was ticked is not deleted with a
--      month keyed in by mistake.
--
-- ROLLBACK
--   drop trigger if exists ops_engagements_hand_on_checks on public.ops_engagements;
--   drop function if exists public.ops_engagements_hand_on_checks();
--   Re-run 2026-09-24-the-month-in-two-ticks.sql for the upsert that seeds
--   every month. The rows removed from later months are not put back.
-- ===========================================================================

-- 1. The first month keeps what any month recorded --------------------------------
insert into public.ops_engagement_checks (engagement_id, key)
select f.id, k.key
  from (select distinct on (client_id) id, client_id from public.ops_engagements
         order by client_id, period, created_at) f
 cross join (values ('onboarding'), ('pre_ads')) k(key)
 where exists (select 1 from public.ops_engagement_checks c
                 join public.ops_engagements e on e.id = c.engagement_id
                where e.client_id = f.client_id)
on conflict do nothing;

with firsts as (
  select distinct on (client_id) id, client_id from public.ops_engagements
   order by client_id, period, created_at
), best as (
  select distinct on (e.client_id, c.key)
         e.client_id, c.key, c.state, c.owner_id, c.updated_by, c.updated_at, c.note
    from public.ops_engagement_checks c
    join public.ops_engagements e on e.id = c.engagement_id
   order by e.client_id, c.key,
            case c.state when 'ready' then 0 when 'na' then 1 when 'in_progress' then 2
                         when 'waiting_client' then 3 else 4 end,
            c.updated_at desc nulls last
)
update public.ops_engagement_checks c
   set state = b.state, owner_id = b.owner_id, updated_by = b.updated_by,
       updated_at = b.updated_at, note = b.note
  from firsts f join best b on b.client_id = f.client_id
 where c.engagement_id = f.id and c.key = b.key and c.state is distinct from b.state;

delete from public.ops_engagement_checks c
 using public.ops_engagements e
 where e.id = c.engagement_id
   and e.id <> (select f.id from public.ops_engagements f where f.client_id = e.client_id
                 order by f.period, f.created_at limit 1);

-- 2. A new month is seeded only when it is the client's first ----------------------
/* One a client a month. A second call for the same month edits the one row
   rather than making a second. The two checks are onboarding, so they are
   seeded on the client's first month and on no later one. */
create or replace function public.ops_engagement_upsert(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  cid uuid;
  per text;
  eid uuid;
  k text;
  fresh boolean := false;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  if cid is null or not exists (select 1 from public.clients where id = cid) then
    return jsonb_build_object('error', 'client-required');
  end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;

  select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
  if eid is null then
    insert into public.ops_engagements (client_id, period, manager_id, planned_count, drive_url, created_by)
    values (cid, per, coalesce((p_payload ->> 'manager_id')::uuid, m.id),
            coalesce((p_payload ->> 'planned_count')::integer, 0),
            nullif(p_payload ->> 'drive_url', ''), m.id)
    on conflict (client_id, period) do nothing
    returning id into eid;
    /* Somebody else made it between the read and the write: theirs stands. */
    if eid is null then
      select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
    else
      fresh := true;
    end if;
  end if;
  if fresh then
    if not exists (select 1 from public.ops_engagements o where o.client_id = cid and o.id <> eid) then
    foreach k in array array['onboarding', 'pre_ads'] loop
      insert into public.ops_engagement_checks (engagement_id, key) values (eid, k)
      on conflict do nothing;
    end loop;
    end if;
    perform public.ops_engagement_log(eid, 'created', p_payload - 'client_id');
  else
    if not public.ops_may_see_engagement(eid) then return jsonb_build_object('error', 'denied'); end if;
    /* Asked for with nothing to change, the month is answered as it stands:
       a task made for a month joins it without editing it. */
    if (p_payload - 'client_id' - 'period') = '{}'::jsonb then
      return public.ops_engagement_json(eid) || jsonb_build_object('created', false);
    end if;
    update public.ops_engagements set
      manager_id = coalesce((p_payload ->> 'manager_id')::uuid, manager_id),
      planned_count = coalesce((p_payload ->> 'planned_count')::integer, planned_count),
      drive_url = case when p_payload ? 'drive_url' then nullif(p_payload ->> 'drive_url', '') else drive_url end,
      updated_at = now(), version = version + 1
    where id = eid;
    perform public.ops_engagement_log(eid, 'edited', p_payload - 'client_id' - 'period');
  end if;
  return public.ops_engagement_json(eid) || jsonb_build_object('created', fresh);
end $$;
grant execute on function public.ops_engagement_upsert(jsonb) to authenticated;

-- 3. The first month's checks outlive the month --------------------------------------
/* A first month deleted as a mistake takes the onboarding record to the
   earliest month left rather than with it. Where that month already holds
   checks, they stand. */
create or replace function public.ops_engagements_hand_on_checks()
returns trigger
language plpgsql security definer set search_path = public as $$
declare nxt uuid;
begin
  select e.id into nxt from public.ops_engagements e
   where e.client_id = old.client_id and e.id <> old.id
   order by e.period, e.created_at limit 1;
  if nxt is not null and not exists (select 1 from public.ops_engagement_checks where engagement_id = nxt) then
    update public.ops_engagement_checks set engagement_id = nxt where engagement_id = old.id;
  end if;
  return old;
end $$;
drop trigger if exists ops_engagements_hand_on_checks on public.ops_engagements;
create trigger ops_engagements_hand_on_checks before delete on public.ops_engagements
  for each row execute function public.ops_engagements_hand_on_checks();

-- END OF READINESS IS THE FIRST MONTH'S -------------------------------------

-- ===========================================================================
-- PERFORMANCE REVIEWS — the monthly score, the breach log, the dispute and
-- the signed record: each person reads their own, and management reads
-- everyone's behind a master code.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/perf.js compares the two.
--
-- WHAT THIS IS.
--
--   The ADspace Performance Framework v2.0 and its calculator workbook, as a
--   record: six categories out of 100, breaches that deduct (capped at 35),
--   grade caps for a Level 3 or 4 breach, the five grades, reward
--   eligibility, the development and accountability paths. Decided with the
--   user on 2026-09-24:
--     - Grades read Distinction, Strong, Baseline, Needs Guidance,
--       Performance Review.
--     - Grade C is reward eligible, unless the month before was also C; a
--       Level 3 or 4 breach that month makes any month not eligible.
--     - The member sees nothing of a month, breaches included, until it is
--       released, which happens at the monthly 1-1.
--     - A released month may be disputed for 3 days, one dispute a version,
--       item by item, each with a reason; management answers each with a
--       reason; the member acknowledges; management finalises.
--     - Budget pacing counts only for somebody who runs client ads.
--
-- WHO READS WHAT, AND HOW THE DATABASE MAKES IT TRUE.
--
--   Every table below has row level security on and NO policy at all, so a
--   browser reads and writes nothing directly, whatever it sends. Everything
--   goes through the functions:
--     - `perf_mine()` and the member's own acts answer only for the signed-in
--       person's own released months.
--     - Every management function asks `team.performance` (granted, never
--       inherited: `ops_granted()` reads the exact key, so a group given Team
--       does not get this) AND a live unlock token, which only the master
--       code produces. An admin passes the first test and still needs the
--       second.
--     - Nobody acts on their own review, and the management list leaves the
--       caller out: their own months are in My performance like everybody's.
--   The master code is stored as a bcrypt hash in `app_secrets`, which no
--   browser can read. Five wrong tries lock that person out for 15 minutes;
--   an unlock lasts 15 minutes from the last use.
--
-- SET OR CHANGE THE MASTER CODE (in the Supabase SQL editor, never in chat):
--   select public.perf_code_reset('your code here');
-- Changing it ends every open unlock.
--
-- ROLLBACK
--   drop function if exists public.perf_code_reset(text), public.perf_code_set(),
--     public.perf_unlock(text), public.perf_lock(text), public.perf_gate_info(),
--     public.perf_month(text, date), public.perf_open(text, uuid, date),
--     public.perf_save(text, uuid, date, jsonb, integer), public.perf_release(text, uuid, integer),
--     public.perf_unrelease(text, uuid, text), public.perf_decide(text, uuid, text, text, numeric),
--     public.perf_finalise(text, uuid), public.perf_reopen(text, uuid, text),
--     public.perf_breach_log(text, uuid, jsonb), public.perf_breach_void(text, uuid, text),
--     public.perf_profile_set(text, uuid, jsonb), public.perf_mine(),
--     public.perf_dispute(uuid, jsonb), public.perf_acknowledge(uuid),
--     public.perf_printed(uuid, text), public.perf_check(text, text),
--     public.perf_log(uuid, uuid, text, jsonb), public.perf_calc(public.perf_reviews),
--     public.perf_json(public.perf_reviews, boolean), public.perf_ops_rate(uuid, date),
--     public.perf_breaches_json(uuid, date, boolean), public.perf_notify(uuid, text, text, text),
--     public.perf_grade_of(numeric), public.perf_grade_word(text), public.perf_band(numeric, numeric),
--     public.perf_pacing_band(numeric), public.perf_deduction(integer, boolean, boolean),
--     public.perf_month_word(date), public.perf_reviewed(uuid) cascade;
--   drop table if exists public.perf_events, public.perf_disputes, public.perf_breaches,
--     public.perf_reviews, public.perf_people, public.perf_unlocks, public.perf_attempts cascade;
--   delete from public.app_secrets where key = 'perf_code';
-- ===========================================================================

create table if not exists public.app_secrets (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);

-- 1. The record ---------------------------------------------------------------------
/* Who is reviewed and how. A row exists only once somebody has set it; a
   colleague with none is reviewed, unless they are an admin, which is the
   owner's own account. */
create table if not exists public.perf_people (
  team_member_id uuid primary key references public.team_members(id) on delete cascade,
  department     text check (department in ('creative', 'marketing')),
  role_family    text check (role_family in ('visual', 'video', 'planner', 'account')),
  runs_ads       boolean not null default false,
  reviewed       boolean,
  updated_at     timestamptz not null default now()
);

create table if not exists public.perf_reviews (
  id              uuid primary key default gen_random_uuid(),
  team_member_id  uuid not null references public.team_members(id) on delete cascade,
  period          date not null check (extract(day from period) = 1),
  status          text not null default 'draft'
                  check (status in ('draft', 'released', 'disputed', 'resolved', 'acknowledged', 'final')),
  s_output        numeric(4,1) check (s_output between 0 and 25),
  s_accuracy      numeric(4,1) check (s_accuracy between 0 and 15),
  s_delivery      numeric(4,1) check (s_delivery between 0 and 15),
  s_client        numeric(4,1) check (s_client between 0 and 20),
  s_comms         numeric(4,1) check (s_comms between 0 and 15),
  s_initiative    numeric(4,1) check (s_initiative between 0 and 10),
  r_posting       numeric(5,1) check (r_posting between 0 and 100),
  r_timeline      numeric(5,1) check (r_timeline between 0 and 100),
  r_satisfaction  numeric(5,1) check (r_satisfaction between 0 and 100),
  r_pacing        numeric(6,1) check (r_pacing between 0 and 1000),
  r_sla           numeric(5,1) check (r_sla between 0 and 100),
  notes           jsonb not null default '{}'::jsonb,
  improvement     text,
  review_by       date,
  reward_step     text,
  serial          text,
  reviewer_id     uuid references public.team_members(id) on delete set null,
  released_at     timestamptz,
  dispute_until   timestamptz,
  acknowledged_at timestamptz,
  finalised_at    timestamptz,
  finalised_by    uuid references public.team_members(id) on delete set null,
  result          jsonb,
  version         integer not null default 1,
  rev             integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (team_member_id, period)
);
create unique index if not exists perf_reviews_serial_idx
  on public.perf_reviews(serial) where serial is not null;

create table if not exists public.perf_breaches (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  occurred_on    date not null,
  period         date not null,
  category       text not null check (category in ('client', 'delivery', 'compliance', 'asset')),
  severity       integer not null check (severity between 1 and 4),
  repeated       boolean not null default false,
  late           boolean not null default false,
  what           text not null,
  evidence       text,
  logged_by      uuid references public.team_members(id) on delete set null,
  logged_at      timestamptz not null default now(),
  voided_at      timestamptz,
  voided_by      uuid references public.team_members(id) on delete set null,
  void_reason    text
);
create index if not exists perf_breaches_member_idx on public.perf_breaches(team_member_id, period);

create table if not exists public.perf_disputes (
  id           uuid primary key default gen_random_uuid(),
  review_id    uuid not null references public.perf_reviews(id) on delete cascade,
  version      integer not null default 1,
  item         text not null check (item in ('output', 'accuracy', 'delivery', 'client', 'comms', 'initiative', 'breach')),
  breach_id    uuid references public.perf_breaches(id) on delete set null,
  reason       text not null,
  raised_at    timestamptz not null default now(),
  decision     text check (decision in ('upheld', 'partly', 'not_upheld')),
  response     text,
  before_value numeric(4,1),
  after_value  numeric(4,1),
  decided_by   uuid references public.team_members(id) on delete set null,
  decided_at   timestamptz
);
create index if not exists perf_disputes_review_idx on public.perf_disputes(review_id);

/* Append only: what happened to a review, who did it and when, including
   every unlock and every printed copy. Nothing here is read by the member. */
create table if not exists public.perf_events (
  id             uuid primary key default gen_random_uuid(),
  review_id      uuid references public.perf_reviews(id) on delete cascade,
  team_member_id uuid references public.team_members(id) on delete cascade,
  actor_id       uuid,
  actor_email    text,
  kind           text not null,
  detail         jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index if not exists perf_events_review_idx on public.perf_events(review_id, created_at desc);

create table if not exists public.perf_unlocks (
  token_hash     text primary key,
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null
);
create table if not exists public.perf_attempts (
  team_member_id uuid primary key references public.team_members(id) on delete cascade,
  failures       integer not null default 0,
  locked_until   timestamptz
);

-- 2. Nobody reads a table directly -------------------------------------------------
alter table public.app_secrets enable row level security;
alter table public.perf_people enable row level security;
alter table public.perf_reviews enable row level security;
alter table public.perf_breaches enable row level security;
alter table public.perf_disputes enable row level security;
alter table public.perf_events enable row level security;
alter table public.perf_unlocks enable row level security;
alter table public.perf_attempts enable row level security;
revoke all on public.app_secrets, public.perf_people, public.perf_reviews, public.perf_breaches,
  public.perf_disputes, public.perf_events, public.perf_unlocks, public.perf_attempts
  from anon, authenticated;
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies
            where schemaname = 'public'
              and tablename in ('perf_people', 'perf_reviews', 'perf_breaches', 'perf_disputes',
                                'perf_events', 'perf_unlocks', 'perf_attempts') loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

create or replace function public.perf_events_frozen()
returns trigger language plpgsql as $$
begin
  if pg_trigger_depth() > 1 then return coalesce(old, new); end if;
  raise exception 'perf-events-append-only';
end $$;
drop trigger if exists perf_events_frozen on public.perf_events;
create trigger perf_events_frozen before update or delete on public.perf_events
  for each row execute function public.perf_events_frozen();

-- 3. The rules, stated once ----------------------------------------------------------
create or replace function public.perf_grade_of(p_score numeric)
returns text language sql immutable as $$
  select case when p_score >= 90 then 'A' when p_score >= 80 then 'B'
              when p_score >= 70 then 'C' when p_score >= 60 then 'D' else 'E' end
$$;
create or replace function public.perf_grade_word(p_grade text)
returns text language sql immutable as $$
  select case p_grade when 'A' then 'Distinction' when 'B' then 'Strong' when 'C' then 'Baseline'
                      when 'D' then 'Needs Guidance' when 'E' then 'Performance Review' end
$$;
create or replace function public.perf_deduction(p_severity integer, p_repeated boolean, p_late boolean)
returns integer language sql immutable as $$
  select (case p_severity when 1 then -3 when 2 then -7 when 3 then -15 when 4 then -30 else 0 end)
       + (case when p_repeated then -5 else 0 end) + (case when p_late then -5 else 0 end)
$$;
/* Green at the target, amber within 10% of it, red below that. */
create or replace function public.perf_band(p_rate numeric, p_target numeric)
returns text language sql immutable as $$
  select case when p_rate is null then null when p_rate >= p_target then 'green'
              when p_rate >= p_target * 0.9 then 'amber' else 'red' end
$$;
/* Budget pacing is a variance, so lower is better: within 10% green, within
   20% amber, the workbook's own rule. */
create or replace function public.perf_pacing_band(p_variance numeric)
returns text language sql immutable as $$
  select case when p_variance is null then null when p_variance <= 10 then 'green'
              when p_variance <= 20 then 'amber' else 'red' end
$$;
create or replace function public.perf_month_word(p_period date)
returns text language sql immutable as $$
  select trim(to_char(p_period, 'FMMonth YYYY'))
$$;

/* Is this colleague on the monthly review? Their own setting where one was
   made, else everybody but an admin. */
create or replace function public.perf_reviewed(p_member uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select pp.reviewed from public.perf_people pp where pp.team_member_id = m.id),
                  not (m.is_admin or m.role = 'admin'))
    from public.team_members m where m.id = p_member
$$;

-- 4. The gate -----------------------------------------------------------------------
create or replace function public.perf_code_set()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_secrets where key = 'perf_code' and value <> '')
$$;

/* Run by the owner in the SQL editor. Never granted to a browser. */
create or replace function public.perf_code_reset(p_code text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_code, '')) < 6 then
    raise exception 'The master code needs at least 6 characters.';
  end if;
  insert into public.app_secrets (key, value) values ('perf_code', crypt(p_code, gen_salt('bf', 8)))
  on conflict (key) do update set value = excluded.value, updated_at = now();
  delete from public.perf_unlocks;
  delete from public.perf_attempts;
  return 'Master code set.';
end $$;

create or replace function public.perf_log(p_review uuid, p_member uuid, p_kind text, p_detail jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  insert into public.perf_events (review_id, team_member_id, actor_id, actor_email, kind, detail)
  values (p_review, p_member, m.id, m.email, p_kind, coalesce(p_detail, '{}'::jsonb));
end $$;

/* The two tests every management function asks, in one place: the granted
   part at the level the act needs, and a live unlock. A live unlock is
   extended by its use, so somebody working through the month is not asked
   again mid review. Null means pass. */
create or replace function public.perf_check(p_token text, p_level text)
returns text
language plpgsql security definer set search_path = public as $$
declare m public.team_members; n integer;
begin
  m := public.ops_me();
  if m.id is null then return 'not-team'; end if;
  if not public.ops_granted('team.performance', p_level) then return 'denied'; end if;
  if not public.perf_code_set() then return 'no-code'; end if;
  update public.perf_unlocks set expires_at = now() + interval '15 minutes'
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and team_member_id = m.id and expires_at > now();
  get diagnostics n = row_count;
  if n = 0 then return 'code-needed'; end if;
  return null;
end $$;

create or replace function public.perf_gate_info()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; a public.perf_attempts;
begin
  m := public.ops_me();
  if m.id is null or not public.ops_granted('team.performance', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into a from public.perf_attempts where team_member_id = m.id;
  return jsonb_build_object('code_set', public.perf_code_set(),
    'locked_until', case when a.locked_until > now() then a.locked_until end,
    'can_work', public.ops_granted('team.performance', 'work'),
    'can_manage', public.ops_granted('team.performance', 'manage'));
end $$;

create or replace function public.perf_unlock(p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  m public.team_members; h text; a public.perf_attempts; tok text; f integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('team.performance', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select value into h from public.app_secrets where key = 'perf_code';
  if coalesce(h, '') = '' then return jsonb_build_object('error', 'no-code'); end if;
  select * into a from public.perf_attempts where team_member_id = m.id;
  if a.locked_until > now() then
    return jsonb_build_object('error', 'locked', 'until', a.locked_until);
  end if;
  if crypt(coalesce(p_code, ''), h) <> h then
    f := case when a.locked_until is not null then 1 else coalesce(a.failures, 0) + 1 end;
    insert into public.perf_attempts (team_member_id, failures, locked_until)
    values (m.id, f, case when f >= 5 then now() + interval '15 minutes' end)
    on conflict (team_member_id) do update
      set failures = excluded.failures, locked_until = excluded.locked_until;
    perform public.perf_log(null, null, 'unlock_failed', jsonb_build_object('failures', f));
    if f >= 5 then
      return jsonb_build_object('error', 'locked', 'until', now() + interval '15 minutes');
    end if;
    return jsonb_build_object('error', 'wrong-code', 'left', 5 - f);
  end if;
  delete from public.perf_attempts where team_member_id = m.id;
  delete from public.perf_unlocks where expires_at < now();
  tok := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.perf_unlocks (token_hash, team_member_id, expires_at)
  values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), m.id, now() + interval '15 minutes');
  perform public.perf_log(null, null, 'unlocked', '{}'::jsonb);
  return jsonb_build_object('token', tok, 'expires_at', now() + interval '15 minutes');
end $$;

create or replace function public.perf_lock(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  delete from public.perf_unlocks
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex');
  return jsonb_build_object('ok', true);
end $$;

-- 5. The calculator -----------------------------------------------------------------
create or replace function public.perf_breaches_json(p_member uuid, p_period date, p_with_void boolean)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'occurred_on', b.occurred_on, 'category', b.category,
           'severity', b.severity, 'repeated', b.repeated, 'late', b.late,
           'what', b.what, 'evidence', b.evidence,
           'deduction', public.perf_deduction(b.severity, b.repeated, b.late),
           'logged_by', (select name from public.team_members where id = b.logged_by),
           'logged_at', b.logged_at, 'voided_at', b.voided_at, 'void_reason', b.void_reason)
         order by b.occurred_on, b.logged_at), '[]'::jsonb)
    from public.perf_breaches b
   where b.team_member_id = p_member and b.period = p_period
     and (p_with_void or b.voided_at is null)
$$;

/* One definition of the month's result, read by the management page, the
   member's page and the printed copy alike. A final review keeps the result
   it was finalised with, so a later change to an earlier month cannot move
   a record somebody has signed. */
create or replace function public.perf_calc(r public.perf_reviews)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  base numeric; raw_ded integer; ded integer; fin numeric; l3 boolean; l4 boolean;
  g text; cap integer; rk integer; prev public.perf_reviews; prev_g text; ok boolean;
  complete boolean; path text; ads boolean; bd text; bc text; bm text;
  rank_of constant text := 'ABCDE';
begin
  if r.status = 'final' and r.result is not null then return r.result; end if;
  complete := r.s_output is not null and r.s_accuracy is not null and r.s_delivery is not null
          and r.s_client is not null and r.s_comms is not null and r.s_initiative is not null;
  base := coalesce(r.s_output, 0) + coalesce(r.s_accuracy, 0) + coalesce(r.s_delivery, 0)
        + coalesce(r.s_client, 0) + coalesce(r.s_comms, 0) + coalesce(r.s_initiative, 0);
  select coalesce(sum(public.perf_deduction(severity, repeated, late)), 0),
         coalesce(bool_or(severity = 3), false), coalesce(bool_or(severity = 4), false)
    into raw_ded, l3, l4
    from public.perf_breaches
   where team_member_id = r.team_member_id and period = r.period and voided_at is null;
  ded := greatest(raw_ded, -35);
  fin := greatest(0, least(100, base + ded));
  g := public.perf_grade_of(fin);
  cap := case when l4 then 4 when l3 then 2 else 0 end;
  rk := greatest(position(g in rank_of), cap);
  g := substr(rank_of, rk, 1);

  select * into prev from public.perf_reviews
   where team_member_id = r.team_member_id and period = (r.period - interval '1 month')::date
     and status <> 'draft';
  if prev.id is not null then
    prev_g := (public.perf_calc(prev)) ->> 'grade';
  end if;
  ok := (g in ('A', 'B') or (g = 'C' and prev_g is distinct from 'C')) and not l3 and not l4;
  path := case when g = 'E' or l3 or l4 then 'accountability' when g = 'D' then 'development' end;

  ads := coalesce((select runs_ads from public.perf_people where team_member_id = r.team_member_id), false);
  bd := (select b from unnest(array[public.perf_band(r.r_posting, 95), public.perf_band(r.r_timeline, 90)]) b
          where b is not null order by position(b in 'green amber red') desc limit 1);
  bc := (select b from unnest(array[public.perf_band(r.r_satisfaction, 90),
                                    case when ads then public.perf_pacing_band(r.r_pacing) end]) b
          where b is not null order by position(b in 'green amber red') desc limit 1);
  bm := public.perf_band(r.r_sla, 90);

  return jsonb_build_object(
    'complete', complete, 'base', base, 'deduction', ded, 'deduction_raw', raw_ded,
    'final', fin, 'raw_grade', public.perf_grade_of(fin), 'grade', g,
    'grade_word', public.perf_grade_word(g),
    'capped', case when rk > position(public.perf_grade_of(fin) in rank_of) then (case when l4 then 'D' else 'B' end) end,
    'l3', l3, 'l4', l4, 'review', l4,
    'eligible', ok, 'previous_grade', prev_g,
    'path', path,
    'suggested', jsonb_build_object(
      'delivery', case bd when 'green' then 15 when 'amber' then 12 when 'red' then 7.5 end,
      'delivery_band', bd,
      'client', case bc when 'green' then 20 when 'amber' then 16 when 'red' then 10 end,
      'client_band', bc,
      'comms', case bm when 'green' then 15 when 'amber' then 12 when 'red' then 7.5 end,
      'comms_band', bm));
end $$;

/* What My Work already knows: the tasks this person owned that were finished
   in the month with a due date, and how many were finished by it. A hint for
   the reviewer, never a score. */
create or replace function public.perf_ops_rate(p_member uuid, p_period date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d integer; o integer;
begin
  if to_regclass('public.ops_tasks') is null then return null; end if;
  select count(*),
         count(*) filter (where coalesce(t.completed_at, t.delivered_at)::date <= t.current_final_due_at::date)
    into d, o
    from public.ops_tasks t
   where t.completed_at >= p_period and t.completed_at < (p_period + interval '1 month')
     and t.current_final_due_at is not null
     and (select a.team_member_id from public.ops_task_assignees a
           where a.task_id = t.id and a.responsibility = 'owner'
           order by a.ended_at nulls first, a.assigned_at desc limit 1) = p_member;
  return jsonb_build_object('done', d, 'on_time', o);
end $$;

create or replace function public.perf_json(r public.perf_reviews, p_full boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.team_members; pp public.perf_people; out jsonb;
begin
  select * into m from public.team_members where id = r.team_member_id;
  select * into pp from public.perf_people where team_member_id = r.team_member_id;
  out := jsonb_build_object(
    'id', r.id, 'team_member_id', r.team_member_id, 'period', r.period,
    'month', public.perf_month_word(r.period), 'status', r.status,
    'member', jsonb_build_object('name', m.name, 'staff_code', m.staff_code,
      'designation', m.designation, 'department', pp.department,
      'role_family', pp.role_family, 'runs_ads', coalesce(pp.runs_ads, false)),
    'scores', jsonb_build_object('output', r.s_output, 'accuracy', r.s_accuracy,
      'delivery', r.s_delivery, 'client', r.s_client, 'comms', r.s_comms,
      'initiative', r.s_initiative),
    'rates', jsonb_build_object('posting', r.r_posting, 'timeline', r.r_timeline,
      'satisfaction', r.r_satisfaction, 'pacing', r.r_pacing, 'sla', r.r_sla),
    'notes', r.notes, 'improvement', r.improvement, 'review_by', r.review_by,
    'reward_step', r.reward_step, 'serial', r.serial,
    'reviewer', (select name from public.team_members where id = r.reviewer_id),
    'released_at', r.released_at, 'dispute_until', r.dispute_until,
    'dispute_open', r.status = 'released' and r.dispute_until > now()
                    and not exists (select 1 from public.perf_disputes d
                                     where d.review_id = r.id and d.version = r.version),
    'acknowledged_at', r.acknowledged_at, 'finalised_at', r.finalised_at,
    'finalised_by', (select name from public.team_members where id = r.finalised_by),
    'version', r.version, 'rev', r.rev,
    'result', public.perf_calc(r),
    'breaches', public.perf_breaches_json(r.team_member_id, r.period, false),
    'disputes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', d.id, 'item', d.item, 'breach_id', d.breach_id, 'reason', d.reason,
        'breach_what', (select b.what from public.perf_breaches b where b.id = d.breach_id),
        'raised_at', d.raised_at, 'decision', d.decision, 'response', d.response,
        'before_value', d.before_value, 'after_value', d.after_value,
        'decided_by', (select name from public.team_members where id = d.decided_by),
        'decided_at', d.decided_at) order by d.raised_at)
        from public.perf_disputes d where d.review_id = r.id and d.version = r.version), '[]'::jsonb));
  if p_full then
    out := out || jsonb_build_object(
      'voided', (select coalesce(jsonb_agg(x), '[]'::jsonb)
                   from jsonb_array_elements(public.perf_breaches_json(r.team_member_id, r.period, true)) x
                  where x ->> 'voided_at' is not null),
      'ops', public.perf_ops_rate(r.team_member_id, r.period),
      'events', coalesce((select jsonb_agg(jsonb_build_object(
          'kind', e.kind, 'detail', e.detail, 'at', e.created_at,
          'by', coalesce((select name from public.team_members where id = e.actor_id), e.actor_email))
          order by e.created_at desc)
          from public.perf_events e where e.review_id = r.id), '[]'::jsonb));
  end if;
  return out;
end $$;

create or replace function public.perf_notify(p_member uuid, p_kind text, p_title text, p_dedupe text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_member is null or to_regclass('public.ops_notifications') is null then return; end if;
  insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
  values (p_member, null, p_kind, p_title, null, p_dedupe)
  on conflict (dedupe_key) do nothing;
end $$;

-- 6. Management: the month, one review, the breach log ------------------------------
create or replace function public.perf_month(p_token text, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  return jsonb_build_object(
    'period', p, 'month', public.perf_month_word(p),
    'people', coalesce((select jsonb_agg(x order by x ->> 'name') from (
      select jsonb_build_object(
        'team_member_id', t.id, 'name', t.name, 'staff_code', t.staff_code,
        'designation', t.designation,
        'department', pp.department, 'role_family', pp.role_family,
        'runs_ads', coalesce(pp.runs_ads, false),
        'reviewed', public.perf_reviewed(t.id),
        'breaches', (select count(*) from public.perf_breaches b
                      where b.team_member_id = t.id and b.period = p and b.voided_at is null),
        'review', case when r.id is null then null else jsonb_build_object(
          'id', r.id, 'status', r.status, 'result', public.perf_calc(r),
          'open_disputes', (select count(*) from public.perf_disputes d
                             where d.review_id = r.id and d.version = r.version and d.decision is null),
          'dispute_until', r.dispute_until) end) as x
        from public.team_members t
        left join public.perf_people pp on pp.team_member_id = t.id
        left join public.perf_reviews r on r.team_member_id = t.id and r.period = p
       where t.active and t.id <> m.id) q), '[]'::jsonb));
end $$;

create or replace function public.perf_open(p_token text, p_member uuid, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  select * into r from public.perf_reviews where team_member_id = p_member and period = p;
  if r.id is null then
    /* Not started: the shape of a draft, written nowhere until it is saved. */
    r.team_member_id := p_member; r.period := p; r.status := 'draft';
    r.notes := '{}'::jsonb; r.version := 1; r.rev := 0;
  end if;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_save(p_token text, p_member uuid, p_period date,
                                            p_payload jsonb, p_rev integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; r public.perf_reviews; p date := date_trunc('month', p_period)::date;
  sc jsonb := coalesce(p_payload -> 'scores', '{}'::jsonb);
  rt jsonb := coalesce(p_payload -> 'rates', '{}'::jsonb);
  k text; v jsonb; mx numeric; rb date;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if jsonb_typeof(sc) <> 'object' or jsonb_typeof(rt) <> 'object'
     or (p_payload ? 'notes' and jsonb_typeof(p_payload -> 'notes') <> 'object') then
    return jsonb_build_object('error', 'bad-payload');
  end if;
  for k, v in select key, value from jsonb_each(sc) loop
    mx := case k when 'output' then 25 when 'accuracy' then 15 when 'delivery' then 15
                 when 'client' then 20 when 'comms' then 15 when 'initiative' then 10 end;
    if mx is null then return jsonb_build_object('error', 'bad-score', 'key', k); end if;
    if jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-score', 'key', k, 'max', mx); end if;
      if (v #>> '{}')::numeric not between 0 and mx or round((v #>> '{}')::numeric, 1) <> (v #>> '{}')::numeric then
        return jsonb_build_object('error', 'bad-score', 'key', k, 'max', mx);
      end if;
    end if;
  end loop;
  for k, v in select key, value from jsonb_each(rt) loop
    mx := case k when 'pacing' then 1000 when 'posting' then 100 when 'timeline' then 100
                 when 'satisfaction' then 100 when 'sla' then 100 end;
    if mx is null then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
    if jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
      if (v #>> '{}')::numeric not between 0 and mx then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
    end if;
  end loop;
  if coalesce(p_payload ->> 'review_by', '') <> '' then
    begin
      rb := (p_payload ->> 'review_by')::date;
    exception when others then
      return jsonb_build_object('error', 'bad-date');
    end;
  end if;

  select * into r from public.perf_reviews where team_member_id = p_member and period = p for update;
  if r.id is null then
    insert into public.perf_reviews (team_member_id, period) values (p_member, p)
    on conflict (team_member_id, period) do nothing;
    select * into r from public.perf_reviews where team_member_id = p_member and period = p for update;
    perform public.perf_log(r.id, p_member, 'started', '{}'::jsonb);
  elsif p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  /* The scores are the draft's. What the month asks of the person next (the
     improvement, the date it is reviewed by, the step or reward) is written
     at the 1-1 and may be filled in until the record is final. */
  if r.status = 'final' or (r.status <> 'draft'
       and (p_payload - 'improvement' - 'review_by' - 'reward_step') <> '{}'::jsonb) then
    return jsonb_build_object('error', 'not-draft');
  end if;

  update public.perf_reviews set
    s_output     = case when sc ? 'output'     then (sc ->> 'output')::numeric     else s_output end,
    s_accuracy   = case when sc ? 'accuracy'   then (sc ->> 'accuracy')::numeric   else s_accuracy end,
    s_delivery   = case when sc ? 'delivery'   then (sc ->> 'delivery')::numeric   else s_delivery end,
    s_client     = case when sc ? 'client'     then (sc ->> 'client')::numeric     else s_client end,
    s_comms      = case when sc ? 'comms'      then (sc ->> 'comms')::numeric      else s_comms end,
    s_initiative = case when sc ? 'initiative' then (sc ->> 'initiative')::numeric else s_initiative end,
    r_posting      = case when rt ? 'posting'      then (rt ->> 'posting')::numeric      else r_posting end,
    r_timeline     = case when rt ? 'timeline'     then (rt ->> 'timeline')::numeric     else r_timeline end,
    r_satisfaction = case when rt ? 'satisfaction' then (rt ->> 'satisfaction')::numeric else r_satisfaction end,
    r_pacing       = case when rt ? 'pacing'       then (rt ->> 'pacing')::numeric       else r_pacing end,
    r_sla          = case when rt ? 'sla'          then (rt ->> 'sla')::numeric          else r_sla end,
    notes       = case when p_payload ? 'notes' then coalesce(p_payload -> 'notes', '{}'::jsonb) else notes end,
    improvement = case when p_payload ? 'improvement' then nullif(btrim(p_payload ->> 'improvement'), '') else improvement end,
    review_by   = case when p_payload ? 'review_by' then rb else review_by end,
    reward_step = case when p_payload ? 'reward_step' then nullif(btrim(p_payload ->> 'reward_step'), '') else reward_step end,
    updated_at = now(), rev = rev + 1
  where id = r.id
  returning * into r;
  if p_payload <> '{}'::jsonb then
    perform public.perf_log(r.id, p_member, 'scored', jsonb_build_object('fields',
      (select coalesce(jsonb_agg(k2), '[]'::jsonb) from jsonb_object_keys(p_payload) k2)));
  end if;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_release(p_token text, p_review uuid, p_rev integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; tm public.team_members;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  if not (public.perf_calc(r) ->> 'complete')::boolean then
    return jsonb_build_object('error', 'incomplete');
  end if;
  select * into tm from public.team_members where id = r.team_member_id;
  if r.serial is null and coalesce(btrim(tm.staff_code), '') = '' then
    return jsonb_build_object('error', 'no-staff-code');
  end if;
  update public.perf_reviews set status = 'released', released_at = now(),
         dispute_until = now() + interval '3 days', reviewer_id = m.id,
         serial = coalesce(serial, 'ADHR/' || upper(btrim(tm.staff_code)) || '/PR' || to_char(period, 'YYMM')),
         rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'released', jsonb_build_object('version', r.version));
  perform public.perf_notify(r.team_member_id, 'perf.released',
    'Your ' || public.perf_month_word(r.period) || ' performance review is ready.',
    'perf.released.' || r.id || '.' || r.version);
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_unrelease(p_token text, p_review uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status <> 'released' or exists (select 1 from public.perf_disputes d
                                        where d.review_id = r.id and d.version = r.version) then
    return jsonb_build_object('error', 'cannot-return');
  end if;
  update public.perf_reviews set status = 'draft', released_at = null, dispute_until = null,
         rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'returned', jsonb_build_object('reason', btrim(p_reason)));
  perform public.perf_notify(r.team_member_id, 'perf.returned',
    'Your ' || public.perf_month_word(r.period) || ' review was taken back for correction.',
    'perf.returned.' || r.id || '.' || r.rev);
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_decide(p_token text, p_dispute uuid, p_decision text,
                                              p_response text, p_value numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; d public.perf_disputes; r public.perf_reviews;
  b public.perf_breaches; mx numeric; was numeric; col text;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_decision not in ('upheld', 'partly', 'not_upheld') then return jsonb_build_object('error', 'bad-decision'); end if;
  if coalesce(btrim(p_response), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into d from public.perf_disputes where id = p_dispute for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.perf_reviews where id = d.review_id for update;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status <> 'disputed' or d.decision is not null or d.version <> r.version then
    return jsonb_build_object('error', 'already-decided');
  end if;

  if d.item = 'breach' then
    select * into b from public.perf_breaches where id = d.breach_id for update;
    was := b.severity;
    if p_decision = 'upheld' then
      update public.perf_breaches set voided_at = now(), voided_by = m.id, void_reason = 'Dispute upheld'
       where id = b.id;
    elsif p_decision = 'partly' then
      if p_value is null or p_value not in (1, 2, 3) or p_value >= b.severity then
        return jsonb_build_object('error', 'bad-severity');
      end if;
      update public.perf_breaches set severity = p_value::integer where id = b.id;
    end if;
  else
    mx := case d.item when 'output' then 25 when 'accuracy' then 15 when 'delivery' then 15
                      when 'client' then 20 when 'comms' then 15 when 'initiative' then 10 end;
    col := 's_' || d.item;
    execute format('select %I from public.perf_reviews where id = $1', col) into was using r.id;
    if p_decision in ('upheld', 'partly') then
      if p_value is null or p_value < 0 or p_value > mx or round(p_value, 1) <> p_value then
        return jsonb_build_object('error', 'bad-score', 'max', mx);
      end if;
      execute format('update public.perf_reviews set %I = $1 where id = $2', col) using p_value, r.id;
    end if;
  end if;

  update public.perf_disputes set decision = p_decision, response = btrim(p_response),
         before_value = was,
         after_value = case when p_decision = 'not_upheld' then was
                            when d.item = 'breach' and p_decision = 'upheld' then 0
                            else p_value end,
         decided_by = m.id, decided_at = now()
   where id = d.id;
  if not exists (select 1 from public.perf_disputes x
                  where x.review_id = r.id and x.version = r.version and x.decision is null) then
    update public.perf_reviews set status = 'resolved' where id = r.id;
    perform public.perf_notify(r.team_member_id, 'perf.answered',
      'Your dispute on ' || public.perf_month_word(r.period) || ' has been answered.',
      'perf.answered.' || r.id || '.' || r.version);
  end if;
  update public.perf_reviews set rev = rev + 1, updated_at = now() where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'decided',
    jsonb_build_object('item', d.item, 'decision', p_decision, 'was', was,
                       'after', case when p_decision = 'not_upheld' then was else p_value end));
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_finalise(p_token text, p_review uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; res jsonb;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status = 'disputed' then return jsonb_build_object('error', 'open-dispute'); end if;
  if r.status not in ('released', 'resolved', 'acknowledged') then
    return jsonb_build_object('error', 'not-released');
  end if;
  if r.status <> 'acknowledged' and r.dispute_until > now() then
    return jsonb_build_object('error', 'window-open', 'until', r.dispute_until);
  end if;
  res := public.perf_calc(r);
  update public.perf_reviews set status = 'final', result = res, finalised_at = now(),
         finalised_by = m.id, rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'finalised',
    jsonb_build_object('grade', res ->> 'grade', 'final', res -> 'final'));
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_reopen(p_token text, p_review uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews;
begin
  err := public.perf_check(p_token, 'manage');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status <> 'final' then return jsonb_build_object('error', 'not-final'); end if;
  perform public.perf_log(r.id, r.team_member_id, 'reopened',
    jsonb_build_object('reason', btrim(p_reason), 'was', public.perf_json(r, false)));
  update public.perf_reviews set status = 'draft', result = null, released_at = null,
         dispute_until = null, acknowledged_at = null, finalised_at = null, finalised_by = null,
         version = version + 1, rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_breach_log(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; on_ date; p date; cat text; sev integer; rep boolean;
  st text; nb public.perf_breaches;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
  end if;
  begin on_ := (p_payload ->> 'occurred_on')::date; exception when others then on_ := null; end;
  if on_ is null or on_ > current_date then return jsonb_build_object('error', 'bad-date'); end if;
  cat := p_payload ->> 'category';
  if cat is null or cat not in ('client', 'delivery', 'compliance', 'asset') then
    return jsonb_build_object('error', 'bad-category');
  end if;
  sev := case when (p_payload ->> 'severity') ~ '^[1-4]$' then (p_payload ->> 'severity')::integer end;
  if sev is null then return jsonb_build_object('error', 'bad-severity'); end if;
  if coalesce(btrim(p_payload ->> 'what'), '') = '' then return jsonb_build_object('error', 'what-needed'); end if;
  p := date_trunc('month', on_)::date;
  select status into st from public.perf_reviews where team_member_id = p_member and period = p;
  if st is not null and st <> 'draft' then
    return jsonb_build_object('error', 'month-released', 'month', public.perf_month_word(p));
  end if;
  /* The same kind of breach earlier in the same quarter is a repeat, unless
     the reviewer says otherwise. */
  rep := case when p_payload ? 'repeated' and jsonb_typeof(p_payload -> 'repeated') = 'boolean'
              then (p_payload ->> 'repeated')::boolean
              else exists (select 1 from public.perf_breaches b
                            where b.team_member_id = p_member and b.category = cat
                              and b.voided_at is null
                              and date_trunc('quarter', b.occurred_on) = date_trunc('quarter', on_)
                              and b.occurred_on <= on_) end;
  insert into public.perf_breaches (team_member_id, occurred_on, period, category, severity,
                                    repeated, late, what, evidence, logged_by)
  values (p_member, on_, p, cat, sev, rep, coalesce((p_payload ->> 'late')::boolean, false),
          btrim(p_payload ->> 'what'), nullif(btrim(p_payload ->> 'evidence'), ''), m.id)
  returning * into nb;
  perform public.perf_log((select id from public.perf_reviews where team_member_id = p_member and period = p),
    p_member, 'breach_logged', jsonb_build_object('breach', nb.id, 'category', cat, 'severity', sev,
      'repeated', rep, 'late', nb.late, 'deduction', public.perf_deduction(sev, rep, nb.late)));
  return jsonb_build_object('ok', true, 'id', nb.id, 'repeated', rep,
    'deduction', public.perf_deduction(sev, rep, nb.late), 'period', p);
end $$;

create or replace function public.perf_breach_void(p_token text, p_breach uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; b public.perf_breaches; st text;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into b from public.perf_breaches where id = p_breach for update;
  if b.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if b.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if b.voided_at is not null then return jsonb_build_object('ok', true); end if;
  select status into st from public.perf_reviews where team_member_id = b.team_member_id and period = b.period;
  if st is not null and st <> 'draft' then
    return jsonb_build_object('error', 'month-released', 'month', public.perf_month_word(b.period));
  end if;
  update public.perf_breaches set voided_at = now(), voided_by = m.id, void_reason = btrim(p_reason)
   where id = b.id;
  perform public.perf_log((select id from public.perf_reviews where team_member_id = b.team_member_id and period = b.period),
    b.team_member_id, 'breach_voided', jsonb_build_object('breach', b.id, 'reason', btrim(p_reason)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.perf_profile_set(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; dep text; fam text;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  dep := nullif(p_payload ->> 'department', '');
  fam := nullif(p_payload ->> 'role_family', '');
  if dep is not null and dep not in ('creative', 'marketing') then return jsonb_build_object('error', 'bad-department'); end if;
  if fam is not null and fam not in ('visual', 'video', 'planner', 'account') then return jsonb_build_object('error', 'bad-role'); end if;
  insert into public.perf_people (team_member_id, department, role_family, runs_ads, reviewed)
  values (p_member, dep, fam, coalesce((p_payload ->> 'runs_ads')::boolean, false),
          case when p_payload ? 'reviewed' then (p_payload ->> 'reviewed')::boolean end)
  on conflict (team_member_id) do update set
    department = case when p_payload ? 'department' then dep else perf_people.department end,
    role_family = case when p_payload ? 'role_family' then fam else perf_people.role_family end,
    runs_ads = case when p_payload ? 'runs_ads' then coalesce((p_payload ->> 'runs_ads')::boolean, false) else perf_people.runs_ads end,
    reviewed = case when p_payload ? 'reviewed' then (p_payload ->> 'reviewed')::boolean else perf_people.reviewed end,
    updated_at = now();
  perform public.perf_log(null, p_member, 'profile', p_payload);
  return jsonb_build_object('ok', true);
end $$;

-- 7. The member: their own months, a dispute, an acknowledgement --------------------
create or replace function public.perf_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  return jsonb_build_object('reviews', coalesce((
    select jsonb_agg(public.perf_json(r, false) order by r.period desc)
      from public.perf_reviews r
     where r.team_member_id = m.id and r.status <> 'draft'), '[]'::jsonb));
end $$;

create or replace function public.perf_dispute(p_review uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; it jsonb; n integer := 0; itm text; bid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status <> 'released' or exists (select 1 from public.perf_disputes d
                                        where d.review_id = r.id and d.version = r.version) then
    return jsonb_build_object('error', 'dispute-closed');
  end if;
  if r.dispute_until <= now() then return jsonb_build_object('error', 'window-closed'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('error', 'nothing-disputed');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    itm := it ->> 'item';
    if itm is null or itm not in ('output', 'accuracy', 'delivery', 'client', 'comms', 'initiative', 'breach') then
      return jsonb_build_object('error', 'bad-item');
    end if;
    if coalesce(btrim(it ->> 'reason'), '') = '' then return jsonb_build_object('error', 'reason-needed', 'item', itm); end if;
    bid := null;
    if itm = 'breach' then
      begin bid := (it ->> 'breach_id')::uuid; exception when others then bid := null; end;
      if bid is null or not exists (select 1 from public.perf_breaches b
                                     where b.id = bid and b.team_member_id = m.id
                                       and b.period = r.period and b.voided_at is null) then
        return jsonb_build_object('error', 'bad-item');
      end if;
    end if;
    insert into public.perf_disputes (review_id, version, item, breach_id, reason)
    values (r.id, r.version, itm, bid, btrim(it ->> 'reason'));
    n := n + 1;
  end loop;
  update public.perf_reviews set status = 'disputed', rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'disputed', jsonb_build_object('items', n));
  perform public.perf_notify(r.reviewer_id, 'perf.disputed',
    m.name || ' disputed ' || public.perf_month_word(r.period) || '.',
    'perf.disputed.' || r.id || '.' || r.version);
  return public.perf_json(r, false);
end $$;

create or replace function public.perf_acknowledge(p_review uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status = 'acknowledged' or r.status = 'final' then return public.perf_json(r, false); end if;
  if r.status = 'disputed' then return jsonb_build_object('error', 'open-dispute'); end if;
  update public.perf_reviews set status = 'acknowledged', acknowledged_at = now(),
         dispute_until = least(dispute_until, now()), rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'acknowledged', '{}'::jsonb);
  return public.perf_json(r, false);
end $$;

/* A copy was drawn: by the member for their own month, or by management with
   a live unlock. The record keeps who printed what. */
create or replace function public.perf_printed(p_review uuid, p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id <> m.id and public.perf_check(p_token, 'view') is not null then
    return jsonb_build_object('error', 'denied');
  end if;
  if r.team_member_id = m.id and r.status = 'draft' then return jsonb_build_object('error', 'not-found'); end if;
  perform public.perf_log(r.id, r.team_member_id, 'printed', jsonb_build_object('version', r.version));
  return jsonb_build_object('ok', true);
end $$;

-- 8. Who may call what ----------------------------------------------------------------
/* Postgres lets PUBLIC execute every new function and Supabase grants anon
   and authenticated as well, so each is closed first. The helpers stay
   closed: the calculator and the record builder would read anybody's
   breaches for whoever called them, and the code reset is the owner's in the
   SQL editor. The functions a page calls are opened to a signed-in browser
   and answer for themselves. */
revoke all on function public.perf_code_reset(text) from public, anon, authenticated;
revoke all on function public.perf_log(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.perf_calc(public.perf_reviews) from public, anon, authenticated;
revoke all on function public.perf_json(public.perf_reviews, boolean) from public, anon, authenticated;
revoke all on function public.perf_ops_rate(uuid, date) from public, anon, authenticated;
revoke all on function public.perf_breaches_json(uuid, date, boolean) from public, anon, authenticated;
revoke all on function public.perf_notify(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.perf_reviewed(uuid) from public, anon, authenticated;
revoke all on function public.perf_check(text, text) from public, anon, authenticated;
revoke all on function public.perf_events_frozen() from public, anon, authenticated;
revoke all on function public.perf_grade_of(numeric) from public, anon, authenticated;
revoke all on function public.perf_grade_word(text) from public, anon, authenticated;
revoke all on function public.perf_deduction(integer, boolean, boolean) from public, anon, authenticated;
revoke all on function public.perf_band(numeric, numeric) from public, anon, authenticated;
revoke all on function public.perf_pacing_band(numeric) from public, anon, authenticated;
revoke all on function public.perf_month_word(date) from public, anon, authenticated;
revoke all on function public.perf_code_set() from public, anon, authenticated;
revoke all on function public.perf_gate_info() from public, anon, authenticated;
revoke all on function public.perf_unlock(text) from public, anon, authenticated;
revoke all on function public.perf_lock(text) from public, anon, authenticated;
revoke all on function public.perf_month(text, date) from public, anon, authenticated;
revoke all on function public.perf_open(text, uuid, date) from public, anon, authenticated;
revoke all on function public.perf_save(text, uuid, date, jsonb, integer) from public, anon, authenticated;
revoke all on function public.perf_release(text, uuid, integer) from public, anon, authenticated;
revoke all on function public.perf_unrelease(text, uuid, text) from public, anon, authenticated;
revoke all on function public.perf_decide(text, uuid, text, text, numeric) from public, anon, authenticated;
revoke all on function public.perf_finalise(text, uuid) from public, anon, authenticated;
revoke all on function public.perf_reopen(text, uuid, text) from public, anon, authenticated;
revoke all on function public.perf_breach_log(text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_breach_void(text, uuid, text) from public, anon, authenticated;
revoke all on function public.perf_profile_set(text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_mine() from public, anon, authenticated;
revoke all on function public.perf_dispute(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_acknowledge(uuid) from public, anon, authenticated;
revoke all on function public.perf_printed(uuid, text) from public, anon, authenticated;
grant execute on function public.perf_code_set() to authenticated;
grant execute on function public.perf_gate_info() to authenticated;
grant execute on function public.perf_unlock(text) to authenticated;
grant execute on function public.perf_lock(text) to authenticated;
grant execute on function public.perf_month(text, date) to authenticated;
grant execute on function public.perf_open(text, uuid, date) to authenticated;
grant execute on function public.perf_save(text, uuid, date, jsonb, integer) to authenticated;
grant execute on function public.perf_release(text, uuid, integer) to authenticated;
grant execute on function public.perf_unrelease(text, uuid, text) to authenticated;
grant execute on function public.perf_decide(text, uuid, text, text, numeric) to authenticated;
grant execute on function public.perf_finalise(text, uuid) to authenticated;
grant execute on function public.perf_reopen(text, uuid, text) to authenticated;
grant execute on function public.perf_breach_log(text, uuid, jsonb) to authenticated;
grant execute on function public.perf_breach_void(text, uuid, text) to authenticated;
grant execute on function public.perf_profile_set(text, uuid, jsonb) to authenticated;
grant execute on function public.perf_mine() to authenticated;
grant execute on function public.perf_dispute(uuid, jsonb) to authenticated;
grant execute on function public.perf_acknowledge(uuid) to authenticated;
grant execute on function public.perf_printed(uuid, text) to authenticated;

-- END OF PERFORMANCE REVIEWS ------------------------------------------------

-- ===========================================================================
-- BULK ADD SPREADS THE MONTH — a month of tasks is shared across its four
-- weeks, not piled into the last one.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   `ops_generate_month` with no week counts gave weeks 1 to 3 the whole
--   quarter of the count and week 4 everything left over, so six tasks came
--   out 1, 1, 1, 3 and one, two or three tasks all landed in week 4 (the
--   user, 2026-09-24: "it should proceed to divide every 30 days ... not just
--   keep all at the last week"). Task i, counted from 0, now falls in week
--   floor(i * 4 / n) + 1: eight is two a week, six is 2, 1, 2, 1, five is
--   2, 1, 1, 1, two is weeks 1 and 3. The running number still runs 01 to n
--   across the month.
--
--   The tentative publish date moves with it: each task sits inside its own
--   week, the week's tasks spread over its seven days, where every task in a
--   week used to share that week's first day.
--
--   Week counts typed on the sheet (Set how many in each week) are used as
--   typed, as before. Tasks already made keep their codes: a code is written
--   once and never rewritten.
--
-- ROLLBACK
--   Re-run section 9.12 of 2026-09-23-operations-phase4.sql.
-- ===========================================================================

-- 1. A month of content at once, spread over the month ------------------------
create or replace function public.ops_generate_month(
  p_payload jsonb, p_dry_run boolean default false, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  cid    uuid;
  per    text;
  n      integer;
  weeks  integer[];
  bad    text;
  eng    uuid;
  k      integer;
  w      integer;
  seq    integer;
  seqs   integer;
  made   jsonb := '[]'::jsonb;
  one    jsonb;
  key    text;
  scope  text;
  first_day date;
  last_off integer;
  publish timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  n := coalesce((p_payload ->> 'count')::integer, 0);
  scope := coalesce(p_payload ->> 'scope', 'client');
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  if n < 1 or n > 60 then return jsonb_build_object('error', 'bad-count'); end if;

  if (p_payload -> 'weeks') is not null and jsonb_typeof(p_payload -> 'weeks') = 'array' then
    select array_agg(x::integer) into weeks from jsonb_array_elements_text(p_payload -> 'weeks') x;
    if array_length(weeks, 1) < 1 or array_length(weeks, 1) > 5 then
      return jsonb_build_object('error', 'bad-weeks');
    end if;
    if (select sum(v) from unnest(weeks) v) <> n then return jsonb_build_object('error', 'weeks-do-not-add-up'); end if;
  else
    /* Evenly over four weeks, the extras early: task i (from 0) falls in
       week floor(i * 4 / n) + 1, so eight is two a week, six is 2, 1, 2, 1,
       and two is weeks 1 and 3 rather than both in week 4. */
    weeks := array[]::integer[];
    for w in 1 .. 4 loop
      weeks := weeks || (ceil(w * n / 4.0)::integer - ceil((w - 1) * n / 4.0)::integer);
    end loop;
  end if;

  /* The same press twice is one month, not two. */
  if not p_dry_run and p_idem is not null then
    if exists (select 1 from public.ops_tasks where idem_key = 'month:' || p_idem || ':1') then
      return jsonb_build_object('error', 'already-generated');
    end if;
  end if;

  first_day := (per || '-01')::date;
  last_off := ((first_day + interval '1 month')::date - first_day) - 1;
  /* One lock for the whole run, taken before anything is read: two operators
     generating the same month queue here, so the second sees the first's
     engagement and the first's numbers rather than racing both. */
  perform pg_advisory_xact_lock(hashtext('ops_code:' || cid::text || ':' || per));
  if not p_dry_run then
    eng := coalesce((p_payload ->> 'engagement_id')::uuid,
                    (select e.id from public.ops_engagements e where e.client_id = cid and e.period = per));
    if eng is null then
      eng := (public.ops_engagement_upsert(jsonb_build_object(
                'client_id', cid, 'period', per, 'planned_count', n,
                'manager_id', coalesce((p_payload ->> 'manager_id')::uuid, m.id))) ->> 'id')::uuid;
    else
      update public.ops_engagements set planned_count = greatest(planned_count, n), updated_at = now()
       where id = eng and planned_count < n;
    end if;
  end if;

  /* One lock for the whole month, so the preview and the run see the same
     next number and two operators generating for one client queue. */
  seq := public.ops_next_seq(cid, per) - 1;
  seqs := 0;
  for w in 1 .. array_length(weeks, 1) loop
    for k in 1 .. coalesce(weeks[w], 0) loop
      seq := seq + 1;
      seqs := seqs + 1;
      /* A tentative date inside the task's own week, the week's tasks
         spread across its seven days, so the calendar has somewhere to put
         each one; the content meeting fixes the real date. Never past the
         month's last day, which only a fifth week can reach. */
      publish := (first_day + least((w - 1) * 7 + ((k - 1) * 7) / weeks[w], last_off))::timestamptz;
      if p_dry_run then
        made := made || jsonb_build_object('code', public.ops_code_of(per, w, seq), 'week', w, 'seq', seq);
      else
        key := case when p_idem is null then null else 'month:' || p_idem || ':' || seqs::text end;
        one := public.ops_create_task(jsonb_build_object(
          'scope', scope, 'client_id', cid, 'engagement_id', eng,
          'task_type', coalesce(p_payload ->> 'task_type', 'engagement'),
          'deliverable_type', p_payload ->> 'deliverable_type',
          'priority_level', (p_payload ->> 'priority_level')::integer,
          'complexity', p_payload ->> 'complexity',
          'owner_id', (p_payload ->> 'owner_id')::uuid,
          'manager_id', (p_payload ->> 'manager_id')::uuid,
          'code_period', per, 'code_week', w,
          'publish_at', publish), key);
        if one ? 'error' then return one; end if;
        made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'week', w, 'seq', seq);
      end if;
    end loop;
  end loop;
  return jsonb_build_object('engagement_id', eng, 'period', per, 'count', seqs,
                            'tasks', made, 'dry_run', p_dry_run);
end $$;
grant execute on function public.ops_generate_month(jsonb, boolean, text) to authenticated;

-- END OF BULK ADD SPREADS THE MONTH ------------------------------------------

-- =========================================================================
-- A CREATOR'S OWN PROFILE LINKS
--
-- A creator keeps their own rednote, Instagram, TikTok and Facebook links up
-- to date from the creator portal, and the team edits the same rows from the
-- Creators List. There is one table, `creator_profiles`, so the two sides
-- cannot drift: the client's selection page reads it too, which is why a
-- link is only ever what this section says it is.
--
-- No approval step (decided with the user on 2026-09-24). The link in hand
-- and its access code already say who is typing, and a round for every
-- handle change is a chore on both sides. What replaces the approval is:
--
--   * `profile_of()` accepts a real profile on the four platforms and
--     nothing else. The host is read, never matched anywhere in the text,
--     and the stored link is rebuilt from the handle, so a changed link can
--     only ever open that platform's profile page and never another site.
--   * A profile another creator already holds is refused, without naming
--     who holds it.
--   * Every change, the creator's and the team's, is filed twice: a row in
--     `creator_profile_changes` holding the set before and after, which is
--     what Restore puts back, and a row in the activity record naming every
--     link that went and came in full, so a link typed by mistake can be
--     found and read back.
--
-- The fee is not here and not in `get_creator`: `creators.client_rate` is
-- the client's price and never reaches the creator's page.
--
-- Rollback:
--   drop function if exists public.creator_restore_profiles(uuid);
--   drop function if exists public.creator_save_profiles(uuid, jsonb);
--   drop function if exists public.creator_set_profiles(text, jsonb);
--   drop function if exists public.profiles_replace(uuid, jsonb, text, text, text);
--   drop function if exists public.profiles_diff(jsonb, jsonb);
--   drop function if exists public.profile_of(text);
--   drop table if exists public.creator_profile_changes;
--   and re-run the get_creator of 2026-09-20.
-- =========================================================================

/* One reading of a profile link. Returns {platform, handle, url} or null.
   The host is taken from the URL's own authority and must be the platform's
   (with or without www. or m.); a URL that merely contains "instagram.com/"
   somewhere, as a query or a path on another site, is not a profile. The
   link stored is rebuilt from what was read, so trailing tracking
   parameters, fragments and anything else typed after the handle are gone.
   A rednote short link (xhslink) names nobody, so it is kept as typed on its
   own host with a null handle and cannot claim an identity. */
create or replace function public.profile_of(p_url text)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v    text := btrim(coalesce(p_url, ''));
  m    text[];
  host text;
  bare text;
  path text;
  q    text;
  h    text;
begin
  if v = '' or length(v) > 300 or v ~ '\s' then return null; end if;
  if v !~* '^https?://' then v := 'https://' || v; end if;
  m := regexp_match(v, '^https?://([^/?#]+)([^?#]*)(\?[^#]*)?', 'i');
  if m is null then return null; end if;
  host := lower(m[1]);
  if host ~ '[@:]' then return null; end if;
  bare := regexp_replace(host, '^(www\.|m\.|mobile\.|web\.)', '');
  path := coalesce(m[2], '');
  q := coalesce(m[3], '');

  if bare = 'instagram.com' then
    m := regexp_match(path, '^/([A-Za-z0-9._]{1,40})/?$');
    if m is null then return null; end if;
    h := m[1];
    if lower(h) in ('p', 'reel', 'reels', 'stories', 'explore', 'tv', 'accounts', 'direct') then
      return null;
    end if;
    return jsonb_build_object('platform', 'instagram', 'handle', h,
      'url', 'https://www.instagram.com/' || h || '/');

  elsif bare = 'tiktok.com' then
    m := regexp_match(path, '^/@([A-Za-z0-9._]{1,40})/?$');
    if m is null then return null; end if;
    return jsonb_build_object('platform', 'tiktok', 'handle', m[1],
      'url', 'https://www.tiktok.com/@' || m[1]);

  elsif bare = 'facebook.com' then
    if path ~* '^/profile\.php/?$' then
      m := regexp_match(q, '[?&]id=([0-9]{5,20})(&|$)');
      if m is null then return null; end if;
      return jsonb_build_object('platform', 'facebook', 'handle', m[1],
        'url', 'https://www.facebook.com/profile.php?id=' || m[1]);
    end if;
    m := regexp_match(path, '^/people/([^/]{1,80})/([0-9]{5,20})/?$');
    if m is not null then
      return jsonb_build_object('platform', 'facebook', 'handle', m[2],
        'url', 'https://www.facebook.com/profile.php?id=' || m[2]);
    end if;
    m := regexp_match(path, '^/([A-Za-z0-9.]{2,60})/?$');
    if m is null then return null; end if;
    h := m[1];
    if lower(h) in ('pages', 'groups', 'watch', 'events', 'marketplace', 'people',
                    'share', 'sharer', 'reel', 'reels', 'stories', 'hashtag', 'login',
                    'help', 'photo.php', 'story.php', 'permalink.php') then
      return null;
    end if;
    return jsonb_build_object('platform', 'facebook', 'handle', h,
      'url', 'https://www.facebook.com/' || h);

  elsif bare in ('xiaohongshu.com', 'rednote.com') then
    m := regexp_match(path, '^/user/profile/([0-9a-zA-Z]{8,40})/?$');
    if m is null then return null; end if;
    return jsonb_build_object('platform', 'xhs', 'handle', m[1],
      'url', 'https://' || host || '/user/profile/' || m[1]);

  elsif bare in ('xhslink.com', 'xhslink.cn') then
    m := regexp_match(path, '^/([A-Za-z0-9/_-]{2,60})$');
    if m is null then return null; end if;
    return jsonb_build_object('platform', 'xhs', 'handle', null,
      'url', 'https://' || host || '/' || m[1]);
  end if;
  return null;
end $$;
grant execute on function public.profile_of(text) to anon, authenticated;

/* What a set of links was and what it became, one row a change, the
   creator's and the team's alike. Read by the team; written only by the
   functions below, which is why the table carries a select policy and
   nothing else. Removing a creator removes their history with them. */
create table if not exists public.creator_profile_changes (
  id          uuid primary key default gen_random_uuid(),
  creator_id  uuid not null references public.creators(id) on delete cascade,
  source      text not null check (source in ('creator', 'team')),
  actor       text,
  before      jsonb not null default '[]'::jsonb,
  after       jsonb not null default '[]'::jsonb,
  restored_from uuid references public.creator_profile_changes(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists creator_profile_changes_creator_idx
  on public.creator_profile_changes(creator_id, created_at desc);
alter table public.creator_profile_changes enable row level security;
drop policy if exists creator_profile_changes_read on public.creator_profile_changes;
create policy creator_profile_changes_read on public.creator_profile_changes
  for select to authenticated using (public.allowed('campaigns.creators', 'view'));

/* The change in words, every link in full, so a link typed by mistake can
   be read back off the activity record: one line a platform, "was → is"
   where one link replaced another, otherwise what went and what came. */
create or replace function public.profiles_diff(p_before jsonb, p_after jsonb)
returns text
language plpgsql immutable set search_path = public as $$
declare
  word  constant jsonb := '{"xhs": "rednote", "instagram": "Instagram", "tiktok": "TikTok", "facebook": "Facebook"}';
  gone  jsonb;
  came  jsonb;
  g     jsonb;
  c     jsonb;
  x     jsonb;
  pl    text;
  parts text[] := '{}';
begin
  select coalesce(jsonb_agg(b), '[]'::jsonb) into gone
    from jsonb_array_elements(coalesce(p_before, '[]'::jsonb)) b
   where not exists (select 1 from jsonb_array_elements(coalesce(p_after, '[]'::jsonb)) a
                      where a ->> 'url' = b ->> 'url');
  select coalesce(jsonb_agg(a), '[]'::jsonb) into came
    from jsonb_array_elements(coalesce(p_after, '[]'::jsonb)) a
   where not exists (select 1 from jsonb_array_elements(coalesce(p_before, '[]'::jsonb)) b
                      where b ->> 'url' = a ->> 'url');
  for pl in select distinct y ->> 'platform' from jsonb_array_elements(gone || came) y order by 1 loop
    select coalesce(jsonb_agg(y), '[]'::jsonb) into g from jsonb_array_elements(gone) y where y ->> 'platform' = pl;
    select coalesce(jsonb_agg(y), '[]'::jsonb) into c from jsonb_array_elements(came) y where y ->> 'platform' = pl;
    if jsonb_array_length(g) = 1 and jsonb_array_length(c) = 1 then
      parts := parts || (coalesce(word ->> pl, pl) || ': ' || (g -> 0 ->> 'url') || ' → ' || (c -> 0 ->> 'url'));
    else
      for x in select * from jsonb_array_elements(g) loop
        parts := parts || (coalesce(word ->> pl, pl) || ' removed: ' || (x ->> 'url'));
      end loop;
      for x in select * from jsonb_array_elements(c) loop
        parts := parts || (coalesce(word ->> pl, pl) || ' added: ' || (x ->> 'url'));
      end loop;
    end if;
  end loop;
  return array_to_string(parts, ' · ');
end $$;
grant execute on function public.profiles_diff(jsonb, jsonb) to authenticated;

/* The one write. Every link is read by `profile_of`, a link twice in the
   payload is one link, and a profile another creator holds is refused
   without naming them. The same set again changes nothing and files
   nothing, so a Save pressed twice is one change. Not granted to anybody:
   it takes a creator's id on trust, so only the three functions below,
   which have each checked who is asking, may call it. */
create or replace function public.profiles_replace(
  p_creator uuid, p_profiles jsonb, p_actor text, p_source text, p_action text)
returns jsonb
language plpgsql set search_path = public as $$
declare
  cr        public.creators;
  item      jsonb;
  v_raw     text;
  parsed    jsonb;
  wanted    jsonb := '[]'::jsonb;
  seen      text[] := '{}';
  k         text;
  v_before  jsonb;
  v_after   jsonb;
  v_said    text;
  v_change  uuid;
begin
  select * into cr from public.creators where id = p_creator;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_profiles is null or jsonb_typeof(p_profiles) <> 'array' then
    return jsonb_build_object('error', 'bad-payload');
  end if;
  if jsonb_array_length(p_profiles) > 8 then return jsonb_build_object('error', 'too-many'); end if;

  for item in select * from jsonb_array_elements(p_profiles) loop
    v_raw := case jsonb_typeof(item) when 'string' then item #>> '{}' else item ->> 'url' end;
    if btrim(coalesce(v_raw, '')) = '' then continue; end if;
    parsed := public.profile_of(v_raw);
    if parsed is null then return jsonb_build_object('error', 'unrecognised', 'url', v_raw); end if;
    k := (parsed ->> 'platform') || ':' || lower(coalesce(parsed ->> 'handle', parsed ->> 'url'));
    if k = any(seen) then continue; end if;
    seen := seen || k;
    if parsed ->> 'handle' is not null and exists (
      select 1 from public.creator_profiles p
       where p.platform = parsed ->> 'platform'
         and lower(p.handle) = lower(parsed ->> 'handle')
         and p.creator_id <> p_creator) then
      return jsonb_build_object('error', 'taken', 'url', parsed ->> 'url');
    end if;
    wanted := wanted || jsonb_build_array(parsed);
  end loop;

  if p_source = 'creator' and jsonb_array_length(wanted) = 0 then
    return jsonb_build_object('error', 'none');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('platform', p.platform, 'handle', p.handle, 'url', p.url)
           order by p.platform, p.url), '[]'::jsonb)
    into v_before from public.creator_profiles p where p.creator_id = p_creator;
  select coalesce(jsonb_agg(x order by x ->> 'platform', x ->> 'url'), '[]'::jsonb)
    into v_after from jsonb_array_elements(wanted) x;
  if v_before = v_after then
    return jsonb_build_object('ok', true, 'changed', false, 'profiles', v_after);
  end if;

  begin
    delete from public.creator_profiles where creator_id = p_creator;
    insert into public.creator_profiles (creator_id, platform, url, handle)
      select p_creator, x ->> 'platform', x ->> 'url', x ->> 'handle'
        from jsonb_array_elements(v_after) x;
  exception when unique_violation then
    /* Two creators claiming one profile at the same moment: the index is the
       last word, and the delete above is rolled back with the insert. */
    return jsonb_build_object('error', 'taken');
  end;

  insert into public.creator_profile_changes (creator_id, source, actor, before, after)
  values (p_creator, p_source, p_actor, v_before, v_after)
  returning id into v_change;
  update public.creators c set updated_at = now() where c.id = p_creator;

  v_said := public.profiles_diff(v_before, v_after);
  insert into public.activity_log (actor, action, subject, detail)
  values (p_actor, p_action, cr.name, v_said);

  return jsonb_build_object('ok', true, 'changed', true, 'change', v_change, 'profiles', v_after);
end $$;
revoke execute on function public.profiles_replace(uuid, jsonb, text, text, text) from public, anon, authenticated;

/* The creator's own save, from the portal. The code is the key, as it is for
   every other creator write, and the name on the record is theirs. */
create or replace function public.creator_set_profiles(p_code text, p_profiles jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr public.creators;
begin
  select * into cr from public.creators
   where access_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
     and active;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  return public.profiles_replace(cr.id, p_profiles, cr.name, 'creator', 'creator.links_self');
end $$;
grant execute on function public.creator_set_profiles(text, jsonb) to anon, authenticated;

/* The team's save, from the Creators List, through the same reader and the
   same history, so the two sides cannot disagree about what a link is. */
create or replace function public.creator_save_profiles(p_creator uuid, p_profiles jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
begin
  if not public.allowed('campaigns.creators', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  return public.profiles_replace(p_creator, p_profiles, me.name, 'team', 'creator.links');
end $$;
grant execute on function public.creator_save_profiles(uuid, jsonb) to authenticated;

/* Putting back the links a change replaced. It is itself a change, filed as
   one, so restoring the wrong one is undone the same way. */
create or replace function public.creator_restore_profiles(p_change uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me  public.team_members;
  ch  public.creator_profile_changes;
  res jsonb;
begin
  if not public.allowed('campaigns.creators', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into ch from public.creator_profile_changes x where x.id = p_change;
  if ch.id is null then return jsonb_build_object('error', 'not-found'); end if;
  res := public.profiles_replace(ch.creator_id, ch.before, me.name, 'team', 'creator.links_restored');
  if (res ->> 'change') is not null then
    update public.creator_profile_changes x set restored_from = ch.id where x.id = (res ->> 'change')::uuid;
  end if;
  return res;
end $$;
grant execute on function public.creator_restore_profiles(uuid) to authenticated;

-- END OF A CREATOR'S OWN PROFILE LINKS --------------------------------------

-- ===========================================================================
-- MY PERFORMANCE BEHIND AN EMAIL CODE — a second lock a member may put on
-- their own reviews.
-- 2026-09-24. Safe to run twice. Run after 2026-09-24-performance-reviews.sql.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/perf.js compares the two.
--
-- WHAT THIS IS. Asked for by the user on 2026-09-24 ("a second guard layer
-- ... OTP / link to view the performance section"), with their decisions:
-- each person switches it on for themselves, and it is a 6-digit code sent
-- to their email. While it is on, the member's own functions answer
-- `code-needed` unless the session was verified by an email code in the
-- last 15 minutes. The proof is the session's own `amr` claim, which the
-- auth server writes when a code is verified (`verifyOtp`), so nothing the
-- browser sends can fake it. Turning the lock off needs a fresh code too,
-- so an unattended open laptop cannot switch it off.
--
-- The email is Supabase's own sign-in email, so its template must print the
-- code: Authentication, Emails, Magic Link, add {{ .Token }}. See
-- docs/PERFORMANCE-SETUP.md.
--
-- ROLLBACK
--   drop function if exists public.perf_guard_set(boolean), public.perf_guard_info(),
--     public.perf_guarded(uuid), public.perf_code_fresh();
--   alter table public.perf_people drop column if exists email_code;
--   and re-run perf_mine, perf_dispute and perf_acknowledge from
--   2026-09-24-performance-reviews.sql.
-- ===========================================================================

alter table public.perf_people add column if not exists email_code boolean not null default false;

/* The session was verified by an email code (or an email link, which the
   auth server records the same way) in the last 15 minutes. Read from the
   signed token, never from anything the page passes in. */
create or replace function public.perf_code_fresh()
returns boolean
language sql stable set search_path = public as $$
  select coalesce((
    select bool_or(a ->> 'method' in ('otp', 'magiclink')
                   and (a ->> 'timestamp') ~ '^[0-9]+$'
                   and (a ->> 'timestamp')::bigint >= extract(epoch from now())::bigint - 900)
      from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array'
                                     then auth.jwt() -> 'amr' else '[]'::jsonb end) a), false)
$$;

/* Whether a member has put the lock on their own reviews. */
create or replace function public.perf_guarded(p_member uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select email_code from public.perf_people where team_member_id = p_member), false)
$$;

/* What the page needs to draw the lock: on or off, fresh or not, and the
   address the code goes to. */
create or replace function public.perf_guard_info()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  return jsonb_build_object('on', public.perf_guarded(m.id), 'fresh', public.perf_code_fresh(),
                            'email', m.email);
end $$;

/* The member's own switch. On at any time; off only with a fresh code. */
create or replace function public.perf_guard_set(p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not coalesce(p_on, false) and public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  insert into public.perf_people (team_member_id, email_code, updated_at)
  values (m.id, coalesce(p_on, false), now())
  on conflict (team_member_id) do update set email_code = excluded.email_code, updated_at = now();
  perform public.perf_log(null, m.id, 'email-code', jsonb_build_object('on', coalesce(p_on, false)));
  return jsonb_build_object('ok', true, 'on', coalesce(p_on, false));
end $$;

/* The member's own functions, each refusing while the lock is on and the
   code is not fresh. Otherwise identical to 2026-09-24-performance-reviews. */
create or replace function public.perf_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  return jsonb_build_object('reviews', coalesce((
    select jsonb_agg(public.perf_json(r, false) order by r.period desc)
      from public.perf_reviews r
     where r.team_member_id = m.id and r.status <> 'draft'), '[]'::jsonb));
end $$;

create or replace function public.perf_dispute(p_review uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; it jsonb; n integer := 0; itm text; bid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status <> 'released' or exists (select 1 from public.perf_disputes d
                                        where d.review_id = r.id and d.version = r.version) then
    return jsonb_build_object('error', 'dispute-closed');
  end if;
  if r.dispute_until <= now() then return jsonb_build_object('error', 'window-closed'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('error', 'nothing-disputed');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    itm := it ->> 'item';
    if itm is null or itm not in ('output', 'accuracy', 'delivery', 'client', 'comms', 'initiative', 'breach') then
      return jsonb_build_object('error', 'bad-item');
    end if;
    if coalesce(btrim(it ->> 'reason'), '') = '' then return jsonb_build_object('error', 'reason-needed', 'item', itm); end if;
    bid := null;
    if itm = 'breach' then
      begin bid := (it ->> 'breach_id')::uuid; exception when others then bid := null; end;
      if bid is null or not exists (select 1 from public.perf_breaches b
                                     where b.id = bid and b.team_member_id = m.id
                                       and b.period = r.period and b.voided_at is null) then
        return jsonb_build_object('error', 'bad-item');
      end if;
    end if;
    insert into public.perf_disputes (review_id, version, item, breach_id, reason)
    values (r.id, r.version, itm, bid, btrim(it ->> 'reason'));
    n := n + 1;
  end loop;
  update public.perf_reviews set status = 'disputed', rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'disputed', jsonb_build_object('items', n));
  perform public.perf_notify(r.reviewer_id, 'perf.disputed',
    m.name || ' disputed ' || public.perf_month_word(r.period) || '.',
    'perf.disputed.' || r.id || '.' || r.version);
  return public.perf_json(r, false);
end $$;

create or replace function public.perf_acknowledge(p_review uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status = 'acknowledged' or r.status = 'final' then return public.perf_json(r, false); end if;
  if r.status = 'disputed' then return jsonb_build_object('error', 'open-dispute'); end if;
  update public.perf_reviews set status = 'acknowledged', acknowledged_at = now(),
         dispute_until = least(dispute_until, now()), rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'acknowledged', '{}'::jsonb);
  return public.perf_json(r, false);
end $$;

revoke all on function public.perf_code_fresh() from public, anon, authenticated;
revoke all on function public.perf_guarded(uuid) from public, anon, authenticated;
revoke all on function public.perf_guard_info() from public, anon, authenticated;
revoke all on function public.perf_guard_set(boolean) from public, anon, authenticated;
revoke all on function public.perf_mine() from public, anon, authenticated;
revoke all on function public.perf_dispute(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_acknowledge(uuid) from public, anon, authenticated;
grant execute on function public.perf_guard_info() to authenticated;
grant execute on function public.perf_guard_set(boolean) to authenticated;
grant execute on function public.perf_mine() to authenticated;
grant execute on function public.perf_dispute(uuid, jsonb) to authenticated;
grant execute on function public.perf_acknowledge(uuid) to authenticated;

-- END OF MY PERFORMANCE BEHIND AN EMAIL CODE ---------------------------------

-- ===========================================================================
-- MY PERFORMANCE ALWAYS ASKS FOR AN EMAIL CODE — the lock is no longer a
-- member's own switch.
-- 2026-09-24. Safe to run twice. Run after 2026-09-24-performance-email-code.sql.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED. The user, on 2026-09-24: the page "mandatory requires otp
-- pin", so a tick to turn it on or off is useless. Every member's own
-- reviews now ask for a code emailed to them in the last 15 minutes, with
-- no switch: perf_guarded answers true for everybody and perf_guard_set
-- refuses to turn it off. The `email_code` column stays, unread, so the
-- rollback is two function bodies.
--
-- ROLLBACK
--   re-run perf_guarded and perf_guard_set from
--   2026-09-24-performance-email-code.sql.
-- ===========================================================================

/* Every member's reviews are behind the code. */
create or replace function public.perf_guarded(p_member uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select true
$$;

/* The switch is gone. Kept as a function so an open page from before this
   change is refused in words rather than by a missing function. */
create or replace function public.perf_guard_set(p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not coalesce(p_on, true) then return jsonb_build_object('error', 'always-on'); end if;
  return jsonb_build_object('ok', true, 'on', true);
end $$;

revoke all on function public.perf_guarded(uuid) from public, anon, authenticated;
revoke all on function public.perf_guard_set(boolean) from public, anon, authenticated;
grant execute on function public.perf_guard_set(boolean) to authenticated;

-- END OF MY PERFORMANCE ALWAYS ASKS FOR AN EMAIL CODE ------------------------

-- ===========================================================================
-- A TASK MAY BE MADE FOR A PAST CLIENT — the Client scope takes active and
-- paused clients, and past ones when asked.
-- 2026-09-24. Safe to run twice. Run after 2026-09-23-operations-phase4.sql.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/ops.js compares the two.
--
-- WHAT CHANGED. The new task sheet offered "Include paused clients"; the
-- user asked for "Include past clients" (2026-09-24). A paused client is
-- still a client, so paused is offered by default and the tick adds past
-- clients, whose renewal and wind-down work is still work. The check is
-- still made once, at creation.
--
-- ROLLBACK
--   re-run ops_scope_error from 2026-09-23-operations-phase4.sql.
-- ===========================================================================

create or replace function public.ops_scope_error(p_scope text, p_client uuid)
returns text
language plpgsql stable as $$
declare st text;
begin
  if p_scope = 'internal' then return null; end if;
  if p_scope not in ('client', 'lead') then return 'bad-scope'; end if;
  if p_client is null then return 'client-required'; end if;
  select stage into st from public.clients where id = p_client;
  if st is null then return 'client-required'; end if;
  if p_scope = 'client' and st not in ('active', 'paused', 'past') then return 'client-not-active'; end if;
  if p_scope = 'lead' and st not in ('lead', 'contacted', 'proposal') then return 'not-a-lead'; end if;
  return null;
end $$;

-- END OF A TASK MAY BE MADE FOR A PAST CLIENT --------------------------------

-- =========================================================================
-- SOCIAL MEDIA REPORTS
--
-- A client's monthly social media report: the accounts, every post with its
-- figures, and the team's findings, kept as rows and drawn as a PDF in the
-- browser by js/smreport.js. Asked for by the user on 2026-09-25: the client
-- reads the final report in their own portal, and only once the team has
-- finished it, confirmed it and published it.
--
--   draft  -> review     Submit for review          clients.reports Work
--   review -> draft      Return (a note)            the submitter, or Manage
--   review -> confirmed  Confirm                    Manage, never the submitter
--   confirmed -> draft   Return (a note)            Manage
--   confirmed -> published  Publish                 Manage
--   published -> draft   Revise (the next version)  Work
--   published -> confirmed  Unpublish (a reason)    Manage
--
-- Nothing a client reads is ever a row somebody is still editing. Publishing
-- freezes the report into `sm_report_versions.snapshot`, and the client
-- portal reads only that, the newest version not withdrawn. A revision is a
-- new draft with the next version number; the client goes on reading the
-- version they have until the revision is published.
--
-- The rows are edited directly by the console under row level security
-- (`clients.reports` Work), but only while the report is a draft: a trigger
-- refuses any change to the report's content, its accounts or its posts once
-- it has been submitted, and refuses any change to its status, version or
-- stamps except from the functions below. A browser cannot publish a report
-- by writing a column.
--
-- Thumbnails are kept in the row as small JPEG data URLs (the editor scales
-- them to 320px), not on the CDN: the PDF is drawn in the browser, and the
-- CDN does not answer a cross-origin read, so a CDN thumbnail could not be
-- drawn into the file.
--
-- Rollback:
--   drop function if exists public.portal_report(uuid);
--   drop function if exists public.portal_reports(uuid);
--   drop function if exists public.sm_report_delete(uuid, text);
--   drop function if exists public.sm_report_unpublish(uuid, text);
--   drop function if exists public.sm_report_revise(uuid);
--   drop function if exists public.sm_report_publish(uuid);
--   drop function if exists public.sm_report_confirm(uuid);
--   drop function if exists public.sm_report_return(uuid, text);
--   drop function if exists public.sm_report_submit(uuid);
--   drop function if exists public.sm_report_create(uuid, date, date, text);
--   drop function if exists public.sm_report_snapshot(uuid, boolean);
--   drop function if exists public.sm_report_log(uuid, text, text);
--   drop table if exists public.sm_report_versions, public.sm_report_posts,
--     public.sm_report_platforms, public.sm_reports;
--   drop function if exists public.sm_report_guard(), public.sm_report_child_guard();
--   and re-run the activity_section of 2026-09-24-creator-profile.sql.
-- =========================================================================

create table if not exists public.sm_reports (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.clients(id) on delete cascade,
  -- Which report this is. One engine of steps for every kind; the kind
  -- decides what is entered and how the PDF is drawn. Social media is built,
  -- advertising is next.
  kind          text not null default 'social',
  title         text not null default 'Social Media Report',
  period_start  date not null,
  period_end    date not null,
  headline      text,
  intro         text,
  insights      jsonb not null default '{}'::jsonb,
  rank_metric   text not null default 'views',
  status        text not null default 'draft',
  version_no    integer not null default 1,
  return_note   text,
  submitted_by  uuid references public.team_members(id) on delete set null,
  submitted_at  timestamptz,
  confirmed_by  uuid references public.team_members(id) on delete set null,
  confirmed_at  timestamptz,
  created_by    uuid references public.team_members(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint sm_reports_status check (status in ('draft', 'review', 'confirmed', 'published')),
  constraint sm_reports_kind check (kind in ('social', 'ads')),
  constraint sm_reports_rank check (rank_metric in ('views', 'reach', 'impressions', 'engagements', 'interactions')),
  constraint sm_reports_period check (period_end >= period_start),
  constraint sm_reports_title check (length(btrim(title)) between 1 and 120)
);
create unique index if not exists sm_reports_client_period_idx
  on public.sm_reports (client_id, kind, period_start, period_end);

create table if not exists public.sm_report_platforms (
  id              uuid primary key default gen_random_uuid(),
  report_id       uuid not null references public.sm_reports(id) on delete cascade,
  platform        text not null,
  account_name    text,
  handle          text,
  group_key       text,
  group_label     text,
  position        integer not null default 0,
  metrics         text[] not null default array['views', 'engagements'],
  followers_start bigint,
  followers_end   bigint,
  growth_override bigint,
  growth_reason   text,
  er_basis        text,
  metric_notes    text,
  summary         text,
  worked          text,
  improve         text,
  actions         text,
  created_at      timestamptz not null default now(),
  constraint sm_platforms_platform check (platform in ('facebook', 'instagram', 'tiktok', 'rednote', 'youtube', 'linkedin', 'x', 'threads', 'other')),
  constraint sm_platforms_basis check (er_basis is null or er_basis in ('views', 'reach', 'impressions', 'followers'))
);
create index if not exists sm_report_platforms_report_idx on public.sm_report_platforms (report_id);

create table if not exists public.sm_report_posts (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.sm_reports(id) on delete cascade,
  platform_id   uuid not null references public.sm_report_platforms(id) on delete cascade,
  posted_on     date,
  title         text,
  caption       text,
  content_type  text,
  url           text,
  thumb_data    text,
  views         bigint,
  reach         bigint,
  impressions   bigint,
  interactions  bigint,
  engagements   bigint,
  likes         bigint,
  comments      bigint,
  shares        bigint,
  saves         bigint,
  notable       text,
  observation   text,
  position      integer not null default 0,
  created_at    timestamptz not null default now(),
  constraint sm_posts_thumb check (thumb_data is null or (thumb_data like 'data:image/%' and length(thumb_data) <= 300000))
);
create index if not exists sm_report_posts_report_idx on public.sm_report_posts (report_id);

create table if not exists public.sm_report_versions (
  id               uuid primary key default gen_random_uuid(),
  report_id        uuid not null references public.sm_reports(id) on delete cascade,
  version_no       integer not null,
  snapshot         jsonb not null,
  published_by     text,
  published_at     timestamptz not null default now(),
  withdrawn_at     timestamptz,
  withdrawn_by     text,
  withdraw_reason  text,
  unique (report_id, version_no)
);

alter table public.sm_reports enable row level security;
alter table public.sm_report_platforms enable row level security;
alter table public.sm_report_posts enable row level security;
alter table public.sm_report_versions enable row level security;

drop policy if exists sm_reports_read on public.sm_reports;
create policy sm_reports_read on public.sm_reports for select to authenticated
  using (public.allowed('clients.reports', 'view'));
drop policy if exists sm_reports_write on public.sm_reports;
create policy sm_reports_write on public.sm_reports for update to authenticated
  using (public.allowed('clients.reports', 'work')) with check (public.allowed('clients.reports', 'work'));
drop policy if exists sm_platforms_all on public.sm_report_platforms;
create policy sm_platforms_all on public.sm_report_platforms for all to authenticated
  using (public.allowed('clients.reports', 'view')) with check (public.allowed('clients.reports', 'work'));
drop policy if exists sm_posts_all on public.sm_report_posts;
create policy sm_posts_all on public.sm_report_posts for all to authenticated
  using (public.allowed('clients.reports', 'view')) with check (public.allowed('clients.reports', 'work'));
drop policy if exists sm_versions_read on public.sm_report_versions;
create policy sm_versions_read on public.sm_report_versions for select to authenticated
  using (public.allowed('clients.reports', 'view'));
-- A report's rows are removed only by the functions; a platform or a post
-- may be deleted directly while its report is a draft, which the guard below
-- decides. The versions are written by the functions alone.

/* The functions below set this for their own transaction. Nothing a browser
   sends can: `set_config` is not reachable through PostgREST, and the
   setting lives only as long as the function's own transaction. */
create or replace function public.sm_report_guard()
returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('adspace.sm_fn', true), '') = 'on' then
    new.updated_at := now();
    return new;
  end if;
  if new.status is distinct from old.status or new.version_no is distinct from old.version_no
     or new.submitted_by is distinct from old.submitted_by or new.submitted_at is distinct from old.submitted_at
     or new.confirmed_by is distinct from old.confirmed_by or new.confirmed_at is distinct from old.confirmed_at
     or new.return_note is distinct from old.return_note or new.client_id is distinct from old.client_id
     or new.kind is distinct from old.kind
     or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'sm-status-by-function' using errcode = 'P0001';
  end if;
  if old.status <> 'draft' then
    raise exception 'sm-not-draft' using errcode = 'P0001';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists sm_reports_guard on public.sm_reports;
create trigger sm_reports_guard before update on public.sm_reports
  for each row execute function public.sm_report_guard();

create or replace function public.sm_report_child_guard()
returns trigger
language plpgsql set search_path = public as $$
declare
  st text;
  rid uuid := case when tg_op = 'DELETE' then old.report_id else new.report_id end;
begin
  if coalesce(current_setting('adspace.sm_fn', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'UPDATE' and new.report_id is distinct from old.report_id then
    raise exception 'sm-not-draft' using errcode = 'P0001';
  end if;
  select status into st from public.sm_reports where id = rid;
  -- The report itself is going (a client deleted, a cascade): nothing to guard.
  if st is null and tg_op = 'DELETE' then return old; end if;
  if st is distinct from 'draft' then
    raise exception 'sm-not-draft' using errcode = 'P0001';
  end if;
  -- A post is filed only under an account of its own report. Read through
  -- jsonb, because PL/pgSQL resolves `new.platform_id` on the accounts
  -- table too, where there is no such column.
  if tg_table_name = 'sm_report_posts' and tg_op <> 'DELETE' then
    if not exists (select 1 from public.sm_report_platforms p
                    where p.id = (to_jsonb(new) ->> 'platform_id')::uuid and p.report_id = new.report_id) then
      raise exception 'sm-wrong-platform' using errcode = 'P0001';
    end if;
  end if;
  update public.sm_reports set updated_at = now() where id = rid and status = 'draft'
    and updated_at < now() - interval '1 second';
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists sm_platforms_guard on public.sm_report_platforms;
create trigger sm_platforms_guard before insert or update or delete on public.sm_report_platforms
  for each row execute function public.sm_report_child_guard();
drop trigger if exists sm_posts_guard on public.sm_report_posts;
create trigger sm_posts_guard before insert or update or delete on public.sm_report_posts
  for each row execute function public.sm_report_child_guard();

/* The period in words, as the report and the activity record name it. */
create or replace function public.sm_period_word(p_start date, p_end date)
returns text
language sql immutable set search_path = public as $$
  select case
    when p_start = date_trunc('month', p_start)::date
     and p_end = (date_trunc('month', p_start) + interval '1 month - 1 day')::date
      then trim(to_char(p_start, 'FMMonth YYYY'))
    else to_char(p_start, 'FMDD Mon YYYY') || ' to ' || to_char(p_end, 'FMDD Mon YYYY')
  end
$$;

create or replace function public.sm_report_log(p_id uuid, p_action text, p_extra text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.sm_reports;
  who text;
  cname text;
begin
  select * into r from public.sm_reports where id = p_id;
  select c.name into cname from public.clients c where c.id = r.client_id;
  who := coalesce((public.ops_me()).name, auth.jwt() ->> 'email');
  insert into public.activity_log (actor, action, subject, detail)
  values (who, p_action, cname,
          public.sm_period_word(r.period_start, r.period_end) || ' · v' || r.version_no
          || coalesce(' · ' || nullif(btrim(p_extra), ''), ''));
end $$;
revoke all on function public.sm_report_log(uuid, text, text) from public, anon, authenticated;

/* The whole report as js/smreport.js reads it. `p_final` is the published
   form: the status the PDF prints as issued, and the time it was issued. */
create or replace function public.sm_report_snapshot(p_id uuid, p_final boolean default false)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  c public.clients;
begin
  if not public.allowed('clients.reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  return jsonb_build_object(
    'report', jsonb_build_object(
      'id', r.id, 'kind', r.kind, 'title', r.title, 'client_name', c.name, 'client_logo_url', c.logo_url,
      'period_start', r.period_start, 'period_end', r.period_end,
      'headline', r.headline, 'intro', r.intro, 'insights', r.insights, 'rank_metric', r.rank_metric,
      'status', case when p_final then 'final' else r.status end,
      'version_no', r.version_no, 'generated_at', now(),
      'prepared_by_name', (select name from public.team_members where id = r.submitted_by)),
    'platforms', coalesce((select jsonb_agg(to_jsonb(p) - 'created_at' order by p.position, p.created_at)
                  from public.sm_report_platforms p where p.report_id = r.id), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg((to_jsonb(q) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', q.thumb_data)
                  order by q.posted_on nulls last, q.position, q.created_at)
                  from public.sm_report_posts q where q.report_id = r.id), '[]'::jsonb));
end $$;
grant execute on function public.sm_report_snapshot(uuid, boolean) to authenticated;

/* A new report of a kind for a client and a period. The accounts of the
   client's latest earlier report of the same kind are carried forward, each
   starting with the followers that report ended on, so a month starts with
   its accounts in place and only the figures to type. Only the kinds the
   console can draw are accepted. */
create or replace function public.sm_report_create(p_client uuid, p_start date, p_end date, p_kind text default 'social')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rid uuid;
  prev uuid;
begin
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_client is null or not exists (select 1 from public.clients where id = p_client) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('error', 'bad-period'); end if;
  if coalesce(p_kind, '') not in ('social') then return jsonb_build_object('error', 'bad-kind'); end if;
  select id into rid from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start = p_start and period_end = p_end;
  if rid is not null then return jsonb_build_object('error', 'exists', 'id', rid); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  insert into public.sm_reports (client_id, kind, period_start, period_end, created_by)
  values (p_client, p_kind, p_start, p_end, me.id) returning id into rid;
  select id into prev from public.sm_reports
   where client_id = p_client and kind = p_kind and id <> rid and period_start < p_start
   order by period_start desc limit 1;
  if prev is not null then
    insert into public.sm_report_platforms (report_id, platform, account_name, handle, group_key, group_label,
      position, metrics, followers_start, er_basis, metric_notes)
    select rid, p.platform, p.account_name, p.handle, p.group_key, p.group_label, p.position, p.metrics,
           coalesce(p.followers_end, case when p.followers_start is not null and p.growth_override is not null
                                          then p.followers_start + p.growth_override end),
           p.er_basis, p.metric_notes
      from public.sm_report_platforms p where p.report_id = prev;
  end if;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(rid, 'report.created');
  return jsonb_build_object('ok', true, 'id', rid, 'carried', prev is not null);
end $$;
grant execute on function public.sm_report_create(uuid, date, date, text) to authenticated;

create or replace function public.sm_report_submit(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if not exists (select 1 from public.sm_report_platforms where report_id = p_id) then
    return jsonb_build_object('error', 'no-platforms');
  end if;
  if not exists (select 1 from public.sm_report_posts where report_id = p_id) then
    return jsonb_build_object('error', 'no-posts');
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'review', submitted_by = me.id, submitted_at = now(),
    return_note = null, confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.submitted');
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
grant execute on function public.sm_report_submit(uuid) to authenticated;

/* Back to draft with a note saying what to change. The person who
   submitted it may take it back while it waits; otherwise it is the
   reviewer's act, which is Manage. */
create or replace function public.sm_report_return(p_id uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status not in ('review', 'confirmed') then return jsonb_build_object('error', 'not-returnable', 'status', r.status); end if;
  if not public.allowed('clients.reports', 'manage')
     and not (r.status = 'review' and r.submitted_by = me.id) then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('error', 'note-required'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'draft', return_note = btrim(p_note),
    confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.returned', btrim(p_note));
  return jsonb_build_object('ok', true, 'status', 'draft');
end $$;
grant execute on function public.sm_report_return(uuid, text) to authenticated;

/* The internal confirmation: somebody who may manage reports, and never
   the person who submitted it, reads it and says it is right. */
create or replace function public.sm_report_confirm(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('clients.reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'review' then return jsonb_build_object('error', 'not-in-review', 'status', r.status); end if;
  if r.submitted_by = me.id then return jsonb_build_object('error', 'self-confirm'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'confirmed', confirmed_by = me.id, confirmed_at = now() where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.confirmed');
  return jsonb_build_object('ok', true, 'status', 'confirmed');
end $$;
grant execute on function public.sm_report_confirm(uuid) to authenticated;

/* Publish: the confirmed report is frozen as its version and the client
   can read it. The same press twice publishes once. */
create or replace function public.sm_report_publish(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  snap jsonb;
  vid uuid;
begin
  if me.id is null or not public.allowed('clients.reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status = 'published' then
    select id into vid from public.sm_report_versions where report_id = p_id and version_no = r.version_no;
    return jsonb_build_object('ok', true, 'status', 'published', 'version_id', vid, 'again', true);
  end if;
  if r.status <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed', 'status', r.status); end if;
  snap := public.sm_report_snapshot(p_id, true);
  perform set_config('adspace.sm_fn', 'on', true);
  insert into public.sm_report_versions (report_id, version_no, snapshot, published_by)
  values (p_id, r.version_no, snap, me.name)
  on conflict (report_id, version_no) do update
    set snapshot = excluded.snapshot, published_by = excluded.published_by, published_at = now(),
        withdrawn_at = null, withdrawn_by = null, withdraw_reason = null
  returning id into vid;
  update public.sm_reports set status = 'published' where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.published');
  return jsonb_build_object('ok', true, 'status', 'published', 'version_id', vid);
end $$;
grant execute on function public.sm_report_publish(uuid) to authenticated;

/* Revise a published report: a new draft with the next version number.
   The client goes on reading the published version until the revision is
   published in its place. */
create or replace function public.sm_report_revise(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('clients.reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'published' then return jsonb_build_object('error', 'not-published', 'status', r.status); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'draft', version_no = r.version_no + 1, return_note = null,
    submitted_by = null, submitted_at = null, confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.revised');
  return jsonb_build_object('ok', true, 'status', 'draft', 'version_no', r.version_no + 1);
end $$;
grant execute on function public.sm_report_revise(uuid) to authenticated;

/* Take the published version off the client's portal, with a reason. The
   version is kept, marked withdrawn; a published report goes back to
   confirmed so it can be published again. */
create or replace function public.sm_report_unpublish(p_id uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  n int;
begin
  if me.id is null or not public.allowed('clients.reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_report_versions set withdrawn_at = now(), withdrawn_by = me.name, withdraw_reason = btrim(p_reason)
   where report_id = p_id and withdrawn_at is null;
  get diagnostics n = row_count;
  if n = 0 then
    perform set_config('adspace.sm_fn', 'off', true);
    return jsonb_build_object('error', 'not-published');
  end if;
  if r.status = 'published' then
    update public.sm_reports set status = 'confirmed' where id = p_id;
  end if;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.unpublished', btrim(p_reason));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.sm_report_unpublish(uuid, text) to authenticated;

/* A report that was never published may be deleted, with its period typed
   back. One that a client has read is not: unpublish it instead, so the
   record of what the client was shown stands. */
create or replace function public.sm_report_delete(p_id uuid, p_confirm text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  word text;
  cname text;
begin
  if me.id is null or not public.allowed('clients.reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.sm_report_versions where report_id = p_id) then
    return jsonb_build_object('error', 'has-versions');
  end if;
  word := public.sm_period_word(r.period_start, r.period_end);
  if lower(btrim(coalesce(p_confirm, ''))) <> lower(word) then return jsonb_build_object('error', 'confirm-mismatch'); end if;
  select name into cname from public.clients where id = r.client_id;
  perform set_config('adspace.sm_fn', 'on', true);
  delete from public.sm_reports where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'report.deleted', cname, word || ' · v' || r.version_no);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.sm_report_delete(uuid, text) to authenticated;

/* The client portal: the newest version of each report that stands, for a
   client the signed-in address may open, and one version's snapshot. */
create or replace function public.portal_reports(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  return jsonb_build_object('reports', coalesce((
    select jsonb_agg(jsonb_build_object('id', v.id, 'kind', r.kind, 'title', r.title, 'period_start', r.period_start,
             'period_end', r.period_end, 'version_no', v.version_no, 'published_at', v.published_at)
           order by r.period_start desc)
      from public.sm_reports r
      join lateral (select * from public.sm_report_versions x
                     where x.report_id = r.id and x.withdrawn_at is null
                     order by x.version_no desc limit 1) v on true
     where r.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.portal_reports(uuid) from public, anon;
grant execute on function public.portal_reports(uuid) to authenticated;

create or replace function public.portal_report(p_version uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  v public.sm_report_versions;
  cid uuid;
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select * into v from public.sm_report_versions where id = p_version and withdrawn_at is null;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select client_id into cid from public.sm_reports where id = v.report_id;
  if cid is null or cid not in (select public.portal_clients()) then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.sm_report_versions x where x.report_id = v.report_id
              and x.withdrawn_at is null and x.version_no > v.version_no) then
    return jsonb_build_object('error', 'not-found');
  end if;
  return jsonb_build_object('snapshot', v.snapshot);
end $$;
revoke all on function public.portal_report(uuid) from public, anon;
grant execute on function public.portal_report(uuid) to authenticated;

revoke all on function public.sm_report_guard() from public, anon, authenticated;
revoke all on function public.sm_report_child_guard() from public, anon, authenticated;
-- END OF SOCIAL MEDIA REPORTS

-- =========================================================================
-- SOCIAL MEDIA ADVERTISING REPORTS
--
-- The second kind the report builder makes: a client's monthly paid social
-- report, from the team's two templates (a first month, and every month
-- after it). Same engine of steps as the social media report (draft,
-- review, confirmed, published), same versions and the same client portal;
-- what differs is what is entered and how the PDF is drawn (js/smreport.js).
--
--   sm_reports.first_month  The client's first month of ads. Set when the
--                           report is made (no earlier advertising report
--                           for the client) and the team's to change. A
--                           first month carries the reading guidance and
--                           no previous period; a later month compares
--                           against the one before.
--   sm_reports.ads_totals   The account's own figures for the period, which
--                           cannot be added up from the ads (reach counts a
--                           person once however many ads they saw), and the
--                           previous period's, carried forward from the last
--                           advertising report when a new one is made:
--                           { reach, impressions, spend,
--                             prev_start, prev_end, prev_reach,
--                             prev_impressions, prev_spend,
--                             prev_groups: { objective: { results, spend } },
--                             groups: { objective: { results, label } } }
--   sm_report_ads           One row an ad and objective: the same creative
--                           run under two goals is two rows, compared side by
--                           side in the PDF.
--
-- Rollback:
--   drop table if exists public.sm_report_ads;
--   alter table public.sm_reports drop column if exists first_month,
--     drop column if exists ads_totals;
--   and re-run sm_report_create, sm_report_submit and sm_report_snapshot from
--   2026-09-25-social-media-reports.sql.
-- =========================================================================

alter table public.sm_reports add column if not exists first_month boolean not null default false;
alter table public.sm_reports add column if not exists ads_totals jsonb not null default '{}'::jsonb;

create table if not exists public.sm_report_ads (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.sm_reports(id) on delete cascade,
  position      integer not null default 0,
  name          text not null,
  objective     text not null default 'awareness',
  result_label  text,
  audience      text,
  starts_on     date,
  ends_on       date,
  spend         numeric(12, 2),
  results       bigint,
  reach         bigint,
  impressions   bigint,
  ctr           numeric(8, 4),
  -- The cost per result as Ads Manager prints it, where it was typed; the PDF
  -- works it out from spend and results otherwise. `thousand` is a figure
  -- per 1,000 people reached, as Ads Manager prices a reach result.
  cpr           numeric(12, 4),
  cpr_basis     text,
  -- The share of results by age band, in per cent: {"18-24": 0, "25-34": 47.6, ...}.
  age           jsonb not null default '{}'::jsonb,
  hook_rate     numeric(8, 4),
  hold_rate     numeric(8, 4),
  -- Average play time, in seconds.
  avg_play      numeric(8, 2),
  -- Plays reaching each quarter of the video, in per cent of plays:
  -- {"p25": 40, "p50": 22, "p75": 12, "p95": 7, "p100": 5}.
  retention     jsonb not null default '{}'::jsonb,
  thumb_data    text,
  remark        text,
  created_at    timestamptz not null default now(),
  constraint sm_ads_basis check (cpr_basis is null or cpr_basis in ('result', 'thousand')),
  constraint sm_ads_objective check (objective in ('awareness', 'traffic', 'engagement', 'leads', 'messaging', 'sales', 'app')),
  constraint sm_ads_name check (btrim(name) <> ''),
  constraint sm_ads_dates check (starts_on is null or ends_on is null or ends_on >= starts_on),
  constraint sm_ads_figures check (coalesce(spend, 0) >= 0 and coalesce(results, 0) >= 0
                                   and coalesce(reach, 0) >= 0 and coalesce(impressions, 0) >= 0),
  constraint sm_ads_thumb check (thumb_data is null or (thumb_data like 'data:image/%' and length(thumb_data) <= 300000))
);
create index if not exists sm_report_ads_report_idx on public.sm_report_ads (report_id, position);

alter table public.sm_report_ads enable row level security;
drop policy if exists sm_ads_all on public.sm_report_ads;
create policy sm_ads_all on public.sm_report_ads for all to authenticated
  using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
drop trigger if exists sm_ads_guard on public.sm_report_ads;
create trigger sm_ads_guard before insert or update or delete on public.sm_report_ads
  for each row execute function public.sm_report_child_guard();

/* The whole report as js/smreport.js reads it. `p_final` is the published
   form: the status the PDF prints as issued, and the time it was issued.
   The client's market is read through jsonb, because it decides which
   taxes the spend note names and a database without the column still draws
   the report. Reports View reads any report; Clients View reads a finished
   one, which is what the client record's Reports tab shows. */
create or replace function public.sm_report_snapshot(p_id uuid, p_final boolean default false)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  c public.clients;
begin
  if not public.allowed('reports', 'view') and not public.allowed('clients', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  -- Somebody who reads Clients but not Reports reads the finished report
  -- only: once it is confirmed, never while it is being prepared.
  if not public.allowed('reports', 'view') and r.status not in ('confirmed', 'published') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into c from public.clients where id = r.client_id;
  return jsonb_build_object(
    'report', jsonb_build_object(
      'id', r.id, 'kind', r.kind, 'title', r.title, 'client_name', c.name, 'client_logo_url', c.logo_url,
      'market', to_jsonb(c) ->> 'market',
      'period_start', r.period_start, 'period_end', r.period_end,
      'headline', r.headline, 'intro', r.intro, 'insights', r.insights, 'rank_metric', r.rank_metric,
      'first_month', r.first_month, 'ads_totals', r.ads_totals,
      'status', case when p_final then 'final' else r.status end,
      'version_no', r.version_no, 'generated_at', now(),
      'prepared_by_name', (select name from public.team_members where id = r.submitted_by)),
    'platforms', coalesce((select jsonb_agg(to_jsonb(p) - 'created_at' order by p.position, p.created_at)
                  from public.sm_report_platforms p where p.report_id = r.id), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg((to_jsonb(q) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', q.thumb_data)
                  order by q.posted_on nulls last, q.position, q.created_at)
                  from public.sm_report_posts q where q.report_id = r.id), '[]'::jsonb),
    'ads', coalesce((select jsonb_agg((to_jsonb(a) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', a.thumb_data)
                  order by a.position, a.created_at)
                  from public.sm_report_ads a where a.report_id = r.id), '[]'::jsonb));
end $$;
grant execute on function public.sm_report_snapshot(uuid, boolean) to authenticated;

/* A new report of a kind for a client and a period.
   Social: the accounts of the client's latest earlier social report are
   carried forward, each starting with the followers that report ended on.
   Advertising: the first one a client has is their first month; a later one
   carries the previous report's period and totals forward as the figures it
   is compared against, so a month opens with its comparison in place. */
create or replace function public.sm_report_create(p_client uuid, p_start date, p_end date, p_kind text default 'social')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rid uuid;
  prev uuid;
  pr public.sm_reports;
  totals jsonb := '{}'::jsonb;
  pgroups jsonb;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_client is null or not exists (select 1 from public.clients where id = p_client) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('error', 'bad-period'); end if;
  if coalesce(p_kind, '') not in ('social', 'ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select id into rid from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start = p_start and period_end = p_end;
  if rid is not null then return jsonb_build_object('error', 'exists', 'id', rid); end if;
  select id into prev from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start < p_start
   order by period_start desc limit 1;
  perform set_config('adspace.sm_fn', 'on', true);
  if p_kind = 'ads' then
    if prev is not null then
      select * into pr from public.sm_reports where id = prev;
      select coalesce(jsonb_object_agg(g.objective, jsonb_build_object('results',
               coalesce(nullif(pr.ads_totals #>> array['groups', g.objective, 'results'], '')::numeric, g.results),
               'spend', g.spend)), '{}'::jsonb)
        into pgroups
        from (select a.objective, sum(a.results) as results, sum(a.spend) as spend
                from public.sm_report_ads a where a.report_id = prev group by a.objective) g;
      totals := jsonb_strip_nulls(jsonb_build_object(
        'prev_start', pr.period_start, 'prev_end', pr.period_end,
        'prev_reach', nullif(pr.ads_totals ->> 'reach', '')::numeric,
        'prev_impressions', coalesce(nullif(pr.ads_totals ->> 'impressions', '')::numeric,
                                     (select sum(impressions) from public.sm_report_ads where report_id = prev)),
        'prev_spend', coalesce(nullif(pr.ads_totals ->> 'spend', '')::numeric,
                               (select sum(spend) from public.sm_report_ads where report_id = prev)),
        'prev_groups', pgroups));
    end if;
    insert into public.sm_reports (client_id, kind, title, period_start, period_end, created_by, first_month, ads_totals)
    values (p_client, p_kind, 'Social Media Advertising Report', p_start, p_end, me.id, prev is null, totals)
    returning id into rid;
  else
    insert into public.sm_reports (client_id, kind, period_start, period_end, created_by)
    values (p_client, p_kind, p_start, p_end, me.id) returning id into rid;
    if prev is not null then
      insert into public.sm_report_platforms (report_id, platform, account_name, handle, group_key, group_label,
        position, metrics, followers_start, er_basis, metric_notes)
      select rid, p.platform, p.account_name, p.handle, p.group_key, p.group_label, p.position, p.metrics,
             coalesce(p.followers_end, case when p.followers_start is not null and p.growth_override is not null
                                            then p.followers_start + p.growth_override end),
             p.er_basis, p.metric_notes
        from public.sm_report_platforms p where p.report_id = prev;
    end if;
  end if;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(rid, 'report.created');
  return jsonb_build_object('ok', true, 'id', rid, 'carried', prev is not null);
end $$;
grant execute on function public.sm_report_create(uuid, date, date, text) to authenticated;

/* Submit for review: a social report needs its accounts and posts, an
   advertising report its ads. */
create or replace function public.sm_report_submit(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if r.kind = 'ads' then
    if not exists (select 1 from public.sm_report_ads where report_id = p_id) then
      return jsonb_build_object('error', 'no-ads');
    end if;
  else
    if not exists (select 1 from public.sm_report_platforms where report_id = p_id) then
      return jsonb_build_object('error', 'no-platforms');
    end if;
    if not exists (select 1 from public.sm_report_posts where report_id = p_id) then
      return jsonb_build_object('error', 'no-posts');
    end if;
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'review', submitted_by = me.id, submitted_at = now(),
    return_note = null, confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.submitted');
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
grant execute on function public.sm_report_submit(uuid) to authenticated;
-- END OF SOCIAL MEDIA ADVERTISING REPORTS

-- =========================================================================
-- THE REPORTS SECTION
--
-- Reports were a part of Clients (`clients.reports`), so a colleague who
-- prepared reports had to be able to read every client record, and the
-- report opened on the client's record. They are a section of their own now:
--
--   reports View    read every report, preview its PDF
--   reports Work    start a report, enter its figures and text, submit it,
--                   revise a published one
--   reports Manage  also confirm, return, publish, unpublish and delete
--
-- A group's level moves across once: its `clients.reports` level where it
-- set one, else its Clients level (which the part fell back to), `none`
-- included, and the old key goes. Guarded on the new key, so a re-run moves
-- nothing. The client record keeps a Reports tab that shows the finished
-- reports only, read by anybody who reads Clients through the two functions
-- at the foot of this section; the tables themselves answer Reports alone.
--
-- Rollback:
--   update public.team_roles set access = (access - 'reports')
--     || jsonb_build_object('clients.reports', access ->> 'reports') where access ? 'reports';
--   drop function if exists public.sm_client_reports(uuid);
--   drop function if exists public.sm_report_file(uuid);
--   and re-run the policies and functions of 2026-09-25-social-media-reports.sql.
-- =========================================================================

update public.team_roles
   set access = (access - 'clients.reports')
       || jsonb_build_object('reports', coalesce(access ->> 'clients.reports', access ->> 'clients', 'none'))
 where not (access ? 'reports');
update public.team_members
   set access = (access - 'clients.reports')
       || jsonb_build_object('reports', coalesce(access ->> 'clients.reports', access ->> 'clients', 'none'))
 where not (access ? 'reports');

drop policy if exists sm_reports_read on public.sm_reports;
create policy sm_reports_read on public.sm_reports for select to authenticated
  using (public.allowed('reports', 'view'));
drop policy if exists sm_reports_write on public.sm_reports;
create policy sm_reports_write on public.sm_reports for update to authenticated
  using (public.allowed('reports', 'work')) with check (public.allowed('reports', 'work'));
drop policy if exists sm_platforms_all on public.sm_report_platforms;
create policy sm_platforms_all on public.sm_report_platforms for all to authenticated
  using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
drop policy if exists sm_posts_all on public.sm_report_posts;
create policy sm_posts_all on public.sm_report_posts for all to authenticated
  using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
drop policy if exists sm_versions_read on public.sm_report_versions;
create policy sm_versions_read on public.sm_report_versions for select to authenticated
  using (public.allowed('reports', 'view'));

-- A report is started for a client from the Reports section, so the client
-- list is read there too.
drop policy if exists clients_read on public.clients;
create policy clients_read on public.clients for select to authenticated
  using (public.allowed('clients', 'view') or public.allowed('review', 'view')
      or public.allowed('campaigns', 'view') or public.allowed('reports', 'view'));

/* Back to draft with a note saying what to change. The person who
   submitted it may take it back while it waits; otherwise it is the
   reviewer's act, which is Manage. */
create or replace function public.sm_report_return(p_id uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status not in ('review', 'confirmed') then return jsonb_build_object('error', 'not-returnable', 'status', r.status); end if;
  if not public.allowed('reports', 'manage')
     and not (r.status = 'review' and r.submitted_by = me.id) then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('error', 'note-required'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'draft', return_note = btrim(p_note),
    confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.returned', btrim(p_note));
  return jsonb_build_object('ok', true, 'status', 'draft');
end $$;
grant execute on function public.sm_report_return(uuid, text) to authenticated;

/* The internal confirmation: somebody who may manage reports, and never
   the person who submitted it, reads it and says it is right. */
create or replace function public.sm_report_confirm(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'review' then return jsonb_build_object('error', 'not-in-review', 'status', r.status); end if;
  if r.submitted_by = me.id then return jsonb_build_object('error', 'self-confirm'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'confirmed', confirmed_by = me.id, confirmed_at = now() where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.confirmed');
  return jsonb_build_object('ok', true, 'status', 'confirmed');
end $$;
grant execute on function public.sm_report_confirm(uuid) to authenticated;

/* Publish: the confirmed report is frozen as its version and the client
   can read it. The same press twice publishes once. */
create or replace function public.sm_report_publish(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  snap jsonb;
  vid uuid;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status = 'published' then
    select id into vid from public.sm_report_versions where report_id = p_id and version_no = r.version_no;
    return jsonb_build_object('ok', true, 'status', 'published', 'version_id', vid, 'again', true);
  end if;
  if r.status <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed', 'status', r.status); end if;
  snap := public.sm_report_snapshot(p_id, true);
  perform set_config('adspace.sm_fn', 'on', true);
  insert into public.sm_report_versions (report_id, version_no, snapshot, published_by)
  values (p_id, r.version_no, snap, me.name)
  on conflict (report_id, version_no) do update
    set snapshot = excluded.snapshot, published_by = excluded.published_by, published_at = now(),
        withdrawn_at = null, withdrawn_by = null, withdraw_reason = null
  returning id into vid;
  update public.sm_reports set status = 'published' where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.published');
  return jsonb_build_object('ok', true, 'status', 'published', 'version_id', vid);
end $$;
grant execute on function public.sm_report_publish(uuid) to authenticated;

/* Revise a published report: a new draft with the next version number.
   The client goes on reading the published version until the revision is
   published in its place. */
create or replace function public.sm_report_revise(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'published' then return jsonb_build_object('error', 'not-published', 'status', r.status); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'draft', version_no = r.version_no + 1, return_note = null,
    submitted_by = null, submitted_at = null, confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.revised');
  return jsonb_build_object('ok', true, 'status', 'draft', 'version_no', r.version_no + 1);
end $$;
grant execute on function public.sm_report_revise(uuid) to authenticated;

/* Take the published version off the client's portal, with a reason. The
   version is kept, marked withdrawn; a published report goes back to
   confirmed so it can be published again. */
create or replace function public.sm_report_unpublish(p_id uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  n int;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_report_versions set withdrawn_at = now(), withdrawn_by = me.name, withdraw_reason = btrim(p_reason)
   where report_id = p_id and withdrawn_at is null;
  get diagnostics n = row_count;
  if n = 0 then
    perform set_config('adspace.sm_fn', 'off', true);
    return jsonb_build_object('error', 'not-published');
  end if;
  if r.status = 'published' then
    update public.sm_reports set status = 'confirmed' where id = p_id;
  end if;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.unpublished', btrim(p_reason));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.sm_report_unpublish(uuid, text) to authenticated;

/* A report that was never published may be deleted, with its period typed
   back. One that a client has read is not: unpublish it instead, so the
   record of what the client was shown stands. */
create or replace function public.sm_report_delete(p_id uuid, p_confirm text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  word text;
  cname text;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.sm_report_versions where report_id = p_id) then
    return jsonb_build_object('error', 'has-versions');
  end if;
  word := public.sm_period_word(r.period_start, r.period_end);
  if lower(btrim(coalesce(p_confirm, ''))) <> lower(word) then return jsonb_build_object('error', 'confirm-mismatch'); end if;
  select name into cname from public.clients where id = r.client_id;
  perform set_config('adspace.sm_fn', 'on', true);
  delete from public.sm_reports where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'report.deleted', cname, word || ' · v' || r.version_no);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.sm_report_delete(uuid, text) to authenticated;

/* The client record's Reports tab: a client's finished reports, for
   anybody who reads Clients or Reports. Finished is confirmed or published,
   or a report being revised whose earlier version the client still reads. */
create or replace function public.sm_client_reports(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if not public.allowed('clients', 'view') and not public.allowed('reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('reports', coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period_start', r.period_start,
             'period_end', r.period_end, 'status', r.status, 'version_no', r.version_no,
             'confirmed_at', r.confirmed_at, 'live_version', v.version_no, 'published_at', v.published_at)
           order by r.period_start desc, r.kind)
      from public.sm_reports r
      left join lateral (select x.version_no, x.published_at from public.sm_report_versions x
                          where x.report_id = r.id and x.withdrawn_at is null
                          order by x.version_no desc limit 1) v on true
     where r.client_id = p_client
       and (r.status in ('confirmed', 'published') or v.version_no is not null)), '[]'::jsonb));
end $$;
grant execute on function public.sm_client_reports(uuid) to authenticated;

/* The file of a finished report: the version the client reads where one is
   published, else the confirmed report as it stands. */
create or replace function public.sm_report_file(p_id uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  snap jsonb;
begin
  if not public.allowed('clients', 'view') and not public.allowed('reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select x.snapshot into snap from public.sm_report_versions x
   where x.report_id = p_id and x.withdrawn_at is null order by x.version_no desc limit 1;
  if snap is not null then return jsonb_build_object('snapshot', snap); end if;
  if r.status <> 'confirmed' then return jsonb_build_object('error', 'not-finished'); end if;
  return jsonb_build_object('snapshot', public.sm_report_snapshot(p_id, false));
end $$;
grant execute on function public.sm_report_file(uuid) to authenticated;
-- END OF THE REPORTS SECTION

-- ===========================================================================
-- BULK ADD FROM THE MONTH — Bulk add takes tasks only into a content month
-- the client already has, with its meeting confirmed; an admin moves a due
-- date without the approval round.
-- 2026-09-25. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   1. `ops_generate_month` made the client's month when there was none, so
--      Bulk add could fill a month nobody had planned (the user, 2026-09-25:
--      "if under client -> work is not created for the month, then it
--      shouldnt have tasks within it"). It now refuses, on the preview and on
--      the run alike: `no-month` where the client has no month for that
--      period, `month-closed` where the month is completed or cancelled, and
--      `month-not-confirmed` where its content meeting is neither set nor
--      marked not applicable. The spread over weeks, the codes and the
--      publish dates are unchanged.
--
--   2. `ops_request_due_change` sends an admin's move straight through, as it
--      already did for the person who created the task (the user: "admin
--      should have the full access to overwrite everything"). The move still
--      goes through `ops_change_due_date`, so the original commitment is kept
--      and the event is filed. Everybody else still asks the creator.
--
-- ROLLBACK
--   Re-run 2026-09-24-bulk-add-spreads-the-month.sql and section 4 of
--   2026-09-21-draft-date-is-the-teams-own.sql.
-- ===========================================================================

-- 1. A month of content, only into a month the client has ---------------------
create or replace function public.ops_generate_month(
  p_payload jsonb, p_dry_run boolean default false, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  cid    uuid;
  per    text;
  n      integer;
  weeks  integer[];
  bad    text;
  eng    uuid;
  e      public.ops_engagements;
  k      integer;
  w      integer;
  seq    integer;
  seqs   integer;
  made   jsonb := '[]'::jsonb;
  one    jsonb;
  key    text;
  scope  text;
  first_day date;
  last_off integer;
  publish timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  n := coalesce((p_payload ->> 'count')::integer, 0);
  scope := coalesce(p_payload ->> 'scope', 'client');
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  if n < 1 or n > 60 then return jsonb_build_object('error', 'bad-count'); end if;

  if (p_payload -> 'weeks') is not null and jsonb_typeof(p_payload -> 'weeks') = 'array' then
    select array_agg(x::integer) into weeks from jsonb_array_elements_text(p_payload -> 'weeks') x;
    if array_length(weeks, 1) < 1 or array_length(weeks, 1) > 5 then
      return jsonb_build_object('error', 'bad-weeks');
    end if;
    if (select sum(v) from unnest(weeks) v) <> n then return jsonb_build_object('error', 'weeks-do-not-add-up'); end if;
  else
    /* Evenly over four weeks, the extras early: task i (from 0) falls in
       week floor(i * 4 / n) + 1, so eight is two a week, six is 2, 1, 2, 1,
       and two is weeks 1 and 3 rather than both in week 4. */
    weeks := array[]::integer[];
    for w in 1 .. 4 loop
      weeks := weeks || (ceil(w * n / 4.0)::integer - ceil((w - 1) * n / 4.0)::integer);
    end loop;
  end if;

  /* The same press twice is one month, not two. */
  if not p_dry_run and p_idem is not null then
    if exists (select 1 from public.ops_tasks where idem_key = 'month:' || p_idem || ':1') then
      return jsonb_build_object('error', 'already-generated');
    end if;
  end if;

  first_day := (per || '-01')::date;
  last_off := ((first_day + interval '1 month')::date - first_day) - 1;
  /* One lock for the whole run, taken before anything is read: two operators
     generating the same month queue here, so the second sees the first's
     engagement and the first's numbers rather than racing both. */
  perform pg_advisory_xact_lock(hashtext('ops_code:' || cid::text || ':' || per));
  /* The month must already exist on the client's Work pane, still be open,
     and have its content meeting confirmed: a month nobody planned holds no
     tasks. Asked on the preview as well as the run, so the sheet cannot
     show codes for a month the run would refuse. */
  select * into e from public.ops_engagements
   where client_id = cid and period = per;
  if e.id is null then return jsonb_build_object('error', 'no-month'); end if;
  if (p_payload ->> 'engagement_id') is not null and (p_payload ->> 'engagement_id')::uuid <> e.id then
    return jsonb_build_object('error', 'no-month');
  end if;
  if e.status in ('completed', 'cancelled') then return jsonb_build_object('error', 'month-closed'); end if;
  if e.meeting_at is null and not e.meeting_na then
    return jsonb_build_object('error', 'month-not-confirmed');
  end if;
  eng := e.id;
  if not p_dry_run then
    update public.ops_engagements set planned_count = greatest(planned_count, n), updated_at = now()
     where id = eng and planned_count < n;
  end if;

  /* One lock for the whole month, so the preview and the run see the same
     next number and two operators generating for one client queue. */
  seq := public.ops_next_seq(cid, per) - 1;
  seqs := 0;
  for w in 1 .. array_length(weeks, 1) loop
    for k in 1 .. coalesce(weeks[w], 0) loop
      seq := seq + 1;
      seqs := seqs + 1;
      /* A tentative date inside the task's own week, the week's tasks
         spread across its seven days, so the calendar has somewhere to put
         each one; the content meeting fixes the real date. Never past the
         month's last day, which only a fifth week can reach. */
      publish := (first_day + least((w - 1) * 7 + ((k - 1) * 7) / weeks[w], last_off))::timestamptz;
      if p_dry_run then
        made := made || jsonb_build_object('code', public.ops_code_of(per, w, seq), 'week', w, 'seq', seq);
      else
        key := case when p_idem is null then null else 'month:' || p_idem || ':' || seqs::text end;
        one := public.ops_create_task(jsonb_build_object(
          'scope', scope, 'client_id', cid, 'engagement_id', eng,
          'task_type', coalesce(p_payload ->> 'task_type', 'engagement'),
          'deliverable_type', p_payload ->> 'deliverable_type',
          'priority_level', (p_payload ->> 'priority_level')::integer,
          'complexity', p_payload ->> 'complexity',
          'owner_id', (p_payload ->> 'owner_id')::uuid,
          'manager_id', (p_payload ->> 'manager_id')::uuid,
          'code_period', per, 'code_week', w,
          'publish_at', publish), key);
        if one ? 'error' then return one; end if;
        made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'week', w, 'seq', seq);
      end if;
    end loop;
  end loop;
  return jsonb_build_object('engagement_id', eng, 'period', per, 'count', seqs,
                            'tasks', made, 'dry_run', p_dry_run);
end $$;
grant execute on function public.ops_generate_month(jsonb, boolean, text) to authenticated;

-- 2. Asking to move a date; an admin moves it --------------------------------
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
  /* An admin moves any date directly: the round protects the person who set
     the date from somebody else, and an admin is the one who may overwrite
     anybody's. The move still files its event and keeps the original. */
  if who is null or who = m.id or public.allowed('admin') then
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

-- END OF BULK ADD FROM THE MONTH -------------------------------------------

-- ===========================================================================
-- THE OWNER MOVES THE TASK — every task has an owner, and only the owner
-- (or an admin) moves its stage.
-- 2026-09-25. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   1. `ops_create_task` makes the person creating a task its owner when the
--      payload names nobody and the template names nobody, so no task is made
--      ownerless (the team, 2026-09-25: "cannot have no owner situation").
--      Open tasks already without an owner take whoever created them.
--
--   2. `ops_transition_task` and `ops_set_blocked` refuse `not-owner` unless
--      the caller is the task's current owner or an admin (the team: "when
--      owner alr changed, other users shouldnt have the authority to mark the
--      status for them"). Unblocking, marking live and a board drag all go
--      through the transition, so they follow. A task with no owner, which
--      now only a hand edit could leave, may be moved by anybody who works it.
--
--   Assigning, handing over, dates, links and comments are unchanged.
--
-- ROLLBACK
--   Re-run the ops_create_task, ops_transition_task and ops_set_blocked
--   definitions in 2026-09-24-my-work-daily-tasks.sql and
--   2026-09-19-operations-system.sql, then
--   drop function if exists public.ops_owner_may_move(uuid);
--   The owners the backfill added stay; end them by hand if wanted.
-- ===========================================================================

-- 1. Who may move a task ------------------------------------------------------
create or replace function public.ops_owner_may_move(p_task uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select public.allowed('admin')
      or not exists (select 1 from public.ops_task_assignees a
                      where a.task_id = p_task and a.responsibility = 'owner' and a.ended_at is null)
      or exists (select 1 from public.ops_task_assignees a
                  where a.task_id = p_task and a.responsibility = 'owner' and a.ended_at is null
                    and a.team_member_id = (public.ops_me()).id)
$$;
grant execute on function public.ops_owner_may_move(uuid) to authenticated;

-- 2. A new task is owned from the start -------------------------------------
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
  scope text;
  ttype text;
  cid   uuid;
  bad   text;
  descr text;
  period text;
  week  integer;
  seq   integer;
  code  text;
  title text;
  first_stage text;
  wkey  text;
  base  timestamptz;
  eng   public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  scope := coalesce(p_payload ->> 'scope', 'client');
  cid := (p_payload ->> 'client_id')::uuid;
  /* A task linked to a month's engagement takes the client from it: the
     person names the month once and the client comes with it. */
  if (p_payload ->> 'engagement_id') is not null then
    select * into eng from public.ops_engagements where id = (p_payload ->> 'engagement_id')::uuid;
    if eng.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if cid is null then cid := eng.client_id; scope := 'client'; end if;
  end if;
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;

  ttype := coalesce(p_payload ->> 'task_type', 'adhoc');
  if ttype not in ('engagement', 'adhoc', 'goodwill', 'special') then
    return jsonb_build_object('error', 'bad-task-type');
  end if;

  /* The description is the team's to edit and may start blank on a task that
     carries a code; a task with no code is named by its description alone, so
     there it is required. `title` is accepted from older callers as the
     description. */
  descr := nullif(btrim(coalesce(p_payload ->> 'content_desc', p_payload ->> 'title', '')), '');

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
    descr := coalesce(descr, nullif(btrim(coalesce(tpl.default_title, tpl.name, '')), ''));
  end if;
  /* New work goes on the content workflow. A caller may still name another
     (a template's own, or one somebody adds), and a task already on a retired
     workflow is never moved. */
  wf := coalesce((p_payload ->> 'workflow_id')::uuid,
                 (select id from public.ops_workflows where key = p_payload ->> 'workflow_key' and active),
                 tpl.workflow_id,
                 (select id from public.ops_workflows where key = 'content' and active),
                 (select id from public.ops_workflows where active order by created_at limit 1));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  select key into first_stage from public.ops_workflow_stages
   where workflow_id = wf order by position limit 1;
  select key into wkey from public.ops_workflows where id = wf;

  publish := (p_payload ->> 'publish_at')::timestamptz;
  fd := coalesce((p_payload ->> 'first_draft_due_at')::timestamptz,
        case when publish is not null and tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.first_draft_offset_business_days)
             when tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.first_draft_offset_business_days)
        end);
  /* A template's due date is a number of calendar days from the day the
     work is made for (the base date the caller names, else today). */
  base := coalesce((p_payload ->> 'base_date')::timestamptz, now());
  fin := coalesce((p_payload ->> 'final_due_at')::timestamptz,
        case when tpl.due_offset_days is not null
             then date_trunc('day', base) + make_interval(days => tpl.due_offset_days)
             when publish is not null and tpl.final_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.final_offset_business_days)
             when tpl.final_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.final_offset_business_days)
        end);
  if fd is not null and fin is not null and not public.ops_due_order_ok(fd, fin) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  /* The name. The month is the content month (the scheduled publish date's,
     else the one the caller names, else this one); the week is the planned
     publishing week, chosen by the caller and prefilled by the page from the
     date; the running number is the client's for the month. Generated once,
     under the lock, and never rewritten: a publish date that moves later
     leaves the name as it was, because the name is a label and not a fact
     about the date. */
  if wkey = 'task' then
    /* An everyday task is named by what it is. It carries no content code,
       because the code numbers a client's deliverables for the month and a
       task is not one; the content month is kept where it is known, so the
       task can be grouped with the month it belongs to. */
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
    period := coalesce(nullif(p_payload ->> 'code_period', ''), eng.period);
  elsif scope <> 'internal' then
    period := coalesce(nullif(p_payload ->> 'code_period', ''),
                       case when publish is not null then to_char(publish, 'YYYY-MM') end,
                       to_char(now(), 'YYYY-MM'));
    if period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
    week := coalesce((p_payload ->> 'code_week')::integer,
                     case when publish is not null
                          then least(5, ((extract(day from publish)::integer - 1) / 7) + 1) end,
                     1);
    if week < 1 or week > 5 then return jsonb_build_object('error', 'bad-week'); end if;
    seq := public.ops_next_seq(cid, period);
    code := public.ops_code_of(period, week, seq);
    title := btrim(code || ' ' || coalesce(descr, ''));
  else
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
  end if;

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality,
    task_type, code, code_period, code_week, code_seq, content_desc,
    engagement_id, manager_id, parent_task_id)
  values (
    scope, cid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, coalesce(first_stage, 'intake'),
    title, p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'other'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'),
    ttype, code, period, week, seq, descr,
    coalesce((p_payload ->> 'engagement_id')::uuid, eng.id),
    coalesce((p_payload ->> 'manager_id')::uuid, m.id),
    (p_payload ->> 'parent_task_id')::uuid)
  returning id into tid;

  /* Every task has an owner from the moment it exists: the one named, the
     template's, or else whoever made it. */
  owner := coalesce((p_payload ->> 'owner_id')::uuid, tpl.default_owner_id, m.id);
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

  -- The template's checklist, or the one the caller hands over (a duplicate
  -- carries its source's labels, unticked), in the order stated.
  for item in select * from jsonb_array_elements(
      coalesce(p_payload -> 'checklist', tpl.checklist, '[]'::jsonb)) loop
    i := i + 1;
    insert into public.ops_task_checklist_items (task_id, label, position)
    values (tid, item #>> '{}', i);
  end loop;

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
    jsonb_build_object('title', title, 'code', code,
                       'first_draft_due_at', fd, 'final_due_at', fin),
    case when (p_payload ->> 'duplicated_from') is null then '{}'::jsonb
         else jsonb_build_object('duplicated_from', p_payload ->> 'duplicated_from') end);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

-- 3. Only the owner moves the stage ------------------------------------------
create or replace function public.ops_transition_task(
  p_task uuid, p_next text, p_version integer default null, p_note text default null,
  p_assignee uuid default null, p_skip_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cur public.ops_workflow_stages;
  nxt public.ops_workflow_stages;
  sk  public.ops_workflow_stages;
  eng public.ops_engagements;
  has_owner boolean;
  has_draft boolean;
  has_final boolean;
  was_owner uuid;
  side text[] := array['blocked', 'waiting', 'kiv', 'cancelled'];
  skipping boolean := false;
  ws  public.ops_work_sessions;
  wmins integer;
  v_round integer;
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
  if t.stage_key = p_next then return public.ops_task_json(p_task); end if;
  /* The stage is the owner's to move. Once a task is handed to somebody,
     whoever created it or held it before reads it and no longer moves it; an
     admin still may. */
  if not public.ops_owner_may_move(p_task) then return jsonb_build_object('error', 'not-owner'); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  if not (p_next = any (cur.next_stage_keys)) then
    /* A step the deliverable does not need is skipped, forward along the
       line, with a reason on the record: who skipped it and why is written
       against every stage that was passed over. Nothing beside the line can
       be skipped into or out of, and nothing is skipped backwards. */
    /* A revision is where work is sent back from a review, so it is never
       a step somebody skips forward into. */
    if not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.stage_group <> 'revision'
       and nxt.position > cur.position then
      if nullif(btrim(coalesce(p_skip_reason, '')), '') is null then
        return jsonb_build_object('error', 'skip-reason-required');
      end if;
      skipping := true;
    else
      return jsonb_build_object('error', 'bad-transition',
        'allowed', to_jsonb(cur.next_stage_keys));
    end if;
  end if;

  /* A performance review goes back to whoever created the task unless the
     move names somebody else. */
  if p_next = 'performance_review' and p_assignee is null and exists (
       select 1 from public.team_members where id = t.created_by and active) then
    p_assignee := t.created_by;
  end if;

  -- What each gate needs before it opens.
  has_owner := exists (select 1 from public.ops_task_assignees
                        where task_id = p_task and responsibility = 'owner' and ended_at is null)
               or p_assignee is not null;
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
  /* Production waits on the engagement: planning marked complete, and the
     content meeting held or marked not applicable. A task with no engagement
     (ad hoc, internal) has nothing to wait on. */
  if p_next = 'in_production' and t.engagement_id is not null then
    select * into eng from public.ops_engagements where id = t.engagement_id;
    if eng.status = 'planning' then return jsonb_build_object('error', 'planning-incomplete'); end if;
    if not (eng.meeting_na or (eng.meeting_at is not null and eng.meeting_at <= now())) then
      return jsonb_build_object('error', 'meeting-required');
    end if;
  end if;
  /* AQC review comes first: the client sees the work only once it has been
     through AQC review at least once. */
  if p_next = 'client_review'
     and exists (select 1 from public.ops_workflow_stages s
                  where s.workflow_id = t.workflow_id and s.key = 'internal_review')
     and not exists (select 1 from public.ops_task_events e
                      where e.task_id = p_task and e.event_type = 'stage_changed'
                        and e.to_value ->> 'stage_key' = 'internal_review') then
    return jsonb_build_object('error', 'needs-aqc');
  end if;
  /* The draft reaches the client as a link on the task or through the
     team's WhatsApp group with the client. Either way the record says how:
     the link, or a note naming where it went. */
  if p_next = 'client_review' and not has_draft
     and nullif(btrim(coalesce(p_note, '')), '') is null then
    return jsonb_build_object('error', 'needs-draft');
  end if;
  /* A revision says what has to change, and so does taking a post down. */
  if ((nxt.stage_group = 'revision' and p_next <> 'changes_requested') or p_next = 'taken_down')
     and nullif(btrim(coalesce(p_note, '')), '') is null then
    return jsonb_build_object('error', 'note-required');
  end if;
  /* After approval: a schedule needs its date, going live is confirmed with
     its own date through ops_mark_live and needs the post's link or a note,
     and a task is completed only once its performance checklist is done. */
  if p_next = 'scheduled' and t.publish_at is null then
    return jsonb_build_object('error', 'needs-schedule');
  end if;
  if p_next = 'live' and t.live_at is null then
    return jsonb_build_object('error', 'needs-live-date');
  end if;
  if p_next = 'live' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;
  if p_next = 'completed' and exists (
       select 1 from public.ops_task_checklist_items c
        where c.task_id = p_task and c.required and c.completed_at is null) then
    return jsonb_build_object('error', 'checklist-incomplete');
  end if;
  if p_next = 'delivered' and not has_final then
    return jsonb_build_object('error', 'needs-final-link');
  end if;
  if p_next = 'done' and t.delivered_at is null
     and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-delivery-or-reason');
  end if;
  if p_next = 'published' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;

  /* The hand to the next person, recorded on the move: the previous owner
     ends, the new one begins, and the event names both with the stage it
     happened at. Work level, because handing the work on is part of doing
     it; reassigning a task without moving it stays Manage. */
  if p_assignee is not null then
    select team_member_id into was_owner from public.ops_task_assignees
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    if p_assignee is distinct from was_owner then
      if not exists (select 1 from public.team_members where id = p_assignee and active) then
        return jsonb_build_object('error', 'no-such-person');
      end if;
      update public.ops_task_assignees set ended_at = now()
       where task_id = p_task and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, p_assignee, 'owner', m.id);
      perform public.ops_log(p_task, 'assignment_changed',
        jsonb_build_object('owner_id', was_owner),
        jsonb_build_object('owner_id', p_assignee),
        jsonb_build_object('handover', true, 'stage_key', p_next, 'from_stage_key', t.stage_key));
    end if;
  end if;

  if skipping then
    for sk in select * from public.ops_workflow_stages
               where workflow_id = t.workflow_id
                 and position > cur.position and position < nxt.position
                 and not (stage_group = any (side))
               order by position loop
      perform public.ops_log(p_task, 'stage_skipped',
        jsonb_build_object('stage_key', sk.key), jsonb_build_object('stage_key', p_next),
        jsonb_build_object('reason', btrim(p_skip_reason)));
    end loop;
  end if;

  /* The round: how many times this task has now entered this review or
     this revision, counted off its own history, so nothing is stored that
     a reverted move could leave wrong. */
  if nxt.is_review or nxt.stage_group = 'revision' then
    select count(*) + 1 into v_round from public.ops_task_events e
     where e.task_id = p_task and e.event_type = 'stage_changed'
       and e.to_value ->> 'stage_key' = p_next;
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
    /* Leaving Cancelled for a live stage is a reopening, and the stamp
       leaves with it, as completed_at does; left behind, the task went on
       reading cancelled at the stage it had been reopened to. */
    cancelled_at = case when p_next = 'cancelled' then coalesce(cancelled_at, now())
                        when not nxt.is_terminal then null
                        else cancelled_at end,
    blocked_at = case when p_next = 'blocked' then blocked_at else null end,
    blocked_category = case when p_next = 'blocked' then blocked_category else null end
  where id = p_task;

  /* The performance review brings its own checklist, the same five checks
     for a brand post and a KOC post, added once however often the task
     comes back to the stage. */
  if p_next = 'performance_review' then
    insert into public.ops_task_checklist_items (task_id, label, position, required)
    select p_task, x.label,
           coalesce((select max(c.position) from public.ops_task_checklist_items c
                      where c.task_id = p_task), 0) + x.n,
           true
      from (values (1, 'Reach and views checked'),
                   (2, 'Engagement checked (likes, comments, shares, saves)'),
                   (3, 'Comments checked for brand safety'),
                   (4, 'Leads or sales checked, where tracked'),
                   (5, 'Keep live or take down decided')) as x(n, label)
     where not exists (select 1 from public.ops_task_checklist_items c
                        where c.task_id = p_task and c.label = x.label);
  end if;

  /* A finished task is not being worked on, so every timer running on it
     stops with it, each filed as the stop it is. */
  if nxt.is_terminal then
    for ws in select * from public.ops_work_sessions
               where task_id = p_task and ended_at is null loop
      wmins := greatest(0, (extract(epoch from (now() - ws.started_at)) / 60)::integer);
      update public.ops_work_sessions set ended_at = now(), minutes = wmins where id = ws.id;
      perform public.ops_log(p_task, 'work_stopped', null,
        jsonb_build_object('session_id', ws.id, 'minutes', wmins),
        jsonb_build_object('note', 'Stopped when the task finished'));
    end loop;
  end if;

  perform public.ops_log(p_task, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', p_next),
    (case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end)
    || (case when skipping then jsonb_build_object('skip_reason', btrim(p_skip_reason)) else '{}'::jsonb end)
    || (case when v_round is not null then jsonb_build_object('round', v_round) else '{}'::jsonb end));
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
grant execute on function public.ops_transition_task(uuid, text, integer, text, uuid, text) to authenticated;

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
  if not public.ops_owner_may_move(p_task) then return jsonb_build_object('error', 'not-owner'); end if;

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

-- 4. The open tasks with no owner take their creator -------------------------
/* The tasks made before this with no owner take the person who made them,
   where that person is still on the team; nothing else is touched, so a
   second run finds nothing to do. */
insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
select t.id, t.created_by, 'owner', t.created_by
  from public.ops_tasks t
  join public.team_members tm on tm.id = t.created_by and tm.active
 where t.completed_at is null and t.cancelled_at is null
   and not exists (select 1 from public.ops_task_assignees a
                    where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null);

-- END OF THE OWNER MOVES THE TASK -------------------------------------------

-- ===========================================================================
-- A FORMAT PER TASK — Bulk add gives each task in the month its own
-- deliverable format, so a month can be mixed.
-- 2026-09-25. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   `ops_generate_month` takes an optional `formats` array in its payload,
--   one entry per task in the order the tasks are made (week 1's first, then
--   on), so a month of eight can be three Reels and five graphics (the user,
--   2026-09-25: "if 8 contents, not all 8 are same deliverables"). An array
--   whose length is not the count is refused with `formats-do-not-match`; a
--   blank entry takes the run's `deliverable_type` as before. The preview
--   answers each code with its format. The month rules, the spread over weeks,
--   the codes and the publish dates are unchanged.
--
-- ROLLBACK
--   Re-run section 1 of 2026-09-25-bulk-add-from-the-month.sql.
-- ===========================================================================

create or replace function public.ops_generate_month(
  p_payload jsonb, p_dry_run boolean default false, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  cid    uuid;
  per    text;
  n      integer;
  weeks  integer[];
  bad    text;
  eng    uuid;
  e      public.ops_engagements;
  k      integer;
  w      integer;
  seq    integer;
  seqs   integer;
  made   jsonb := '[]'::jsonb;
  one    jsonb;
  key    text;
  scope  text;
  first_day date;
  last_off integer;
  publish timestamptz;
  fmts   text[];
  fmt    text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  n := coalesce((p_payload ->> 'count')::integer, 0);
  scope := coalesce(p_payload ->> 'scope', 'client');
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  if n < 1 or n > 60 then return jsonb_build_object('error', 'bad-count'); end if;

  if (p_payload -> 'weeks') is not null and jsonb_typeof(p_payload -> 'weeks') = 'array' then
    select array_agg(x::integer) into weeks from jsonb_array_elements_text(p_payload -> 'weeks') x;
    if array_length(weeks, 1) < 1 or array_length(weeks, 1) > 5 then
      return jsonb_build_object('error', 'bad-weeks');
    end if;
    if (select sum(v) from unnest(weeks) v) <> n then return jsonb_build_object('error', 'weeks-do-not-add-up'); end if;
  else
    /* Evenly over four weeks, the extras early: task i (from 0) falls in
       week floor(i * 4 / n) + 1, so eight is two a week, six is 2, 1, 2, 1,
       and two is weeks 1 and 3 rather than both in week 4. */
    weeks := array[]::integer[];
    for w in 1 .. 4 loop
      weeks := weeks || (ceil(w * n / 4.0)::integer - ceil((w - 1) * n / 4.0)::integer);
    end loop;
  end if;

  /* A format for each task, in the order the tasks are made (week by week,
     then by number), because a month is usually mixed: three Reels and five
     graphics, not eight of one. A task given no format of its own takes the
     one for the run. */
  if (p_payload -> 'formats') is not null and jsonb_typeof(p_payload -> 'formats') = 'array' then
    select array_agg(nullif(btrim(x), '') order by i) into fmts
      from jsonb_array_elements_text(p_payload -> 'formats') with ordinality as a(x, i);
    if coalesce(array_length(fmts, 1), 0) <> n then return jsonb_build_object('error', 'formats-do-not-match'); end if;
  end if;

  /* The same press twice is one month, not two. */
  if not p_dry_run and p_idem is not null then
    if exists (select 1 from public.ops_tasks where idem_key = 'month:' || p_idem || ':1') then
      return jsonb_build_object('error', 'already-generated');
    end if;
  end if;

  first_day := (per || '-01')::date;
  last_off := ((first_day + interval '1 month')::date - first_day) - 1;
  /* One lock for the whole run, taken before anything is read: two operators
     generating the same month queue here, so the second sees the first's
     engagement and the first's numbers rather than racing both. */
  perform pg_advisory_xact_lock(hashtext('ops_code:' || cid::text || ':' || per));
  /* The month must already exist on the client's Work pane, still be open,
     and have its content meeting confirmed: a month nobody planned holds no
     tasks. Asked on the preview as well as the run, so the sheet cannot
     show codes for a month the run would refuse. */
  select * into e from public.ops_engagements
   where client_id = cid and period = per;
  if e.id is null then return jsonb_build_object('error', 'no-month'); end if;
  if (p_payload ->> 'engagement_id') is not null and (p_payload ->> 'engagement_id')::uuid <> e.id then
    return jsonb_build_object('error', 'no-month');
  end if;
  if e.status in ('completed', 'cancelled') then return jsonb_build_object('error', 'month-closed'); end if;
  if e.meeting_at is null and not e.meeting_na then
    return jsonb_build_object('error', 'month-not-confirmed');
  end if;
  eng := e.id;
  if not p_dry_run then
    update public.ops_engagements set planned_count = greatest(planned_count, n), updated_at = now()
     where id = eng and planned_count < n;
  end if;

  /* One lock for the whole month, so the preview and the run see the same
     next number and two operators generating for one client queue. */
  seq := public.ops_next_seq(cid, per) - 1;
  seqs := 0;
  for w in 1 .. array_length(weeks, 1) loop
    for k in 1 .. coalesce(weeks[w], 0) loop
      seq := seq + 1;
      seqs := seqs + 1;
      /* A tentative date inside the task's own week, the week's tasks
         spread across its seven days, so the calendar has somewhere to put
         each one; the content meeting fixes the real date. Never past the
         month's last day, which only a fifth week can reach. */
      fmt := coalesce(fmts[seqs], nullif(p_payload ->> 'deliverable_type', ''));
      publish := (first_day + least((w - 1) * 7 + ((k - 1) * 7) / weeks[w], last_off))::timestamptz;
      if p_dry_run then
        made := made || jsonb_build_object('code', public.ops_code_of(per, w, seq), 'week', w, 'seq', seq, 'format', fmt);
      else
        key := case when p_idem is null then null else 'month:' || p_idem || ':' || seqs::text end;
        one := public.ops_create_task(jsonb_build_object(
          'scope', scope, 'client_id', cid, 'engagement_id', eng,
          'task_type', coalesce(p_payload ->> 'task_type', 'engagement'),
          'deliverable_type', fmt,
          'priority_level', (p_payload ->> 'priority_level')::integer,
          'complexity', p_payload ->> 'complexity',
          'owner_id', (p_payload ->> 'owner_id')::uuid,
          'manager_id', (p_payload ->> 'manager_id')::uuid,
          'code_period', per, 'code_week', w,
          'publish_at', publish), key);
        if one ? 'error' then return one; end if;
        made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'week', w, 'seq', seq, 'format', fmt);
      end if;
    end loop;
  end loop;
  return jsonb_build_object('engagement_id', eng, 'period', per, 'count', seqs,
                            'tasks', made, 'dry_run', p_dry_run);
end $$;
grant execute on function public.ops_generate_month(jsonb, boolean, text) to authenticated;

-- END OF A FORMAT PER TASK ------------------------------------------------

-- ===========================================================================
-- EVERY TASK IN A CONFIRMED MONTH — a client's deliverable, made one at a
-- time or by a repeat rule, goes only into a month the team has planned; and
-- the client portal reads the month's content meetings.
-- 2026-09-25. Safe to run twice. Rollback at the foot. Run after
-- 2026-09-25-a-format-per-task.sql. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   1. `ops_create_task` refuses a client's content deliverable for a month
--      that does not exist (`no-month`), is completed or cancelled
--      (`month-closed`), or has no content meeting set or marked not
--      applicable (`month-not-confirmed`), and joins the task to that month.
--      These are Bulk add's refusals, so New task, From template and
--      Duplicate now answer the same way (the user, 2026-09-25: "Go").
--      An everyday task, an internal task and a lead's task are unchanged.
--
--   2. `ops_generate_recurring` holds a client's repeat rule until the
--      client's month is confirmed, counts it as `held`, and makes nothing
--      for it; a later run makes the tasks. Internal rules are unchanged.
--
--   3. `portal_meetings(client)` lets a signed-in client contact read the
--      client's content meetings (month, date and time, length, channel, and
--      the link while the meeting is ahead). Never a task, a check or a note.
--
-- ROLLBACK
--   Re-run the ops_create_task definition in
--   2026-09-25-the-owner-moves-the-task.sql and the ops_generate_recurring
--   definition in 2026-09-23-operations-phase4.sql, then
--   drop function if exists public.portal_meetings(uuid);
-- ===========================================================================

-- 1. A client's deliverable goes into a confirmed month ----------------------
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
  scope text;
  ttype text;
  cid   uuid;
  bad   text;
  descr text;
  period text;
  cper  text;
  week  integer;
  seq   integer;
  code  text;
  title text;
  first_stage text;
  wkey  text;
  base  timestamptz;
  eng   public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  scope := coalesce(p_payload ->> 'scope', 'client');
  cid := (p_payload ->> 'client_id')::uuid;
  /* A task linked to a month's engagement takes the client from it: the
     person names the month once and the client comes with it. */
  if (p_payload ->> 'engagement_id') is not null then
    select * into eng from public.ops_engagements where id = (p_payload ->> 'engagement_id')::uuid;
    if eng.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if cid is null then cid := eng.client_id; scope := 'client'; end if;
  end if;
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;

  ttype := coalesce(p_payload ->> 'task_type', 'adhoc');
  if ttype not in ('engagement', 'adhoc', 'goodwill', 'special') then
    return jsonb_build_object('error', 'bad-task-type');
  end if;

  /* The description is the team's to edit and may start blank on a task that
     carries a code; a task with no code is named by its description alone, so
     there it is required. `title` is accepted from older callers as the
     description. */
  descr := nullif(btrim(coalesce(p_payload ->> 'content_desc', p_payload ->> 'title', '')), '');

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
    descr := coalesce(descr, nullif(btrim(coalesce(tpl.default_title, tpl.name, '')), ''));
  end if;
  /* New work goes on the content workflow. A caller may still name another
     (a template's own, or one somebody adds), and a task already on a retired
     workflow is never moved. */
  wf := coalesce((p_payload ->> 'workflow_id')::uuid,
                 (select id from public.ops_workflows where key = p_payload ->> 'workflow_key' and active),
                 tpl.workflow_id,
                 (select id from public.ops_workflows where key = 'content' and active),
                 (select id from public.ops_workflows where active order by created_at limit 1));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  select key into first_stage from public.ops_workflow_stages
   where workflow_id = wf order by position limit 1;
  select key into wkey from public.ops_workflows where id = wf;

  publish := (p_payload ->> 'publish_at')::timestamptz;
  fd := coalesce((p_payload ->> 'first_draft_due_at')::timestamptz,
        case when publish is not null and tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.first_draft_offset_business_days)
             when tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.first_draft_offset_business_days)
        end);
  /* A template's due date is a number of calendar days from the day the
     work is made for (the base date the caller names, else today). */
  base := coalesce((p_payload ->> 'base_date')::timestamptz, now());
  fin := coalesce((p_payload ->> 'final_due_at')::timestamptz,
        case when tpl.due_offset_days is not null
             then date_trunc('day', base) + make_interval(days => tpl.due_offset_days)
             when publish is not null and tpl.final_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.final_offset_business_days)
             when tpl.final_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.final_offset_business_days)
        end);
  if fd is not null and fin is not null and not public.ops_due_order_ok(fd, fin) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  /* The name. The month is the content month (the scheduled publish date's,
     else the one the caller names, else this one); the week is the planned
     publishing week, chosen by the caller and prefilled by the page from the
     date; the running number is the client's for the month. Generated once,
     under the lock, and never rewritten: a publish date that moves later
     leaves the name as it was, because the name is a label and not a fact
     about the date. */
  if wkey = 'task' then
    /* An everyday task is named by what it is. It carries no content code,
       because the code numbers a client's deliverables for the month and a
       task is not one; the content month is kept where it is known, so the
       task can be grouped with the month it belongs to. */
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
    period := coalesce(nullif(p_payload ->> 'code_period', ''), eng.period);
  elsif scope <> 'internal' then
    period := coalesce(nullif(p_payload ->> 'code_period', ''),
                       case when publish is not null then to_char(publish, 'YYYY-MM') end,
                       to_char(now(), 'YYYY-MM'));
    if period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
    /* A client's deliverable belongs to a month the team has planned: one
       that exists, is still open, and has its content meeting set or marked
       not applicable. The same three refusals Bulk add gives. */
    if scope = 'client' then
      cper := period;
      if eng.id is null or eng.period <> cper then
        select * into eng from public.ops_engagements x where x.client_id = cid and x.period = cper;
      end if;
      if eng.id is null then return jsonb_build_object('error', 'no-month'); end if;
      if eng.status in ('completed', 'cancelled') then return jsonb_build_object('error', 'month-closed'); end if;
      if eng.meeting_at is null and not eng.meeting_na then
        return jsonb_build_object('error', 'month-not-confirmed');
      end if;
    end if;
    week := coalesce((p_payload ->> 'code_week')::integer,
                     case when publish is not null
                          then least(5, ((extract(day from publish)::integer - 1) / 7) + 1) end,
                     1);
    if week < 1 or week > 5 then return jsonb_build_object('error', 'bad-week'); end if;
    seq := public.ops_next_seq(cid, period);
    code := public.ops_code_of(period, week, seq);
    title := btrim(code || ' ' || coalesce(descr, ''));
  else
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
  end if;

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality,
    task_type, code, code_period, code_week, code_seq, content_desc,
    engagement_id, manager_id, parent_task_id)
  values (
    scope, cid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, coalesce(first_stage, 'intake'),
    title, p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'other'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'),
    ttype, code, period, week, seq, descr,
    coalesce(eng.id, (p_payload ->> 'engagement_id')::uuid),
    coalesce((p_payload ->> 'manager_id')::uuid, m.id),
    (p_payload ->> 'parent_task_id')::uuid)
  returning id into tid;

  /* Every task has an owner from the moment it exists: the one named, the
     template's, or else whoever made it. */
  owner := coalesce((p_payload ->> 'owner_id')::uuid, tpl.default_owner_id, m.id);
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

  -- The template's checklist, or the one the caller hands over (a duplicate
  -- carries its source's labels, unticked), in the order stated.
  for item in select * from jsonb_array_elements(
      coalesce(p_payload -> 'checklist', tpl.checklist, '[]'::jsonb)) loop
    i := i + 1;
    insert into public.ops_task_checklist_items (task_id, label, position)
    values (tid, item #>> '{}', i);
  end loop;

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
    jsonb_build_object('title', title, 'code', code,
                       'first_draft_due_at', fd, 'final_due_at', fin),
    case when (p_payload ->> 'duplicated_from') is null then '{}'::jsonb
         else jsonb_build_object('duplicated_from', p_payload ->> 'duplicated_from') end);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

-- 2. A client's repeats wait for the month --------------------------------
create or replace function public.ops_generate_recurring(
  p_period text, p_rules uuid[] default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  r     public.ops_recurring_rules;
  src   public.ops_tasks;
  made  integer := 0;
  skip  integer := 0;
  key   text;
  first_day date;
  last_day date;
  anchor date;
  d     date;
  stepd integer;
  one   jsonb;
  wk    integer;
  held  integer := 0;
  ccl   uuid;
  mon   public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  first_day := (p_period || '-01')::date;
  last_day := (first_day + interval '1 month' - interval '1 day')::date;

  for r in select * from public.ops_recurring_rules
            where active and (p_rules is null or id = any (p_rules))
              and (source_task_id is null or public.ops_may_see_task(source_task_id)) loop
    if r.source_task_id is not null then
      select * into src from public.ops_tasks where id = r.source_task_id;
    else
      src := null;
    end if;

    /* A client's repeats wait for the client's month: one that exists, is
       open and has its content meeting set or marked not applicable. Until
       then the rule is held and counted, and a later run makes them. */
    ccl := case when src.id is not null then case when src.scope = 'client' then src.client_id end
                else r.client_id end;
    mon := null;
    if ccl is not null then
      select * into mon from public.ops_engagements x where x.client_id = ccl and x.period = p_period;
      if mon.id is null or mon.status in ('completed', 'cancelled')
         or (mon.meeting_at is null and not mon.meeting_na) then
        held := held + 1;
        continue;
      end if;
    end if;

    /* The dates this rule falls on inside the month. */
    if r.frequency = 'monthly' then
      d := first_day + (least(coalesce(r.day_of_month,
              case when src.publish_at is not null then extract(day from src.publish_at)::integer else 1 end),
              extract(day from last_day)::integer) - 1);
      stepd := null;
    else
      stepd := case when r.frequency = 'weekly' then 7 else greatest(1, coalesce(r.interval_days, 7)) end;
      anchor := coalesce(src.publish_at::date, r.created_at::date, first_day);
      if anchor > first_day then d := anchor;
      else d := anchor + ((((first_day - anchor) + stepd - 1) / stepd) * stepd); end if;
    end if;

    while d is not null and d <= last_day loop
      if d >= first_day
         and (r.ends_on is null or d <= r.ends_on)
         and (r.max_count is null or r.generated_count < r.max_count) then
        key := 'recur:' || r.id::text || ':' || to_char(d, 'YYYY-MM-DD');
        if exists (select 1 from public.ops_tasks where idem_key = key) then
          skip := skip + 1;
        else
          wk := coalesce(r.code_week, least(5, ((extract(day from d)::integer - 1) / 7) + 1));
          if src.id is not null then
            one := public.ops_duplicate_task(src.id, jsonb_build_object(
              'keep_desc', true, 'copy_dates', false, 'copy_assignees', true,
              'publish_at', d::timestamptz, 'code_period', p_period, 'code_week', wk,
              'engagement_id', mon.id), key);
          else
            one := public.ops_create_task(jsonb_build_object(
              'scope', case when r.client_id is null then 'internal' else 'client' end,
              'client_id', r.client_id, 'template_id', r.template_id,
              'title', r.name || ' — ' || p_period, 'content_desc', r.name,
              'owner_id', r.owner_id, 'publish_at', d::timestamptz,
              'code_period', p_period, 'code_week', wk, 'engagement_id', mon.id), key);
          end if;
          if one ? 'error' then return one || jsonb_build_object('rule', r.id); end if;
          made := made + 1;
          update public.ops_recurring_rules
             set generated_count = generated_count + 1, last_generated_period = p_period, updated_at = now()
           where id = r.id;
          r.generated_count := r.generated_count + 1;
        end if;
      end if;
      exit when stepd is null;
      d := d + stepd;
    end loop;
  end loop;
  return jsonb_build_object('created', made, 'skipped', skip, 'held', held, 'period', p_period);
end $$;
grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;

-- 3. The client reads the meeting schedule ---------------------------------
create or replace function public.portal_meetings(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  /* The content meetings the team has put in the diary, from three months
     back. Nothing about the month's tasks, checks or status beyond this: a
     client reads when we meet, never how the work inside the month is going.
     The link is sent only while the meeting is still ahead. */
  return jsonb_build_object('meetings', coalesce((
    select jsonb_agg(jsonb_build_object(
             'period', e.period, 'at', e.meeting_at, 'minutes', coalesce(e.meeting_minutes, 30),
             'channel', e.meeting_channel,
             'link', case when e.meeting_at + make_interval(mins => coalesce(e.meeting_minutes, 30)) > now()
                          then e.meeting_link end)
           order by e.meeting_at desc)
      from public.ops_engagements e
     where e.client_id = p_client
       and e.meeting_at is not null
       and not coalesce(e.meeting_na, false)
       and e.status <> 'cancelled'
       and e.meeting_at >= date_trunc('month', now()) - interval '3 months'), '[]'::jsonb));
end $$;
revoke all on function public.portal_meetings(uuid) from public, anon;
grant execute on function public.portal_meetings(uuid) to authenticated;
-- END OF EVERY TASK IN A CONFIRMED MONTH ------------------------------------
-- ===========================================================================
-- THE CAMPAIGN CLOCK — when a campaign moved, and when each booking finished.
-- 2026-09-26. Safe to run twice. Rollback at the foot. Mirrored in
-- supabase/schema.sql under the same banner.
--
-- Asked for by the user: an internal timing under Key dates, from created
-- through confirmed and in production to completed, each stage's hours. The
-- page reads it; nothing client-facing sends it.
--
--   1. `campaigns.state_log`: every state the campaign has been in, with when,
--      stamped by a trigger on the move, never by a page. A new campaign
--      starts with its first state at its creation time. Campaigns that
--      existed before this have no log of their past moves: the page omits
--      a stage it cannot date rather than guessing.
--
--   2. `campaign_options.completed_at`: stamped when a booking reaches
--      Completed and cleared if it is reverted, so a campaign is complete at
--      the moment its last booking was.
--
-- ROLLBACK
--   drop trigger if exists campaigns_state_clock on public.campaigns;
--   drop function if exists public.campaigns_state_clock();
--   drop trigger if exists campaign_options_done_clock on public.campaign_options;
--   drop function if exists public.campaign_options_done_clock();
--   alter table public.campaigns drop column if exists state_log;
--   alter table public.campaign_options drop column if exists completed_at;
-- ===========================================================================

alter table public.campaigns add column if not exists state_log jsonb not null default '[]'::jsonb;

create or replace function public.campaigns_state_clock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.state_log is null or jsonb_array_length(new.state_log) = 0 then
      new.state_log := jsonb_build_array(
        jsonb_build_object('state', new.state, 'at', coalesce(new.created_at, now())));
    end if;
    return new;
  end if;
  if new.state is distinct from old.state then
    new.state_log := coalesce(old.state_log, '[]'::jsonb) ||
      jsonb_build_array(jsonb_build_object('state', new.state, 'at', now()));
  end if;
  return new;
end $$;

drop trigger if exists campaigns_state_clock on public.campaigns;
create trigger campaigns_state_clock before insert or update on public.campaigns
  for each row execute function public.campaigns_state_clock();

alter table public.campaign_options add column if not exists completed_at timestamptz;

create or replace function public.campaign_options_done_clock()
returns trigger
language plpgsql
as $$
begin
  if new.state = 'completed' then
    if tg_op = 'INSERT' or old.state is distinct from 'completed' then
      new.completed_at := now();
    end if;
  else
    new.completed_at := null;
  end if;
  return new;
end $$;

drop trigger if exists campaign_options_done_clock on public.campaign_options;
create trigger campaign_options_done_clock before insert or update on public.campaign_options
  for each row execute function public.campaign_options_done_clock();
-- END OF THE CAMPAIGN CLOCK -------------------------------------------------

-- ===========================================================================
-- DEPARTMENT AND ROLE ON THE TEAM — who a colleague is is kept where the
-- team keeps them, and Performance reads it from there.
-- 2026-09-26. Safe to run twice. Run after 2026-09-24-performance-code-always.sql.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED. The user, on 2026-09-26: department and role are changed on
-- the Team page for each member and carried over to Performance. They were
-- kept on perf_people behind both performance locks, so a department was
-- typed into the designation on the Team page ("Creative, Production
-- Executive") and set again on the review sheet. `team_members` gains
-- `department` and `role_family` (the role standard); perf_json and
-- perf_month read them from the team row, and perf_profile_set keeps only
-- the two review settings (runs client ads, reviewed every month). The Team
-- page writes the columns under the policy that already governs that row.
--
-- THE DATA, ONCE. (1) Each colleague's department and role standard move
-- from perf_people to the team row where the team row has none, and are
-- cleared on perf_people, so a later run cannot put back a value somebody
-- has since cleared on the Team page. (2) A designation typed as a
-- department, a comma and a position ("Creative, Production Executive")
-- becomes the department Creative and the position Production Executive,
-- where the row has no department yet or names the same one; any other
-- designation is left as typed. The last statement lists every colleague
-- holding a department or a role afterwards.
--
-- ROLLBACK
--   update public.perf_people pp set department = t.department, role_family = t.role_family
--     from public.team_members t where t.id = pp.team_member_id;
--   then re-run perf_json, perf_month and perf_profile_set from
--   2026-09-24-performance-reviews.sql. The columns on team_members may stay.
--   A split designation is not put back by itself: the list at the foot of
--   the first run names who had one.
-- ===========================================================================

alter table public.team_members add column if not exists department text;
alter table public.team_members add column if not exists role_family text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'team_members_department_check') then
    alter table public.team_members add constraint team_members_department_check
      check (department in ('creative', 'marketing'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'team_members_role_family_check') then
    alter table public.team_members add constraint team_members_role_family_check
      check (role_family in ('visual', 'video', 'planner', 'account'));
  end if;
end $$;

/* (1) What the review sheet held moves to the team row, once. */
update public.team_members t
   set department = coalesce(t.department, pp.department),
       role_family = coalesce(t.role_family, pp.role_family)
  from public.perf_people pp
 where pp.team_member_id = t.id
   and (pp.department is not null or pp.role_family is not null);
update public.perf_people set department = null, role_family = null
 where department is not null or role_family is not null;

/* (2) "Creative, Production Executive" is a department and a position. */
update public.team_members t
   set department = lower(s.parts[1]), designation = btrim(s.parts[2])
  from (select id, regexp_match(designation, '^\s*(creative|marketing)\s*,\s*(\S.*)$', 'i') as parts
          from public.team_members) s
 where s.id = t.id and s.parts is not null
   and (t.department is null or t.department = lower(s.parts[1]));

/* Performance reads the team row. */
create or replace function public.perf_json(r public.perf_reviews, p_full boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.team_members; pp public.perf_people; out jsonb;
begin
  select * into m from public.team_members where id = r.team_member_id;
  select * into pp from public.perf_people where team_member_id = r.team_member_id;
  out := jsonb_build_object(
    'id', r.id, 'team_member_id', r.team_member_id, 'period', r.period,
    'month', public.perf_month_word(r.period), 'status', r.status,
    'member', jsonb_build_object('name', m.name, 'staff_code', m.staff_code,
      'designation', m.designation, 'department', m.department,
      'role_family', m.role_family, 'runs_ads', coalesce(pp.runs_ads, false)),
    'scores', jsonb_build_object('output', r.s_output, 'accuracy', r.s_accuracy,
      'delivery', r.s_delivery, 'client', r.s_client, 'comms', r.s_comms,
      'initiative', r.s_initiative),
    'rates', jsonb_build_object('posting', r.r_posting, 'timeline', r.r_timeline,
      'satisfaction', r.r_satisfaction, 'pacing', r.r_pacing, 'sla', r.r_sla),
    'notes', r.notes, 'improvement', r.improvement, 'review_by', r.review_by,
    'reward_step', r.reward_step, 'serial', r.serial,
    'reviewer', (select name from public.team_members where id = r.reviewer_id),
    'released_at', r.released_at, 'dispute_until', r.dispute_until,
    'dispute_open', r.status = 'released' and r.dispute_until > now()
                    and not exists (select 1 from public.perf_disputes d
                                     where d.review_id = r.id and d.version = r.version),
    'acknowledged_at', r.acknowledged_at, 'finalised_at', r.finalised_at,
    'finalised_by', (select name from public.team_members where id = r.finalised_by),
    'version', r.version, 'rev', r.rev,
    'result', public.perf_calc(r),
    'breaches', public.perf_breaches_json(r.team_member_id, r.period, false),
    'disputes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', d.id, 'item', d.item, 'breach_id', d.breach_id, 'reason', d.reason,
        'breach_what', (select b.what from public.perf_breaches b where b.id = d.breach_id),
        'raised_at', d.raised_at, 'decision', d.decision, 'response', d.response,
        'before_value', d.before_value, 'after_value', d.after_value,
        'decided_by', (select name from public.team_members where id = d.decided_by),
        'decided_at', d.decided_at) order by d.raised_at)
        from public.perf_disputes d where d.review_id = r.id and d.version = r.version), '[]'::jsonb));
  if p_full then
    out := out || jsonb_build_object(
      'voided', (select coalesce(jsonb_agg(x), '[]'::jsonb)
                   from jsonb_array_elements(public.perf_breaches_json(r.team_member_id, r.period, true)) x
                  where x ->> 'voided_at' is not null),
      'ops', public.perf_ops_rate(r.team_member_id, r.period),
      'events', coalesce((select jsonb_agg(jsonb_build_object(
          'kind', e.kind, 'detail', e.detail, 'at', e.created_at,
          'by', coalesce((select name from public.team_members where id = e.actor_id), e.actor_email))
          order by e.created_at desc)
          from public.perf_events e where e.review_id = r.id), '[]'::jsonb));
  end if;
  return out;
end $$;

create or replace function public.perf_month(p_token text, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  return jsonb_build_object(
    'period', p, 'month', public.perf_month_word(p),
    'people', coalesce((select jsonb_agg(x order by x ->> 'name') from (
      select jsonb_build_object(
        'team_member_id', t.id, 'name', t.name, 'staff_code', t.staff_code,
        'designation', t.designation,
        'department', t.department, 'role_family', t.role_family,
        'runs_ads', coalesce(pp.runs_ads, false),
        'reviewed', public.perf_reviewed(t.id),
        'breaches', (select count(*) from public.perf_breaches b
                      where b.team_member_id = t.id and b.period = p and b.voided_at is null),
        'review', case when r.id is null then null else jsonb_build_object(
          'id', r.id, 'status', r.status, 'result', public.perf_calc(r),
          'open_disputes', (select count(*) from public.perf_disputes d
                             where d.review_id = r.id and d.version = r.version and d.decision is null),
          'dispute_until', r.dispute_until) end) as x
        from public.team_members t
        left join public.perf_people pp on pp.team_member_id = t.id
        left join public.perf_reviews r on r.team_member_id = t.id and r.period = p
       where t.active and t.id <> m.id) q), '[]'::jsonb));
end $$;

create or replace function public.perf_profile_set(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; kept jsonb;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  /* Department and role are the Team page's now. A page from before this
     change may still send them; they are left out rather than refused, so
     its two ticks still save. */
  kept := coalesce(p_payload, '{}'::jsonb) - 'department' - 'role_family';
  insert into public.perf_people (team_member_id, runs_ads, reviewed)
  values (p_member, coalesce((kept ->> 'runs_ads')::boolean, false),
          case when kept ? 'reviewed' then (kept ->> 'reviewed')::boolean end)
  on conflict (team_member_id) do update set
    runs_ads = case when kept ? 'runs_ads' then coalesce((kept ->> 'runs_ads')::boolean, false) else perf_people.runs_ads end,
    reviewed = case when kept ? 'reviewed' then (kept ->> 'reviewed')::boolean else perf_people.reviewed end,
    updated_at = now();
  perform public.perf_log(null, p_member, 'profile', kept);
  return jsonb_build_object('ok', true);
end $$;

select name, department, role_family, designation from public.team_members
 where department is not null or role_family is not null order by name;

-- END OF DEPARTMENT AND ROLE ON THE TEAM -------------------------------------
