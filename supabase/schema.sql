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
alter table public.clients add column if not exists social_ig         text;
alter table public.clients add column if not exists social_fb         text;
alter table public.clients add column if not exists social_tiktok     text;
alter table public.clients add column if not exists social_xhs        text;
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

-- One row per profile link. A creator may hold several: RedNote, Instagram,
-- TikTok, Facebook, or two accounts on one platform.
--
-- `handle` is the canonical identity pulled out of the URL: the id after
-- /user/profile/ on RedNote, the handle elsewhere. A xhslink.com short link
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
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into cl from clients where id = c.client_id;

  if c.passcode is not null and c.passcode <> '' then
    if p_passcode is null or p_passcode <> c.passcode then
      return jsonb_build_object('error', 'passcode', 'client', cl.name);
    end if;
  end if;

  return jsonb_build_object(
    'campaign', jsonb_build_object(
      'title', c.title, 'title_zh', c.title_zh,
      'purpose', c.purpose, 'purpose_zh', c.purpose_zh, 'slots', c.slots,
      'deadline', c.deadline, 'state', c.state, 'deliverable', c.deliverable,
      'push_format', c.push_format, 'brief', c.brief, 'brief_zh', c.brief_zh,
      'invoice_no', c.invoice_no, 'invoice_url', c.invoice_url),
    -- Currency and tax travel with the campaign, because the client's page
    -- prints both and must not assume Malaysia.
    'client', jsonb_build_object('name', cl.name, 'logo_url', cl.logo_url,
      'market', coalesce(cl.market, 'MY'), 'sst_applies', coalesce(cl.sst_applies, true)),
    'options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'name', cr.name,
        'rate', o.rate, 'platforms', o.platforms, 'state', o.state,
        'is_replacement', o.is_replacement, 'added_at', o.added_at,
        -- Production. Present once a creator is locked; null before that, so
        -- the page can tell "not started" from "nothing to say".
        'visit_date', o.visit_date, 'visit_time', o.visit_time,
        'visit_location', o.visit_location, 'visit_pic', o.visit_pic,
        'visit_pic_phone', o.visit_pic_phone, 'tracking_no', o.tracking_no,
        'draft_url', o.draft_url, 'revision_round', o.revision_round,
        'planned_publish', o.planned_publish,
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
          from option_posts pp where pp.option_id = o.id), '[]'::jsonb))
        order by o.position, o.added_at)
      from campaign_options o
      join creators cr on cr.id = o.creator_id
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
       set state = 'changes', revision_round = greatest(n, 1) + 1
     where id = p_option;
  end if;

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
  if coalesce(array_length(p_backup, 1), 0) > 0 then
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
create unique index if not exists team_members_email_idx
  on public.team_members(lower(email)) where email is not null;

-- Everyone who can already sign in carries over as Account. Nobody is locked
-- out by this file; someone is only ever narrowed from the Team page.
insert into public.team_members (name, email, role)
  select coalesce(u.raw_user_meta_data ->> 'name', split_part(u.email, '@', 1)), u.email, 'account'
  from auth.users u
  where u.email is not null
    and not exists (select 1 from public.team_members t where lower(t.email) = lower(u.email));

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

-- One predicate for every policy: may this person do this? Admin may do all.
create or replace function public.allowed(flag text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
    where lower(email) = lower(auth.jwt() ->> 'email') and active limit 1;
  if t.id is null then return false; end if;
  if t.role = 'admin' then return true; end if;
  return coalesce(case flag
    when 'clients'   then t.can_clients
    when 'review'    then t.can_review
    when 'campaigns' then t.can_campaigns
    when 'links'     then t.can_links
    when 'activity'  then t.can_activity
    when 'billing'   then t.can_billing
    when 'remove'    then t.can_remove
    when 'admin'     then false
  end, false);
end $$;
grant execute on function public.allowed(text) to authenticated;

-- The section tables, each gated by its section, with removal gated twice.
-- Policies are additive, so the old blanket ones have to go first.
do $$
declare
  spec text[][] := array[
    ['client_contacts',        'clients'],
    ['client_touches',         'clients'],
    ['batches',                'review'],
    ['posts',                  'review'],
    ['reviews',                'review'],
    ['drive_assets',           'review'],
    ['links',                  'links'],
    ['link_qrs',               'links'],
    ['creators',               'campaigns'],
    ['creator_profiles',       'campaigns'],
    ['campaigns',              'campaigns'],
    ['campaign_options',       'campaigns'],
    ['campaign_confirmations', 'campaigns'],
    ['option_posts',           'campaigns'],
    ['option_reviews',         'campaigns']
  ];
  i int; t text; f text; p record;
begin
  for i in 1 .. array_length(spec, 1) loop
    t := spec[i][1]; f := spec[i][2];
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy if exists %I on public.%I', p.policyname, t);
    end loop;
    execute format('create policy %I on public.%I for select to authenticated using (public.allowed(%L))', t || '_read', t, f);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.allowed(%L))', t || '_write', t, f);
    execute format('create policy %I on public.%I for update to authenticated using (public.allowed(%L)) with check (public.allowed(%L))', t || '_edit', t, f, f);
    execute format('create policy %I on public.%I for delete to authenticated using (public.allowed(%L) and public.allowed(''remove''))', t || '_del', t, f);
  end loop;
end $$;

-- Clients are read by every section that hangs off them, and written by the
-- CRM and by Content Review (handles, logo, passcode, the review flag).
drop policy if exists team_all       on public.clients;
drop policy if exists clients_read   on public.clients;
drop policy if exists clients_write  on public.clients;
drop policy if exists clients_update on public.clients;
create policy clients_read on public.clients for select to authenticated
  using (public.allowed('clients') or public.allowed('review') or public.allowed('campaigns'));
create policy clients_write on public.clients for insert to authenticated
  with check (public.allowed('clients'));
create policy clients_update on public.clients for update to authenticated
  using (public.allowed('clients') or public.allowed('review'))
  with check (public.allowed('clients') or public.allowed('review'));

-- The activity record is written by anyone and read by those allowed to.
-- activity_viewers is no longer consulted; the switch lives on the team row.
drop policy if exists activity_read on public.activity_log;
create policy activity_read on public.activity_log
  for select to authenticated using (public.allowed('activity'));

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
  using (public.allowed('admin'))
  with check (public.allowed('admin'));

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
  position      integer not null default 0,
  created_at    timestamptz not null default now()
);
alter table public.team_roles enable row level security;
insert into public.team_roles
  (slug, name, is_admin, can_clients, can_review, can_campaigns, can_links, can_activity, can_billing, can_remove, position)
values
  ('admin',   'Admin',   true,  true, true,  true,  true,  true,  true, true,  0),
  ('account', 'Account', false, true, true,  true,  true,  false, true, false, 1),
  ('sales',   'Sales',   false, true, false, false, false, false, true, false, 2)
on conflict (slug) do nothing;

alter table public.team_members add column if not exists is_admin boolean not null default false;
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
  new.can_remove    := r.can_remove;
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

-- Admin is a property of the group now, not the word.
create or replace function public.allowed(flag text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
    where lower(email) = lower(auth.jwt() ->> 'email') and active limit 1;
  if t.id is null then return false; end if;
  if t.is_admin then return true; end if;
  return coalesce(case flag
    when 'clients'   then t.can_clients
    when 'review'    then t.can_review
    when 'campaigns' then t.can_campaigns
    when 'links'     then t.can_links
    when 'activity'  then t.can_activity
    when 'billing'   then t.can_billing
    when 'remove'    then t.can_remove
    when 'admin'     then false
  end, false);
end $$;

-- Re-stamp every member from their group once, so rows written before this
-- block carry the right switches.
update public.team_members set role = role;

drop policy if exists roles_read  on public.team_roles;
drop policy if exists roles_admin on public.team_roles;
create policy roles_read  on public.team_roles for select to authenticated using (true);
create policy roles_admin on public.team_roles for all to authenticated
  using (public.allowed('admin')) with check (public.allowed('admin'));

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
  using (public.allowed('admin')) with check (public.allowed('admin'));

insert into public.services (slug, category, name, rate, unit, position) values
  ('static-graphic',   'Content',            'Static graphic',                       360,  'Per post',                          10),
  ('gif',              'Content',            'GIF',                                  450,  'Per GIF',                           11),
  ('carousel',         'Content',            'Carousel',                             600,  'Per set',                           12),
  ('reels-30',         'Content',            'Reels, up to 30 seconds',              550,  'Per video',                         13),
  ('reels-60',         'Content',            'Reels, up to 60 seconds',              800,  'Per video',                         14),
  ('short-video-120',  'Content',            'Short video, up to 120 seconds',       1200, 'Per video',                         15),
  ('mgmt-meta',        'Account management', 'Meta (Facebook and Instagram)',        500,  'Per post',                          20),
  ('mgmt-tiktok',      'Account management', 'TikTok / Douyin',                      500,  'Per GIF',                           21),
  ('mgmt-xhs',         'Account management', 'RedNote (XHS)',                        600,  'Per set',                           22),
  ('mgmt-linkedin',    'Account management', 'LinkedIn',                             700,  'Per video, up to 30 seconds',       23),
  ('verify-meta',      'Verification',       'Meta Verified (blue tick)',            200,  'Per account, plus Meta subscription', 30),
  ('verify-xhs',       'Verification',       'RedNote Professional (blue tick)',     1299, 'Per account, RM 450 platform fee included', 31),
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
  using (public.allowed('clients')) with check (public.allowed('clients'));

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
  using (public.allowed('clients')) with check (public.allowed('clients'));

-- A line can run for a term: qty × rate × months, from a start month.
alter table public.client_services add column if not exists tenure   int  not null default 1;
alter table public.client_services add column if not exists start_on text;   -- YYYY-MM-DD (older lines YYYY-MM)

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

-- Deleting a client is the team's alone, whatever the code says.
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
  using (public.allowed('clients')) with check (public.allowed('clients'));
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
      select jsonb_agg(jsonb_build_object('id', s.id, 'label', s.label, 'unit', s.unit, 'qty', s.qty,
        'rate', s.rate, 'tenure', s.tenure, 'start_on', s.start_on, 'state', s.state, 'note', s.note)
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
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.get_portal(uuid) from public;
revoke all on function public.portal_request(uuid, text, uuid, text) from public;
revoke all on function public.portal_withdraw(uuid, boolean) from public;
grant execute on function public.get_portal(uuid) to authenticated;
grant execute on function public.portal_request(uuid, text, uuid, text) to authenticated;
grant execute on function public.portal_withdraw(uuid, boolean) to authenticated;
