-- ==========================================================================
-- MY WORK: DELETING A TASK
-- 2026-09-22. Safe to run twice. Rollback at the foot.
--
-- Archive is list hygiene and reverses; Cancel is a business outcome and is a
-- stage. Neither removes a row, and until now nothing did: a task keyed in
-- twice, or against the wrong client, stayed in the database for ever and the
-- console offered no way out of it. That is the same case a client record has
-- (`delete_client`, "for the lead keyed in twice"), so it takes the same
-- shape: the section's Manage level, the thing's own identifier typed back,
-- a reason, no restore, and a row in the activity record naming what went —
-- because the task's own events go with it.
--
-- Everything hanging off a task already cascades (checklist, links, events,
-- assignees, work sessions, video details, revisions, notifications), and a
-- task generated from this one as a parent is set null rather than removed,
-- so a series survives the removal of one of its members.
-- ==========================================================================

create or replace function public.ops_delete_task(
  p_task uuid, p_confirm text, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cl  text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  /* A permission can be taken away while the sheet is open, so the level is
     asked again when the button is pressed and not only when it was drawn. */
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  /* The number typed back, because a deletion with no way back is agreed to
     and never merely clicked. */
  if coalesce(p_confirm, '') <> 'T' || t.task_no::text then
    return jsonb_build_object('error', 'confirm-required');
  end if;

  select c.name into cl from public.clients c where c.id = t.client_id;

  /* The record outlives the row, and it is the only place this deletion can
     be read afterwards: the task's own events are about to be cascaded. */
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.deleted',
          'T' || t.task_no::text,
          t.title ||
          coalesce(' · ' || cl, case when t.scope = 'internal' then ' · Internal' else '' end) ||
          coalesce(' · ' || nullif(btrim(p_reason), ''), ''));

  delete from public.ops_tasks where id = p_task;
  return jsonb_build_object('deleted', true, 'task_no', t.task_no);
end $$;
grant execute on function public.ops_delete_task(uuid, text, text) to authenticated;

-- Rollback:
--   drop function if exists public.ops_delete_task(uuid, text, text);
