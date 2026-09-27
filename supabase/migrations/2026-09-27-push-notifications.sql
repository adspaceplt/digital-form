-- ===========================================================================
-- PUSH NOTIFICATIONS — the team, a client on the creator selection page and
-- a creator on their own page are told on their phone when something moves.
-- 2026-09-27. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-09-27: "Mobile notifications for all,
-- client-facing esp on the creator selection; creator portal once it
-- receives updates (like requested changes / ready to post etc.); admin
-- internal team mostly on those that is now active notifications alr"):
--  1. A device turns notifications on from the page it is on, and follows
--     what that page belongs to, proved as the page proves it: the signed-in
--     colleague (the console), a campaign (the client's selection page, by
--     its token) or a creator (their page, by their code). A device follows
--     one colleague and one creator at most, and any number of campaigns.
--     Only a real push service's address is accepted, so the sender never
--     posts anywhere else.
--  2. What to send is queued in `push_outbox` by triggers, only where a
--     device follows it: a colleague's bell notification (`ops_notifications`)
--     as it is written; a draft released to the client and a post going live;
--     a creator booked, sent back for changes, and cleared to post. Only a
--     forward move is told. The client's words carry the creator and the
--     campaign; the creator's carry the campaign.
--  3. The queue is sent by the `push-send` edge function, which `pg_net`
--     wakes after the write commits. Where `pg_net` is not installed the
--     queue waits and nothing else is affected: a notification never fails
--     the write that caused it.
--  4. The sender's keys (VAPID) are made by `push-send` on its first run and
--     kept in `app_secrets`; only the public half ever leaves the database
--     (`push_public_key`). Nothing is typed or pasted by anybody.
--  5. The tables have row level security and no policy; every read and
--     write goes through these functions. The queue and the keys answer to
--     the service role alone.
--
-- ROLLBACK
--   drop trigger if exists ops_notifications_push on public.ops_notifications;
--   drop trigger if exists campaign_options_push on public.campaign_options;
--   drop function if exists public.ops_notifications_push(), public.campaign_options_push(),
--     public.push_queue(text, uuid, jsonb, text, text), public.push_kick(),
--     public.push_endpoint_ok(text), public.push_target(text, text),
--     public.push_subscribe(text, text, text, text, text, text),
--     public.push_unsubscribe(text, text, text), public.push_status(text, text, text),
--     public.push_public_key(), public.push_keys(), public.push_set_keys(text, text),
--     public.push_claim(integer), public.push_done(uuid, integer, integer, uuid[]);
--   drop table if exists public.push_outbox, public.push_subscriptions;
--   delete from public.app_secrets where key in ('push_vapid_public', 'push_vapid_private');
-- ===========================================================================

do $$ begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net is not available here; the queue is sent when push-send is next called';
end $$;

create table if not exists public.push_subscriptions (
  id             uuid primary key default gen_random_uuid(),
  endpoint       text not null,
  p256dh         text not null,
  auth           text not null,
  audience       text not null check (audience in ('team', 'client', 'creator')),
  team_member_id uuid references public.team_members(id) on delete cascade,
  campaign_id    uuid references public.campaigns(id) on delete cascade,
  creator_id     uuid references public.creators(id) on delete cascade,
  target         uuid generated always as (coalesce(team_member_id, campaign_id, creator_id)) stored,
  lang           text not null default 'en' check (lang in ('en', 'zh')),
  created_at     timestamptz not null default now(),
  seen_at        timestamptz not null default now(),
  check ((audience = 'team') = (team_member_id is not null)),
  check ((audience = 'client') = (campaign_id is not null)),
  check ((audience = 'creator') = (creator_id is not null)),
  unique (endpoint, target)
);
create index if not exists push_subscriptions_target_idx on public.push_subscriptions(target);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from public, anon, authenticated;

create table if not exists public.push_outbox (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  audience       text not null check (audience in ('team', 'client', 'creator')),
  target         uuid not null,
  message        jsonb not null,
  url            text not null,
  tag            text,
  claimed_at     timestamptz,
  sent_at        timestamptz,
  sent           integer not null default 0,
  failed         integer not null default 0
);
create index if not exists push_outbox_open_idx on public.push_outbox(created_at) where sent_at is null;
alter table public.push_outbox enable row level security;
revoke all on public.push_outbox from public, anon, authenticated;

/* The half of the sender's key a browser needs to subscribe; null until
   push-send has made the pair, and the pages hide their control until then. */
create or replace function public.push_public_key()
returns text
language sql stable security definer set search_path = public as $$
  select s.value from public.app_secrets s where s.key = 'push_vapid_public'
$$;
revoke all on function public.push_public_key() from public;
grant execute on function public.push_public_key() to anon, authenticated;

/* A push service's own address, and nothing else: Chrome and Android
   (Google), Safari and iPhone (Apple), Firefox (Mozilla), Edge (Microsoft).
   The sender posts to whatever is stored here, so an address anybody could
   type is refused. */
create or replace function public.push_endpoint_ok(p_endpoint text)
returns boolean
language sql immutable set search_path = public as $$
  select coalesce(length(p_endpoint) <= 1000 and p_endpoint ~ ('^https://(fcm\.googleapis\.com|android\.googleapis\.com'
    || '|([a-z0-9-]+\.)*push\.apple\.com|updates\.push\.services\.mozilla\.com'
    || '|([a-z0-9-]+\.)*notify\.windows\.com)/'), false)
$$;
revoke all on function public.push_endpoint_ok(text) from public, anon, authenticated;

/* What a page follows, proved as the page proves it: the signed-in
   colleague, the campaign's token, the creator's code. */
create or replace function public.push_target(p_audience text, p_ref text)
returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  v_code text := upper(regexp_replace(coalesce(p_ref, ''), '[^A-Za-z0-9]', '', 'g'));
  v_id   uuid;
begin
  if p_audience = 'team' then
    return (public.ops_me()).id;
  elsif p_audience = 'client' and coalesce(p_ref, '') <> '' then
    select c.id into v_id from public.campaigns c where c.access_token = p_ref;
  elsif p_audience = 'creator' and length(v_code) >= 8 then
    select k.id into v_id from public.creators k where k.access_code = v_code and k.active;
  end if;
  return v_id;
end $$;
revoke all on function public.push_target(text, text) from public, anon, authenticated;

/* A device turns notifications on for what its page follows. A console
   follows one colleague and a creator's page one creator, so turning on
   there moves the device; a client's device adds each campaign it is turned
   on for. Twenty devices at most follow one thing: the oldest leaves. */
create or replace function public.push_subscribe(
  p_audience text, p_ref text, p_endpoint text, p_p256dh text, p_auth text, p_lang text default 'en')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_target uuid;
  v_lang   text := case when p_lang = 'zh' then 'zh' else 'en' end;
begin
  if not public.push_endpoint_ok(p_endpoint)
     or coalesce(length(p_p256dh), 0) not between 80 and 100
     or coalesce(length(p_auth), 0) not between 16 and 32 then
    return jsonb_build_object('error', 'bad-subscription');
  end if;
  if p_audience not in ('team', 'client', 'creator') then
    return jsonb_build_object('error', 'bad-audience');
  end if;
  v_target := public.push_target(p_audience, p_ref);
  if v_target is null then
    return jsonb_build_object('error', case when p_audience = 'team' then 'not-team' else 'not-found' end);
  end if;

  if p_audience in ('team', 'creator') then
    delete from public.push_subscriptions s
     where s.endpoint = p_endpoint and s.audience = p_audience and s.target <> v_target;
  end if;
  insert into public.push_subscriptions
    (endpoint, p256dh, auth, audience, team_member_id, campaign_id, creator_id, lang)
  values (p_endpoint, p_p256dh, p_auth, p_audience,
          case when p_audience = 'team' then v_target end,
          case when p_audience = 'client' then v_target end,
          case when p_audience = 'creator' then v_target end, v_lang)
  on conflict (endpoint, target) do update
     set lang = excluded.lang, seen_at = now();
  update public.push_subscriptions s set p256dh = p_p256dh, auth = p_auth
   where s.endpoint = p_endpoint and (s.p256dh <> p_p256dh or s.auth <> p_auth);
  delete from public.push_subscriptions s
   where s.target = v_target
     and s.id not in (select x.id from public.push_subscriptions x where x.target = v_target
                       order by x.seen_at desc limit 20);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.push_subscribe(text, text, text, text, text, text) from public;
grant execute on function public.push_subscribe(text, text, text, text, text, text) to anon, authenticated;

/* Turning off is the device's own act: whoever holds the endpoint. With a
   page's audience and reference it stops that one; without, everything the
   device follows. `left` says whether the device still follows anything. */
create or replace function public.push_unsubscribe(p_endpoint text, p_audience text default null, p_ref text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_target uuid;
begin
  if p_audience is null then
    delete from public.push_subscriptions s where s.endpoint = p_endpoint;
  else
    v_target := public.push_target(p_audience, p_ref);
    delete from public.push_subscriptions s where s.endpoint = p_endpoint and s.target = v_target;
  end if;
  return jsonb_build_object('ok', true,
    'left', (select count(*) from public.push_subscriptions s where s.endpoint = p_endpoint));
end $$;
revoke all on function public.push_unsubscribe(text, text, text) from public;
grant execute on function public.push_unsubscribe(text, text, text) to anon, authenticated;

/* Whether this device follows what this page belongs to. It says nothing
   about any other device, or anything else this one follows. */
create or replace function public.push_status(p_endpoint text, p_audience text, p_ref text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('on', exists (
    select 1 from public.push_subscriptions s
     where s.endpoint = p_endpoint and s.target = public.push_target(p_audience, p_ref)))
$$;
revoke all on function public.push_status(text, text, text) from public;
grant execute on function public.push_status(text, text, text) to anon, authenticated;

/* Wakes push-send once the write has committed. Silent where pg_net is not
   installed or refuses: the queue is kept, and the next wake sends it. */
create or replace function public.push_kick()
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2)'
    using 'https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/push-send', '{}'::jsonb;
exception when others then
  return;
end $$;
revoke all on function public.push_kick() from public, anon, authenticated;

/* One message into the queue, only where a device follows it. */
create or replace function public.push_queue(
  p_audience text, p_target uuid, p_message jsonb, p_url text, p_tag text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_target is null or not exists (select 1 from public.push_subscriptions s
                  where s.audience = p_audience and s.target = p_target) then
    return;
  end if;
  insert into public.push_outbox (audience, target, message, url, tag)
  values (p_audience, p_target, p_message, p_url, p_tag);
  perform public.push_kick();
end $$;
revoke all on function public.push_queue(text, uuid, jsonb, text, text) from public, anon, authenticated;

/* A colleague's bell, on their phone: the same words, and the task opens. */
create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.task_id is null then '/admin/' else '/admin/?s=work&open=' || new.task_id::text end,
    case when new.task_id is null then null else 'task-' || new.task_id::text end);
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists ops_notifications_push on public.ops_notifications;
create trigger ops_notifications_push after insert on public.ops_notifications
  for each row execute function public.ops_notifications_push();

/* A booking's step, told to whoever follows it: the client when a draft
   is released to them and when the post goes live; the creator when they are
   booked, asked for changes, and cleared to post. Only a forward move is
   told: a Revert back into a step tells nobody. */
create or replace function public.campaign_options_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title    text;
  v_title_zh text;
  v_token    text;
  v_creator  text;
  v_msg      jsonb;
begin
  if new.state is not distinct from old.state then return new; end if;
  select coalesce(nullif(btrim(c.title), ''), 'Your campaign'),
         coalesce(nullif(btrim(c.title_zh), ''), nullif(btrim(c.title), ''), '您的活动'),
         c.access_token
    into v_title, v_title_zh, v_token from public.campaigns c where c.id = new.campaign_id;
  select coalesce(nullif(btrim(k.name), ''), 'A creator') into v_creator
    from public.creators k where k.id = new.creator_id;
  v_creator := coalesce(v_creator, 'A creator');

  if v_token is not null and ((new.state = 'reviewing' and old.state = 'submitted')
                           or (new.state = 'posted' and old.state = 'scheduled')) then
    v_msg := case new.state
      when 'reviewing' then jsonb_build_object(
        'en', jsonb_build_object('title', 'Draft ready for review', 'body', v_creator || ' · ' || v_title),
        'zh', jsonb_build_object('title', '初稿待审阅', 'body', v_creator || ' · ' || v_title_zh))
      else jsonb_build_object(
        'en', jsonb_build_object('title', 'Post is live', 'body', v_creator || ' · ' || v_title),
        'zh', jsonb_build_object('title', '帖子已发布', 'body', v_creator || ' · ' || v_title_zh))
    end;
    perform public.push_queue('client', new.campaign_id, v_msg,
      '/creators/?k=' || v_token, 'option-' || new.id::text);
  end if;

  if (new.state = 'confirmed' and old.state in ('option', 'shortlisted', 'backup'))
     or new.state = 'changes'
     or (new.state = 'scheduled' and old.state in ('submitted', 'reviewing', 'changes')) then
    v_msg := case new.state
      when 'confirmed' then jsonb_build_object(
        'en', jsonb_build_object('title', 'Booking confirmed', 'body', v_title),
        'zh', jsonb_build_object('title', '合作已确认', 'body', v_title_zh))
      when 'changes' then jsonb_build_object(
        'en', jsonb_build_object('title', 'Changes requested', 'body', v_title),
        'zh', jsonb_build_object('title', '需要修改', 'body', v_title_zh))
      else jsonb_build_object(
        'en', jsonb_build_object('title', 'Approved: ready to post', 'body', v_title),
        'zh', jsonb_build_object('title', '已通过，可以发布', 'body', v_title_zh))
    end;
    perform public.push_queue('creator', new.creator_id, v_msg,
      '/creator/#b=' || new.id::text, 'option-' || new.id::text);
  end if;
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists campaign_options_push on public.campaign_options;
create trigger campaign_options_push after update of state on public.campaign_options
  for each row execute function public.campaign_options_push();

/* The sender's keys, for push-send alone. */
create or replace function public.push_keys()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'public',  (select s.value from public.app_secrets s where s.key = 'push_vapid_public'),
    'private', (select s.value from public.app_secrets s where s.key = 'push_vapid_private'))
$$;
revoke all on function public.push_keys() from public, anon, authenticated;
grant execute on function public.push_keys() to service_role;

/* Kept once: a second run, or two at once, keeps the first pair. */
create or replace function public.push_set_keys(p_public text, p_private text)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_public, '') = '' or coalesce(p_private, '') = '' then
    return public.push_keys();
  end if;
  if not exists (select 1 from public.app_secrets s where s.key = 'push_vapid_private') then
    insert into public.app_secrets (key, value) values ('push_vapid_private', p_private)
      on conflict (key) do nothing;
    insert into public.app_secrets (key, value) values ('push_vapid_public', p_public)
      on conflict (key) do nothing;
  end if;
  return public.push_keys();
end $$;
revoke all on function public.push_set_keys(text, text) from public, anon, authenticated;
grant execute on function public.push_set_keys(text, text) to service_role;

/* The next messages to send, each with the devices that follow it. A claim
   holds a message for five minutes, so two runs never send it twice; a
   message older than two days is not sent. */
create or replace function public.push_claim(p_limit integer default 50)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_out jsonb;
begin
  with c as (
    select o.id from public.push_outbox o
     where o.sent_at is null
       and (o.claimed_at is null or o.claimed_at < now() - interval '5 minutes')
       and o.created_at > now() - interval '2 days'
     order by o.created_at
     limit greatest(1, least(coalesce(p_limit, 50), 200))
     for update skip locked
  ), took as (
    update public.push_outbox o set claimed_at = now() from c where o.id = c.id returning o.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'message', t.message, 'url', t.url, 'tag', t.tag,
           'subs', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', s.id, 'endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth, 'lang', s.lang))
                     from public.push_subscriptions s
                    where s.audience = t.audience and s.target = t.target), '[]'::jsonb))
           order by t.created_at), '[]'::jsonb)
    into v_out from took t;
  return v_out;
end $$;
revoke all on function public.push_claim(integer) from public, anon, authenticated;
grant execute on function public.push_claim(integer) to service_role;

/* What a send did: the message is done, a device the push service no longer
   knows is taken off with everything it followed, and a month of the queue
   is kept. */
create or replace function public.push_done(p_outbox uuid, p_sent integer, p_failed integer, p_dead uuid[])
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.push_outbox
     set sent_at = now(), sent = coalesce(p_sent, 0), failed = coalesce(p_failed, 0)
   where id = p_outbox;
  if p_dead is not null and array_length(p_dead, 1) > 0 then
    delete from public.push_subscriptions s
     where s.endpoint in (select d.endpoint from public.push_subscriptions d where d.id = any (p_dead));
  end if;
  delete from public.push_outbox where created_at < now() - interval '30 days';
end $$;
revoke all on function public.push_done(uuid, integer, integer, uuid[]) from public, anon, authenticated;
grant execute on function public.push_done(uuid, integer, integer, uuid[]) to service_role;

-- END OF PUSH NOTIFICATIONS ---------------------------------------------------
