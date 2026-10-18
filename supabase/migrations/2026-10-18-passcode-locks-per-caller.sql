-- ===========================================================================
-- PASSCODE LOCKS PER CALLER — wrong passcodes lock out the caller who typed
-- them, not the client: counted per link and caller address, with a much
-- higher count for the link as a whole that never shuts out a caller who
-- has already opened it. A lock is said as a lock, and the team sees and
-- clears it. 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored
-- byte for byte in supabase/schema.sql under the same banner;
-- tests/confirmonce.js compares the two.
--
-- WHY (second audit, item 4)
--   PASSCODE ATTEMPTS counted wrong tries per link alone and looked at the
--   lock before the passcode, so anyone holding a link kept its client out
--   with five wrong guesses every 15 minutes, and the page called the lock
--   Link not recognised.
--
-- WHAT CHANGED
--   1. `request_ip()`: the caller's address as PostgREST passes it, the
--      first entry of X-Forwarded-For (Supabase's documented reading), else
--      CF-Connecting-IP, else X-Real-IP, else empty. media-pass and
--      sign-download forward their own caller's address the same way.
--   2. `link_tries` (kind, the link's key, the caller's address; wrong
--      tries, the last, locked until, the last right passcode; RLS on, no
--      policy, no grant): five wrong tries from one address within 15
--      minutes lock that address out of that link for 15 minutes.
--   3. `link_attempts` is the link's backstop: 100 wrong tries from every
--      address within an hour lock the link for an hour, for every caller
--      but one whose address gave the right passcode in the last 30 days.
--   4. `link_passcode(p_kind, p_token, p_stored, p_given)` keeps its answers
--      (`ok`, `wrong`, `locked`); asking without a passcode is still never
--      counted. A wrong try takes its rows with insert … on conflict do
--      nothing, then select … for update, so two at once count twice.
--   5. `link_locked(p_kind, p_token)` answers `{error: 'locked', minutes}`,
--      which get_review_feed, get_campaign, save_selection,
--      confirm_selection, confirm_selection_with and review_draft now return
--      in place of `not_found` / `not-found`; each is restated whole from
--      its last definition with only that answer changed. The pages say it
--      in words.
--   6. `link_lock_state(p_kind, p_id)` (Content Review settings or Creator
--      Campaigns: Campaigns at View, client scope) answers whether a
--      client's review link or a campaign's selection link is locked now,
--      until when and for how many addresses; `link_lock_clear(p_kind,
--      p_id)` (the same at Work) clears every lock and count on it, filed
--      `client.profile` / `campaign.edited` as the colleague.
--
-- ROLLBACK
--   Run PASSCODE ATTEMPTS (2026-10-18-passcode-attempts.sql) again for
--   link_passcode, get_review_feed and get_campaign, and PAST CLIENT LINKS
--   ACT ON NOTHING (2026-10-18-past-client-links-act-on-nothing.sql) for
--   the other four, then in the SQL Editor:
--   drop function if exists public.link_lock_clear(text, uuid);
--   drop function if exists public.link_lock_state(text, uuid);
--   drop function if exists public.link_locked(text, text);
--   drop function if exists public.request_ip();
--   drop table if exists public.link_tries;
-- ===========================================================================

create table if not exists public.link_tries (
  kind         text not null,
  token        text not null,
  ip           text not null,
  fails        integer not null default 0,
  last_at      timestamptz not null default now(),
  locked_until timestamptz,
  ok_at        timestamptz,
  primary key (kind, token, ip)
);
alter table public.link_tries enable row level security;
revoke all on public.link_tries from public, anon, authenticated;

create or replace function public.request_ip()
returns text
language sql stable set search_path = public as $$
  select left(coalesce(
    nullif(btrim(split_part(h ->> 'x-forwarded-for', ',', 1)), ''),
    nullif(btrim(h ->> 'cf-connecting-ip'), ''),
    nullif(btrim(h ->> 'x-real-ip'), ''),
    ''), 64)
  from (select coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json as h) r
$$;
revoke all on function public.request_ip() from public, anon, authenticated;

create or replace function public.link_passcode(p_kind text, p_token text, p_stored text, p_given text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_ip text := public.request_ip();
  a public.link_tries%rowtype;
  b public.link_attempts%rowtype;
  v_known boolean;
begin
  if coalesce(p_stored, '') = '' then return 'ok'; end if;
  select * into a from public.link_tries where kind = p_kind and token = p_token and ip = v_ip;
  select * into b from public.link_attempts where kind = p_kind and token = p_token;
  -- An address that opened the link in the last 30 days is never held by
  -- the link's backstop, only by its own count.
  v_known := a.ok_at is not null and a.ok_at > now() - interval '30 days';
  if a.locked_until > now() then return 'locked'; end if;
  if b.locked_until > now() and not v_known then return 'locked'; end if;
  -- Asked without one: the page learning that a passcode is needed.
  if coalesce(p_given, '') = '' then return 'wrong'; end if;
  if p_given = p_stored then
    if a.kind is null or a.fails > 0 or a.locked_until is not null or coalesce(a.ok_at < now() - interval '1 day', true) then
      insert into public.link_tries as t (kind, token, ip, fails, last_at, ok_at)
      values (p_kind, p_token, v_ip, 0, now(), now())
      on conflict (kind, token, ip) do update
         set fails = 0, locked_until = null, ok_at = now();
    end if;
    return 'ok';
  end if;

  insert into public.link_tries (kind, token, ip) values (p_kind, p_token, v_ip)
  on conflict (kind, token, ip) do nothing;
  select * into a from public.link_tries
   where kind = p_kind and token = p_token and ip = v_ip for update;
  if a.locked_until > now() then return 'locked'; end if;
  a.fails := case when a.locked_until is not null or a.last_at < now() - interval '15 minutes'
                  then 1 else a.fails + 1 end;
  a.locked_until := case when a.fails >= 5 then now() + interval '15 minutes' end;
  update public.link_tries set fails = a.fails, last_at = now(), locked_until = a.locked_until
   where kind = p_kind and token = p_token and ip = v_ip;

  insert into public.link_attempts (kind, token) values (p_kind, p_token)
  on conflict (kind, token) do nothing;
  select * into b from public.link_attempts
   where kind = p_kind and token = p_token for update;
  if b.locked_until is null or b.locked_until <= now() then
    b.fails := case when b.locked_until is not null or b.last_at < now() - interval '1 hour'
                    then 1 else b.fails + 1 end;
    b.locked_until := case when b.fails >= 100 then now() + interval '1 hour' end;
    update public.link_attempts set fails = b.fails, last_at = now(), locked_until = b.locked_until
     where kind = p_kind and token = p_token;
  end if;

  if a.locked_until is not null then return 'locked'; end if;
  if b.locked_until > now() and not v_known then return 'locked'; end if;
  return 'wrong';
end $$;
revoke all on function public.link_passcode(text, text, text, text) from public, anon, authenticated;

-- What a locked caller is told: a lock, and how long it has to run.
create or replace function public.link_locked(p_kind text, p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a public.link_tries%rowtype;
  v_until timestamptz;
begin
  select * into a from public.link_tries
   where kind = p_kind and token = p_token and ip = public.request_ip();
  v_until := case when a.locked_until > now() then a.locked_until end;
  if not coalesce(a.ok_at > now() - interval '30 days', false) then
    v_until := greatest(v_until, (select l.locked_until from public.link_attempts l
                                   where l.kind = p_kind and l.token = p_token and l.locked_until > now()));
  end if;
  return jsonb_build_object('error', 'locked', 'minutes',
    greatest(1, ceil(extract(epoch from (coalesce(v_until, now() + interval '15 minutes') - now())) / 60))::int);
end $$;
revoke all on function public.link_locked(text, text) from public, anon, authenticated;

-- The link's key behind a client's review or a campaign's selection, asked
-- as the colleague: the section's level and the client's scope.
create or replace function public.link_lock_state(p_kind text, p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_token text;
  v_until timestamptz;
  v_n     integer;
begin
  if p_kind = 'review' then
    if not public.allowed('review.settings', 'view') then return jsonb_build_object('error', 'denied'); end if;
    if not public.client_scope_ok('client', p_id, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
    select c.access_token into v_token from public.clients c where c.id = p_id;
  elsif p_kind = 'selection' then
    if not public.allowed('campaigns.campaigns', 'view') then return jsonb_build_object('error', 'denied'); end if;
    if not public.client_scope_ok('campaign', p_id, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
    select k.access_token into v_token from public.campaigns k where k.id = p_id;
  else
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if v_token is null then return jsonb_build_object('error', 'not-found'); end if;
  select max(t.locked_until), count(*) into v_until, v_n
    from public.link_tries t
   where t.kind = p_kind and t.token = v_token and t.locked_until > now();
  return jsonb_build_object(
    'locked', v_n > 0 or exists (select 1 from public.link_attempts a
                                  where a.kind = p_kind and a.token = v_token and a.locked_until > now()),
    'all', exists (select 1 from public.link_attempts a
                    where a.kind = p_kind and a.token = v_token and a.locked_until > now()),
    'addresses', v_n,
    'until', greatest(v_until, (select a.locked_until from public.link_attempts a
                                 where a.kind = p_kind and a.token = v_token and a.locked_until > now())));
end $$;
revoke all on function public.link_lock_state(text, uuid) from public, anon;
grant execute on function public.link_lock_state(text, uuid) to authenticated;

create or replace function public.link_lock_clear(p_kind text, p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me      public.team_members;
  v_token text;
  v_name  text;
  v_n     integer;
begin
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_kind = 'review' then
    if not public.allowed('review.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
    if not public.client_scope_ok('client', p_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
    select c.access_token, c.name into v_token, v_name from public.clients c where c.id = p_id;
  elsif p_kind = 'selection' then
    if not public.allowed('campaigns.campaigns', 'work') then return jsonb_build_object('error', 'denied'); end if;
    if not public.client_scope_ok('campaign', p_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
    select k.access_token, k.title into v_token, v_name from public.campaigns k where k.id = p_id;
  else
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if v_token is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.link_tries set fails = 0, locked_until = null
   where kind = p_kind and token = v_token and (fails > 0 or locked_until is not null);
  get diagnostics v_n = row_count;
  update public.link_attempts set fails = 0, locked_until = null
   where kind = p_kind and token = v_token;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, case when p_kind = 'review' then 'client.profile' else 'campaign.edited' end, v_name,
          case when p_kind = 'review' then 'Review link' else 'Selection link' end
          || ' unlocked · incorrect access codes cleared');
  return jsonb_build_object('ok', true, 'cleared', v_n);
end $$;
revoke all on function public.link_lock_clear(text, uuid) from public, anon;
grant execute on function public.link_lock_clear(text, uuid) to authenticated;

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

  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4); a passcode asked for names nobody (item 6).
  case public.link_passcode('review', v_client.access_token, v_client.passcode, p_passcode)
    when 'locked' then return public.link_locked('review', v_client.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode_required');
    else null;
  end case;

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
  -- A past client's links close (second audit, item 5): answered as a key
  -- nobody knows, so the page says the link is not recognised.
  if cl.stage = 'past' then return jsonb_build_object('error', 'not-found'); end if;

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

  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4); a passcode asked for names nobody (item 6).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return public.link_locked('selection', c.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;

  return jsonb_build_object(
    'campaign', jsonb_build_object(
      'title', c.title, 'title_zh', c.title_zh,
      'purpose', c.purpose, 'purpose_zh', c.purpose_zh, 'slots', c.slots,
      'backups_open', coalesce(c.backups_open, false),
      'selection_closed', c.selection_closed_at is not null,
      'deadline', c.deadline, 'state', c.state, 'deliverable', c.deliverable,
      'push_format', c.push_format, 'brief', c.brief, 'brief_zh', c.brief_zh,
      'invoice_no', case when billable then c.invoice_no end,
      'invoice_url', case when billable then c.invoice_url end,
      /* The client's last confirmation: who, when, and the creators it
         named, so a page opened again says the selection was confirmed and
         asks again only once the picks differ (2026-10-14). */
      'confirmed', (
        select jsonb_build_object('person', k.person, 'at', k.created_at,
                 'selected', coalesce((select jsonb_agg(x->>'id') from jsonb_array_elements(coalesce(k.snapshot, '[]'::jsonb)) x
                                        where x->>'as' = 'shortlisted'), '[]'::jsonb))
          from campaign_confirmations k
         where k.campaign_id = c.id and k.kind = 'client'
         order by k.created_at desc limit 1)),
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
        /* The client's own rounds: a round the team sent back, or a request
           taken back, is not one the client made (2026-09-27). */
        'revision_round', (select count(*) from public.option_reviews r
                            where r.option_id = o.id and r.source = 'client'
                              and r.decision = 'changes' and r.undone_at is null)::int + 1,
        'planned_publish', o.planned_publish,
        /* What the creator uploaded, once it has been released: the round
           the team last released (`released_round`, stamped at release), so
           a creator's next round, uploaded after the client asked for
           changes, stays with the team until it is released in its turn
           (audit S5, 2026-10-10). A file hidden after the client's approval
           is never sent (audit S6). */
        'files', case when s.released then coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', d.id, 'url', d.url, 'name', d.name, 'kind', d.kind,
              'bytes', d.bytes) order by d.uploaded_at)
            from campaign_deliverables d
            where d.option_id = o.id and d.removed_at is null and d.hidden_at is null
              and d.round = coalesce(o.released_round,
                            (select max(d2.round) from campaign_deliverables d2
                              where d2.option_id = o.id and d2.removed_at is null))
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
        /* What was last decided, so the card can say who approved it and
           when rather than jumping to the next step with nothing to show for
           the decision. The client's own decisions, and an approval the team
           gave on the client's behalf (`by_team`, read "Proceeded by"); a
           team send-back stays withheld. Withheld with the draft it is about. */
        'review', case when s.released then (
            select jsonb_build_object('decision', r.decision, 'reviewer', r.reviewer,
                                      'note', case when r.source = 'client' then r.note end,
                                      'at', r.created_at, 'by_team', r.source = 'team')
            from option_reviews r where r.option_id = o.id
              and (r.source = 'client' or r.decision = 'approved') and r.undone_at is null
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

revoke all on function public.get_campaign(text, text) from public;
grant execute on function public.get_campaign(text, text) to anon, authenticated;

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
  -- A past client's link acts on nothing, as it reads nothing (second
  -- audit, item 7): answered as a key nobody knows, before the passcode.
  if exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return public.link_locked('selection', c.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;

  n := coalesce(array_length(p_selected, 1), 0);
  /* Closed once the slots were full, until the team reopens it; backups
     alone may still be named where the team opened them. */
  if c.selection_closed_at is not null and not (coalesce(c.backups_open, false) and n = 0) then
    return jsonb_build_object('error', 'closed');
  end if;
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

revoke all on function public.save_selection(text, uuid[], uuid[], text) from public;
grant execute on function public.save_selection(text, uuid[], uuid[], text) to anon, authenticated;

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
  -- A past client's link acts on nothing, as it reads nothing (second
  -- audit, item 7): answered as a key nobody knows, before the passcode.
  if exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return public.link_locked('selection', c.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
  if c.selection_closed_at is not null and not coalesce(c.backups_open, false) then
    return jsonb_build_object('error', 'closed');
  end if;
  -- Nothing saved is nothing to confirm (a save refused under the page).
  if not exists (select 1 from campaign_options o
                  where o.campaign_id = c.id
                    and o.state = case when c.selection_closed_at is not null
                                       then 'backup' else 'shortlisted' end) then
    return jsonb_build_object('error', 'empty');
  end if;

  insert into campaign_confirmations (campaign_id, kind, person, source)
  values (c.id, 'client', trim(p_person), 'portal');

  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          (select count(*)::text || ' creator' || case when count(*) = 1 then '' else 's' end
             from campaign_options
            where campaign_id = c.id and state = 'shortlisted') || ' confirmed');

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.confirm_selection(text, text, text) from public;
grant execute on function public.confirm_selection(text, text, text) to anon, authenticated;

create or replace function public.confirm_selection_with(
  p_token text, p_person text, p_passcode text, p_selected uuid[], p_backup uuid[],
  p_seen jsonb, p_idem text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c      campaigns%rowtype;
  v_sel  uuid[];
  v_bak  uuid[];
  v_all  uuid[];
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
  v_now  jsonb;
  v_snap jsonb;
  n      integer;
  v_booked integer;
begin
  select * into c from campaigns where access_token = p_token for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  -- A past client's link acts on nothing, as it reads nothing (second
  -- audit, item 7): answered as a key nobody knows, before the passcode.
  if exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return public.link_locked('selection', c.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
  -- The same press again: the first answer stands and nothing is filed twice.
  if v_idem is not null and exists (select 1 from campaign_confirmations k
                                     where k.campaign_id = c.id and k.idem = v_idem) then
    return jsonb_build_object('ok', true, 'again', true);
  end if;

  v_sel := array(select distinct x from unnest(coalesce(p_selected, '{}'::uuid[])) x where x is not null);
  v_bak := case when coalesce(c.backups_open, false)
                then array(select distinct x from unnest(coalesce(p_backup, '{}'::uuid[])) x
                            where x is not null and not (x = any (v_sel)))
                else '{}'::uuid[] end;
  v_all := v_sel || v_bak;
  n := cardinality(v_sel);

  if c.selection_closed_at is not null and not (coalesce(c.backups_open, false) and n = 0) then
    return jsonb_build_object('error', 'closed');
  end if;
  if cardinality(v_all) = 0 then return jsonb_build_object('error', 'empty'); end if;
  -- The slots left are the slots less the creators already booked: a
  -- selection reopened for four of ten never books sixteen.
  v_booked := public.campaign_booked(c.id);
  if n > 0 and n > c.slots - v_booked then
    return jsonb_build_object('error', 'over-slots', 'slots', c.slots, 'booked', v_booked);
  end if;
  -- Every creator named is still on the campaign and open to choose.
  if (select count(*) from campaign_options o
       where o.id = any (v_all) and o.campaign_id = c.id
         and o.state in ('option', 'shortlisted', 'backup')) <> cardinality(v_all) then
    return jsonb_build_object('error', 'stale');
  end if;
  -- The prices the client read are the prices now.
  select jsonb_object_agg(o.id::text, o.rate) into v_now
    from campaign_options o where o.id = any (v_all);
  if exists (select 1 from campaign_options o
              where o.id = any (v_all)
                and coalesce(p_seen -> (o.id::text), 'null'::jsonb)
                    is distinct from coalesce(to_jsonb(o.rate), 'null'::jsonb)) then
    return jsonb_build_object('error', 'prices', 'rates', v_now);
  end if;

  update campaign_options set state = 'option'
   where campaign_id = c.id and state in ('shortlisted', 'backup');
  if n > 0 then
    update campaign_options set state = 'shortlisted'
     where campaign_id = c.id and id = any (v_sel) and state = 'option';
  end if;
  if cardinality(v_bak) > 0 then
    update campaign_options set state = 'backup'
     where campaign_id = c.id and id = any (v_bak) and state = 'option';
  end if;

  select jsonb_agg(jsonb_build_object('id', o.id, 'creator', cr.name, 'rate', o.rate, 'as', o.state)
                   order by o.position, o.added_at)
    into v_snap
    from campaign_options o join creators cr on cr.id = o.creator_id
   where o.id = any (v_all);
  insert into campaign_confirmations (campaign_id, kind, person, source, idem, snapshot)
  values (c.id, 'client', trim(p_person), 'portal', v_idem, coalesce(v_snap, '[]'::jsonb));

  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          case when n > 0 then n::text || ' creator' || case when n = 1 then '' else 's' end || ' confirmed'
               else cardinality(v_bak)::text || ' backup' || case when cardinality(v_bak) = 1 then '' else 's' end || ' confirmed' end);

  return jsonb_build_object('ok', true, 'selected', n);
end $$;

revoke all on function public.confirm_selection_with(text, text, text, uuid[], uuid[], jsonb, text) from public;
grant execute on function public.confirm_selection_with(text, text, text, uuid[], uuid[], jsonb, text) to anon, authenticated;

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
  -- A past client's link acts on nothing, as it reads nothing (second
  -- audit, item 7): answered as a key nobody knows, before the passcode.
  if exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return public.link_locked('selection', c.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;
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
  /* A draft the team sent back to the creator is not with the client: the
     selection page shows it as Pending draft, so only a hand-made call
     could rule on it (audit B, 2026-10-17). */
  if o.state = 'changes' and coalesce(o.changes_by, 'client') = 'team' then
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

-- END OF PASSCODE LOCKS PER CALLER ------------------------------------------

select public.functions_tidy();
