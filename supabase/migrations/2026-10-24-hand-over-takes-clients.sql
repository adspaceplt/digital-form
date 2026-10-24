-- ===========================================================================
-- HAND-OVER TAKES CLIENTS — a colleague's clients and open campaigns are
-- counted and handed over by the database, and a rename follows them
-- (2026-10-24)
-- ===========================================================================
-- WHY (the Team audit of 2026-10-24, TEAM2-3)
--   The page found a colleague's clients and open campaigns by reading every
--   client and campaign in the browser, under the caller's own policies: a
--   group seeing its own clients only missed the rest, a read stopped at a
--   thousand rows, and three heavy reads ran each time the Work pane, Set
--   inactive or Delete opened. The person in charge was then moved row by
--   row from the page, and a rename was carried the same way.
--
-- WHAT CHANGED
--   * `team_work_held(p_member)` also counts `clients` (every client whose
--     person in charge is the colleague, matched on the trimmed name in any
--     case, as the page matched it) and `campaigns` (their campaigns not
--     completed), and lists them (`client_list`: id, name, slug, Client ID,
--     stage; `campaign_list`: id, title, state) for the Work pane. Team Full
--     Access reads them whatever its client scope.
--   * `team_hand_over(p_member, p_to)` takes the kinds `clients` and
--     `campaigns`: the person in charge becomes the colleague chosen, each
--     record filed on its own Activity (`client.edited`, `campaign.edited`:
--     Person in charge: … to …) and in the one line under the colleague. A
--     completed campaign keeps who ran it. Every refusal it gave stands.
--   * `client_scope_guard` lets that write through (`adspace.team_owner`,
--     set by the function alone for its own statements), so a Team Full
--     Access colleague seeing their own clients only still hands over
--     clients they cannot see.
--   * Trigger `team_members_rename_owner` (after a change of name): every
--     client and every campaign naming the colleague as person in charge,
--     completed ones included (the same person, renamed), reads the new
--     name, each filed. It runs inside the colleague's write, so
--     `clients_owner_guard` and the scope guard, which leave a write made by
--     a trigger alone, do not stand in its way.
--
-- ORDER
--   This file, then the page (`js/team.js` stops reading clients and
--   campaigns itself). An open tab of the page before meets the old reads,
--   which still work; the new page on a database without this file finds no
--   `clients` in `team_work_held` and offers no client hand-over.
--
-- Safe to run twice. Rollback: run COLLEAGUE HAND-OVER's team_work_held,
-- COLLEAGUE LEAVING's team_hand_over and SALES BY's client_scope_guard again,
-- then in the SQL Editor:
--   drop trigger if exists team_members_rename_owner on public.team_members;
--   drop function if exists public.team_members_rename_owner();
-- ===========================================================================

create or replace function public.team_work_held(p_member uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text;
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select lower(btrim(coalesce(x.name, ''))) into v_name from public.team_members x where x.id = p_member;
  if not found then
    return jsonb_build_object('error', 'not-found');
  end if;
  return jsonb_build_object('ok', true,
    'clients', (select count(*) from public.clients c where v_name <> '' and lower(btrim(coalesce(c.owner, ''))) = v_name),
    'campaigns', (select count(*) from public.campaigns g where v_name <> '' and lower(btrim(coalesce(g.owner, ''))) = v_name
                    and g.state is distinct from 'completed'),
    'client_list', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'slug', c.slug,
                      'client_code', c.client_code, 'stage', c.stage) order by c.name, c.id)
                    from public.clients c where v_name <> '' and lower(btrim(coalesce(c.owner, ''))) = v_name), '[]'::jsonb),
    'campaign_list', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'title', g.title, 'state', g.state)
                      order by g.title, g.id)
                    from public.campaigns g where v_name <> '' and lower(btrim(coalesce(g.owner, ''))) = v_name
                      and g.state is distinct from 'completed'), '[]'::jsonb),
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

create or replace function public.client_scope_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  kind text := tg_argv[0];
  col  text := tg_argv[1];
  o jsonb;
  n jsonb := to_jsonb(new);
begin
  if pg_trigger_depth() > 1 or public.client_scope_free('work') then return new; end if;
  if tg_op = 'UPDATE' and tg_table_name = 'sm_report_versions'
     and coalesce(current_setting('adspace.keep_file', true), '') = 'on' then
    return new;
  end if;
  -- `team_hand_over` moving the person in charge (HAND-OVER TAKES CLIENTS).
  if tg_op = 'UPDATE' and tg_table_name in ('clients', 'campaigns')
     and coalesce(current_setting('adspace.team_owner', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    o := to_jsonb(old);
    if (kind = 'self' and not public.client_row_seen_by(o ->> 'stage', o ->> 'owner', (o ->> 'sales_by')::uuid, 'work'))
       or (kind <> 'self' and not public.client_scope_ok(kind, (o ->> col)::uuid, 'work')) then
      raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
    end if;
  end if;
  if (kind = 'self' and not public.client_row_seen_by(n ->> 'stage', n ->> 'owner', (n ->> 'sales_by')::uuid, 'work'))
     or (kind <> 'self' and not public.client_scope_ok(kind, (n ->> col)::uuid, 'work')) then
    raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
  end if;
  return new;
end $$;
revoke all on function public.client_scope_guard() from public, anon, authenticated;

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
  v_key   text;
  r       record;
  v_kinds constant text[] := array['clients', 'campaigns', 'tasks', 'months', 'meetings', 'repeats', 'reviews',
                                   'extensions', 'templates'];
  v_words constant text[] := array['clients', 'open campaigns', 'open tasks', 'months', 'meetings', 'repeating tasks',
                                   'reports to review', 'extension requests', 'templates'];
  v_one   constant text[] := array['client', 'open campaign', 'open task', 'month', 'meeting', 'repeating task',
                                   'report to review', 'extension request', 'template'];
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

  v_key := lower(btrim(coalesce(v_from.name, '')));
  for v_kind in select unnest(v_kinds) loop
    v_id := nullif(btrim(coalesce(p_to ->> v_kind, '')), '');
    if v_id is null then continue; end if;
    v_to := v_id::uuid;
    select * into v_who from public.team_members x where x.id = v_to;
    v_n := 0;
    if v_kind = 'clients' then
      perform set_config('adspace.team_owner', 'on', true);
      for r in select c.id, c.name from public.clients c
                where v_key <> '' and lower(btrim(coalesce(c.owner, ''))) = v_key order by c.id for update loop
        update public.clients c set owner = v_who.name where c.id = r.id;
        insert into public.activity_log (actor, action, subject, detail)
        values (me.name, 'client.edited', r.name, 'Person in charge: ' || v_from.name || ' to ' || v_who.name);
        v_n := v_n + 1;
      end loop;
      perform set_config('adspace.team_owner', 'off', true);
    elsif v_kind = 'campaigns' then
      perform set_config('adspace.team_owner', 'on', true);
      for r in select g.id, g.title from public.campaigns g
                where v_key <> '' and lower(btrim(coalesce(g.owner, ''))) = v_key
                  and g.state is distinct from 'completed' order by g.id for update loop
        update public.campaigns g set owner = v_who.name where g.id = r.id;
        insert into public.activity_log (actor, action, subject, detail)
        values (me.name, 'campaign.edited', r.title, 'Person in charge: ' || v_from.name || ' to ' || v_who.name);
        v_n := v_n + 1;
      end loop;
      perform set_config('adspace.team_owner', 'off', true);
    elsif v_kind = 'tasks' then
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

create or replace function public.team_members_rename_owner()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old text := lower(btrim(coalesce(old.name, '')));
  v_new text := btrim(coalesce(new.name, ''));
  v_by  text := coalesce((public.ops_me()).name, 'system');
  r     record;
begin
  if v_old = '' or v_new = '' or v_old = lower(v_new) and btrim(coalesce(old.name, '')) = v_new then
    return new;
  end if;
  for r in select c.id, c.name from public.clients c where lower(btrim(coalesce(c.owner, ''))) = v_old order by c.id loop
    update public.clients c set owner = v_new where c.id = r.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (v_by, 'client.edited', r.name, 'Person in charge: ' || btrim(old.name) || ' to ' || v_new);
  end loop;
  for r in select g.id, g.title from public.campaigns g where lower(btrim(coalesce(g.owner, ''))) = v_old order by g.id loop
    update public.campaigns g set owner = v_new where g.id = r.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (v_by, 'campaign.edited', r.title, 'Person in charge: ' || btrim(old.name) || ' to ' || v_new);
  end loop;
  return new;
end $$;
revoke all on function public.team_members_rename_owner() from public, anon, authenticated;

create or replace trigger team_members_rename_owner after update of name on public.team_members
  for each row when (old.name is distinct from new.name) execute function public.team_members_rename_owner();

-- END OF HAND-OVER TAKES CLIENTS ---------------------------------------------

select public.functions_tidy();
