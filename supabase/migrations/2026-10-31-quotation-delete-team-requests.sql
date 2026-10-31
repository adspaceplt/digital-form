-- ===========================================================================
-- QUOTATIONS DELETED AND REQUESTS RECORDED BY THE TEAM — a removed quotation
-- is deleted for good, and the team records and deletes a client's request
-- (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31, items 3 and 4 of the Services tab review): a
-- quotation could be removed and restored but never deleted, against the
-- rule that whatever a person adds they can delete where nothing names it;
-- and a client's request came only from the client portal, so a request
-- made on a call or in a chat could not be written down, nor a request
-- filed by mistake taken away.
--
-- WHAT CHANGED
--   * `quotation_refs_kept` (ref, deleted_at, deleted_by; RLS on, no policy,
--     no grant): the reference of every quotation deleted, so it is never
--     issued again.
--   * `quote_ref` counts the references kept beside the quotations standing.
--   * `quotation_delete(p_id, p_ref)` (Clients: Quotations Full Access, the
--     client in scope at Manage): a removed quotation alone (`not-removed`),
--     its reference typed back (`bad-ref`), refused while a service line
--     holds it (`lines`, with the count), a letter quotes it (`letter`, with
--     its number) or a quotation revises it (`revised`, with its
--     reference); filed `client.quotation` "{ref} deleted".
--   * `client_requests.recorded_by`: the colleague who recorded a request
--     for the client (empty for a request the client sent).
--   * `client_request_add(p_client, p_kind, p_service, p_contact, p_note,
--     p_idem)` (Clients: Requests at Work, the client in scope at Work): the
--     portal's own checks (`bad-kind`, `too-long`, `no-service` for a kind
--     that needs a confirmed line, `note-required` unless Cancel), a contact
--     of the client or none (`bad-contact`); the same key twice is one
--     request (`again`); filed `request.added`.
--   * `client_request_delete(p_id)` (Clients: Requests Full Access, the
--     client in scope at Manage); filed `request.deleted`.
--   * `activity_section()` files `request.added` and `request.deleted`
--     under Clients.
--
-- ORDER: this file, then the pages. A page served before never asks the
-- new functions; a page served after on a database without them reads
-- "This needs a database update". The bodies of the two delete functions
-- hold `delete`, so the connector may hold them for the SQL Editor. Safe to
-- run twice.
--
-- ROLLBACK: drop function public.quotation_delete(uuid, text);
-- drop function public.client_request_add(uuid, text, uuid, uuid, text, text);
-- drop function public.client_request_delete(uuid); run QUOTATIONS' quote_ref
-- and REPORT VERSIONS RESTORED AND DELETED's activity_section() again. The
-- table and the column may stay (unread).
-- ===========================================================================

-- QUOTATIONS DELETED AND REQUESTS RECORDED BY THE TEAM ----------------------

create table if not exists public.quotation_refs_kept (
  ref        text primary key,
  deleted_at timestamptz not null default now(),
  deleted_by text
);
alter table public.quotation_refs_kept enable row level security;
revoke all on table public.quotation_refs_kept from public, anon, authenticated;

create or replace function public.quote_ref(p_brand text, p_at timestamptz)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v_z text := upper(left(regexp_replace(coalesce(p_brand, ''), '[^A-Za-z]', '', 'g'), 1));
  v_head text;
  v_n int;
begin
  if v_z = '' then v_z := 'X'; end if;
  v_head := 'ADP/QT' || to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'YYMM') || '-' || v_z;
  perform pg_advisory_xact_lock(hashtext('quote_ref:' || v_head));
  -- A deleted quotation's reference is kept, so it is never issued again.
  select coalesce(max(substr(x.ref, length(v_head) + 1)::int), 0) + 1 into v_n
    from (select q.ref from public.quotations q
          union all
          select k.ref from public.quotation_refs_kept k) x
   where x.ref like v_head || '%' and substr(x.ref, length(v_head) + 1) ~ '^[0-9]+$';
  return v_head || lpad(v_n::text, 2, '0');
end $$;
revoke all on function public.quote_ref(text, timestamptz) from public, anon, authenticated;

create or replace function public.quotation_delete(p_id uuid, p_ref text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_n int;
  v_doc text;
  v_by text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'manage') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.removed_at is null then return jsonb_build_object('error', 'not-removed'); end if;
  if btrim(coalesce(p_ref, '')) <> v_q.ref then return jsonb_build_object('error', 'bad-ref'); end if;
  select count(*) into v_n from public.client_services s where s.quotation_id = v_q.id;
  if v_n > 0 then return jsonb_build_object('error', 'lines', 'count', v_n); end if;
  select d.number into v_doc from public.client_documents d
   where d.lines @> jsonb_build_array(jsonb_build_object('quotation_id', v_q.id::text))
   order by d.created_at limit 1;
  if v_doc is not null then return jsonb_build_object('error', 'letter', 'number', v_doc); end if;
  select x.ref into v_by from public.quotations x where x.replaces = v_q.id order by x.issued_at limit 1;
  if v_by is not null then return jsonb_build_object('error', 'revised', 'ref', v_by); end if;
  insert into public.quotation_refs_kept (ref, deleted_by) values (v_q.ref, me.name)
  on conflict (ref) do nothing;
  delete from public.quotations where id = v_q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' deleted');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_delete(uuid, text) from public, anon;
grant execute on function public.quotation_delete(uuid, text) to authenticated;

alter table public.client_requests add column if not exists recorded_by text;

create or replace function public.client_request_word(p_kind text)
returns text
language sql immutable set search_path = public as $$
  select case p_kind when 'upgrade' then 'Upgrade' when 'downgrade' then 'Downgrade'
                     when 'cancel' then 'Cancel' when 'details' then 'Change of details' else p_kind end;
$$;
revoke all on function public.client_request_word(text) from public, anon, authenticated;

create or replace function public.client_request_add(p_client uuid, p_kind text, p_service uuid,
  p_contact uuid, p_note text, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  cl public.clients;
  ct public.client_contacts;
  sv public.client_services;
  rid uuid;
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
begin
  if me.id is null or not public.allowed('clients.requests', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into cl from public.clients where id = p_client;
  if cl.id is null or not public.client_scope_ok('client', cl.id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- The same request again (a reply lost on the way): the one already filed.
  if v_idem is not null then
    select r.id into rid from public.client_requests r where r.client_id = cl.id and r.idem = v_idem;
    if rid is not null then return jsonb_build_object('ok', true, 'id', rid, 'again', true); end if;
  end if;
  if p_kind is null or p_kind not in ('upgrade', 'downgrade', 'cancel', 'details') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if length(coalesce(p_note, '')) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  if p_kind <> 'details' then
    select * into sv from public.client_services
     where id = p_service and client_id = cl.id and archived_at is null and state = 'confirmed';
    if sv.id is null then return jsonb_build_object('error', 'no-service'); end if;
  end if;
  if p_kind <> 'cancel' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note-required');
  end if;
  if p_contact is not null then
    select * into ct from public.client_contacts
     where id = p_contact and client_id = cl.id and archived_at is null;
    if ct.id is null then return jsonb_build_object('error', 'bad-contact'); end if;
  end if;
  insert into public.client_requests (client_id, contact_id, contact_name, kind, service_id, service_label,
                                      note, idem, recorded_by)
  values (cl.id, ct.id, ct.name, p_kind, sv.id, sv.label, nullif(btrim(p_note), ''), v_idem, me.name)
  on conflict (client_id, idem) where idem is not null do nothing
  returning id into rid;
  if rid is null then
    select r.id into rid from public.client_requests r where r.client_id = cl.id and r.idem = v_idem;
    return jsonb_build_object('ok', true, 'id', rid, 'again', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'request.added', cl.name,
          public.client_request_word(p_kind) || coalesce(' · ' || sv.label, '') ||
          coalesce(' · for ' || ct.name, ''));
  return jsonb_build_object('ok', true, 'id', rid);
end $$;
revoke all on function public.client_request_add(uuid, text, uuid, uuid, text, text) from public, anon;
grant execute on function public.client_request_add(uuid, text, uuid, uuid, text, text) to authenticated;

create or replace function public.client_request_delete(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r  public.client_requests;
  v_name text;
begin
  if me.id is null or not public.allowed('clients.requests', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.client_requests where id = p_id for update;
  if r.id is null or not public.client_scope_ok('client', r.client_id, 'manage') then
    return jsonb_build_object('error', 'not-found');
  end if;
  select c.name into v_name from public.clients c where c.id = r.client_id;
  delete from public.client_requests where id = r.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'request.deleted', v_name,
          public.client_request_word(r.kind) || coalesce(' · ' || r.service_label, '') ||
          ' · ' || public.register_day((r.created_at at time zone 'Asia/Kuala_Lumpur')::date));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_request_delete(uuid) from public, anon;
grant execute on function public.client_request_delete(uuid) to authenticated;

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

-- END OF QUOTATIONS DELETED AND REQUESTS RECORDED BY THE TEAM ---------------

select public.functions_tidy();
