-- ===========================================================================
-- COLLEAGUE LEAVING — a colleague who leaves takes no work, device or short
-- link with them, and a removed colleague stays removed (2026-10-15)
-- ===========================================================================
-- WHY (the audit of 2026-10-15, I4, S6, S9, I9)
--   * I4: Delete their data emptied the namecard slug, and the slug trigger
--     made it again from the name that stays, so the short link was never
--     freed.
--   * S6: an extension on a task a departed colleague created was still
--     asked of them, and their phone kept its notification device after Set
--     inactive or a removal with their data kept.
--   * S9: `team_hand_over` did not refuse one's own row or a system account,
--     and a direct update could make a removed colleague active again.
--   * I9: a removed colleague's helper and reviewer places on tasks, the
--     talks colleagues asked of them, and an on-site meeting's outstation
--     reminder stayed with them.
--
-- WHAT CHANGED
--   * `team_card_slug` leaves the slug empty once `erased_at` is set.
--   * `ops_due_decider` asks the task's creator while they are active, else
--     the first active admin who is not a system account.
--   * `team_hand_over` refuses `own` and `system-account`.
--   * `team_access_guard` refuses `removed` to an update making a removed
--     colleague active.
--   * `ops_outstation_remind` tells the meeting's leader while active, else
--     the month's manager while active.
--   * `team_members_leaving` (trigger, after update): Set inactive, an
--     expiry or a removal takes away the colleague's notification devices; a
--     removal ends their helper and reviewer places on tasks and withdraws
--     the open talks colleagues asked of them.
--
-- ORDER
--   This file, then the page (`js/team.js` stops a Delete whose hand-over
--   failed). The trigger's function removes rows (the devices), so it is
--   run in the SQL Editor: the part from "LEAVING TRIGGER" to the end.
--
-- Safe to run twice. Rollback: run COLLEAGUE HAND-OVER's team_hand_over,
-- NAMECARD SHORT LINKS' team_card_slug, TEAM ACCESS TIME's
-- team_access_guard, ON-SITE MEETINGS' ops_outstation_remind and the
-- operations ops_due_decider again; remove the trigger team_members_leaving.
-- ===========================================================================

create or replace function public.team_card_slug()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- A colleague whose details were deleted keeps no short link: their
  -- slug is freed, never made again from the name that stays.
  if new.erased_at is not null then
    new.card_slug := null;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.card_slug is not distinct from old.card_slug then
    return new;
  end if;
  if new.card_slug is null or btrim(new.card_slug) = '' then
    new.card_slug := public.card_slug_free(public.card_slug_from(new.name, new.email), new.id);
    return new;
  end if;
  new.card_slug := lower(btrim(new.card_slug));
  if new.card_slug !~ '^[a-z0-9][a-z0-9._-]{2,79}$' then
    raise exception 'slug-shape' using hint = 'At least three lowercase letters, digits, dots, dashes or underscores.';
  end if;
  if exists (select 1 from public.links l where l.slug = new.card_slug)
     or exists (select 1 from public.team_members t where t.card_slug = new.card_slug and t.id <> new.id) then
    raise exception 'slug-taken' using errcode = '23505';
  end if;
  return new;
end $$;
revoke all on function public.team_card_slug() from public, anon, authenticated;

create or replace function public.ops_due_decider(p_task uuid, p_kind text)
returns uuid
language sql security definer stable set search_path = public as $$
  select case when p_kind = 'first_draft' then null
              else coalesce(
                (select t.created_by from public.ops_tasks t
                   join public.team_members m on m.id = t.created_by and m.active
                  where t.id = p_task),
                (select m.id from public.team_members m
                  where m.active and not coalesce(m.system, false) and (m.is_admin or m.role = 'admin')
                  order by m.name, m.id limit 1),
                (select t.created_by from public.ops_tasks t where t.id = p_task))
         end
$$;
grant execute on function public.ops_due_decider(uuid, text) to authenticated;

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
  if v_from.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_from.system, false) then return jsonb_build_object('error', 'system-account'); end if;
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

create or replace function public.team_access_guard()
returns trigger language plpgsql as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  ends timestamptz := public.team_access_ends(new.access_until, new.access_until_time);
  moved boolean := new.access_until is distinct from old.access_until
                   or new.access_until_time is distinct from old.access_until_time;
begin
  if moved and who <> '' and lower(old.email) = who then
    raise exception 'own-expiry' using hint = 'Another admin sets your access date.';
  end if;
  if new.active and not old.active and new.removed_at is not null then
    raise exception 'removed' using hint = 'A removed colleague does not come back; add them again.';
  end if;
  if new.active and not old.active then
    if ends is not null and ends <= now() then
      raise exception 'expired-date' using hint = 'Move the access date first.';
    end if;
    new.expired_at := null;
  elsif old.expired_at is not null and moved and (ends is null or ends > now()) then
    new.active := true;
    new.expired_at := null;
  end if;
  return new;
end $$;

create or replace function public.ops_outstation_remind()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  for r in
    select e.id, e.meeting_at, coalesce((select t.id from public.team_members t where t.id = e.meeting_owner_id and t.active),
                                       (select t.id from public.team_members t where t.id = e.manager_id and t.active)) as who, c.name as client_name
      from public.ops_engagements e
      left join public.clients c on c.id = e.client_id
     where e.meeting_channel = 'onsite' and not e.meeting_na and e.meeting_at is not null
       and e.outstation_told_at is null
       and e.meeting_at + make_interval(mins => coalesce(e.meeting_minutes, 30)) <= now()
       and coalesce(e.status, '') <> 'cancelled'
     for update of e skip locked
  loop
    if r.who is not null and exists (select 1 from public.team_members t where t.id = r.who and t.active) then
      insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
      values (r.who, 'outstation', 'Submit the outstation record',
              coalesce(r.client_name, 'Client') || ' · on-site meeting on ' ||
                public.register_day((r.meeting_at at time zone 'Asia/Kuala_Lumpur')::date),
              'https://go.adspace.me/outstation',
              'outstation.' || r.id::text || '.' || extract(epoch from r.meeting_at)::bigint::text)
      on conflict (dedupe_key) do nothing;
      n := n + 1;
    end if;
    update public.ops_engagements set outstation_told_at = now() where id = r.id;
  end loop;
  return n;
end $$;
revoke all on function public.ops_outstation_remind() from public, anon, authenticated;

-- LEAVING TRIGGER (run in the SQL Editor: it removes the devices)
create or replace function public.team_members_leaving()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.active and not new.active then
    delete from public.push_subscriptions s where s.team_member_id = new.id;
  end if;
  if old.removed_at is null and new.removed_at is not null then
    update public.ops_task_assignees a set ended_at = now()
     where a.team_member_id = new.id and a.ended_at is null and a.responsibility <> 'owner';
    update public.health_talks h set status = 'withdrawn', closed_at = now()
     where h.with_id = new.id and h.status = 'open';
  end if;
  return null;
end $$;
revoke all on function public.team_members_leaving() from public, anon, authenticated;
create or replace trigger team_members_leaving after update of active, removed_at on public.team_members
  for each row execute function public.team_members_leaving();

-- END OF COLLEAGUE LEAVING ---------------------------------------------------
select public.functions_tidy();
