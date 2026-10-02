-- ===========================================================================
-- HANDBOOK — the company's internal files (the Employee Handbook, SOPs,
-- policies, templates and forms) in one console section, kept private and
-- opened through a link that lasts 60 seconds.
-- 2026-10-01. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner, and activity_section() in
-- THE ACTIVITY RECORD, SECTION BY SECTION; tests/handbook-sql.js compares
-- them.
--
-- WHAT CHANGED
--   1. `handbook_docs` (a title, a category, a summary, an outside link or
--      none, the current version, archived or not) and `handbook_versions`
--      (each file kept: its private path, name, size, type, what changed,
--      who and when). Every colleague on the team reads both (`is_team()`);
--      nothing writes them but the four functions below.
--   2. `handbook_save`, `handbook_add_version`, `handbook_archive`,
--      `handbook_delete`: admins only (`allowed('admin')`), each filed
--      under Handbook in the Activity record. A file is never overwritten:
--      a new version is a new row and a new object, and every earlier one
--      stays readable. Delete takes the title typed back and answers the
--      paths of the files it removed, which the page then takes out of
--      storage.
--   3. Storage, where the project has it: the private bucket `handbook`
--      (50 MB a file, never public). Every colleague reads an object, which
--      the page does only through a signed link of 60 seconds; only an
--      admin adds or removes one. Nothing in the bucket is served by the
--      CDN.
--   4. `activity_section()` files `handbook.*` under Handbook, a part of
--      the Activity record that answers with the record's level unless set.
--
-- ROLLBACK
--   drop function if exists public.handbook_delete(uuid, text),
--     public.handbook_archive(uuid, boolean),
--     public.handbook_add_version(uuid, text, text, bigint, text, text),
--     public.handbook_save(uuid, text, text, text, text);
--   drop table if exists public.handbook_versions, public.handbook_docs;
--   Storage: drop the three policies `handbook_files_*` on storage.objects
--   and empty and delete the bucket in the dashboard. Re-run activity_section
--   from 2026-10-01-activity-reports-tab.sql.
-- ===========================================================================

create table if not exists public.handbook_docs (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  category        text not null default 'handbook',
  summary         text,
  link_url        text,
  current_version integer not null default 0,
  archived_at     timestamptz,
  created_at      timestamptz not null default now(),
  created_by      text,
  updated_at      timestamptz not null default now(),
  constraint handbook_docs_category check (category in ('handbook', 'sop', 'policy', 'template', 'other')),
  constraint handbook_docs_link check (link_url is null or link_url ~ '^https://')
);
create table if not exists public.handbook_versions (
  id          uuid primary key default gen_random_uuid(),
  doc_id      uuid not null references public.handbook_docs(id) on delete cascade,
  version_no  integer not null,
  file_path   text not null,
  file_name   text not null,
  file_size   bigint,
  mime        text,
  note        text,
  created_at  timestamptz not null default now(),
  created_by  text,
  unique (doc_id, version_no)
);
create index if not exists handbook_versions_doc_idx on public.handbook_versions (doc_id, version_no desc);

alter table public.handbook_docs enable row level security;
alter table public.handbook_versions enable row level security;
revoke all on public.handbook_docs from anon;
revoke all on public.handbook_versions from anon;
drop policy if exists handbook_docs_read on public.handbook_docs;
create policy handbook_docs_read on public.handbook_docs for select to authenticated using (public.is_team());
drop policy if exists handbook_versions_read on public.handbook_versions;
create policy handbook_versions_read on public.handbook_versions for select to authenticated using (public.is_team());

create or replace function public.handbook_save(p_id uuid, p_title text, p_category text, p_summary text, p_link text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_title text := btrim(coalesce(p_title, ''));
  v_link text := nullif(btrim(coalesce(p_link, '')), '');
  v_changed text;
  d public.handbook_docs;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  if v_title = '' then return jsonb_build_object('error', 'no-title'); end if;
  if coalesce(p_category, '') not in ('handbook', 'sop', 'policy', 'template', 'other') then
    return jsonb_build_object('error', 'bad-category');
  end if;
  if v_link is not null and v_link !~ '^https://' then return jsonb_build_object('error', 'bad-link'); end if;
  select * into d from public.handbook_docs h where h.id = p_id;
  if d.id is null then
    insert into public.handbook_docs (id, title, category, summary, link_url, created_by)
    values (coalesce(p_id, gen_random_uuid()), v_title, p_category, nullif(btrim(coalesce(p_summary, '')), ''), v_link, who)
    returning * into d;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'handbook.added', d.title, case d.category when 'handbook' then 'Employee Handbook'
      when 'sop' then 'SOPs' when 'policy' then 'Policies' when 'template' then 'Templates and forms' else 'Other' end);
  else
    v_changed := concat_ws(', ',
      case when d.title is distinct from v_title then 'title' end,
      case when d.category is distinct from p_category then 'category' end,
      case when d.summary is distinct from nullif(btrim(coalesce(p_summary, '')), '') then 'summary' end,
      case when d.link_url is distinct from v_link then 'link' end);
    if v_changed = '' then return jsonb_build_object('ok', true, 'id', d.id, 'changed', false); end if;
    update public.handbook_docs h
       set title = v_title, category = p_category,
           summary = nullif(btrim(coalesce(p_summary, '')), ''), link_url = v_link, updated_at = now()
     where h.id = p_id returning * into d;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'handbook.edited', d.title, upper(left(v_changed, 1)) || substr(v_changed, 2));
  end if;
  return jsonb_build_object('ok', true, 'id', d.id);
end $$;

create or replace function public.handbook_add_version(p_doc uuid, p_path text, p_name text, p_size bigint, p_mime text, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  d public.handbook_docs;
  n integer;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.handbook_docs h where h.id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(p_path, '') = '' or position(p_doc::text || '/' in p_path) <> 1 then
    return jsonb_build_object('error', 'bad-path');
  end if;
  if btrim(coalesce(p_name, '')) = '' then return jsonb_build_object('error', 'no-file'); end if;
  select coalesce(max(v.version_no), 0) + 1 into n from public.handbook_versions v where v.doc_id = p_doc;
  insert into public.handbook_versions (doc_id, version_no, file_path, file_name, file_size, mime, note, created_by)
  values (p_doc, n, p_path, btrim(p_name), p_size, p_mime, nullif(btrim(coalesce(p_note, '')), ''), who);
  update public.handbook_docs h set current_version = n, updated_at = now() where h.id = p_doc;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'handbook.version', d.title,
          concat_ws(' · ', 'Version ' || n, btrim(p_name), nullif(btrim(coalesce(p_note, '')), '')));
  return jsonb_build_object('ok', true, 'version', n);
end $$;

create or replace function public.handbook_archive(p_id uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  d public.handbook_docs;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  update public.handbook_docs h
     set archived_at = case when p_on then coalesce(h.archived_at, now()) end
   where h.id = p_id returning * into d;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, case when p_on then 'handbook.archived' else 'handbook.restored' end, d.title, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.handbook_delete(p_id uuid, p_title text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  d public.handbook_docs;
  v_paths jsonb;
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.handbook_docs h where h.id = p_id;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if lower(btrim(coalesce(p_title, ''))) <> lower(btrim(d.title)) then
    return jsonb_build_object('error', 'mismatch');
  end if;
  select coalesce(jsonb_agg(v.file_path order by v.version_no), '[]'::jsonb) into v_paths
    from public.handbook_versions v where v.doc_id = p_id;
  delete from public.handbook_docs h where h.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'handbook.deleted', d.title,
          jsonb_array_length(v_paths) || case when jsonb_array_length(v_paths) = 1 then ' version' else ' versions' end);
  return jsonb_build_object('ok', true, 'paths', v_paths);
end $$;

revoke all on function public.handbook_save(uuid, text, text, text, text) from public, anon;
revoke all on function public.handbook_add_version(uuid, text, text, bigint, text, text) from public, anon;
revoke all on function public.handbook_archive(uuid, boolean) from public, anon;
revoke all on function public.handbook_delete(uuid, text) from public, anon;
grant execute on function public.handbook_save(uuid, text, text, text, text) to authenticated;
grant execute on function public.handbook_add_version(uuid, text, text, bigint, text, text) to authenticated;
grant execute on function public.handbook_archive(uuid, boolean) to authenticated;
grant execute on function public.handbook_delete(uuid, text) to authenticated;

/* The private bucket and who may touch it, where the project has storage. */
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'storage') then
    raise notice 'handbook: no storage schema here, so no bucket or policy was written.';
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit)
  values ('handbook', 'handbook', false, 52428800)
  on conflict (id) do update set public = false, file_size_limit = 52428800;
  execute 'drop policy if exists handbook_files_read on storage.objects';
  execute $p$create policy handbook_files_read on storage.objects for select to authenticated
    using (bucket_id = 'handbook' and public.is_team())$p$;
  execute 'drop policy if exists handbook_files_add on storage.objects';
  execute $p$create policy handbook_files_add on storage.objects for insert to authenticated
    with check (bucket_id = 'handbook' and public.allowed('admin'))$p$;
  execute 'drop policy if exists handbook_files_remove on storage.objects';
  execute $p$create policy handbook_files_remove on storage.objects for delete to authenticated
    using (bucket_id = 'handbook' and public.allowed('admin'))$p$;
end $$;

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
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.returned', 'report.revised', 'report.saved',
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

-- END OF HANDBOOK -----------------------------------------------------------
