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


-- The record files a deleted month under My Work.
-- Identical to activity_section in supabase/schema.sql.
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
