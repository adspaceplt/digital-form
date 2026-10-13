-- ===========================================================================
-- BILLING CONTACT AND REMOVED SERVICES — the billing contact follows the main
-- contact unless somebody else is chosen, and a removed service line no
-- letter quoted can be deleted.
-- 2026-10-13. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-13: a client's main contact changed and
-- the next letter still named the old one, "by default billing contact
-- fills main contact"; and that a removed service line should go for good)
--   1. An empty `clients.bill_contact_id` is the main contact: the Billing
--      sheet saves it empty while the main contact is chosen, and
--      `issue_letter` already answers Attn that way. Trigger
--      `client_contacts_bill_follows`: a contact that stops being the main
--      contact, or is removed, lets go of the billing contact it held, so
--      the next letter names the main contact. A billing contact chosen
--      apart from the main contact is left alone. Nothing issued changes:
--      a letter keeps the contact it was issued to.
--   2. A removed service line is deleted at Clients: Services Full Access
--      (the table's own policy, unchanged), filed `client.service_deleted`;
--      a line a Letter of Offer quoted stays (the letter's foreign key
--      restricts it). `activity_section()` names the new tag under Clients.
--
-- ORDER
--   Pages first, then this file. A page from before files nothing new.
--
-- ROLLBACK
--   Take the trigger client_contacts_bill_follows off public.client_contacts
--   in the SQL Editor; the function may stay. activity_section from the band
--   before this one runs again.
-- ===========================================================================

create or replace function public.client_contacts_bill_follows()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (old.is_primary and not new.is_primary)
     or (old.archived_at is null and new.archived_at is not null) then
    update public.clients c set bill_contact_id = null
     where c.id = new.client_id and c.bill_contact_id = new.id;
  end if;
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.client_contacts_bill_follows() from public, anon, authenticated;

create or replace trigger client_contacts_bill_follows
  after update of is_primary, archived_at on public.client_contacts
  for each row execute function public.client_contacts_bill_follows();

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.file_deleted', 'campaign.file_hidden',
                    'campaign.file_shown', 'campaign.qc',
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
                    'client.service_deleted', 'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('wa.sent', 'wa.template') then 'whatsapp'
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
                    'set.created', 'set.deleted', 'set.month', 'set.published', 'set.renamed',
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

-- END OF BILLING CONTACT AND REMOVED SERVICES -------------------------------

select public.functions_tidy();
