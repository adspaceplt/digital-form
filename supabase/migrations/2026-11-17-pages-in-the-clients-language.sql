-- 2026-11-17 Pages open in the client's language.
-- The user, 2026-11-17: a contact prefers English or 中文 alone (no Malay
-- portal), and a client's pages open in that language until the browser
-- holds a choice of its own. A contact's Malay becomes English; the client
-- portal answers the signed-in contact's own language (get_portal `me.lang`),
-- and the review, selection and Video Scripts links their client's primary
-- contact's (`lang`, 'en' or 'zh', nothing else about the contact).
-- Safe to run twice. Rollback: drop the check, drop client_lang after
-- restating the four functions without it (the sections before this one).

-- PAGES IN THE CLIENT'S LANGUAGE ---------------------------------------------
update public.client_contacts set lang = 'en' where lang is not null and lang not in ('en', 'zh');
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_contacts_lang_check'
                   and conrelid = 'public.client_contacts'::regclass) then
    alter table public.client_contacts add constraint client_contacts_lang_check
      check (lang is null or lang in ('en', 'zh'));
  end if;
end $$;

-- The language a client's pages open in: its primary contact's, else the
-- first live contact's, English unless that is 中文. Only other functions ask.
create or replace function public.client_lang(p_client uuid)
returns text
language sql stable security definer set search_path = public as $$
  select case when (select k.lang from public.client_contacts k
                     where k.client_id = p_client and k.archived_at is null
                     order by k.is_primary desc, k.created_at limit 1) = 'zh'
              then 'zh' else 'en' end;
$$;
revoke all on function public.client_lang(uuid) from public, anon, authenticated;

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
      'bill_market', public.client_bill_market(cl.market, cl.bill_sgd),
      'sst_applies', coalesce(cl.sst_applies, true), 'stage', cl.stage, 'owner', cl.owner,
      'industry', cl.industry, 'website', cl.website, 'logo_url', cl.logo_url),
    'me', jsonb_build_object('id', me.id, 'name', me.name, 'email', me.email,
      'lang', case when me.lang = 'zh' then 'zh' else 'en' end),
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
                    'reviewer',   case when r.source = 'team' then null else r.reviewer end,
                    'by_team',    r.source = 'team',
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
  ) || jsonb_build_object('lang', public.client_lang(v_client.id));
end $$;

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
  -- nobody knows, so the page says the link is not recognised. A completed
  -- campaign stays readable for its results, read only (the user,
  -- 2026-10-18: a client moved to Past before reading them lost the link);
  -- every write on the link still refuses a Past client.
  if cl.stage = 'past' and c.state <> 'completed' then
    return jsonb_build_object('error', 'not-found');
  end if;

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
      -- A Past client's completed campaign offers nothing to choose.
      'backups_open', coalesce(c.backups_open, false) and cl.stage <> 'past',
      'selection_closed', c.selection_closed_at is not null or cl.stage = 'past',
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
      'market', coalesce(cl.market, 'MY'), 'bill_market', public.client_bill_market(cl.market, cl.bill_sgd), 'sst_applies', coalesce(cl.sst_applies, true)),
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
  ) || jsonb_build_object('lang', public.client_lang(cl.id));
end $$;

create or replace function public.get_scripts(p_token text)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  v_cl public.clients;
begin
  select * into v_cl from public.clients c
   where c.script_key = p_token and p_token is not null and c.active;
  if v_cl.id is null then return jsonb_build_object('error', 'not_found'); end if;
  return jsonb_build_object(
    'client', jsonb_build_object('name', v_cl.name, 'logo_url', v_cl.logo_url),
    'scripts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'code', s.code, 'period', s.period, 'kind', s.kind,
               'title', s.title, 'reference_url', s.reference_url, 'platform', s.platform,
               'language', s.language, 'shoot_on', s.shoot_on, 'shoot_time', s.shoot_time,
               'venue', s.venue, 'duration_minutes', s.duration_minutes, 'cast_names', s.cast_names,
               'aspect', s.aspect, 'length_seconds', s.length_seconds, 'plan', s.plan,
               'context', s.context, 'vo', s.vo, 'remarks', s.remarks,
               'shared_at', s.shared_at, 'updated_at', s.updated_at,
               'scenes', coalesce((select jsonb_agg(jsonb_build_object('id', sc.id, 'position', sc.position,
                                                     'visual', sc.visual, 'line', sc.line,
                                                     't_from', sc.t_from, 't_to', sc.t_to,
                                                     'shot_size', sc.shot_size, 'angle', sc.angle,
                                                     'camera_move', sc.camera_move, 'on_screen', sc.on_screen,
                                                     'sound', sc.sound)
                                                     order by sc.position)
                                     from public.video_script_scenes sc where sc.script_id = s.id), '[]'::jsonb))
             order by s.period desc, s.seq)
        from public.video_scripts s
       where s.client_id = v_cl.id and s.status = 'shared'), '[]'::jsonb),
    'lang', public.client_lang(v_cl.id));
end $$;

-- END OF PAGES IN THE CLIENT'S LANGUAGE --------------------------------------

select public.functions_tidy();
