-- ===========================================================================
-- OWNERS BY ID (2026-11-28)
-- ===========================================================================
-- WHY: restructure release 2 (docs/MAP.md §G). A campaign's Person in
-- charge was held by name alone (`campaigns.owner`), and a client's was
-- resolved from the name written (`client_owner_id_stamp`), matched again
-- by name in the hand-over, the rename and the work a colleague holds; the
-- Activity record named its actor and a colleague it was about by name. A
-- renamed colleague, or two of one name, moved work and access to the
-- wrong person. A colleague is traced by their id; the name is a snapshot.
-- WHAT IT CHANGES
--   * `clients.owner_id` is read by a signed-in colleague (its select grant
--     was never given: the pages could not read it).
--   * `campaigns.owner_id` (uuid, on delete set null, indexed), read and
--     written by the pages; backfilled only where exactly one colleague
--     holds the name.
--   * `owner_id_stamp()` (triggers `client_owner_id_stamp` and
--     `campaign_owner_id_stamp`, before insert or update of owner,
--     owner_id; replaces the function `client_owner_id_stamp`): the id
--     leads. An id written takes its colleague's name as the snapshot; an
--     id cleared clears the name. A name alone (an open tab served before
--     this release) is taken to an id only where exactly one colleague not
--     removed holds it (`client_owner_id_of`, no longer "the active first").
--   * `clients_owner_guard` also fires on `owner_id`, so a change of the
--     Person in charge by id asks Clients at Full control as by name.
--   * `team_members_rename_owner`, `team_hand_over`, `team_work_held` find
--     a colleague's clients and campaigns by `owner_id`, never the name.
--   * `activity_log.actor_id` (who did it) and `member_id` (the colleague a
--     line is about), on delete set null. `activity_log_actor_id()` (before
--     insert) stamps the actor's id where the line names the caller (their
--     name or address); backfilled where one colleague holds the name or
--     the address. `personnel_revealed` files and reads them by id.
-- ORDER: this file first, then the pages (they read `clients.owner_id`
-- through its new grant and write `owner_id`). An open tab served before
-- writes the name, which the stamp still takes to its one colleague.
-- ROLLBACK: run ACCESS SECURITY FIXES' `client_owner_id_of`,
-- `client_owner_id_stamp` and its trigger, and the latest earlier bands of
-- `clients_owner_guard` (and its trigger `before update of owner`),
-- `team_members_rename_owner`, `team_hand_over`, `team_work_held` and
-- `personnel_revealed` again; drop trigger campaign_owner_id_stamp on
-- public.campaigns; drop trigger activity_log_actor_id on
-- public.activity_log; drop function public.owner_id_stamp(); drop function
-- public.activity_log_actor_id(). The columns stay. Safe to run twice.

-- OWNERS BY ID -------------------------------------------------------------

grant select (owner_id) on table public.clients to authenticated;

alter table public.campaigns add column if not exists owner_id uuid
  references public.team_members(id) on delete set null;
create index if not exists campaigns_owner_id_idx on public.campaigns (owner_id);
grant select (owner_id), insert (owner_id), update (owner_id) on table public.campaigns to authenticated;

alter table public.activity_log add column if not exists actor_id uuid
  references public.team_members(id) on delete set null;
alter table public.activity_log add column if not exists member_id uuid
  references public.team_members(id) on delete set null;
create index if not exists activity_log_member_id_idx on public.activity_log (member_id) where member_id is not null;

/* The one colleague of a name, not removed; none where two hold it. */
create or replace function public.client_owner_id_of(p_owner text)
returns uuid language sql stable security definer set search_path = public as $$
  select min(t.id::text)::uuid from public.team_members t
   where nullif(btrim(coalesce(p_owner, '')), '') is not null
     and lower(btrim(t.name)) = lower(btrim(p_owner)) and t.removed_at is null
  having count(*) = 1
$$;
revoke all on function public.client_owner_id_of(text) from public, anon, authenticated;

/* The Person in charge of a client or a campaign: the id leads, the name
   is its snapshot. */
create or replace function public.owner_id_stamp()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  if tg_op = 'UPDATE' and new.owner is not distinct from old.owner
     and new.owner_id is not distinct from old.owner_id then
    return new;
  end if;
  if new.owner_id is not null then
    select t.name into v_name from public.team_members t where t.id = new.owner_id;
    /* An id written, or kept beside its own colleague's name (a rename
       carried by `team_members_rename_owner`), names the snapshot. */
    if tg_op = 'INSERT' or new.owner_id is distinct from old.owner_id
       or lower(btrim(coalesce(new.owner, ''))) is not distinct from lower(btrim(coalesce(v_name, ''))) then
      new.owner := coalesce(v_name, new.owner);
      return new;
    end if;
  elsif tg_op = 'UPDATE' and old.owner_id is not null then
    /* The id cleared: nobody holds it. */
    new.owner := null;
    return new;
  end if;
  /* A name alone, from a tab served before the id was written. */
  if nullif(btrim(coalesce(new.owner, '')), '') is null then
    new.owner := null;
    new.owner_id := null;
    return new;
  end if;
  new.owner_id := public.client_owner_id_of(new.owner);
  return new;
end $$;
revoke all on function public.owner_id_stamp() from public, anon, authenticated;

/* Named to fire before the scope and owner guards, which read the id. */
drop trigger if exists client_owner_id_stamp on public.clients;
create trigger client_owner_id_stamp before insert or update of owner, owner_id on public.clients
  for each row execute function public.owner_id_stamp();
drop function if exists public.client_owner_id_stamp();

/* Backfill with the trigger off, then on: a campaign's name held by
   exactly one colleague takes that colleague's id. */
drop trigger if exists campaign_owner_id_stamp on public.campaigns;
do $$
begin
  update public.campaigns g set owner_id = public.client_owner_id_of(g.owner)
   where g.owner_id is null and nullif(btrim(coalesce(g.owner, '')), '') is not null;
end $$;
create trigger campaign_owner_id_stamp before insert or update of owner, owner_id on public.campaigns
  for each row execute function public.owner_id_stamp();

/* A change of the Person in charge, by name or by id. */
create or replace function public.clients_owner_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if (old.owner_id is not null or nullif(btrim(coalesce(old.owner, '')), '') is not null)
     and (new.owner_id is distinct from old.owner_id or coalesce(btrim(new.owner), '') is distinct from coalesce(btrim(old.owner), ''))
     and (select t.id from public.team_members t
           where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1) is not null
     and not public.allowed('clients', 'manage') and not public.allowed('team', 'manage') then
    raise exception 'Only a colleague at Clients Full Access can change the Person in charge. Please ask one.' using errcode = '42501', hint = 'owner-change';
  end if;
  return new;
end $$;
revoke all on function public.clients_owner_guard() from public, anon, authenticated;
drop trigger if exists clients_owner_guard on public.clients;
create trigger clients_owner_guard before update of owner, owner_id on public.clients
  for each row execute function public.clients_owner_guard();

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
  for r in select c.id, c.name from public.clients c
            where c.owner_id = new.id order by c.id loop
    update public.clients c set owner = v_new where c.id = r.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (v_by, 'client.edited', r.name, 'Person in charge: ' || btrim(old.name) || ' to ' || v_new);
  end loop;
  for r in select g.id, g.title from public.campaigns g where g.owner_id = new.id order by g.id loop
    update public.campaigns g set owner = v_new where g.id = r.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (v_by, 'campaign.edited', r.title, 'Person in charge: ' || btrim(old.name) || ' to ' || v_new);
  end loop;
  return new;
end $$;
revoke all on function public.team_members_rename_owner() from public, anon, authenticated;

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

  for v_kind in select unnest(v_kinds) loop
    v_id := nullif(btrim(coalesce(p_to ->> v_kind, '')), '');
    if v_id is null then continue; end if;
    v_to := v_id::uuid;
    select * into v_who from public.team_members x where x.id = v_to;
    v_n := 0;
    if v_kind = 'clients' then
      perform set_config('adspace.team_owner', 'on', true);
      for r in select c.id, c.name from public.clients c
                where c.owner_id = p_member order by c.id for update loop
        update public.clients c set owner_id = v_to where c.id = r.id;
        insert into public.activity_log (actor, action, subject, detail)
        values (me.name, 'client.edited', r.name, 'Person in charge: ' || v_from.name || ' to ' || v_who.name);
        v_n := v_n + 1;
      end loop;
      perform set_config('adspace.team_owner', 'off', true);
    elsif v_kind = 'campaigns' then
      perform set_config('adspace.team_owner', 'on', true);
      for r in select g.id, g.title from public.campaigns g
                where g.owner_id = p_member
                  and g.state is distinct from 'completed' order by g.id for update loop
        update public.campaigns g set owner_id = v_to where g.id = r.id;
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

create or replace function public.team_work_held(p_member uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_found boolean;
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select true into v_found from public.team_members x where x.id = p_member;
  if not found then
    return jsonb_build_object('error', 'not-found');
  end if;
  return jsonb_build_object('ok', true,
    'clients', (select count(*) from public.clients c where c.owner_id = p_member),
    'campaigns', (select count(*) from public.campaigns g where g.owner_id = p_member
                    and g.state is distinct from 'completed'),
    'client_list', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'slug', c.slug,
                      'client_code', c.client_code, 'stage', c.stage) order by c.name, c.id)
                    from public.clients c where c.owner_id = p_member), '[]'::jsonb),
    'campaign_list', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'title', g.title, 'state', g.state)
                      order by g.title, g.id)
                    from public.campaigns g where g.owner_id = p_member
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

/* Who filed a line, by id, where the line names the caller. */
create or replace function public.activity_log_actor_id()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
begin
  if new.actor_id is not null or nullif(btrim(coalesce(new.actor, '')), '') is null then return new; end if;
  me := public.ops_me();
  if me.id is not null
     and (btrim(new.actor) is not distinct from btrim(me.name) or lower(btrim(new.actor)) is not distinct from lower(me.email)) then
    new.actor_id := me.id;
  end if;
  return new;
end $$;
revoke all on function public.activity_log_actor_id() from public, anon, authenticated;
drop trigger if exists activity_log_actor_id on public.activity_log;
create trigger activity_log_actor_id before insert on public.activity_log
  for each row execute function public.activity_log_actor_id();

/* Backfill: an actor's address, or a name exactly one colleague holds;
   a Signed-in device's line about a colleague by the same rule. */
do $$
begin
  update public.activity_log a set actor_id = m.id
    from public.team_members m
   where a.actor_id is null and position('@' in a.actor) > 0 and lower(m.email) = lower(btrim(a.actor));
  update public.activity_log a set actor_id = public.client_owner_id_of(a.actor)
   where a.actor_id is null and position('@' in coalesce(a.actor, '')) = 0 and nullif(btrim(coalesce(a.actor, '')), '') is not null;
  update public.activity_log a set member_id = public.client_owner_id_of(a.subject)
   where a.member_id is null and a.action = 'team.revealed';
end $$;

create or replace function public.personnel_revealed(p_member uuid, p_field text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members; t public.team_members; g jsonb; v_label text; v_line text;
begin
  if p_member is null then
    g := public.perf_mine_gate();
    if g is not null then return g; end if;
    me := public.ops_me();
    t := me;
  else
    if not public.ops_granted('team.personnel', 'work') then return jsonb_build_object('error', 'denied'); end if;
    me := public.ops_me();
    select * into t from public.team_members x where x.id = p_member;
    if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_field is null or not (p_field = any (public.personnel_hidden())) then
    return jsonb_build_object('error', 'bad-field');
  end if;
  v_label := public.personnel_fields() -> p_field ->> 1;
  v_line := v_label || ' shown';
  if not exists (select 1 from public.activity_log a
                  where a.action = 'team.revealed' and a.actor_id = me.id and a.member_id = t.id and a.detail = v_line
                    and a.created_at > now() - interval '1 minute') then
    insert into public.activity_log (actor, actor_id, action, subject, member_id, detail)
    values (me.name, me.id, 'team.revealed', t.name, t.id, v_line);
  end if;
  -- The value itself, answered only here, each time filed above.
  return jsonb_build_object('ok', true,
    'value', (select r.data ->> p_field from public.personnel_records r where r.team_member_id = t.id));
end $$;
revoke all on function public.personnel_revealed(uuid, text) from public, anon;
grant execute on function public.personnel_revealed(uuid, text) to authenticated;

-- END OF OWNERS BY ID ---------------------------------------------------------

select public.functions_tidy();
