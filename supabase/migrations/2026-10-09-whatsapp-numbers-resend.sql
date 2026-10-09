-- ===========================================================================
-- WHATSAPP NUMBERS AND RESEND — numbers read as the team types them, and a
-- creator's booking sent again by hand.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-09: "malaysia numbers could be 0123456789
-- or 01234567890, singapore numbers 12345678"; "proceed with your
-- recommendations")
--   1. `wa_number`: a leading 0 is Malaysia (60 for the 0); any other eight
--      digits are Singapore (65); nine or ten digits starting 1 are a
--      Malaysian mobile typed without its 0 (60); a number already carrying
--      its country code is kept. The market no longer decides.
--   2. `wa_creator_send(p_option)`: Send on WhatsApp in a booking's ⋯ (a
--      creator booked: confirmed or later, not withdrawn or replaced), the
--      creator template again with the creator's code for the link button,
--      queued as the confirmation is. Its own part, `campaigns.whatsapp` at
--      Work, following Creator Campaigns unless a group shuts it; the
--      campaign's client within the colleague's scope. Filed
--      `campaign.whatsapp` under the campaign (Creator Campaigns in the
--      activity map, restated whole below).
--
-- ROLLBACK
--   Restate wa_number from 2026-10-09-whatsapp-creator-link.sql and the
--   activity map from 2026-10-09-whatsapp.sql; revoke wa_creator_send from
--   authenticated.
-- ===========================================================================

/* A WhatsApp number in its international form, or null. */
create or replace function public.wa_number(p_raw text, p_market text default 'MY')
returns text
language sql immutable set search_path = public as $$
  select case
    when p_raw is null or btrim(p_raw) like '@%' then null
    else (select case
            when length(d) < 8 or length(d) > 15 then null
            when d like '0%' then '60' || substr(d, 2)
            when length(d) = 8 then '65' || d
            when length(d) in (9, 10) and d like '1%' then '60' || d
            else d end
          from (select regexp_replace(p_raw, '[^0-9]', '', 'g') as d) x)
  end
$$;

revoke all on function public.wa_number(text, text) from public, anon, authenticated;

/* A creator's booking sent again on WhatsApp, by hand. */
create or replace function public.wa_creator_send(p_option uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  o    public.campaign_options;
  c    public.campaigns;
  k    public.creators;
  t    public.wa_templates;
  v_n  text;
begin
  if me.id is null or not public.allowed('campaigns.whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.campaigns x where x.id = o.campaign_id;
  if c.id is null or (c.client_id is not null and not public.client_seen(c.client_id, 'work')) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if o.state in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced') then
    return jsonb_build_object('error', 'not-booked');
  end if;
  select * into t from public.wa_templates x where x.purpose = 'creator' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  select * into k from public.creators x where x.id = o.creator_id;
  v_n := public.wa_number(k.whatsapp, 'MY');
  if v_n is null then return jsonb_build_object('error', 'no-number'); end if;
  perform public.wa_enqueue('creator', v_n, k.name,
    jsonb_build_array(split_part(btrim(k.name), ' ', 1), coalesce(nullif(btrim(c.title), ''), 'Your campaign')),
    'option', o.id, c.client_id, k.access_code);
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'campaign.whatsapp', coalesce(c.title, ''), k.name || ' · Booking sent on WhatsApp');
  return jsonb_build_object('ok', true, 'to', k.name);
end $$;

revoke all on function public.wa_creator_send(uuid) from public, anon;
grant execute on function public.wa_creator_send(uuid) to authenticated;

-- A creator's booking sent on WhatsApp files under Creator Campaigns
-- (js/admin.js ACTION_LABEL 'campaign.whatsapp').
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
                    'campaign.unkeyed', 'campaign.whatsapp', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch', 'wa.sent',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished') then 'reports'
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
                    'review.unconfirmed',
                    'set.created', 'set.deleted', 'set.published', 'set.renamed',
                    'set.task_linked', 'set.task_unlinked',
                    'set.withdrawn') then 'review'
    when action in ('script.approved', 'script.changes', 'script.created', 'script.deleted',
                    'script.link', 'script.saved', 'script.shared', 'script.shot',
                    'script.unshared') then 'scripts'
    when action in ('handbook.added', 'handbook.archived', 'handbook.deleted',
                    'handbook.edited', 'handbook.restored', 'handbook.version') then 'handbook'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

-- END OF WHATSAPP NUMBERS AND RESEND ------------------------------------------

select public.functions_tidy();
