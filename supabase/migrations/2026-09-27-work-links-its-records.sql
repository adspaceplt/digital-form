-- ===========================================================================
-- TASKS LINK RECORDS — a task names the Creator Campaign or content set it
-- is for, and that record lists the tasks that name it.
-- 2026-09-27. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT CHANGED (the user, 2026-09-27: "for files and links is it possible to
-- add one more inside, link to which creator campaigns or content reviews
-- etc. it works like a backlinks kind"):
--  1. A link on a task may name a record instead of an address: `ref_type`
--     (campaign, set) and `ref_id`, kind `record`. The label is the record's
--     title when it was linked and the address is its console route; the
--     page reads the title again when it draws the link.
--  2. `ops_link_record` links one, at My Work's Work level, only a record of
--     the task's own client and only once while the link stands. Removing
--     it is `ops_set_link_archived`, with its Undo, as for any link.
--  3. Both sides are filed: the task's own log (Link added, removed,
--     restored), and the Activity record under the campaign
--     (`campaign.task_linked`, `campaign.task_unlinked`) or the set
--     (`set.task_linked`, `set.task_unlinked`).
--  4. `ops_record_tasks` is the backlink list: the tasks linking a record
--     that the caller may see, with the stage, owner and final date. It
--     answers only a person who may read the record's own section.
--  5. `ops_update_link` refuses a record link (`record-link`): a record is
--     unlinked and linked again, never retyped as an address.
--
-- ROLLBACK
--   drop function if exists public.ops_link_record(uuid, text, uuid, integer);
--   drop function if exists public.ops_record_tasks(text, uuid);
--   Re-run ops_set_link_archived (operations phase 2) and ops_update_link
--   (operations phase 4) from their canonical sections above, and
--   activity_section from 2026-09-27-two-tags-filed.sql.
--   drop index if exists public.ops_links_ref_idx;
--   alter table public.ops_task_links drop constraint if exists ops_task_links_ref_check;
--   alter table public.ops_task_links drop column if exists ref_type,
--     drop column if exists ref_id;
-- ===========================================================================

alter table public.ops_task_links add column if not exists ref_type text;
alter table public.ops_task_links add column if not exists ref_id uuid;
do $$ begin
  alter table public.ops_task_links add constraint ops_task_links_ref_check
    check ((ref_type is null and ref_id is null)
        or (ref_type in ('campaign', 'set') and ref_id is not null and kind = 'record'));
exception when duplicate_object then null;
end $$;
create index if not exists ops_links_ref_idx
  on public.ops_task_links(ref_type, ref_id) where archived_at is null;

/* What a record is called and where it lives, read the same way by the
   link, the unlink and the record's own Activity. `null` where the record is
   gone. */
create or replace function public.ops_ref_of(p_type text, p_ref uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case p_type
    when 'campaign' then (
      select jsonb_build_object(
               'client_id', c.client_id,
               'title', coalesce(nullif(btrim(c.title), ''), 'Untitled campaign'),
               'subject', coalesce(c.title, ''),
               'url', '/admin/?s=campaigns&campaign=' || c.id::text)
        from public.campaigns c where c.id = p_ref)
    when 'set' then (
      select jsonb_build_object(
               'client_id', b.client_id,
               'title', coalesce(nullif(btrim(b.title), ''), 'Content set'),
               'subject', coalesce(cl.name, '') || ' — ' || coalesce(b.title, ''),
               'url', '/admin/?s=review&client=' || coalesce(nullif(cl.slug, ''), cl.id::text)
                      || '&set=' || b.id::text)
        from public.batches b left join public.clients cl on cl.id = b.client_id
       where b.id = p_ref)
  end
$$;
revoke all on function public.ops_ref_of(text, uuid) from public, anon, authenticated;

/* Both sides of one link filed at once: the task's own log in the words
   every link uses, and the record's Activity naming the task. */
create or replace function public.ops_ref_file(
  p_link public.ops_task_links, p_act text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_ref jsonb := public.ops_ref_of(p_link.ref_type, p_link.ref_id);
  v_t   public.ops_tasks;
  v_me  public.team_members := public.ops_me();
begin
  select * into v_t from public.ops_tasks where id = p_link.task_id;
  perform public.ops_log(p_link.task_id,
    case p_act when 'linked' then 'file_added' when 'unlinked' then 'file_removed' else 'file_restored' end,
    null,
    jsonb_build_object('link_id', p_link.id, 'kind', 'record', 'ref_type', p_link.ref_type,
                       'label', coalesce(v_ref->>'title', p_link.label)),
    '{}'::jsonb);
  if v_ref is null then return; end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.email, v_me.name),
          p_link.ref_type || case when p_act = 'unlinked' then '.task_unlinked' else '.task_linked' end,
          v_ref->>'subject',
          public.ops_serial(v_t.task_no) || ' · ' || public.ops_title(v_t));
end $$;
revoke all on function public.ops_ref_file(public.ops_task_links, text) from public, anon, authenticated;

create or replace function public.ops_link_record(
  p_task uuid, p_type text, p_ref uuid, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me  public.team_members;
  v_t   public.ops_tasks;
  v_ref jsonb;
  v_l   public.ops_task_links;
begin
  v_me := public.ops_me();
  if v_me.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_type is null or p_type not in ('campaign', 'set') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  select * into v_t from public.ops_tasks where id = p_task for update;
  if v_t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> v_t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  v_ref := public.ops_ref_of(p_type, p_ref);
  if v_ref is null then return jsonb_build_object('error', 'record-not-found'); end if;
  if v_t.client_id is null or (v_ref->>'client_id') is null
     or (v_ref->>'client_id')::uuid <> v_t.client_id then
    return jsonb_build_object('error', 'other-client');
  end if;
  select * into v_l from public.ops_task_links k
   where k.task_id = p_task and k.ref_type = p_type and k.ref_id = p_ref and k.archived_at is null
   limit 1;
  if v_l.id is not null then
    return jsonb_build_object('link_id', v_l.id, 'already', true, 'task', public.ops_task_json(p_task));
  end if;

  insert into public.ops_task_links (task_id, kind, label, url, created_by, ref_type, ref_id)
  values (p_task, 'record', v_ref->>'title', v_ref->>'url', v_me.id, p_type, p_ref)
  returning * into v_l;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_ref_file(v_l, 'linked');
  return jsonb_build_object('link_id', v_l.id, 'task', public.ops_task_json(p_task));
end $$;
revoke all on function public.ops_link_record(uuid, text, uuid, integer) from public, anon;
grant execute on function public.ops_link_record(uuid, text, uuid, integer) to authenticated;

/* ops_set_link_archived as phase 2 left it, filing a record link on both
   sides. */
create or replace function public.ops_set_link_archived(p_link uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.ops_task_links;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into l from public.ops_task_links where id = p_link for update;
  if l.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(l.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if (l.archived_at is not null) = p_on then
    return jsonb_build_object('link_id', l.id, 'archived', p_on,
                              'task', public.ops_task_json(l.task_id));
  end if;

  update public.ops_task_links
     set archived_at = case when p_on then now() else null end
   where id = p_link;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = l.task_id;
  if l.ref_type is not null then
    perform public.ops_ref_file(l, case when p_on then 'unlinked' else 'relinked' end);
  else
    perform public.ops_log(l.task_id,
      case when p_on then 'file_removed' else 'file_restored' end, null,
      jsonb_build_object('link_id', l.id, 'kind', l.kind, 'label', l.label), '{}'::jsonb);
  end if;
  return jsonb_build_object('link_id', l.id, 'archived', p_on,
                            'task', public.ops_task_json(l.task_id));
end $$;
grant execute on function public.ops_set_link_archived(uuid, boolean) to authenticated;

/* ops_update_link as phase 4 left it, refusing a record link. */
create or replace function public.ops_update_link(
  p_link uuid, p_label text, p_url text, p_kind text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  l   public.ops_task_links;
  t   public.ops_tasks;
  lbl text;
  u   text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into l from public.ops_task_links where id = p_link for update;
  if l.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(l.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if l.ref_type is not null then return jsonb_build_object('error', 'record-link'); end if;
  if p_kind not in ('brief', 'asset', 'draft', 'review', 'final', 'other') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  u := nullif(btrim(coalesce(p_url, '')), '');
  if u is null then return jsonb_build_object('error', 'url-required'); end if;
  select * into t from public.ops_tasks where id = l.task_id for update;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(l.task_id));
  end if;
  lbl := coalesce(nullif(btrim(coalesce(p_label, '')), ''), initcap(p_kind) || ' link');
  if lbl = l.label and u = l.url and p_kind = l.kind then
    return jsonb_build_object('link_id', l.id, 'task', public.ops_task_json(l.task_id));
  end if;
  update public.ops_task_links set label = lbl, url = u, kind = p_kind where id = p_link;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = l.task_id;
  perform public.ops_log(l.task_id, 'file_changed',
    jsonb_build_object('link_id', l.id, 'label', l.label, 'url', l.url, 'kind', l.kind),
    jsonb_build_object('link_id', l.id, 'label', lbl, 'url', u, 'kind', p_kind), '{}'::jsonb);
  return jsonb_build_object('link_id', l.id, 'task', public.ops_task_json(l.task_id));
end $$;
grant execute on function public.ops_update_link(uuid, text, text, text, integer) to authenticated;

/* The backlinks: every task linking a record, open work first, that the
   caller may see. A person who may not read the record's own section is
   told nothing of it, and a task they may not see is left out. */
create or replace function public.ops_record_tasks(p_type text, p_ref uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return '[]'::jsonb; end if;
  if p_type = 'campaign' and not public.allowed('campaigns', 'view') then return '[]'::jsonb; end if;
  if p_type = 'set' and not public.allowed('review', 'view') then return '[]'::jsonb; end if;
  if p_type is null or p_type not in ('campaign', 'set') then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x.j order by x.done, x.due nulls last, x.no)
      from (
        select distinct on (t.id)
               t.id, t.task_no as no,
               (t.completed_at is not null or t.cancelled_at is not null) as done,
               t.current_final_due_at as due,
               jsonb_build_object(
                 'id', t.id,
                 'serial', public.ops_serial(t.task_no),
                 'title', public.ops_title(t),
                 'stage_key', t.stage_key,
                 'stage', coalesce(s.label, initcap(replace(t.stage_key, '_', ' '))),
                 'stage_group', s.stage_group,
                 'owner', (select m.name from public.ops_task_assignees a
                             join public.team_members m on m.id = a.team_member_id
                            where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null
                            limit 1),
                 'final_due_at', t.current_final_due_at,
                 'completed_at', t.completed_at,
                 'cancelled_at', t.cancelled_at,
                 'link_id', k.id) as j
          from public.ops_task_links k
          join public.ops_tasks t on t.id = k.task_id
          left join public.ops_workflow_stages s
                 on s.workflow_id = t.workflow_id and s.key = t.stage_key
         where k.ref_type = p_type and k.ref_id = p_ref and k.archived_at is null
           and public.ops_may_see_task(t.id)
         order by t.id, k.created_at
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.ops_record_tasks(text, uuid) from public, anon;
grant execute on function public.ops_record_tasks(text, uuid) to authenticated;

-- END OF TASKS LINK RECORDS ----------------------------------------------------

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
                    'campaign.reinstated', 'campaign.replaced', 'campaign.review',
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
