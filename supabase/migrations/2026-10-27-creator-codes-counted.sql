-- ===========================================================================
-- CREATOR CODES COUNTED — a wrong creator access code is counted against the
-- caller's address, five within 15 minutes locking it out (2026-10-27)
-- ===========================================================================
-- WHY (the user, 2026-10-27: "What if someone keeps trying on one
-- browser?"): every other code a page takes (a link's passcode, /verify/,
-- the demo PIN) was counted; a creator's eight-character code was not, so
-- `get_creator` answered any number of guesses. Once the creator's page
-- checks a code by itself at its eighth character, the server must count.
--
-- WHAT IT CHANGES
--   `creator_code_try(p_code)` (internal) reads an eight-character code and
--     answers its creator (active or not), or nothing, or the minutes a
--     locked caller has left. A wrong code is counted in `link_tries`
--     (kind `creator`, token `code`, the caller's address from
--     `request_ip()`): five within 15 minutes lock that address out for 15
--     minutes, then an hour, then a day where it is locked again within a
--     day of the last lock ending, as `link_passcode` does. While locked
--     nothing is looked up, the right code included. A right code changes
--     no count, so a creator holding one code cannot reset a guesser's.
--     No backstop across addresses: one held over every caller would let a
--     guesser lock every creator out. `privacy_retention` already clears
--     the rows after 30 days.
--   `get_creator` (now volatile) answers `locked` with `minutes`;
--   `creator_set_profiles` and the creator branch of `share_link_preview`
--     (now plpgsql, volatile) take the code through the same count, so
--     neither tells a right code from a wrong one beyond it.
--   `push_subscribe` is in the SQL Editor part
--     (2026-10-27-creator-codes-counted-editor.sql), since it holds a
--     delete the connector holds.
--
-- ORDER: this file (connector), then the editor part, then the pages. An
-- old page reads `locked` as a code not recognised.
--
-- ROLLBACK: get_creator, creator_set_profiles and share_link_preview as
-- schema.sql defined them before this banner, then in the SQL Editor:
--   drop function if exists public.creator_code_try(text);
--   delete from public.link_tries where kind = 'creator';
-- ===========================================================================

/* One eight-character code, counted. Answers the creator it opens (active
   or not), or nothing; `o_locked` is the minutes a locked caller has left. */
create or replace function public.creator_code_try(p_code text, out o_creator uuid, out o_locked integer)
language plpgsql security definer set search_path = public as $$
declare
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_ip   text := public.request_ip();
  a      public.link_tries%rowtype;
begin
  if v_code !~ '^[A-Z0-9]{8}$' then return; end if;
  select * into a from public.link_tries t where t.kind = 'creator' and t.token = 'code' and t.ip = v_ip;
  if a.locked_until > now() then
    o_locked := greatest(1, ceil(extract(epoch from a.locked_until - now()) / 60))::integer;
    return;
  end if;
  select k.id into o_creator from public.creators k where k.access_code = v_code;
  if o_creator is not null then return; end if;

  insert into public.link_tries (kind, token, ip) values ('creator', 'code', v_ip)
  on conflict (kind, token, ip) do nothing;
  select * into a from public.link_tries t
   where t.kind = 'creator' and t.token = 'code' and t.ip = v_ip for update;
  if a.locked_until > now() then
    o_locked := greatest(1, ceil(extract(epoch from a.locked_until - now()) / 60))::integer;
    return;
  end if;
  a.fails := case when a.locked_until is not null or a.last_at < now() - interval '15 minutes'
                  then 1 else a.fails + 1 end;
  if a.fails >= 5 then
    a.strikes := case when a.struck_until > now() - interval '24 hours' then a.strikes + 1 else 1 end;
    a.locked_until := now() + case a.strikes when 1 then interval '15 minutes'
                                             when 2 then interval '1 hour'
                                             else interval '24 hours' end;
    a.struck_until := a.locked_until;
    o_locked := greatest(1, ceil(extract(epoch from a.locked_until - now()) / 60))::integer;
  else
    a.locked_until := null;
  end if;
  update public.link_tries t
     set fails = a.fails, last_at = now(), locked_until = a.locked_until,
         strikes = a.strikes, struck_until = a.struck_until
   where t.kind = 'creator' and t.token = 'code' and t.ip = v_ip;
end $$;
revoke all on function public.creator_code_try(text) from public, anon, authenticated;

/* The creator's page: a code opens its creator's bookings, a wrong one is
   counted against the caller (`creator_code_try`), and a caller locked out
   is answered `locked` with the minutes left, the right code included.
   Volatile now: it writes the count. */
create or replace function public.get_creator(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr     creators%rowtype;
  v_id   uuid;
  v_lock integer;
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from creators where id = v_id;
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
          /* The open request's note, whoever made it: the client's through
             their page, the team's through the send-back (2026-09-27). A
             team round sent back before the record held it is in
             `drop_reason`. */
          'change_note', case when o.state = 'changes' then coalesce(
            (select r.note from public.option_reviews r
              where r.option_id = o.id and r.decision = 'changes' and r.undone_at is null
                and r.source = case when coalesce(o.changes_by, 'client') = 'team' then 'team' else 'client' end
              order by r.created_at desc limit 1),
            case when o.changes_by = 'team' then o.drop_reason end) end,
          /* Each placement's post and its numbers, and the period the team
             set to count them over: the creator fills in the link and the
             figures here (2026-09-27). */
          'posts', coalesce((
            select jsonb_agg(jsonb_build_object(
              'platform', pp.platform, 'post_url', pp.post_url,
              'published_at', pp.published_at,
              'measure_from', pp.measure_from, 'measure_to', pp.measure_to,
              'impressions', pp.impressions, 'engagements', pp.engagements,
              'views', pp.views, 'measured_at', pp.measured_at,
              'entered_by', pp.entered_by) order by pp.platform)
            from public.option_posts pp where pp.option_id = o.id), '[]'::jsonb),
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
grant execute on function public.get_creator(text) to anon, authenticated;

create or replace function public.creator_set_profiles(p_code text, p_profiles jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr     public.creators;
  v_id   uuid;
  v_lock integer;
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from public.creators k where k.id = v_id and k.active;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  return public.profiles_replace(cr.id, p_profiles, cr.name, 'creator', 'creator.links_self');
end $$;
grant execute on function public.creator_set_profiles(text, jsonb) to anon, authenticated;

/* A link's preview. A creator's code is counted as the creator's page
   counts it (a locked caller is answered the plain title); the other kinds
   read as before. */
create or replace function public.share_link_preview(p_kind text, p_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_lock integer;
  v_out  jsonb;
begin
  if p_kind = 'creator' then
    if coalesce(p_key, '') !~ '^[A-Za-z0-9]{8}$' then return '{}'::jsonb; end if;
    select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_key) t;
    if v_id is null then return '{}'::jsonb; end if;
    select case when count(*) = 1 then jsonb_strip_nulls(jsonb_build_object('brand', min(c.name), 'title', nullif(btrim(min(k.title)), ''))) end
      into v_out
      from public.creators cr
      join public.campaign_options o on o.creator_id = cr.id
       and o.state in ('confirmed', 'pending_visit', 'pending_draft', 'submitted', 'reviewing', 'changes', 'scheduled', 'posted')
      join public.campaigns k on k.id = o.campaign_id
      join public.clients c on c.id = k.client_id
     where cr.id = v_id and cr.active;
    return coalesce(v_out, '{}'::jsonb);
  end if;
  select case p_kind
    when 'which' then (
      select case
        when exists (select 1 from public.campaigns k where k.access_token = p_key) then jsonb_build_object('kind', 'campaign')
        when exists (select 1 from public.clients c where c.script_key = p_key) then jsonb_build_object('kind', 'script')
      end
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$')
    when 'script' then (
      select jsonb_strip_nulls(jsonb_build_object('brand', c.name))
        from public.clients c
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$'
         and c.script_key = p_key and c.active
         and exists (select 1 from public.video_scripts s where s.client_id = c.id and s.status = 'shared')
       limit 1)
    when 'campaign' then (
      select jsonb_strip_nulls(jsonb_build_object('brand', c.name, 'title', nullif(btrim(k.title), '')))
        from public.campaigns k
        join public.clients c on c.id = k.client_id
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$'
         and k.access_token = p_key
         and coalesce(k.passcode, '') = '' and k.state <> 'draft'
         and coalesce(c.stage, '') <> 'past'
       limit 1)
  end into v_out;
  return coalesce(v_out, '{}'::jsonb);
end $$;
revoke all on function public.share_link_preview(text, text) from public;
grant execute on function public.share_link_preview(text, text) to anon, authenticated;

-- END OF CREATOR CODES COUNTED -----------------------------------------------

select public.functions_tidy();
