-- ============================================================================
-- CONTENT LOOP, PHASE 2: A REEL'S SCRIPT AND ITS SHOOT (2026-11-10)
-- ============================================================================
-- The user, 2026-11-10: "phase 2 and 3 proceed all until completion"; a reel
-- script is approved internally or by the client, either works.
--
--   1. `ops_task_links.script_id`: a task links one video script of its own
--      client, one task a script (`ops_link_script`; My Work at Work, Video
--      Scripts at View; `script-taken`, `has-script`, `other-client`).
--   2. `ops_script_follow(p_script)`: the script fills its task's video
--      details: Script Ready once published (shown to the client, the
--      team's approval), Not ready while a draft; the shoot from its shoot
--      day and time; Footage Ready once every scene is ticked shot, Not
--      ready while any is not; and the footage in moves a task still at
--      Ready to start to In progress, filed on the task and told to its
--      owner. Called by triggers on `video_scripts` and its scenes; a fault
--      never fails the script's write.
--   3. `ops_script_task(p_script)`: the task a script feeds, as the reader
--      may see it, for the script's own page.
--
-- Re-runnable. Rollback: drop the two triggers, the functions in 1 to 3,
-- the column and its indexes.

alter table public.ops_task_links add column if not exists script_id uuid
  references public.video_scripts(id) on delete set null;
create unique index if not exists ops_task_links_script_once
  on public.ops_task_links (script_id) where script_id is not null and archived_at is null;
create unique index if not exists ops_task_links_one_script
  on public.ops_task_links (task_id) where script_id is not null and archived_at is null;

create or replace function public.ops_script_follow(p_script uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  k      public.ops_task_links;
  t      public.ops_tasks;
  s      public.video_scripts;
  v      public.ops_video_details;
  v_shot boolean;
  v_at   timestamptz;
  v_own  uuid;
  v_me   uuid := (public.ops_me()).id;
  v_dest public.ops_workflow_stages;
begin
  select * into k from public.ops_task_links x
   where x.script_id = p_script and x.archived_at is null limit 1;
  if k.id is null then return; end if;
  select * into s from public.video_scripts x where x.id = p_script;
  select * into t from public.ops_tasks x where x.id = k.task_id for update;
  if s.id is null or t.id is null or t.completed_at is not null or t.cancelled_at is not null
     or t.archived_at is not null then
    return;
  end if;
  select count(*) > 0 and count(*) filter (where c.shot_at is null) = 0 into v_shot
    from public.video_script_scenes c where c.script_id = s.id;
  v_at := case when s.shoot_on is null then null
               else (s.shoot_on + coalesce(s.shoot_time, time '09:00')) at time zone 'Asia/Kuala_Lumpur' end;
  insert into public.ops_video_details (task_id) values (t.id) on conflict (task_id) do nothing;
  select * into v from public.ops_video_details x where x.task_id = t.id for update;
  if v.script_ready is distinct from (s.status = 'shared') or v.footage_ready is distinct from v_shot
     or v.shoot_at is distinct from v_at or v.shoot_required is distinct from (s.shoot_on is not null) then
    update public.ops_video_details set script_ready = (s.status = 'shared'), footage_ready = v_shot,
           shoot_at = v_at, shoot_required = (s.shoot_on is not null)
     where task_id = t.id;
    insert into public.ops_task_events (task_id, event_type, actor_id, actor_email, from_value, to_value, detail)
    values (t.id, 'video_changed', v_me, null,
            jsonb_build_object('script_ready', v.script_ready, 'footage_ready', v.footage_ready, 'shoot_at', v.shoot_at),
            jsonb_build_object('script_ready', s.status = 'shared', 'footage_ready', v_shot, 'shoot_at', v_at),
            jsonb_build_object('note', 'From its script in Video Scripts', 'script_id', s.id));
    update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
  end if;
  -- The footage in: a task not started moves into its work.
  if v_shot and v.footage_ready is distinct from true and t.stage_key = 'ready' then
    v_dest := public.ops_stage(t.workflow_id, 'in_production');
    if v_dest.key is not null and not coalesce(v_dest.retired, false) then
      update public.ops_tasks set stage_key = 'in_production', version = version + 1, updated_at = now()
       where id = t.id;
      insert into public.ops_task_events (task_id, event_type, actor_id, actor_email, from_value, to_value, detail)
      values (t.id, 'stage_changed', v_me, null,
              jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', 'in_production'),
              jsonb_build_object('note', 'Every scene shot in Video Scripts', 'script_id', s.id));
      select a.team_member_id into v_own from public.ops_task_assignees a
       where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null limit 1;
      if v_own is not null and v_own is distinct from v_me then
        perform public.ops_notify(v_own, t.id, 'stage_changed',
          public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
          'Moved to ' || v_dest.label || ': every scene shot in Video Scripts.',
          'stage_changed:' || t.id::text || ':' || v_own::text || ':' ||
            to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI'));
      end if;
    end if;
  end if;
exception when others then
  return;
end $$;
revoke all on function public.ops_script_follow(uuid) from public, anon, authenticated;

create or replace function public.ops_link_script(p_task uuid, p_script uuid, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members := public.ops_me();
  v_t  public.ops_tasks;
  v_s  public.video_scripts;
  v_l  public.ops_task_links;
begin
  if v_me.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') or not public.allowed('scripts', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select * into v_t from public.ops_tasks where id = p_task for update;
  if v_t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> v_t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  select * into v_s from public.video_scripts where id = p_script;
  if v_s.id is null then return jsonb_build_object('error', 'record-not-found'); end if;
  if v_t.client_id is null or v_s.client_id is distinct from v_t.client_id then
    return jsonb_build_object('error', 'other-client');
  end if;
  if exists (select 1 from public.ops_task_links x where x.task_id = p_task and x.script_id is not null and x.archived_at is null) then
    return jsonb_build_object('error', 'has-script');
  end if;
  if exists (select 1 from public.ops_task_links x where x.script_id = p_script and x.archived_at is null) then
    return jsonb_build_object('error', 'script-taken');
  end if;
  insert into public.ops_task_links (task_id, kind, label, url, created_by, script_id)
  values (p_task, 'record',
          left(coalesce(nullif(v_s.code, '') || ' · ', '') || coalesce(nullif(btrim(v_s.title), ''), 'Video script'), 200),
          '/admin/?s=scripts&script=' || v_s.id::text, v_me.id, p_script)
  returning * into v_l;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_log(p_task, 'file_added', null,
    jsonb_build_object('link_id', v_l.id, 'kind', 'record', 'ref_type', 'script', 'label', v_l.label), '{}'::jsonb);
  perform public.ops_script_follow(p_script);
  return jsonb_build_object('link_id', v_l.id, 'task', public.ops_task_json(p_task));
end $$;
revoke all on function public.ops_link_script(uuid, uuid, integer) from public, anon;
grant execute on function public.ops_link_script(uuid, uuid, integer) to authenticated;

create or replace function public.ops_script_task(p_script uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('scripts', 'view') then return null; end if;
  return (select jsonb_build_object(
            'id', t.id, 'serial', public.ops_serial(t.task_no), 'title', public.ops_title(t),
            'stage', coalesce(st.label, t.stage_key), 'stage_group', st.stage_group)
            from public.ops_task_links k
            join public.ops_tasks t on t.id = k.task_id
            left join public.ops_workflow_stages st on st.workflow_id = t.workflow_id and st.key = t.stage_key
           where k.script_id = p_script and k.archived_at is null and public.ops_may_see_task(t.id)
           limit 1);
end $$;
revoke all on function public.ops_script_task(uuid) from public, anon;
grant execute on function public.ops_script_task(uuid) to authenticated;

create or replace function public.video_scripts_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.ops_script_follow(new.id);
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.video_scripts_task_follow() from public, anon, authenticated;
create or replace trigger video_scripts_task_follow after update on public.video_scripts
  for each row execute function public.video_scripts_task_follow();

create or replace function public.video_script_scenes_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.shot_at is not distinct from old.shot_at then return null; end if;
  perform public.ops_script_follow(new.script_id);
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.video_script_scenes_task_follow() from public, anon, authenticated;
create or replace trigger video_script_scenes_task_follow after insert or update on public.video_script_scenes
  for each row execute function public.video_script_scenes_task_follow();

select public.functions_tidy();
