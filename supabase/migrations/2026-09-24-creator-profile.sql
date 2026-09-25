-- 2026-09-24 · A creator's own profile links
--
-- Run once in the Supabase SQL editor. Safe to run twice: every statement is
-- `create or replace`, `if not exists`, or a policy dropped before it is made.
-- Mirrored in supabase/schema.sql (the section under the banner below, and
-- get_creator in CREATOR ACCESS AND DELIVERY), compared by tests/sql.js.

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


-- The creator's page reads their profile links and when they joined, and
-- still never the fee. Identical to get_creator in supabase/schema.sql.
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

-- The record files the four creator tags under Creator Campaigns: the three
-- link changes, and the link reset the console has written since it shipped
-- with no word and no section. Identical to activity_section in
-- supabase/schema.sql.
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
                    'contact.restored', 'request.changed', 'request.raised',
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
