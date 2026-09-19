-- ===========================================================================
-- THE OPERATIONS SYSTEM, PHASE 2 — the writes the console needs to drive the
-- stage machine from a page.
--
-- Phase 1 shipped the data model, the read policies and every write that
-- moves a task. Three of its gates are data the page had no way to set:
--
--   Client review is refused without a draft or review link.
--   Delivered is refused without a final link.
--   Editing is refused while the footage is marked not ready.
--
-- There was no function that adds a link, ticks a checklist item, or records
-- that footage is ready, so a task created in the console could reach Ready
-- and stop. These four are that, and nothing else: no table, column, policy
-- or permission changes, and every one asks the same questions every other
-- write in section 6 asks — an active colleague, the one permission that
-- governs it, the task is theirs to see, the version is not stale — and
-- files its event in the same transaction.
--
-- Safe to run twice. Nothing here is a data migration.
--
-- Rollback:
--   drop function if exists public.ops_add_link(uuid, text, text, text, integer);
--   drop function if exists public.ops_set_link_archived(uuid, boolean);
--   drop function if exists public.ops_set_checklist(uuid, boolean);
--   drop function if exists public.ops_set_video(uuid, jsonb);
-- ===========================================================================

-- 7.1 Links ------------------------------------------------------------------
/* A link is the evidence a stage gate asks for, so adding one is a write the
   database owns like any other: the page cannot insert a row that says a
   draft exists. `kind` is closed, because `ops_transition_task` reads exactly
   these words and a typo would be a draft nobody can find. */
create or replace function public.ops_add_link(
  p_task uuid, p_kind text, p_label text, p_url text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  lid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind not in ('brief', 'draft', 'review', 'final', 'asset', 'other') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if coalesce(trim(p_url), '') = '' then return jsonb_build_object('error', 'url-required'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  insert into public.ops_task_links (task_id, kind, label, url, created_by)
  values (p_task, p_kind,
          coalesce(nullif(trim(p_label), ''), initcap(p_kind) || ' link'),
          trim(p_url), m.id)
  returning id into lid;

  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'file_added', null,
    jsonb_build_object('link_id', lid, 'kind', p_kind, 'url', trim(p_url)), '{}'::jsonb);
  return jsonb_build_object('link_id', lid, 'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_add_link(uuid, text, text, text, integer) to authenticated;

/* Taking a link off is a soft remove with a way back, which is this portal's
   law for anything a person can attach, so it is one function and `p_on`
   false is the Undo. Removing the draft link shuts the Client review gate
   again, which is the point: the gate reads the live rows. */
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

  update public.ops_task_links
     set archived_at = case when p_on then now() else null end
   where id = p_link;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = l.task_id;
  perform public.ops_log(l.task_id,
    case when p_on then 'file_removed' else 'file_restored' end, null,
    jsonb_build_object('link_id', l.id, 'kind', l.kind, 'label', l.label), '{}'::jsonb);
  return jsonb_build_object('link_id', l.id, 'archived', p_on,
                            'task', public.ops_task_json(l.task_id));
end $$;
grant execute on function public.ops_set_link_archived(uuid, boolean) to authenticated;

-- 7.2 Checklist ----------------------------------------------------------------
/* A tick is a statement that something was done, so it records who made it
   and when, and untickings are kept in the events rather than erased: a
   checklist that can be cleared with no trace is one nobody can rely on. */
create or replace function public.ops_set_checklist(p_item uuid, p_done boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; c public.ops_task_checklist_items;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into c from public.ops_task_checklist_items where id = p_item for update;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(c.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  update public.ops_task_checklist_items set
    completed_at = case when p_done then coalesce(completed_at, now()) else null end,
    completed_by = case when p_done then coalesce(completed_by, m.id) else null end
  where id = p_item;

  perform public.ops_log(c.task_id, 'checklist_changed',
    jsonb_build_object('label', c.label, 'done', c.completed_at is not null),
    jsonb_build_object('label', c.label, 'done', p_done), '{}'::jsonb);
  return (select to_jsonb(x) from public.ops_task_checklist_items x where x.id = p_item);
end $$;
grant execute on function public.ops_set_checklist(uuid, boolean) to authenticated;

-- 7.3 Video readiness ------------------------------------------------------------
/* Editing is refused while footage is marked not ready, and the mark had no
   control. The row is created on demand, because a task can be moved onto
   the video workflow after it was made and then has no `ops_video_details`
   row at all; a key the payload does not carry is left as it stands, so
   ticking footage cannot blank a duration somebody typed. */
create or replace function public.ops_set_video(p_task uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; v public.ops_video_details;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.ops_tasks where id = p_task) then
    return jsonb_build_object('error', 'not-found');
  end if;

  insert into public.ops_video_details (task_id) values (p_task)
  on conflict (task_id) do nothing;
  select * into v from public.ops_video_details where task_id = p_task for update;

  update public.ops_video_details set
    output_duration_seconds  = coalesce((p_payload ->> 'output_duration_seconds')::integer, output_duration_seconds),
    footage_duration_seconds = coalesce((p_payload ->> 'footage_duration_seconds')::integer, footage_duration_seconds),
    subtitle_required        = coalesce((p_payload ->> 'subtitle_required')::boolean, subtitle_required),
    motion_graphics_required = coalesce((p_payload ->> 'motion_graphics_required')::boolean, motion_graphics_required),
    script_ready             = coalesce((p_payload ->> 'script_ready')::boolean, script_ready),
    footage_ready            = coalesce((p_payload ->> 'footage_ready')::boolean, footage_ready),
    shoot_required           = coalesce((p_payload ->> 'shoot_required')::boolean, shoot_required),
    shoot_at                 = coalesce((p_payload ->> 'shoot_at')::timestamptz, shoot_at),
    variant_count            = coalesce((p_payload ->> 'variant_count')::integer, variant_count)
  where task_id = p_task;

  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'video_changed',
    jsonb_build_object('script_ready', v.script_ready, 'footage_ready', v.footage_ready),
    p_payload, '{}'::jsonb);
  return (select to_jsonb(x) from public.ops_video_details x where x.task_id = p_task);
end $$;
grant execute on function public.ops_set_video(uuid, jsonb) to authenticated;
