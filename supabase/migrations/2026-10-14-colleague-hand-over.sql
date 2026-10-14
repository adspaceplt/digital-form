-- ===========================================================================
-- COLLEAGUE HAND-OVER — a colleague set inactive or removed hands their live
-- work to the colleagues chosen, one for each kind (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-14: "when a team member resigned or removed from
-- the digital portal … would it be replaced to the person that we select as
-- replacement?"; then "A person for each kind")
--   Set inactive moved only the clients and open campaigns a colleague was
--   person in charge of. Their open tasks, the months they managed, the
--   meetings they led, their repeating tasks, the reports waiting for their
--   review, the extension requests waiting on them and the templates naming
--   them stayed with somebody who could no longer sign in.
--
-- WHAT IT ADDS
--   * `team_members.removed_at` (removed, their data kept or not) and
--     `erased_at` (their personal details deleted), stamped by
--     `team_member_remove` (COLLEAGUE REMOVE) alone.
--   * `team_work_held(p_member)` (Team Full Access): how many of each kind of
--     live work the colleague holds: tasks (open tasks they own), months
--     (open months they manage), meetings (meetings ahead they lead),
--     repeats (repeating tasks they own), reviews (reports in review waiting
--     on them), extensions (extension requests waiting on their decision),
--     templates (task templates naming them as the default owner).
--   * `team_hand_over(p_member, p_to)` (Team Full Access): `p_to` names a
--     colleague for each kind to move (an active colleague, never a system
--     account, never the colleague themselves; `bad-person`); a kind left
--     out stays. Each task's hand-over is filed on the task and tells its
--     new owner, a month's on the month, a report's on the report (a
--     reviewer who submitted it or who may not review is left out, counted
--     as skipped); one line is filed under the colleague in the Activity
--     record. Their own records and their name on past work never move.
--
-- Safe to run twice. Rollback: remove the two functions and the two
-- columns; nothing else reads them.
-- ===========================================================================

alter table public.team_members add column if not exists removed_at timestamptz;
alter table public.team_members add column if not exists erased_at timestamptz;

create or replace function public.team_work_held(p_member uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.team_members x where x.id = p_member) then
    return jsonb_build_object('error', 'not-found');
  end if;
  return jsonb_build_object('ok', true,
    'tasks', (select count(*) from public.ops_task_assignees a join public.ops_tasks t on t.id = a.task_id
               where a.team_member_id = p_member and a.responsibility = 'owner' and a.ended_at is null
                 and t.archived_at is null and t.completed_at is null and t.cancelled_at is null),
    'months', (select count(*) from public.ops_engagements e
                where e.manager_id = p_member and e.status not in ('completed', 'cancelled')),
    'meetings', (select count(*) from public.ops_engagements e
                  where e.meeting_owner_id = p_member and e.status not in ('completed', 'cancelled')
                    and e.meeting_at > now()),
    'repeats', (select count(*) from public.ops_recurring_rules r where r.owner_id = p_member and r.active),
    'reviews', (select count(*) from public.sm_reports s where s.reviewer_id = p_member and s.status = 'review'),
    'extensions', (select count(*) from public.ops_due_requests d where d.decider_id = p_member and d.state = 'asked'),
    'templates', (select count(*) from public.ops_task_templates x where x.default_owner_id = p_member and x.active));
end $$;
revoke all on function public.team_work_held(uuid) from public, anon;
grant execute on function public.team_work_held(uuid) to authenticated;

create or replace function public.team_hand_over(p_member uuid, p_to jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_from  public.team_members;
  v_who   public.team_members;
  v_kind  text;
  v_id    text;
  v_to    uuid;
  v_n     integer;
  v_skip  integer := 0;
  v_moved jsonb := '{}'::jsonb;
  v_lines text[] := '{}';
  v_cl    text;
  r       record;
  v_kinds constant text[] := array['tasks', 'months', 'meetings', 'repeats', 'reviews', 'extensions', 'templates'];
  v_words constant text[] := array['open tasks', 'months', 'meetings', 'repeating tasks', 'reports to review',
                                   'extension requests', 'templates'];
  v_one   constant text[] := array['open task', 'month', 'meeting', 'repeating task', 'report to review',
                                   'extension request', 'template'];
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_from from public.team_members x where x.id = p_member;
  if v_from.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if jsonb_typeof(p_to) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  for v_kind in select jsonb_object_keys(p_to) loop
    if not (v_kind = any(v_kinds)) then return jsonb_build_object('error', 'bad-kind', 'kind', v_kind); end if;
    v_id := nullif(btrim(coalesce(p_to ->> v_kind, '')), '');
    if v_id is null then continue; end if;
    if v_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('error', 'bad-person', 'kind', v_kind);
    end if;
    select * into v_who from public.team_members x
     where x.id = v_id::uuid and x.active and not coalesce(x.system, false) and x.id <> p_member;
    if v_who.id is null then return jsonb_build_object('error', 'bad-person', 'kind', v_kind); end if;
  end loop;

  for v_kind in select unnest(v_kinds) loop
    v_id := nullif(btrim(coalesce(p_to ->> v_kind, '')), '');
    if v_id is null then continue; end if;
    v_to := v_id::uuid;
    select * into v_who from public.team_members x where x.id = v_to;
    v_n := 0;
    if v_kind = 'tasks' then
      for r in select t.id, t.stage_key from public.ops_tasks t
                where t.archived_at is null and t.completed_at is null and t.cancelled_at is null
                  and exists (select 1 from public.ops_task_assignees a where a.task_id = t.id and a.responsibility = 'owner'
                                 and a.ended_at is null and a.team_member_id = p_member)
                order by t.id for update of t loop
        update public.ops_task_assignees a set ended_at = now()
         where a.task_id = r.id and a.responsibility = 'owner' and a.ended_at is null;
        insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
        values (r.id, v_to, 'owner', me.id);
        update public.ops_tasks t set version = t.version + 1, updated_at = now() where t.id = r.id;
        perform public.ops_log(r.id, 'assignment_changed',
          jsonb_build_object('owner_id', p_member), jsonb_build_object('owner_id', v_to),
          jsonb_build_object('handover', true, 'stage_key', r.stage_key, 'note', 'Handed over from ' || v_from.name));
        v_n := v_n + 1;
      end loop;
    elsif v_kind = 'months' then
      for r in select e.id from public.ops_engagements e
                where e.manager_id = p_member and e.status not in ('completed', 'cancelled') order by e.id for update loop
        update public.ops_engagements e set manager_id = v_to, updated_at = now(), version = e.version + 1 where e.id = r.id;
        perform public.ops_engagement_log(r.id, 'edited', jsonb_build_object('handover', true,
          'manager_id', jsonb_build_object('from', p_member, 'to', v_to)));
        v_n := v_n + 1;
      end loop;
    elsif v_kind = 'meetings' then
      for r in select e.id from public.ops_engagements e
                where e.meeting_owner_id = p_member and e.status not in ('completed', 'cancelled')
                  and e.meeting_at > now() order by e.id for update loop
        update public.ops_engagements e set meeting_owner_id = v_to, updated_at = now(), version = e.version + 1 where e.id = r.id;
        perform public.ops_engagement_log(r.id, 'edited', jsonb_build_object('handover', true,
          'meeting_owner_id', jsonb_build_object('from', p_member, 'to', v_to)));
        v_n := v_n + 1;
      end loop;
    elsif v_kind = 'repeats' then
      update public.ops_recurring_rules x set owner_id = v_to, updated_at = now()
       where x.owner_id = p_member and x.active;
      get diagnostics v_n = row_count;
    elsif v_kind = 'reviews' then
      for r in select s.id, s.client_id, s.submitted_by, s.period_start, s.period_end from public.sm_reports s
                where s.reviewer_id = p_member and s.status = 'review' order by s.id for update loop
        if r.submitted_by is not distinct from v_to or not public.sm_report_may_review(v_to) then
          v_skip := v_skip + 1;
          continue;
        end if;
        perform set_config('adspace.sm_fn', 'on', true);
        update public.sm_reports s set reviewer_id = v_to where s.id = r.id;
        perform set_config('adspace.sm_fn', 'off', true);
        perform public.sm_report_log(r.id, 'report.reassigned', 'Reviewer: ' || v_from.name || ' → ' || v_who.name);
        select c.name into v_cl from public.clients c where c.id = r.client_id;
        perform public.sm_report_notify(v_to, r.id, 'report.review', 'Report to review',
          coalesce(v_cl, 'A client') || ' · ' || public.sm_period_word(r.period_start, r.period_end));
        v_n := v_n + 1;
      end loop;
    elsif v_kind = 'extensions' then
      update public.ops_due_requests x set decider_id = v_to where x.decider_id = p_member and x.state = 'asked';
      get diagnostics v_n = row_count;
    elsif v_kind = 'templates' then
      update public.ops_task_templates x set default_owner_id = v_to, updated_at = now()
       where x.default_owner_id = p_member and x.active;
      get diagnostics v_n = row_count;
    end if;
    if v_n > 0 then
      v_moved := v_moved || jsonb_build_object(v_kind, v_n);
      v_lines := v_lines || (v_n || ' ' || (case when v_n = 1 then v_one else v_words end)[array_position(v_kinds, v_kind)]
        || ' → ' || v_who.name);
    end if;
  end loop;

  if array_length(v_lines, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', v_from.name, 'Work handed over: ' || array_to_string(v_lines, '; '));
  end if;
  return jsonb_build_object('ok', true, 'moved', v_moved, 'skipped', jsonb_build_object('reviews', v_skip));
end $$;
revoke all on function public.team_hand_over(uuid, jsonb) from public, anon;
grant execute on function public.team_hand_over(uuid, jsonb) to authenticated;

-- END OF COLLEAGUE HAND-OVER -------------------------------------------------

select public.functions_tidy();
