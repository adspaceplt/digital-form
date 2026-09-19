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
                    'campaign.file_added', 'campaign.invoice', 'campaign.invoice_file',
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
    when action in ('ops.deleted') then 'ops'
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
