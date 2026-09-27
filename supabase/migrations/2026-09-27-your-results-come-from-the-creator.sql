-- ===========================================================================
-- THE CREATOR REPORTS THE RESULTS — the post link and the platform's numbers
-- come from the creator's own page, over a period only the team sets.
-- 2026-09-27. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-09-27: "once approved by client, they can fill
-- in ... the posting link, and data within the period given (this should be
-- in sync with admin portal, one special thing is that the period date to
-- date should be set by the admin only ... So we dont need to go back
-- whatsapp communicate and then come back fill in again"; numbers only, no
-- screenshots; the post link moves the booking to Posted):
--  1. `option_posts` gains the measurement period (`measure_from`,
--     `measure_to`) and who last entered the figures (`entered_by`,
--     `entered_at`). Only the team writes the period: the creator's function
--     never touches it.
--  2. `creator_post_save` takes one placement's link, its publish date and
--     its numbers from the creator's page, once the draft is approved
--     (Scheduled, Posted). The link must be the platform's own. The numbers
--     wait for the period, and are whole and not negative. The first link at
--     Scheduled moves the booking to Posted.
--  3. `get_creator` sends each placement's link, period and numbers.
--  4. A creator's entry is filed as `campaign.results`.
--
-- ROLLBACK
--   drop function if exists public.creator_post_save(text, uuid, text, text, date, bigint, bigint, bigint);
--   drop function if exists public.post_link_ok(text, text);
--   Re-run get_creator from THE REVIEW LOOP REACHES EVERYONE and
--   activity_section from TASKS LINK RECORDS.
--   alter table public.option_posts drop column if exists measure_from,
--     drop column if exists measure_to, drop column if exists entered_by,
--     drop column if exists entered_at;
-- ===========================================================================

alter table public.option_posts add column if not exists measure_from date;
alter table public.option_posts add column if not exists measure_to date;
alter table public.option_posts add column if not exists entered_by text;
alter table public.option_posts add column if not exists entered_at timestamptz;

/* A placement's printed name ("rednote", "Instagram") or an older key, as
   one key. */
create or replace function public.post_platform_key(p text)
returns text
language sql immutable set search_path = public as $$
  select case lower(btrim(coalesce(p, '')))
           when 'rednote' then 'xhs' when 'xiaohongshu' then 'xhs' when 'xhs' then 'xhs'
           when 'instagram' then 'instagram' when 'tiktok' then 'tiktok'
           when 'facebook' then 'facebook'
           else lower(btrim(coalesce(p, ''))) end
$$;

/* The link is the platform's own post, on its own host, and nothing else:
   the client's page opens it as "View post on {platform}". */
create or replace function public.post_link_ok(p_platform text, p_url text)
returns boolean
language plpgsql immutable set search_path = public as $$
declare
  v    text := btrim(coalesce(p_url, ''));
  host text;
begin
  if v = '' or length(v) > 500 or v ~ '\s' or v !~* '^https://' then return false; end if;
  host := lower(substring(v from '^https://([^/?#]+)'));
  if host is null or host ~ '[@:]' then return false; end if;
  host := regexp_replace(host, '^(www|m|vm|vt)\.', '');
  return case public.post_platform_key(p_platform)
    when 'xhs' then host in ('xiaohongshu.com', 'xhslink.com')
    when 'instagram' then host = 'instagram.com'
    when 'tiktok' then host = 'tiktok.com'
    when 'facebook' then host in ('facebook.com', 'fb.watch', 'fb.com')
    else true end;
end $$;

create or replace function public.creator_post_save(
  p_code text, p_option uuid, p_platform text, p_url text, p_published date,
  p_impressions bigint, p_engagements bigint, p_views bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr     creators%rowtype;
  o      campaign_options%rowtype;
  p      option_posts%rowtype;
  v_plat text;
  v_url  text := nullif(btrim(coalesce(p_url, '')), '');
  v_nums boolean := p_impressions is not null or p_engagements is not null or p_views is not null;
  v_live boolean := false;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options where id = p_option and creator_id = cr.id for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if o.state not in ('scheduled', 'posted') then return jsonb_build_object('error', 'closed'); end if;

  -- One of the placements this booking is for, by its printed name.
  select btrim(x) into v_plat
    from unnest(string_to_array(coalesce(o.platforms, ''), ',')) x
   where public.post_platform_key(x) = public.post_platform_key(p_platform)
   limit 1;
  if v_plat is null then return jsonb_build_object('error', 'platform'); end if;
  if v_url is not null and not public.post_link_ok(v_plat, v_url) then
    return jsonb_build_object('error', 'link');
  end if;
  if coalesce(p_impressions, 0) < 0 or coalesce(p_engagements, 0) < 0 or coalesce(p_views, 0) < 0 then
    return jsonb_build_object('error', 'number');
  end if;
  if p_published is not null and (p_published > current_date + 1 or p_published < date '2023-08-14') then
    return jsonb_build_object('error', 'date');
  end if;

  select * into p from option_posts
   where option_id = p_option and public.post_platform_key(platform) = public.post_platform_key(v_plat)
   limit 1;
  if p.id is null then
    insert into option_posts (option_id, platform, window_days)
    values (p_option, v_plat, 7) returning * into p;
  end if;
  -- The numbers are counted over the period the team set, and wait for it.
  if v_nums and (p.measure_from is null or p.measure_to is null) then
    return jsonb_build_object('error', 'period');
  end if;

  update option_posts
     set post_url = coalesce(v_url, post_url),
         published_at = coalesce(p_published, published_at, case when v_url is not null then current_date end),
         impressions = case when v_nums then p_impressions else impressions end,
         engagements = case when v_nums then p_engagements else engagements end,
         views = case when v_nums then p_views else views end,
         measured_at = case when v_nums then current_date else measured_at end,
         entered_by = 'creator', entered_at = now()
   where id = p.id;

  -- The post is out: the booking says so, on the creator's word.
  if o.state = 'scheduled' and v_url is not null then
    update campaign_options set state = 'posted' where id = p_option;
    v_live := true;
  end if;

  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.results', c.title,
         cr.name || ' · ' || v_plat ||
         case when v_url is not null and v_url is distinct from p.post_url then ' · link' else '' end ||
         case when v_nums then ' · ' || coalesce(p_views::text, '—') || ' views, ' ||
              coalesce(p_engagements::text, '—') || ' engagements, ' ||
              coalesce(p_impressions::text, '—') || ' impressions' else '' end ||
         case when v_live then ' · Posted' else '' end
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'posted', v_live);
end $$;
revoke all on function public.creator_post_save(text, uuid, text, text, date, bigint, bigint, bigint) from public;
grant execute on function public.creator_post_save(text, uuid, text, text, date, bigint, bigint, bigint) to anon, authenticated;
grant execute on function public.post_link_ok(text, text) to anon, authenticated;
grant execute on function public.post_platform_key(text) to anon, authenticated;

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

-- END OF THE CREATOR REPORTS THE RESULTS ------------------------------------

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
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
                    'set.task_linked', 'set.task_unlinked',
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
