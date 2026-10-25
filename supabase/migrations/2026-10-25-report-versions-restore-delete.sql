-- ===========================================================================
-- REPORT VERSIONS RESTORED AND DELETED — an earlier version of a report is
-- made the draft again, and a version no longer on the client portal is
-- deleted (2026-10-25)
-- ===========================================================================
-- WHY (the user, 2026-10-25: a client asked for the September report again
-- with new figures; "is it still possible to call back v1", then "yes please
-- and also delete for each version"): Revise works on the report's figures
-- in place, so an earlier version lived only in its kept copy, read as a
-- PDF and never brought back.
--
-- WHAT IT CHANGES
--   * `sm_report_version_restore(p_version)` (Reports at Work, the client
--     in scope): the report's figures, accounts, posts, ads and commentary
--     are put back as that version kept them (its snapshot), as a draft; a
--     published report becomes the next version's draft as Revise makes
--     it, a draft stays its own version; a report in review or confirmed
--     is refused (`in-review`). Filed `report.revised` · Restored from
--     version n. The client portal keeps what it shows until the draft is
--     published.
--   * `sm_report_version_delete(p_version)` (Reports Full Access, the
--     client in scope): removes a version and its kept copy's row; the
--     version on the client portal (the newest not withdrawn) is refused
--     (`on-portal`): publish a newer one or unpublish first. Filed
--     `report.version_deleted`. The PDF kept in S3 stays (nothing deletes
--     from S3).
--   * `activity_section()` files `report.version_deleted` under Reports.
--
-- ORDER: this file, then the pages. A page served before it reads no
-- Restore or Delete (the functions are missing; the sheet says the
-- database needs an update). Its bodies hold `delete`, so it is run in the
-- SQL Editor. Safe to run twice. Mirrored byte for byte in
-- supabase/schema.sql under the same banner.
--
-- ROLLBACK: drop function public.sm_report_version_restore(uuid);
-- drop function public.sm_report_version_delete(uuid); run the
-- activity_section() of CREATORS OFFERED ARE FILED again.
-- ===========================================================================

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
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('wa.sent', 'wa.template') then 'whatsapp'
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

/* An earlier version back as the draft: its snapshot's rows written over
   the report's own. A key a snapshot from before a column was added lacks
   takes the column's default. */
create or replace function public.sm_report_version_restore(p_version uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.sm_report_versions;
  r public.sm_reports;
  s jsonb;
  head jsonb;
  nv integer;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.sm_report_versions where id = p_version;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.sm_reports where id = v.report_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if r.status not in ('draft', 'published') then return jsonb_build_object('error', 'in-review', 'status', r.status); end if;
  s := v.snapshot;
  head := coalesce(s -> 'report', '{}'::jsonb);
  nv := case when r.status = 'published' then r.version_no + 1 else r.version_no end;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports
     set status = 'draft', version_no = nv, return_note = null,
         submitted_by = null, submitted_at = null, confirmed_by = null, confirmed_at = null,
         headline = head ->> 'headline', intro = head ->> 'intro',
         insights = coalesce(head -> 'insights', '{}'::jsonb),
         rank_metric = coalesce(head ->> 'rank_metric', r.rank_metric),
         first_month = coalesce((head ->> 'first_month')::boolean, r.first_month),
         ads_totals = coalesce(nullif(head -> 'ads_totals', 'null'::jsonb), '{}'::jsonb)
   where id = r.id;
  delete from public.sm_report_posts where report_id = r.id;
  delete from public.sm_report_platforms where report_id = r.id;
  delete from public.sm_report_ads where report_id = r.id;
  insert into public.sm_report_platforms
  select (jsonb_populate_record(null::public.sm_report_platforms,
           jsonb_build_object('id', gen_random_uuid(), 'position', 0, 'metrics', jsonb_build_array('views', 'engagements'))
           || e.j || jsonb_build_object('report_id', r.id, 'created_at', now() + e.n * interval '1 microsecond'))).*
    from jsonb_array_elements(coalesce(s -> 'platforms', '[]'::jsonb)) with ordinality e(j, n);
  insert into public.sm_report_posts
  select (jsonb_populate_record(null::public.sm_report_posts,
           jsonb_build_object('id', gen_random_uuid(), 'position', 0)
           || (e.j - 'thumb_url')
           || jsonb_build_object('report_id', r.id, 'thumb_data', e.j -> 'thumb_url',
                                 'created_at', now() + e.n * interval '1 microsecond'))).*
    from jsonb_array_elements(coalesce(s -> 'posts', '[]'::jsonb)) with ordinality e(j, n);
  insert into public.sm_report_ads
  select (jsonb_populate_record(null::public.sm_report_ads,
           jsonb_build_object('id', gen_random_uuid(), 'position', 0, 'objective', 'awareness',
                              'age', '{}'::jsonb, 'retention', '{}'::jsonb, 'platform', 'meta')
           || (e.j - 'thumb_url')
           || jsonb_build_object('report_id', r.id, 'thumb_data', e.j -> 'thumb_url',
                                 'created_at', now() + e.n * interval '1 microsecond'))).*
    from jsonb_array_elements(coalesce(s -> 'ads', '[]'::jsonb)) with ordinality e(j, n);
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(r.id, 'report.revised', 'Restored from version ' || v.version_no);
  return jsonb_build_object('ok', true, 'status', 'draft', 'version_no', nv, 'from', v.version_no);
end $$;
revoke all on function public.sm_report_version_restore(uuid) from public, anon;
grant execute on function public.sm_report_version_restore(uuid) to authenticated;

/* A version no longer on the client portal, deleted. */
create or replace function public.sm_report_version_delete(p_version uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.sm_report_versions;
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.sm_report_versions where id = p_version;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.sm_reports where id = v.report_id for update;
  if not public.client_seen(r.client_id, 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if v.withdrawn_at is null and not exists (
       select 1 from public.sm_report_versions x
        where x.report_id = v.report_id and x.withdrawn_at is null and x.version_no > v.version_no) then
    return jsonb_build_object('error', 'on-portal');
  end if;
  delete from public.sm_report_versions where id = p_version;
  perform public.sm_report_log(r.id, 'report.version_deleted', 'Version ' || v.version_no);
  return jsonb_build_object('ok', true, 'version_no', v.version_no);
end $$;
revoke all on function public.sm_report_version_delete(uuid) from public, anon;
grant execute on function public.sm_report_version_delete(uuid) to authenticated;

-- END OF REPORT VERSIONS RESTORED AND DELETED --------------------------------

select public.functions_tidy();
