-- NEW EMAIL, THE SQL EDITOR PART -----------------------------------------------
-- 2026-11-04: what the connector holds for a word it cannot show (CLAUDE.md
-- §3), run in the SQL Editor once NEW EMAIL is applied: email.sent named under
-- Messages, a saved email template deleted (team.settings, its name typed
-- back on the page; an email already sent keeps its words), and the three
-- ways of filing an invoice email that bukku-sync v26 no longer calls
-- (invoice_mail_begin's thirteen-argument form is the one).
--
-- Rollback: restore activity_section from CLIENT DOCUMENT EMAILS; revoke and
-- remove email_template_delete; restore the three from INVOICES SENT BY EMAIL
-- and INVOICE RECIPIENTS CHOSEN.

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
                    'campaign.offered', 'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.unoffered', 'campaign.whatsapp', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.quotation', 'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_deleted', 'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.added', 'request.changed', 'request.deleted', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('wa.sent', 'wa.template', 'email.sent') then 'whatsapp'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished', 'report.version_deleted') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('supplier.added', 'supplier.approved', 'supplier.deleted', 'supplier.edited') then 'suppliers'
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
                    'service.off', 'service.on', 'service.published') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

create or replace function public.email_template_delete(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  t  public.email_templates;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.email_templates x where x.id = p_id for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from public.email_templates x where x.id = t.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Email templates', 'Deleted: ' || t.name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.email_template_delete(uuid) from public, anon;
grant execute on function public.email_template_delete(uuid) to authenticated;

drop function if exists public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean);
drop function if exists public.invoice_send_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean);
drop function if exists public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean);

-- END OF NEW EMAIL, THE SQL EDITOR PART

select public.functions_tidy();
