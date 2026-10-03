-- ===========================================================================
-- CLIENT SCOPE — leads, past clients and a group's own clients, held by the
-- database in every section that hangs off a client.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/levels.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-03: leads and past clients are the
-- managers' and sales' portion; "give option to view or manage or x leads,
-- same goes to past clients"; Own clients only "covers all", an unassigned
-- lead is seen and taken)
--   1. Two parts under Clients, `clients.leads` (Lead, Contacted, Proposal
--      sent) and `clients.past` (Past), each No Access, View or Manage, and
--      Same as section where unset. They narrow and never widen: a lead is
--      read at the lesser of the group's Clients level and its Leads level.
--      The Members group (slug `account`) starts at No Access on both, as the
--      user chose; every other group stays as it was.
--   2. `team_roles.client_scope`, copied to `team_members` with the rest of a
--      group: `all` (as before) or `own`, the clients where the colleague is
--      Person in charge, and any lead nobody is in charge of, to see and take.
--   3. The rule is one function, `client_row_seen(stage, owner, level)`, and
--      the database holds it everywhere a client's work is kept:
--      - a restrictive read policy, `client_scope`, on the client and every
--        table under it (contacts, services, letters, calls, requests,
--        documents, Drive imports, campaigns and their bookings, content
--        sets and posts, reports): a row on a client somebody may not see
--        never arrives;
--      - a guard trigger, `client_scope_guard`, on the same tables, which
--        also catches the security definer functions that write them: a
--        write needs Manage on the client's band (`client-scope`, in the
--        team's words);
--      - My Work through its two helpers: `ops_may_see_task` keeps a
--        colleague's own tasks and gives the whole queue (`ops.all`) only
--        the clients they may see, `ops_may_see_engagement` the same for
--        months, `ops_scope_error` refuses a task on a client out of reach,
--        and `ops_report` counts and names only those tasks;
--      - the functions that read past the policies: `client_billing`,
--        `sm_client_reports`, `sm_report_file`, `sm_report_snapshot`.
--   4. Person in charge changes from one colleague to another only at
--      Clients Full Access, or at Team Full Access for a stand-down or a
--      rename (`owner-change`); taking a lead nobody is in charge of needs
--      Leads at Manage.
--   Not covered: the Activity record keeps one log for every client (its
--   tabs are their own parts), and a client's own pages read through their
--   token functions as before.
--
-- ROLLBACK
--   For each table in the list below:
--     drop policy if exists client_scope on public.<table>;
--     drop trigger if exists client_scope_guard on public.<table>;
--   Then re-run ops_may_see_task, ops_may_see_engagement, ops_scope_error,
--   ops_report, client_billing, sm_client_reports, sm_report_file,
--   sm_report_snapshot and team_role_defaults from their own sections, and
--   remove the functions client_row_seen(text, text, text),
--   client_seen(uuid, text), client_of(text, uuid),
--   client_scope_free(text), client_scope_ok(text, uuid, text),
--   client_scope_guard() and ops_task_in_scope(uuid). The columns may stay;
--   take `clients.leads` and `clients.past` out of a group's access in Team.
-- ===========================================================================

alter table public.team_roles add column if not exists client_scope text not null default 'all';
alter table public.team_members add column if not exists client_scope text not null default 'all';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'team_roles_client_scope') then
    alter table public.team_roles add constraint team_roles_client_scope check (client_scope in ('all', 'own'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'team_members_client_scope') then
    alter table public.team_members add constraint team_members_client_scope check (client_scope in ('all', 'own'));
  end if;
end $$;

-- A member carries their group's switches, its scope among them.
create or replace function public.team_role_defaults()
returns trigger language plpgsql as $$
declare r public.team_roles;
begin
  select * into r from public.team_roles where slug = new.role;
  if r.slug is null then
    select * into r from public.team_roles where slug = 'account';
    new.role := 'account';
  end if;
  new.is_admin      := r.is_admin;
  new.can_clients   := r.can_clients;   new.can_review   := r.can_review;
  new.can_campaigns := r.can_campaigns; new.can_links    := r.can_links;
  new.can_activity  := r.can_activity;  new.can_billing  := r.can_billing;
  new.can_remove    := r.can_remove;    new.can_doc_void := r.can_doc_void;
  new.access        := coalesce(r.access, '{}'::jsonb);
  new.client_scope  := coalesce(r.client_scope, 'all');
  new.updated_at    := now();
  return new;
end $$;

/* The one rule. A client in the lead stages answers to `clients.leads`, a
   past client to `clients.past`, each falling back to the Clients level
   where unset; an active or paused client answers to the section asking.
   Own clients only keeps the clients the colleague is Person in charge of,
   and a lead nobody is in charge of. Somebody who is not on the team is
   left to the other policies, so a client's own pages are untouched. */
create or replace function public.client_row_seen(p_stage text, p_owner text, p_level text)
returns boolean language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members;
  band text;
begin
  select * into t from public.team_members
   where lower(email) = lower(auth.jwt() ->> 'email') and active limit 1;
  if t.id is null or t.is_admin or t.role = 'admin' then return true; end if;
  band := case when p_stage in ('lead', 'contacted', 'proposal') then 'clients.leads'
               when p_stage = 'past' then 'clients.past' end;
  if band is not null and public.level_rank(coalesce(t.access ->> band, t.access ->> 'clients'))
                          < public.level_rank(p_level) then
    return false;
  end if;
  if coalesce(t.client_scope, 'all') = 'own' then
    if nullif(btrim(coalesce(p_owner, '')), '') is null then
      return coalesce(band = 'clients.leads', false);
    end if;
    return lower(btrim(p_owner)) = lower(btrim(coalesce(t.name, '')));
  end if;
  return true;
end $$;
revoke all on function public.client_row_seen(text, text, text) from public, anon, authenticated;

-- A client by its id; no client (internal work) and a client gone are
-- left to the other policies.
create or replace function public.client_seen(p_client uuid, p_level text default 'view')
returns boolean language plpgsql security definer stable set search_path = public as $$
declare
  st text;
  ow text;
begin
  if p_client is null then return true; end if;
  select c.stage, c.owner into st, ow from public.clients c where c.id = p_client;
  if not found then return true; end if;
  return public.client_row_seen(st, ow, p_level);
end $$;
revoke all on function public.client_seen(uuid, text) from public, anon, authenticated;

-- The client a row hangs off, read past the policies.
create or replace function public.client_of(p_kind text, p_id uuid)
returns uuid language sql security definer stable set search_path = public as $$
  select case p_kind
    when 'client' then p_id
    when 'campaign' then (select c.client_id from public.campaigns c where c.id = p_id)
    when 'option' then (select c.client_id from public.campaign_options o
                          join public.campaigns c on c.id = o.campaign_id where o.id = p_id)
    when 'batch' then (select b.client_id from public.batches b where b.id = p_id)
    when 'post' then (select b.client_id from public.posts p
                        join public.batches b on b.id = p.batch_id where p.id = p_id)
    when 'report' then (select r.client_id from public.sm_reports r where r.id = p_id)
  end
$$;
revoke all on function public.client_of(text, uuid) from public, anon, authenticated;

/* True where the rule cannot hide anything from the caller at this level:
   not on the team, an admin, or every client at the level with both bands
   reaching it. A policy asks it once a statement (`(select …)`), so the
   ordinary group pays nothing a row. */
create or replace function public.client_scope_free(p_level text default 'view')
returns boolean language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
   where lower(email) = lower(auth.jwt() ->> 'email') and active limit 1;
  if t.id is null or t.is_admin or t.role = 'admin' then return true; end if;
  if coalesce(t.client_scope, 'all') = 'own' then return false; end if;
  return public.level_rank(coalesce(t.access ->> 'clients.leads', t.access ->> 'clients')) >= public.level_rank(p_level)
     and public.level_rank(coalesce(t.access ->> 'clients.past', t.access ->> 'clients')) >= public.level_rank(p_level);
end $$;
revoke all on function public.client_scope_free(text) from public, anon;
grant execute on function public.client_scope_free(text) to authenticated;

-- The rule for one row, by what it hangs off. Answers a boolean only.
create or replace function public.client_scope_ok(p_kind text, p_id uuid, p_level text default 'view')
returns boolean language sql security definer stable set search_path = public as $$
  select public.client_seen(public.client_of(p_kind, p_id), p_level)
$$;
revoke all on function public.client_scope_ok(text, uuid, text) from public, anon;
grant execute on function public.client_scope_ok(text, uuid, text) to authenticated;

/* Every write, whoever makes it (a page or a security definer function):
   the row before and the row after must both be the caller's at Manage.
   A write made by another trigger (a cascade, a stamp) was already asked.
   A removal is not guarded here: a browser's reaches only rows its read
   policy shows (PostgREST names the row it removes), and the functions that
   remove ask their own permission first. */
create or replace function public.client_scope_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  kind text := tg_argv[0];
  col  text := tg_argv[1];
  o jsonb;
  n jsonb := to_jsonb(new);
begin
  if pg_trigger_depth() > 1 or public.client_scope_free('work') then return new; end if;
  if tg_op = 'UPDATE' then
    o := to_jsonb(old);
    if (kind = 'self' and not public.client_row_seen(o ->> 'stage', o ->> 'owner', 'work'))
       or (kind <> 'self' and not public.client_scope_ok(kind, (o ->> col)::uuid, 'work')) then
      raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
    end if;
  end if;
  if (kind = 'self' and not public.client_row_seen(n ->> 'stage', n ->> 'owner', 'work'))
     or (kind <> 'self' and not public.client_scope_ok(kind, (n ->> col)::uuid, 'work')) then
    raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
  end if;
  return new;
end $$;
revoke all on function public.client_scope_guard() from public, anon, authenticated;

/* Person in charge moves from one colleague to another at Clients Full
   Access, or at Team Full Access, which stands a colleague down and renames
   them and carries both onto their clients; a lead nobody holds is taken at
   Leads Manage, which the guard above has already asked. */
create or replace function public.clients_owner_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if nullif(btrim(coalesce(old.owner, '')), '') is not null
     and coalesce(btrim(new.owner), '') is distinct from btrim(old.owner)
     and (select t.id from public.team_members t
           where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1) is not null
     and not public.allowed('clients', 'manage') and not public.allowed('team', 'manage') then
    raise exception 'Person in charge is changed at Clients Full Access.' using errcode = '42501', hint = 'owner-change';
  end if;
  return new;
end $$;
revoke all on function public.clients_owner_guard() from public, anon, authenticated;
create or replace trigger clients_owner_guard before update of owner on public.clients
  for each row execute function public.clients_owner_guard();

/* The tables a client's work is kept in, and what each hangs off. A read is
   one restrictive policy (it narrows what the other policies allow and
   never widens it); a write is the guard. Altered in place when it exists,
   so a second run changes nothing. */
do $$
declare
  spec text[][] := array[
    ['clients', 'self', 'id'],
    ['client_contacts', 'client', 'client_id'],
    ['client_services', 'client', 'client_id'],
    ['client_documents', 'client', 'client_id'],
    ['client_document_deletions', 'client', 'client_id'],
    ['client_requests', 'client', 'client_id'],
    ['client_touches', 'client', 'client_id'],
    ['documents', 'client', 'client_id'],
    ['drive_assets', 'client', 'client_id'],
    ['campaigns', 'client', 'client_id'],
    ['campaign_confirmations', 'campaign', 'campaign_id'],
    ['campaign_options', 'campaign', 'campaign_id'],
    ['campaign_deliverables', 'option', 'option_id'],
    ['option_posts', 'option', 'option_id'],
    ['option_qc', 'option', 'option_id'],
    ['option_reviews', 'option', 'option_id'],
    ['batches', 'client', 'client_id'],
    ['posts', 'batch', 'batch_id'],
    ['post_versions', 'post', 'post_id'],
    ['reviews', 'post', 'post_id'],
    ['sm_reports', 'client', 'client_id'],
    ['sm_report_ads', 'report', 'report_id'],
    ['sm_report_platforms', 'report', 'report_id'],
    ['sm_report_posts', 'report', 'report_id'],
    ['sm_report_versions', 'report', 'report_id'],
    ['ops_engagements', 'client', 'client_id']];
  i int;
  tbl text;
  kind text;
  col text;
  rule text;
begin
  for i in 1 .. array_length(spec, 1) loop
    tbl := spec[i][1]; kind := spec[i][2]; col := spec[i][3];
    if to_regclass('public.' || tbl) is null then continue; end if;
    rule := format('(select public.client_scope_free(%L)) or public.client_scope_ok(%L, %I, %L)',
                   'view', case when kind = 'self' then 'client' else kind end, col, 'view');
    /* My Work's months are read through `ops_may_see_engagement`; only the
       guard is theirs here. */
    if tbl <> 'ops_engagements' then
      if exists (select 1 from pg_policies where schemaname = 'public' and tablename = tbl
                  and policyname = 'client_scope') then
        execute format('alter policy client_scope on public.%I using (%s)', tbl, rule);
      else
        execute format('create policy client_scope on public.%I as restrictive for select to authenticated using (%s)',
                       tbl, rule);
      end if;
    end if;
    execute format('create or replace trigger client_scope_guard before insert or update on public.%I '
                   || 'for each row execute function public.client_scope_guard(%L, %L)', tbl, kind, col);
  end loop;
end $$;

-- The Members group starts at No Access on leads and past clients (the
-- user, 2026-10-03), once: a group that already says anything about either
-- is left as it is.
do $$
declare g public.team_roles;
begin
  select * into g from public.team_roles where slug = 'account';
  if g.slug is not null and not (coalesce(g.access, '{}'::jsonb) ? 'clients.leads')
     and not (coalesce(g.access, '{}'::jsonb) ? 'clients.past') then
    update public.team_roles
       set access = coalesce(access, '{}'::jsonb) || '{"clients.leads": "none", "clients.past": "none"}'::jsonb
     where slug = 'account';
    insert into public.activity_log (actor, action, subject, detail)
    values ('system', 'team.group_changed', g.name,
            'Clients · Leads: Same as section → No Access; Clients · Past clients: Same as section → No Access');
  end if;
end $$;

/* A task is in scope where it is the colleague's own work, or it hangs off a
   client they may see (no client: internal work). */
create or replace function public.ops_task_in_scope(p_task uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select public.client_scope_free('view')
      or exists (select 1 from public.ops_tasks t
                  where t.id = p_task
                    and (t.created_by = (select id from public.ops_me())
                         or exists (select 1 from public.ops_task_assignees a
                                     where a.task_id = t.id and a.ended_at is null
                                       and a.team_member_id = (select id from public.ops_me()))))
      or public.client_seen((select t.client_id from public.ops_tasks t where t.id = p_task), 'view')
$$;
revoke all on function public.ops_task_in_scope(uuid) from public, anon, authenticated;

/* May the signed-in colleague read this task? Their own work always: owner,
   contributor, reviewer or the person who asked for it. The whole team's
   work with `ops.all`, on the clients they may see. */
create or replace function public.ops_may_see_task(p_task uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when not public.allowed('ops', 'view') then false
    when public.ops_granted('ops.all', 'view') and public.client_scope_free('view') then true
    when exists (
      select 1 from public.ops_tasks t
       where t.id = p_task
         and (t.created_by = (select id from public.ops_me())
              or exists (select 1 from public.ops_task_assignees a
                          where a.task_id = t.id and a.ended_at is null
                            and a.team_member_id = (select id from public.ops_me())))) then true
    when public.ops_granted('ops.all', 'view')
      then public.client_seen((select t.client_id from public.ops_tasks t where t.id = p_task), 'view')
    else false
  end
$$;
grant execute on function public.ops_may_see_task(uuid) to authenticated;

/* An engagement is read by whoever manages it or created it, by anybody who
   may see a task inside it, and by the team queue on the clients it may
   see. */
create or replace function public.ops_may_see_engagement(p_engagement uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when not public.allowed('ops', 'view') then false
    when public.ops_granted('ops.all', 'view') and public.client_scope_free('view') then true
    else exists (
      select 1 from public.ops_engagements e
       where e.id = p_engagement
         and (e.manager_id = (select id from public.ops_me())
              or e.created_by = (select id from public.ops_me())
              or (public.ops_granted('ops.all', 'view') and public.client_seen(e.client_id, 'view'))
              or exists (select 1 from public.ops_tasks t
                          where t.engagement_id = e.id and public.ops_may_see_task(t.id))))
  end
$$;
grant execute on function public.ops_may_see_engagement(uuid) to authenticated;

-- A task is made only on a client the colleague may work.
create or replace function public.ops_scope_error(p_scope text, p_client uuid)
returns text
language plpgsql stable as $$
declare st text;
begin
  if p_scope = 'internal' then return null; end if;
  if p_scope not in ('client', 'lead') then return 'bad-scope'; end if;
  if p_client is null then return 'client-required'; end if;
  select stage into st from public.clients where id = p_client;
  if st is null then return 'client-required'; end if;
  if p_scope = 'client' and st not in ('active', 'paused', 'past') then return 'client-not-active'; end if;
  if p_scope = 'lead' and st not in ('lead', 'contacted', 'proposal') then return 'not-a-lead'; end if;
  if not public.client_seen(p_client, 'work') then return 'client-scope'; end if;
  return null;
end $$;

create or replace function public.ops_report(
  p_from timestamptz default (now() - interval '90 days'),
  p_to   timestamptz default now())
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  out jsonb;
begin
  if not public.ops_granted('ops.reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;

  with
  /* Where client review begins in each workflow. The final due date is the
     day the work is owed AT that stage, so everything below that position is
     "has not reached the client yet". Read from `stage_group` and never from
     a stage key: the two seeded workflows name that stage differently. */
  floors as (
    select workflow_id, min(position) as at
      from public.ops_workflow_stages
     where stage_group = 'client_review'
     group by workflow_id
  ),
  live as (
    select t.*, s.label as stage_label, s.position as stage_position,
           s.stage_group, f.at as review_at
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.workflow_id = t.workflow_id and s.key = t.stage_key
      left join floors f on f.workflow_id = t.workflow_id
     where t.completed_at is null and t.cancelled_at is null
       and t.archived_at is null
       and public.ops_task_in_scope(t.id)
  ),

  /* 1. WHAT IS RUNNING, by the words on the screen. Grouped by the stage's
        own label rather than by its group, because "what is on shooting" is
        the question and Shooting is a label, not a group. */
  running as (
    select jsonb_agg(x order by x ->> 'position', x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key, 'label', stage_label,
               'position', stage_position, 'stage_group', stage_group,
               'count', count(*)) as x
        from live
       group by stage_key, stage_label, stage_position, stage_group
    ) q
  ),

  /* 2. WHAT IS LATE. Past the commitment and still short of client review.
        The same rule the queue row draws, stated once more here because a
        report a page computes for itself is a second definition. */
  late as (
    select jsonb_agg(x order by x ->> 'due_at') as j from (
      select jsonb_build_object(
               'task_id', l.id, 'task_no', l.task_no, 'title', l.title,
               'client', c.name, 'stage', l.stage_label,
               'due_at', l.current_final_due_at,
               'days_over', (current_date - l.current_final_due_at::date),
               'owner', (select tm.name
                           from public.ops_task_assignees a
                           join public.team_members tm on tm.id = a.team_member_id
                          where a.task_id = l.id and a.responsibility = 'owner'
                            and a.ended_at is null
                          limit 1)) as x
        from live l
        left join public.clients c on c.id = l.client_id
       where l.current_final_due_at is not null
         and l.current_final_due_at::date < current_date
         and (l.review_at is null or l.stage_position < l.review_at)
    ) q
  ),

  /* 3. HOW LONG EACH STAGE TAKES. A task enters a stage at the event that
        names it and leaves at the next event, or at its own ending, or now.
        Only spans that were ENTERED inside the period are counted, so the
        window means what it says and a task that sat in Editing since March
        does not land in every report for ever. */
  spans as (
    select e.task_id,
           e.to_value ->> 'stage_key' as stage_key,
           e.created_at as from_at,
           coalesce(
             lead(e.created_at) over (partition by e.task_id order by e.created_at),
             t.completed_at, t.cancelled_at, now()) as to_at
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
     where e.event_type in ('task_created', 'stage_changed')
       and e.to_value ->> 'stage_key' is not null
  ),
  /* One row per span and no grouping: an earlier draft grouped by the span's
     own timestamps, which silently collapsed two tasks that entered the same
     stage in the same instant into one measurement. The label is looked up
     once per stage below instead of aggregated here. */
  span_mins as (
    select s.stage_key,
           extract(epoch from (s.to_at - s.from_at)) / 60 as mins
      from spans s
     where s.from_at >= p_from and s.from_at < p_to
       and s.to_at > s.from_at
  ),
  stage_time as (
    select jsonb_agg(x order by x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key,
               'label', coalesce((select w.label from public.ops_workflow_stages w
                                   where w.key = sm.stage_key limit 1), stage_key),
               'n', count(*),
               'median_minutes', round(percentile_cont(0.5) within group (order by mins))::int,
               'p90_minutes', round(percentile_cont(0.9) within group (order by mins))::int) as x
        from span_mins sm
       group by stage_key
    ) q
  ),

  /* 4. WAS IT THERE ON TIME. Of the tasks that reached client review inside
        the period, how many got there on or before the date they were owed.
        Replanning is counted beside it and never folded into it: an extension
        that moves the date would otherwise erase the miss it was granted for,
        and a rate that cannot be missed is not a measurement. */
  reached as (
    select distinct on (e.task_id)
           e.task_id, e.created_at as at, t.current_final_due_at as due,
           (t.original_final_due_at is distinct from t.current_final_due_at) as replanned
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
      join public.ops_workflow_stages w
        on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
     where e.event_type = 'stage_changed'
       and w.stage_group = 'client_review'
       and e.created_at >= p_from and e.created_at < p_to
     order by e.task_id, e.created_at
  ),
  on_time as (
    select jsonb_build_object(
             'reached', count(*),
             'met', count(*) filter (where due is null or at::date <= due::date),
             'missed', count(*) filter (where due is not null and at::date > due::date),
             'replanned', count(*) filter (where replanned)) as j
      from reached
  ),

  /* 5. BY PERSON. The foundation of a KPI and not a KPI: what somebody
        finished in the window, how much of it was on time, and how long their
        work took end to end. No ranking and no score — a number a person can
        check is worth more than a league table nobody trusts. */
  done as (
    select t.id, t.created_at, coalesce(t.completed_at, t.delivered_at) as ended,
           t.current_final_due_at as due,
           (select a.team_member_id
              from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc
             limit 1) as owner_id
      from public.ops_tasks t
     where t.completed_at is not null
       and t.completed_at >= p_from and t.completed_at < p_to
  ),
  by_person as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', d.owner_id,
               'name', coalesce(tm.name, 'Nobody'),
               'completed', count(*),
               'on_time', count(*) filter (where d.due is null or d.ended::date <= d.due::date),
               'median_cycle_minutes',
                 round(percentile_cont(0.5) within group (
                   order by extract(epoch from (d.ended - d.created_at)) / 60))::int) as x
        from done d
        left join public.team_members tm on tm.id = d.owner_id
       group by d.owner_id, tm.name
    ) q
  ),

  /* 6. WHO IS CARRYING THE OPEN WORK (2026-09-28). One row a Task Owner:
        the open tasks they hold, and how many of those are late by the rule
        in 2 above. The team's whole queue is `ops.all`, so it is answered
        only where that part is granted. */
  open_by_person as (
    select jsonb_agg(x order by (x ->> 'open')::int desc, x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', o.owner_id,
               'name', coalesce(tm.name, 'No task owner'),
               'open', count(*),
               'late', count(*) filter (where o.is_late)) as x
        from (select l.id,
                     (select a.team_member_id
                        from public.ops_task_assignees a
                       where a.task_id = l.id and a.responsibility = 'owner' and a.ended_at is null
                       limit 1) as owner_id,
                     (l.current_final_due_at is not null
                      and l.current_final_due_at::date < current_date
                      and (l.review_at is null or l.stage_position < l.review_at)) as is_late
                from live l) o
        left join public.team_members tm on tm.id = o.owner_id
       where public.ops_granted('ops.all', 'view')
       group by o.owner_id, tm.name
    ) q
  )

  select jsonb_build_object(
           'from', p_from, 'to', p_to,
           'running',    coalesce((select j from running), '[]'::jsonb),
           'late',       coalesce((select j from late), '[]'::jsonb),
           'stage_time', coalesce((select j from stage_time), '[]'::jsonb),
           'on_time',    coalesce((select j from on_time), '{}'::jsonb),
           'by_person',  coalesce((select j from by_person), '[]'::jsonb),
           'open_by_person', case when public.ops_granted('ops.all', 'view')
                                  then coalesce((select j from open_by_person), '[]'::jsonb) end)
    into out;

  return out;
end $$;
grant execute on function public.ops_report(timestamptz, timestamptz) to authenticated;

create or replace function public.client_billing(p_ids uuid[] default null)
returns table (id uuid, legal_name text, company_no text, company_no_old text, tin text,
               sst_no text, bill_contact_id uuid, bill_contact text, bill_contact_email text,
               bill_contact_phone text, finance_email text, billing_address text,
               billing_missing text[])
language sql stable security definer set search_path = public as $$
  select c.id,
         case when p.bill or p.docs then c.legal_name end,
         case when p.bill then c.company_no end,
         case when p.bill then c.company_no_old end,
         case when p.bill then c.tin end,
         case when p.bill then c.sst_no end,
         case when p.bill then c.bill_contact_id end,
         case when p.bill then c.bill_contact end,
         case when p.bill then c.bill_contact_email end,
         case when p.bill then c.bill_contact_phone end,
         case when p.bill then c.finance_email end,
         case when p.bill or p.docs then c.billing_address end,
         array_remove(array[
           case when coalesce(btrim(c.legal_name), '') = '' then 'legal_name' end,
           case when coalesce(btrim(c.company_no), '') = '' then 'company_no' end,
           case when coalesce(btrim(c.billing_address), '') = '' then 'billing_address' end], null)
    from public.clients c,
         (select public.allowed('clients.billing', 'view') as bill,
                 public.register_may('client', 'work') as docs,
                 public.allowed('clients', 'view') as cv) p
   where (p.bill or p.docs or p.cv)
     and (p_ids is null or c.id = any(p_ids))
     and public.client_seen(c.id, 'view')
$$;
revoke all on function public.client_billing(uuid[]) from public, anon;
grant execute on function public.client_billing(uuid[]) to authenticated;

create or replace function public.sm_client_reports(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if not public.allowed('clients', 'view') and not public.allowed('reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.client_seen(p_client, 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('reports', coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period_start', r.period_start,
             'period_end', r.period_end, 'status', r.status, 'version_no', r.version_no,
             'confirmed_at', r.confirmed_at, 'live_version', v.version_no, 'published_at', v.published_at)
           order by r.period_start desc, r.kind)
      from public.sm_reports r
      left join lateral (select x.version_no, x.published_at from public.sm_report_versions x
                          where x.report_id = r.id and x.withdrawn_at is null
                          order by x.version_no desc limit 1) v on true
     where r.client_id = p_client
       and (r.status in ('confirmed', 'published') or v.version_no is not null)), '[]'::jsonb));
end $$;
grant execute on function public.sm_client_reports(uuid) to authenticated;

create or replace function public.sm_report_file(p_id uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  snap jsonb;
begin
  if not public.allowed('clients', 'view') and not public.allowed('reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  select x.snapshot into snap from public.sm_report_versions x
   where x.report_id = p_id and x.withdrawn_at is null order by x.version_no desc limit 1;
  if snap is not null then return jsonb_build_object('snapshot', snap); end if;
  if r.status <> 'confirmed' then return jsonb_build_object('error', 'not-finished'); end if;
  return jsonb_build_object('snapshot', public.sm_report_snapshot(p_id, false));
end $$;
grant execute on function public.sm_report_file(uuid) to authenticated;

create or replace function public.sm_report_snapshot(p_id uuid, p_final boolean default false)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  c public.clients;
begin
  if not public.allowed('reports', 'view') and not public.allowed('clients', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  -- Somebody who reads Clients but not Reports reads the finished report
  -- only: once it is confirmed, never while it is being prepared.
  if not public.allowed('reports', 'view') and r.status not in ('confirmed', 'published') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into c from public.clients where id = r.client_id;
  return jsonb_build_object(
    'report', jsonb_build_object(
      'id', r.id, 'kind', r.kind, 'title', r.title, 'client_name', c.name, 'client_logo_url', c.logo_url,
      'market', to_jsonb(c) ->> 'market', 'lang', r.lang,
      'period_start', r.period_start, 'period_end', r.period_end,
      'headline', r.headline, 'intro', r.intro, 'insights', r.insights, 'rank_metric', r.rank_metric,
      'first_month', r.first_month, 'ads_totals', r.ads_totals,
      'status', case when p_final then 'final' else r.status end,
      'version_no', r.version_no, 'generated_at', now(),
      'prepared_by_name', (select name from public.team_members where id = r.submitted_by)),
    'platforms', coalesce((select jsonb_agg(to_jsonb(p) - 'created_at' order by p.position, p.created_at)
                  from public.sm_report_platforms p where p.report_id = r.id), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg((to_jsonb(q) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', q.thumb_data)
                  order by q.posted_on nulls last, q.position, q.created_at)
                  from public.sm_report_posts q where q.report_id = r.id), '[]'::jsonb),
    'ads', coalesce((select jsonb_agg((to_jsonb(a) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', a.thumb_data)
                  order by a.position, a.created_at)
                  from public.sm_report_ads a where a.report_id = r.id), '[]'::jsonb));
end $$;
grant execute on function public.sm_report_snapshot(uuid, boolean) to authenticated;

-- END OF CLIENT SCOPE --------------------------------------------------------
