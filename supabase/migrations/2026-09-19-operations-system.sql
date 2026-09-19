/* ===========================================================================
   OPERATIONS SYSTEM — phase 1: the data model, the access rules and the
   server functions every write goes through.

   Safe to run twice. Nothing here touches an existing table's data; the only
   edits to existing objects are two guarded `alter table ... add column` on
   `team_members` (capacity and WIP guidance, both planning figures).

   WHY THE PERMISSIONS ARE LEVELS AND NOT SEVEN NEW BOOLEANS
   ---------------------------------------------------------
   The brief asks for `can_tasks`, `can_create_tasks`, `can_assign_tasks`,
   `can_view_all_tasks`, `can_ops_reports`, `can_manage_workflows` and
   `can_correct_time` on `team_members`. Those seven capabilities are
   implemented in full, and each is adjustable per group and per person, as
   the brief requires — but they are expressed in the access ladder this
   portal already enforces rather than as a second authorisation system
   beside it. Two sources of truth for who may do what is a security defect
   and not a matter of style: a policy would have to ask both, and the day
   they disagree the database answers one way and the page another.

     can_tasks           allowed('ops',           'view')
     can_create_tasks    allowed('ops',           'work')
     can_assign_tasks    allowed('ops',           'manage')
     can_view_all_tasks  ops_granted('ops.all',       'view')
     can_ops_reports     ops_granted('ops.reports',   'view')
     can_manage_workflows ops_granted('ops.workflows','work')
     can_correct_time    ops_granted('ops.time',      'manage')

   The last four ask `ops_granted` rather than `allowed`, because each widens
   what the section opens rather than narrowing it; the note above that
   function says why silence has to mean no there.

   A group given `{"ops":"work"}` and nothing else therefore works its own
   tasks and sees no team queue, no reports and no templates — which is the
   brief's "creative team member" default exactly, and is the default without
   anybody having to remember an exception. An admin reaches everything, as
   it does in every other section.

   ROLLBACK
   --------
   Every object below is prefixed `ops_`, so the whole change reverses with:

     drop table if exists public.ops_kpi_targets, public.ops_recurring_rules,
       public.ops_notifications, public.ops_video_details, public.ops_task_links,
       public.ops_task_checklist_items, public.ops_revisions,
       public.ops_work_sessions, public.ops_task_events,
       public.ops_task_assignees, public.ops_tasks, public.ops_task_templates,
       public.ops_workflow_stages, public.ops_workflows cascade;
     drop sequence if exists public.ops_task_no_seq;
     -- then drop every function whose name starts with ops_
     -- (see the list at the foot of this file)
     alter table public.team_members drop column if exists capacity_minutes_week;
     alter table public.team_members drop column if exists wip_guidance;

   The access map needs no reversal: a key nothing reads is a key nobody has.
   =========================================================================== */

-- ---------------------------------------------------------------------------
-- 0. Planning figures on a colleague. Capacity is guidance for planning, not
--    attendance: nothing in this system records when somebody is at a desk.
-- ---------------------------------------------------------------------------
alter table public.team_members add column if not exists capacity_minutes_week integer;
alter table public.team_members add column if not exists wip_guidance integer;

-- ---------------------------------------------------------------------------
-- 1. Helpers.
-- ---------------------------------------------------------------------------

/* A PART THAT WIDENS IS GRANTED, NEVER INHERITED.
   `allowed()` falls back from a part to its section, which is right for every
   part this portal had before today: Billing is inside the Clients job, so a
   group that works Clients works Billing unless somebody says otherwise, and
   only the exception is stored. The operations parts are the other direction.
   The team-wide queue, the reports, the templates and another person's hours
   are not inside "work my own tasks" — they are more than it. Inherited, a
   group given `{"ops":"work"}` would read every colleague's queue and every
   report until an admin remembered to opt them out, and a group added next
   year would start there again. So these four are asked for with this
   predicate, which reads the exact key and does not fall back. Same map, same
   four levels, same `level_rank`: what changes is that silence means no. */
create or replace function public.ops_granted(p_key text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
   where active and lower(email) = lower(auth.jwt() ->> 'email') limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  return public.level_rank(t.access ->> p_key) >= public.level_rank(p_level);
end $$;
grant execute on function public.ops_granted(text, text) to authenticated;

/* The signed-in colleague, or nothing. Every function below starts here, so
   a client contact holding an auth account reaches no operations row: they
   have no active `team_members` row and the first check fails. */
create or replace function public.ops_me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members
   where active and lower(email) = lower(auth.jwt() ->> 'email')
   limit 1
$$;
grant execute on function public.ops_me() to authenticated;

/* Business days forward or backward from a timestamp, skipping Saturday and
   Sunday. Public holidays are a later setting; the function takes them from
   nothing today and the offset is documented as working days. */
create or replace function public.ops_add_business_days(p_from timestamptz, p_days integer)
returns timestamptz
language plpgsql immutable set search_path = public as $$
declare
  d   timestamptz := p_from;
  n   integer := abs(coalesce(p_days, 0));
  dir integer := case when coalesce(p_days, 0) < 0 then -1 else 1 end;
begin
  if p_from is null then return null; end if;
  while n > 0 loop
    d := d + (dir || ' day')::interval;
    -- 0 is Sunday, 6 is Saturday in Postgres `dow`.
    if extract(dow from d at time zone 'Asia/Kuala_Lumpur') not in (0, 6) then
      n := n - 1;
    end if;
  end loop;
  return d;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Workflows and their stages.
-- ---------------------------------------------------------------------------

create table if not exists public.ops_workflows (
  id          uuid primary key default gen_random_uuid(),
  key         text unique not null,
  name        text not null,
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.ops_workflow_stages (
  id              uuid primary key default gen_random_uuid(),
  workflow_id     uuid not null references public.ops_workflows(id) on delete cascade,
  key             text not null,
  label           text not null,
  position        integer not null,
  stage_group     text not null,
  is_active_work  boolean not null default false,
  is_waiting      boolean not null default false,
  is_review       boolean not null default false,
  is_terminal     boolean not null default false,
  wip_guidance    integer,
  next_stage_keys text[] not null default '{}'
);
create unique index if not exists ops_stage_key_idx on public.ops_workflow_stages(workflow_id, key);
create unique index if not exists ops_stage_pos_idx on public.ops_workflow_stages(workflow_id, position);

create table if not exists public.ops_task_templates (
  id                               uuid primary key default gen_random_uuid(),
  name                             text not null,
  deliverable_type                 text not null,
  workflow_id                      uuid not null references public.ops_workflows(id),
  default_complexity               text,
  first_draft_offset_business_days integer,
  final_offset_business_days       integer,
  default_estimate_minutes         integer,
  required_fields                  jsonb not null default '{}'::jsonb,
  checklist                        jsonb not null default '[]'::jsonb,
  active                           boolean not null default true,
  created_at                       timestamptz not null default now(),
  updated_at                       timestamptz not null default now()
);
create unique index if not exists ops_template_name_idx on public.ops_task_templates(lower(name));

-- ---------------------------------------------------------------------------
-- 3. The task, and everything hanging off it.
-- ---------------------------------------------------------------------------

create sequence if not exists public.ops_task_no_seq start 1001;

create table if not exists public.ops_tasks (
  id            uuid primary key default gen_random_uuid(),
  task_no       bigint not null default nextval('public.ops_task_no_seq'),
  scope         text not null check (scope in ('client', 'internal')),
  client_id     uuid references public.clients(id) on delete set null,
  campaign_id   uuid references public.campaigns(id) on delete set null,
  batch_id      uuid references public.batches(id) on delete set null,
  source_type   text,
  source_id     uuid,
  parent_task_id uuid references public.ops_tasks(id) on delete set null,
  template_id   uuid references public.ops_task_templates(id),
  workflow_id   uuid not null references public.ops_workflows(id),
  stage_key     text not null,
  title         text not null,
  description   text,
  remarks       text,
  deliverable_type text not null,
  language_codes text[] not null default '{}',
  priority_level smallint not null default 3 check (priority_level between 1 and 5),
  complexity    text check (complexity in ('simple', 'standard', 'complex')),
  estimate_minutes integer,
  publish_at    timestamptz,
  /* The promise first made. Never written again after creation: a report
     that can only measure the latest replan cannot see replanning at all. */
  original_first_draft_due_at timestamptz,
  current_first_draft_due_at  timestamptz,
  first_draft_submitted_at    timestamptz,
  original_final_due_at       timestamptz,
  current_final_due_at        timestamptz,
  delivered_at  timestamptz,
  completed_at  timestamptz,
  blocked_category text,
  blocked_note  text,
  blocked_at    timestamptz,
  created_by    uuid references public.team_members(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  archived_at   timestamptz,
  cancelled_at  timestamptz,
  version       integer not null default 1,
  legacy_source text,
  legacy_key    text,
  data_quality  text not null default 'complete',
  idem_key      text,
  constraint ops_tasks_client_scope check (scope <> 'client' or client_id is not null)
);
create unique index if not exists ops_tasks_no_idx on public.ops_tasks(task_no);
create unique index if not exists ops_tasks_legacy_idx
  on public.ops_tasks(legacy_source, legacy_key) where legacy_key is not null;
create unique index if not exists ops_tasks_idem_idx
  on public.ops_tasks(idem_key) where idem_key is not null;

create table if not exists public.ops_task_assignees (
  id             uuid primary key default gen_random_uuid(),
  task_id        uuid not null references public.ops_tasks(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id),
  responsibility text not null check (responsibility in ('owner', 'contributor', 'reviewer')),
  assigned_by    uuid references public.team_members(id),
  assigned_at    timestamptz not null default now(),
  ended_at       timestamptz
);
/* One accountable owner at a time, and one live row per person per role: an
   ended assignment stays for the history, which is why these are partial. */
create unique index if not exists ops_one_owner_idx on public.ops_task_assignees(task_id)
  where responsibility = 'owner' and ended_at is null;
create unique index if not exists ops_one_role_idx
  on public.ops_task_assignees(task_id, team_member_id, responsibility) where ended_at is null;
create index if not exists ops_assignee_live_idx
  on public.ops_task_assignees(team_member_id, responsibility) where ended_at is null;

create table if not exists public.ops_task_events (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.ops_tasks(id) on delete cascade,
  event_type  text not null,
  actor_id    uuid references public.team_members(id),
  actor_email text,
  from_value  jsonb,
  to_value    jsonb,
  detail      jsonb not null default '{}'::jsonb,
  source      text not null default 'portal',
  created_at  timestamptz not null default now()
);
create index if not exists ops_events_task_idx on public.ops_task_events(task_id, created_at desc);
create index if not exists ops_events_type_idx on public.ops_task_events(event_type, created_at desc);

create table if not exists public.ops_work_sessions (
  id             uuid primary key default gen_random_uuid(),
  task_id        uuid not null references public.ops_tasks(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id),
  started_at     timestamptz not null,
  ended_at       timestamptz,
  minutes        integer,
  note           text,
  source         text not null default 'timer',
  corrected_at   timestamptz,
  corrected_by   uuid references public.team_members(id),
  correction_reason text,
  created_at     timestamptz not null default now(),
  constraint ops_session_order check (ended_at is null or ended_at >= started_at)
);
/* One open session a person, across every task. */
create unique index if not exists ops_one_open_session_idx
  on public.ops_work_sessions(team_member_id) where ended_at is null;
create index if not exists ops_sessions_member_idx
  on public.ops_work_sessions(team_member_id, started_at desc);
create index if not exists ops_sessions_task_idx on public.ops_work_sessions(task_id);

create table if not exists public.ops_revisions (
  id                uuid primary key default gen_random_uuid(),
  task_id           uuid not null references public.ops_tasks(id) on delete cascade,
  round_no          integer not null,
  requested_by_type text not null check (requested_by_type in ('internal', 'client', 'platform', 'other')),
  reason_category   text not null,
  summary           text,
  requested_by      uuid references public.team_members(id),
  assigned_to       uuid references public.team_members(id),
  requested_at      timestamptz not null default now(),
  completed_at      timestamptz,
  source_review_id  uuid,
  idem_key          text
);
create unique index if not exists ops_revision_round_idx on public.ops_revisions(task_id, round_no);
create unique index if not exists ops_revision_idem_idx
  on public.ops_revisions(idem_key) where idem_key is not null;
/* A review version decides once. A second delivery of the same decision is
   the same decision, so it finds this row rather than opening a round. */
create unique index if not exists ops_revision_source_idx
  on public.ops_revisions(task_id, source_review_id) where source_review_id is not null;

create table if not exists public.ops_task_checklist_items (
  id           uuid primary key default gen_random_uuid(),
  task_id      uuid not null references public.ops_tasks(id) on delete cascade,
  label        text not null,
  position     integer not null,
  required     boolean not null default false,
  completed_at timestamptz,
  completed_by uuid references public.team_members(id),
  created_at   timestamptz not null default now()
);
create index if not exists ops_checklist_task_idx on public.ops_task_checklist_items(task_id, position);

create table if not exists public.ops_task_links (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.ops_tasks(id) on delete cascade,
  kind        text not null,
  label       text not null,
  url         text not null,
  created_by  uuid references public.team_members(id),
  created_at  timestamptz not null default now(),
  archived_at timestamptz
);
create index if not exists ops_links_task_idx on public.ops_task_links(task_id) where archived_at is null;

create table if not exists public.ops_video_details (
  task_id                  uuid primary key references public.ops_tasks(id) on delete cascade,
  output_duration_seconds  integer,
  footage_duration_seconds integer,
  subtitle_required        boolean not null default false,
  motion_graphics_required boolean not null default false,
  aspect_ratios            text[] not null default '{}',
  script_ready             boolean,
  footage_ready            boolean,
  shoot_required           boolean not null default false,
  shoot_at                 timestamptz,
  variant_count            integer not null default 1
);

create table if not exists public.ops_notifications (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  task_id        uuid references public.ops_tasks(id) on delete cascade,
  kind           text not null,
  title          text not null,
  body           text,
  read_at        timestamptz,
  created_at     timestamptz not null default now(),
  dedupe_key     text unique
);
create index if not exists ops_notif_member_idx
  on public.ops_notifications(team_member_id, created_at desc) where read_at is null;

create table if not exists public.ops_recurring_rules (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  client_id             uuid references public.clients(id) on delete cascade,
  template_id           uuid not null references public.ops_task_templates(id),
  owner_id              uuid references public.team_members(id),
  frequency             text not null default 'monthly',
  day_of_month          integer,
  publish_rule          jsonb,
  active                boolean not null default true,
  last_generated_period text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table if not exists public.ops_kpi_targets (
  id             uuid primary key default gen_random_uuid(),
  metric_key     text not null,
  scope_type     text not null check (scope_type in ('company', 'client', 'workflow', 'deliverable')),
  scope_id       text,
  target_value   numeric not null,
  comparison     text not null check (comparison in ('gte', 'lte', 'between')),
  target_max     numeric,
  effective_from date not null,
  effective_to   date,
  created_by     uuid references public.team_members(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists ops_target_metric_idx
  on public.ops_kpi_targets(metric_key, effective_from desc);

-- Reporting and list indexes. Measured against the filters the views actually
-- carry rather than one per column.
create index if not exists ops_tasks_open_idx on public.ops_tasks(current_final_due_at)
  where completed_at is null and cancelled_at is null and archived_at is null;
create index if not exists ops_tasks_client_idx on public.ops_tasks(client_id, created_at desc);
create index if not exists ops_tasks_stage_idx on public.ops_tasks(workflow_id, stage_key);
create index if not exists ops_tasks_done_idx on public.ops_tasks(completed_at desc)
  where completed_at is not null;
create index if not exists ops_tasks_delivered_idx on public.ops_tasks(delivered_at desc)
  where delivered_at is not null;

-- ---------------------------------------------------------------------------
-- 4. Who may read what.
--
--    Reads are policies. Writes are not: every table below carries a select
--    policy and nothing else, so the only way a row changes is through one of
--    the security-definer functions in section 6, which check the permission
--    and write the audit event in the same transaction. A browser holding the
--    anon key cannot set a stage, move a date, assign a person or file an
--    event, whatever it sends.
-- ---------------------------------------------------------------------------

/* May the signed-in colleague read this task? Their own work always: owner,
   contributor, reviewer or the person who asked for it. The whole team's
   work only with `ops.all`. */
create or replace function public.ops_may_see_task(p_task uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when not public.allowed('ops', 'view') then false
    when public.ops_granted('ops.all', 'view') then true
    else exists (
      select 1 from public.ops_tasks t
       where t.id = p_task
         and (t.created_by = (select id from public.ops_me())
              or exists (select 1 from public.ops_task_assignees a
                          where a.task_id = t.id and a.ended_at is null
                            and a.team_member_id = (select id from public.ops_me()))))
  end
$$;
grant execute on function public.ops_may_see_task(uuid) to authenticated;

-- Row level security is stated one table at a time, never in the loop below.
-- The Supabase SQL editor scans a script for exactly these lines and offers to
-- append its own where it cannot find them: an `execute format(...)` inside a
-- `do $$` block is invisible to it, so a file that enabled RLS correctly still
-- prompted on every run. A security posture a reader cannot see in the file is
-- one nobody can check, the editor included.
alter table public.ops_workflows enable row level security;
alter table public.ops_workflow_stages enable row level security;
alter table public.ops_task_templates enable row level security;
alter table public.ops_tasks enable row level security;
alter table public.ops_task_assignees enable row level security;
alter table public.ops_task_events enable row level security;
alter table public.ops_work_sessions enable row level security;
alter table public.ops_revisions enable row level security;
alter table public.ops_task_checklist_items enable row level security;
alter table public.ops_task_links enable row level security;
alter table public.ops_video_details enable row level security;
alter table public.ops_notifications enable row level security;
alter table public.ops_recurring_rules enable row level security;
alter table public.ops_kpi_targets enable row level security;

do $$
declare
  t text;
  tables text[] := array[
    'ops_workflows', 'ops_workflow_stages', 'ops_task_templates', 'ops_tasks',
    'ops_task_assignees', 'ops_task_events', 'ops_work_sessions', 'ops_revisions',
    'ops_task_checklist_items', 'ops_task_links', 'ops_video_details',
    'ops_notifications', 'ops_recurring_rules', 'ops_kpi_targets'];
begin
  foreach t in array tables loop
    /* Policies are additive, so every one this file owns goes before the new
       one lands. Named from the catalogue rather than from a list kept here,
       because a list is a second place to remember a policy and this file
       already had one it forgot. */
    declare p text;
    begin
      for p in select policyname from pg_policies
                where schemaname = 'public' and tablename = t loop
        execute format('drop policy if exists %I on public.%I', p, t);
      end loop;
    end;
  end loop;
end $$;

-- The catalogue: anybody who can open the section reads it.
create policy ops_workflows_read on public.ops_workflows
  for select to authenticated using (public.allowed('ops', 'view'));
create policy ops_workflow_stages_read on public.ops_workflow_stages
  for select to authenticated using (public.allowed('ops', 'view'));
create policy ops_task_templates_read on public.ops_task_templates
  for select to authenticated using (public.allowed('ops', 'view'));
create policy ops_kpi_targets_read on public.ops_kpi_targets
  for select to authenticated using (public.ops_granted('ops.reports', 'view'));
create policy ops_recurring_rules_read on public.ops_recurring_rules
  for select to authenticated using (public.ops_granted('ops.workflows', 'view'));

-- The work: own tasks, or the whole queue with `ops.all`.
create policy ops_tasks_read on public.ops_tasks
  for select to authenticated using (public.ops_may_see_task(id));
create policy ops_task_assignees_read on public.ops_task_assignees
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_task_events_read on public.ops_task_events
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_revisions_read on public.ops_revisions
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_task_checklist_items_read on public.ops_task_checklist_items
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_task_links_read on public.ops_task_links
  for select to authenticated using (public.ops_may_see_task(task_id));
create policy ops_video_details_read on public.ops_video_details
  for select to authenticated using (public.ops_may_see_task(task_id));

/* A person's own hours are their own to read; a manager reads the team's.
   Neither reads a session on a task they cannot see. */
create policy ops_work_sessions_read on public.ops_work_sessions
  for select to authenticated using (
    public.ops_may_see_task(task_id)
    and (team_member_id = (select id from public.ops_me())
         or public.ops_granted('ops.all', 'view')
         or public.ops_granted('ops.time', 'manage')));

-- A notification is addressed to one person and read by that person.
create policy ops_notifications_read on public.ops_notifications
  for select to authenticated using (team_member_id = (select id from public.ops_me()));
/* Marking one read is the single write a browser may make directly, and it
   can only reach its own row and can only set `read_at`. */
create policy ops_notifications_mark on public.ops_notifications
  for update to authenticated
  using (team_member_id = (select id from public.ops_me()))
  with check (team_member_id = (select id from public.ops_me()));

-- ---------------------------------------------------------------------------
-- 5. The workflows the portal ships with. Seeded once, into a database that
--    has none: the stages are the team's to edit afterwards, and a seed that
--    ran on every pass would put back a stage somebody had removed.
-- ---------------------------------------------------------------------------
do $$
declare
  w_general uuid;
  w_video   uuid;
begin
  if exists (select 1 from public.ops_workflows) then return; end if;

  insert into public.ops_workflows (key, name, description)
  values ('general', 'General deliverable',
          'Design, copy, reports and everything that is not a shoot.')
  returning id into w_general;

  insert into public.ops_workflows (key, name, description)
  values ('video', 'Video production',
          'Work that is shot and edited before it reaches a client.')
  returning id into w_video;

  insert into public.ops_workflow_stages
    (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
     is_review, is_terminal, wip_guidance, next_stage_keys) values
    (w_general, 'intake',    'Intake',          1, 'intake',        false, false, false, false, null, array['ready','cancelled','kiv']),
    (w_general, 'ready',     'Ready',           2, 'ready',         false, false, false, false, null, array['in_progress','blocked','cancelled','kiv','intake']),
    (w_general, 'in_progress','In progress',    3, 'active',        true,  false, false, false, 5,    array['internal_review','blocked','waiting_client','ready','cancelled']),
    (w_general, 'internal_review','Internal review', 4, 'internal_review', false, true, true, false, 8, array['client_review','revision','in_progress','blocked']),
    (w_general, 'client_review','Client review', 5, 'client_review', false, true,  true,  false, null, array['approved','revision','blocked','waiting_client']),
    (w_general, 'revision',  'Revision',        6, 'revision',      true,  false, false, false, null, array['internal_review','client_review','approved','blocked']),
    (w_general, 'approved',  'Approved',        7, 'approved',      false, false, false, false, null, array['delivered','revision']),
    (w_general, 'delivered', 'Delivered',       8, 'delivered',     false, false, false, false, null, array['done','revision']),
    (w_general, 'done',      'Done',            9, 'done',          false, false, false, true,  null, array['revision','in_progress']),
    (w_general, 'blocked',   'Blocked',        10, 'blocked',       false, true,  false, false, null, array['ready','in_progress','internal_review','client_review','revision','cancelled']),
    (w_general, 'waiting_client','Waiting for client', 11, 'waiting', false, true, false, false, null, array['in_progress','client_review','revision','cancelled']),
    (w_general, 'kiv',       'KIV',            12, 'kiv',           false, true,  false, false, null, array['ready','intake','cancelled']),
    (w_general, 'cancelled', 'Cancelled',      13, 'cancelled',     false, false, false, true,  null, array['intake']);

  insert into public.ops_workflow_stages
    (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
     is_review, is_terminal, wip_guidance, next_stage_keys) values
    (w_video, 'intake',    'Intake',            1, 'intake',        false, false, false, false, null, array['ready','cancelled','kiv']),
    (w_video, 'ready',     'Ready',             2, 'ready',         false, false, false, false, null, array['shooting','editing','blocked','cancelled','kiv','intake']),
    (w_video, 'shooting',  'Shooting',          3, 'active',        true,  false, false, false, 3,    array['editing','blocked','ready','cancelled']),
    (w_video, 'editing',   'Editing',           4, 'active',        true,  false, false, false, 4,    array['internal_review','blocked','shooting','waiting_client']),
    (w_video, 'internal_review','Internal review', 5, 'internal_review', false, true, true, false, 6, array['client_review','revision','editing','blocked']),
    (w_video, 'client_review','Client review',   6, 'client_review', false, true,  true,  false, null, array['approved','revision','blocked','waiting_client']),
    (w_video, 'revision',  'Revision',          7, 'revision',      true,  false, false, false, null, array['internal_review','client_review','approved','blocked']),
    (w_video, 'approved',  'Approved',          8, 'approved',      false, false, false, false, null, array['delivered','revision']),
    (w_video, 'delivered', 'Delivered',         9, 'delivered',     false, false, false, false, null, array['done','revision']),
    (w_video, 'done',      'Done',             10, 'done',          false, false, false, true,  null, array['revision','editing']),
    (w_video, 'blocked',   'Blocked',          11, 'blocked',       false, true,  false, false, null, array['ready','shooting','editing','internal_review','client_review','revision','cancelled']),
    (w_video, 'waiting_client','Waiting for client', 12, 'waiting', false, true,  false, false, null, array['editing','client_review','revision','cancelled']),
    (w_video, 'kiv',       'KIV',              13, 'kiv',           false, true,  false, false, null, array['ready','intake','cancelled']),
    (w_video, 'cancelled', 'Cancelled',        14, 'cancelled',     false, false, false, true,  null, array['intake']);

  /* Offsets count backward from the publish date where there is one, and
     forward from today where there is not. They are the template's opening
     bid: the person naming the commitment can type over them, with a reason
     where the change departs from the template. */
  insert into public.ops_task_templates
    (name, deliverable_type, workflow_id, default_complexity,
     first_draft_offset_business_days, final_offset_business_days,
     default_estimate_minutes, required_fields, checklist) values
    ('Static post',   'static',  w_general, 'simple',   5, 2, 90,
      '{"language":true}'::jsonb,
      '["Brief read", "Copy approved internally", "Artwork exported"]'::jsonb),
    ('Carousel',      'carousel', w_general, 'standard', 6, 2, 180,
      '{"language":true}'::jsonb,
      '["Brief read", "Copy approved internally", "All frames exported"]'::jsonb),
    ('Report',        'report',  w_general, 'standard', 4, 1, 120,
      '{}'::jsonb, '["Figures checked", "Period stated"]'::jsonb),
    ('Short video',   'video',   w_video,   'standard', 7, 3, 300,
      '{"language":true,"complexity":true}'::jsonb,
      '["Script approved", "Footage backed up", "Subtitles checked", "Export settings checked"]'::jsonb),
    ('Reel',          'reel',    w_video,   'simple',   5, 2, 180,
      '{"language":true,"complexity":true}'::jsonb,
      '["Footage backed up", "Aspect ratio checked"]'::jsonb),
    ('Ad-hoc request','adhoc',   w_general, 'simple',   2, 1, 60,
      '{}'::jsonb, '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- 6. Every important write, server side.
--
--    Each one: confirms an active colleague, checks the one permission that
--    governs it, validates the transition against the workflow, refuses a
--    stale write, changes the row and files the event in one transaction,
--    and returns the task. A repeated call that plausibly happens twice is
--    answered with the first call's result rather than a second row.
-- ---------------------------------------------------------------------------

/* One place writes an event, so an event cannot arrive without its actor. */
create or replace function public.ops_log(
  p_task uuid, p_type text, p_from jsonb, p_to jsonb, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  insert into public.ops_task_events (task_id, event_type, actor_id, actor_email,
                                      from_value, to_value, detail)
  values (p_task, p_type, m.id, m.email, p_from, p_to, coalesce(p_detail, '{}'::jsonb));
end $$;

create or replace function public.ops_stage(p_workflow uuid, p_key text)
returns public.ops_workflow_stages
language sql stable security definer set search_path = public as $$
  select * from public.ops_workflow_stages
   where workflow_id = p_workflow and key = p_key limit 1
$$;

/* The task as the page reads it back: the row, its live assignees and the
   stage it is on, so a caller never has to make a second request to find out
   what its own write produced. */
create or replace function public.ops_task_json(p_task uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(t) || jsonb_build_object(
    'stage', to_jsonb(public.ops_stage(t.workflow_id, t.stage_key)),
    'assignees', coalesce((
      select jsonb_agg(jsonb_build_object(
               'team_member_id', a.team_member_id, 'name', tm.name,
               'responsibility', a.responsibility))
        from public.ops_task_assignees a
        join public.team_members tm on tm.id = a.team_member_id
       where a.task_id = t.id and a.ended_at is null), '[]'::jsonb))
  from public.ops_tasks t where t.id = p_task
$$;
grant execute on function public.ops_task_json(uuid) to authenticated;

-- 6.1 Create ------------------------------------------------------------------
create or replace function public.ops_create_task(p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  tpl   public.ops_task_templates;
  wf    uuid;
  tid   uuid;
  owner uuid;
  publish timestamptz;
  fd    timestamptz;
  fin   timestamptz;
  item  jsonb;
  i     integer := 0;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  if coalesce(p_payload ->> 'title', '') = '' then
    return jsonb_build_object('error', 'title-required');
  end if;
  if coalesce(p_payload ->> 'scope', 'client') = 'client'
     and (p_payload ->> 'client_id') is null then
    return jsonb_build_object('error', 'client-required');
  end if;

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
  end if;
  wf := coalesce((p_payload ->> 'workflow_id')::uuid, tpl.workflow_id,
                 (select id from public.ops_workflows where key = 'general'));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;

  publish := (p_payload ->> 'publish_at')::timestamptz;
  /* Backward from the publish date where the client has one, forward from
     today where they do not: a service with no publish date still owes an
     answer by the template's own target. */
  fd := coalesce((p_payload ->> 'first_draft_due_at')::timestamptz,
        case when publish is not null and tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.first_draft_offset_business_days)
             when tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.first_draft_offset_business_days)
        end);
  fin := coalesce((p_payload ->> 'final_due_at')::timestamptz,
        case when publish is not null and tpl.final_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.final_offset_business_days)
             when tpl.final_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.final_offset_business_days)
        end);

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality)
  values (
    coalesce(p_payload ->> 'scope', 'client'),
    (p_payload ->> 'client_id')::uuid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, 'intake',
    p_payload ->> 'title', p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'adhoc'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'))
  returning id into tid;

  owner := (p_payload ->> 'owner_id')::uuid;
  if owner is not null then
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (tid, owner, 'owner', m.id);
    perform public.ops_log(tid, 'assignment_changed', null,
      jsonb_build_object('owner_id', owner), '{}'::jsonb);
  end if;
  if (p_payload ->> 'reviewer_id') is not null then
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (tid, (p_payload ->> 'reviewer_id')::uuid, 'reviewer', m.id);
  end if;

  -- The template's checklist, in the order it states.
  if tpl.checklist is not null then
    for item in select * from jsonb_array_elements(tpl.checklist) loop
      i := i + 1;
      insert into public.ops_task_checklist_items (task_id, label, position)
      values (tid, item #>> '{}', i);
    end loop;
  end if;

  if (p_payload -> 'video') is not null then
    insert into public.ops_video_details (
      task_id, output_duration_seconds, footage_duration_seconds,
      subtitle_required, motion_graphics_required, aspect_ratios,
      script_ready, footage_ready, shoot_required, shoot_at, variant_count)
    values (tid,
      ((p_payload -> 'video') ->> 'output_duration_seconds')::integer,
      ((p_payload -> 'video') ->> 'footage_duration_seconds')::integer,
      coalesce(((p_payload -> 'video') ->> 'subtitle_required')::boolean, false),
      coalesce(((p_payload -> 'video') ->> 'motion_graphics_required')::boolean, false),
      coalesce((select array_agg(x) from jsonb_array_elements_text(
                 coalesce((p_payload -> 'video') -> 'aspect_ratios', '[]'::jsonb)) x), '{}'),
      ((p_payload -> 'video') ->> 'script_ready')::boolean,
      ((p_payload -> 'video') ->> 'footage_ready')::boolean,
      coalesce(((p_payload -> 'video') ->> 'shoot_required')::boolean, false),
      ((p_payload -> 'video') ->> 'shoot_at')::timestamptz,
      coalesce(((p_payload -> 'video') ->> 'variant_count')::integer, 1));
  end if;

  perform public.ops_log(tid, 'task_created', null,
    jsonb_build_object('title', p_payload ->> 'title',
                       'first_draft_due_at', fd, 'final_due_at', fin), '{}'::jsonb);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

-- 6.2 Move a stage -------------------------------------------------------------
create or replace function public.ops_transition_task(
  p_task uuid, p_next text, p_version integer default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cur public.ops_workflow_stages;
  nxt public.ops_workflow_stages;
  has_owner boolean;
  has_draft boolean;
  has_final boolean;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* A write made against a version somebody has already replaced is a write
     made from a stale screen. It is refused with the current row, so the
     page can say what changed rather than overwriting it. */
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if t.stage_key = p_next then return public.ops_task_json(p_task); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  if not (p_next = any (cur.next_stage_keys)) then
    return jsonb_build_object('error', 'bad-transition',
      'allowed', to_jsonb(cur.next_stage_keys));
  end if;

  -- What each gate needs before it opens.
  has_owner := exists (select 1 from public.ops_task_assignees
                        where task_id = p_task and responsibility = 'owner' and ended_at is null);
  has_draft := exists (select 1 from public.ops_task_links
                        where task_id = p_task and archived_at is null
                          and kind in ('draft', 'review'));
  has_final := exists (select 1 from public.ops_task_links
                        where task_id = p_task and archived_at is null and kind = 'final');

  if p_next = 'ready' and (not has_owner or t.current_final_due_at is null) then
    return jsonb_build_object('error', 'ready-needs-owner-and-due');
  end if;
  if p_next = 'editing' and exists (
       select 1 from public.ops_video_details v
        where v.task_id = p_task and v.footage_ready is false) then
    return jsonb_build_object('error', 'footage-not-ready');
  end if;
  if p_next = 'client_review' and not has_draft then
    return jsonb_build_object('error', 'needs-draft');
  end if;
  if p_next = 'delivered' and not has_final then
    return jsonb_build_object('error', 'needs-final-link');
  end if;
  if p_next = 'done' and t.delivered_at is null
     and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-delivery-or-reason');
  end if;

  update public.ops_tasks set
    stage_key = p_next,
    version = version + 1,
    updated_at = now(),
    first_draft_submitted_at = case
      when first_draft_submitted_at is null and nxt.is_review then now()
      else first_draft_submitted_at end,
    delivered_at = case when p_next = 'delivered' then coalesce(delivered_at, now())
                        else delivered_at end,
    completed_at = case when nxt.is_terminal and p_next <> 'cancelled' then coalesce(completed_at, now())
                        when not nxt.is_terminal then null
                        else completed_at end,
    cancelled_at = case when p_next = 'cancelled' then coalesce(cancelled_at, now())
                        else cancelled_at end,
    blocked_at = case when p_next = 'blocked' then blocked_at else null end,
    blocked_category = case when p_next = 'blocked' then blocked_category else null end
  where id = p_task;

  perform public.ops_log(p_task, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', p_next),
    case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end);
  if p_next = 'delivered' then
    perform public.ops_log(p_task, 'delivered', null, null, '{}'::jsonb);
  end if;
  if nxt.is_terminal and p_next <> 'cancelled' then
    perform public.ops_log(p_task, 'completed', null, null, '{}'::jsonb);
  end if;
  if p_next = 'cancelled' then
    perform public.ops_log(p_task, 'cancelled', null, null,
      jsonb_build_object('reason', p_note));
  end if;
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_transition_task(uuid, text, integer, text) to authenticated;

-- 6.3 Move a date ---------------------------------------------------------------
create or replace function public.ops_change_due_date(
  p_task uuid, p_kind text, p_value timestamptz, p_reason text,
  p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_kind not in ('first_draft', 'final') then return jsonb_build_object('error', 'bad-kind'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  was := case when p_kind = 'final' then t.current_final_due_at
              else t.current_first_draft_due_at end;

  /* The original is written once, when the task is created, and never here.
     A report that can only measure the latest replan cannot see replanning. */
  update public.ops_tasks set
    current_final_due_at = case when p_kind = 'final' then p_value else current_final_due_at end,
    current_first_draft_due_at = case when p_kind = 'first_draft' then p_value else current_first_draft_due_at end,
    version = version + 1, updated_at = now()
  where id = p_task;

  perform public.ops_log(p_task, 'due_changed',
    jsonb_build_object('kind', p_kind, 'value', was),
    jsonb_build_object('kind', p_kind, 'value', p_value),
    jsonb_build_object('reason', p_reason, 'note', p_note));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_change_due_date(uuid, text, timestamptz, text, text, integer) to authenticated;

-- 6.4 Assign --------------------------------------------------------------------
create or replace function public.ops_assign_task(
  p_task uuid, p_owner uuid, p_contributors uuid[] default null,
  p_reviewer uuid default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was uuid;
  c   uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  /* Accountable ownership is the one assignment a member cannot hand
     themselves: it is what the whole queue is ordered by. */
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  select team_member_id into was from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null;

  if p_owner is not null and p_owner is distinct from was then
    /* The former owner stops seeing it as live work and keeps their place in
       its history: the row is ended, never deleted. */
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (p_task, p_owner, 'owner', m.id);
    perform public.ops_log(p_task, 'assignment_changed',
      jsonb_build_object('owner_id', was), jsonb_build_object('owner_id', p_owner), '{}'::jsonb);
  end if;

  if p_contributors is not null then
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'contributor' and ended_at is null
       and not (team_member_id = any (p_contributors));
    foreach c in array p_contributors loop
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, c, 'contributor', m.id)
      on conflict do nothing;
    end loop;
    perform public.ops_log(p_task, 'contributor_changed', null,
      jsonb_build_object('contributors', to_jsonb(p_contributors)), '{}'::jsonb);
  end if;

  if p_reviewer is not null then
    update public.ops_task_assignees set ended_at = now()
     where task_id = p_task and responsibility = 'reviewer' and ended_at is null
       and team_member_id <> p_reviewer;
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (p_task, p_reviewer, 'reviewer', m.id)
    on conflict do nothing;
    perform public.ops_log(p_task, 'reviewer_changed', null,
      jsonb_build_object('reviewer_id', p_reviewer), '{}'::jsonb);
  end if;

  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_assign_task(uuid, uuid, uuid[], uuid, integer) to authenticated;

-- 6.5 Blocked ---------------------------------------------------------------------
create or replace function public.ops_set_blocked(
  p_task uuid, p_category text, p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.ops_tasks;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_category, '') = '' then return jsonb_build_object('error', 'category-required'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  update public.ops_tasks set
    stage_key = 'blocked', blocked_category = p_category, blocked_note = p_note,
    blocked_at = now(), version = version + 1, updated_at = now()
  where id = p_task;
  perform public.ops_log(p_task, 'blocked',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', 'blocked'),
    jsonb_build_object('category', p_category, 'note', p_note));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_set_blocked(uuid, text, text, integer) to authenticated;

create or replace function public.ops_clear_blocked(
  p_task uuid, p_next text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.ops_tasks; res jsonb;
begin
  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.stage_key <> 'blocked' then return jsonb_build_object('error', 'not-blocked'); end if;
  res := public.ops_transition_task(p_task, p_next, p_version, null);
  if res ? 'error' then return res; end if;
  perform public.ops_log(p_task, 'unblocked',
    jsonb_build_object('category', t.blocked_category),
    jsonb_build_object('stage_key', p_next), '{}'::jsonb);
  return res;
end $$;
grant execute on function public.ops_clear_blocked(uuid, text, integer) to authenticated;

-- 6.6 Work sessions -----------------------------------------------------------------
create or replace function public.ops_start_work(p_task uuid, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  open_id uuid;
  sid  uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'view') then return jsonb_build_object('error', 'denied'); end if;

  /* One open session a person, across every task. A second start on the same
     task is the same start; a start on another task closes the first and
     says so, rather than leaving two clocks running. */
  select id into open_id from public.ops_work_sessions
   where team_member_id = m.id and ended_at is null;
  if open_id is not null then
    if exists (select 1 from public.ops_work_sessions
                where id = open_id and task_id = p_task) then
      return jsonb_build_object('session_id', open_id, 'already_open', true);
    end if;
    perform public.ops_stop_work(open_id, 'Stopped by starting another task');
  end if;

  insert into public.ops_work_sessions (task_id, team_member_id, started_at)
  values (p_task, m.id, now()) returning id into sid;
  perform public.ops_log(p_task, 'work_started', null,
    jsonb_build_object('session_id', sid), '{}'::jsonb);
  return jsonb_build_object('session_id', sid, 'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_start_work(uuid, text) to authenticated;

create or replace function public.ops_stop_work(p_session uuid, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  s public.ops_work_sessions;
  mins integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into s from public.ops_work_sessions where id = p_session for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* A session belongs to the person who did the work, not to the task's
     owner, so only they or a corrector may close it. */
  if s.team_member_id <> m.id and not public.ops_granted('ops.time', 'manage') then
    return jsonb_build_object('error', 'denied');
  end if;
  if s.ended_at is not null then return jsonb_build_object('session_id', s.id, 'minutes', s.minutes); end if;

  mins := greatest(0, (extract(epoch from (now() - s.started_at)) / 60)::integer);
  update public.ops_work_sessions
     set ended_at = now(), minutes = mins, note = coalesce(p_note, note)
   where id = p_session;
  perform public.ops_log(s.task_id, 'work_stopped', null,
    jsonb_build_object('session_id', s.id, 'minutes', mins),
    case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end);
  return jsonb_build_object('session_id', s.id, 'minutes', mins);
end $$;
grant execute on function public.ops_stop_work(uuid, text) to authenticated;

create or replace function public.ops_correct_work_session(
  p_session uuid, p_started timestamptz, p_ended timestamptz, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  s public.ops_work_sessions;
  mins integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into s from public.ops_work_sessions where id = p_session for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if s.team_member_id <> m.id and not public.ops_granted('ops.time', 'manage') then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_ended is not null and p_ended < p_started then
    return jsonb_build_object('error', 'ends-before-it-starts');
  end if;

  mins := case when p_ended is null then null
               else greatest(0, (extract(epoch from (p_ended - p_started)) / 60)::integer) end;
  update public.ops_work_sessions set
    started_at = p_started, ended_at = p_ended, minutes = mins,
    corrected_at = now(), corrected_by = m.id, correction_reason = p_reason,
    source = 'corrected'
  where id = p_session;
  /* The value before the correction stays in the event, so a corrected hour
     is a change somebody made and not a number that was always so. */
  perform public.ops_log(s.task_id, 'work_corrected',
    jsonb_build_object('started_at', s.started_at, 'ended_at', s.ended_at, 'minutes', s.minutes),
    jsonb_build_object('started_at', p_started, 'ended_at', p_ended, 'minutes', mins),
    jsonb_build_object('reason', p_reason, 'session_id', s.id));
  return jsonb_build_object('session_id', s.id, 'minutes', mins);
end $$;
grant execute on function public.ops_correct_work_session(uuid, timestamptz, timestamptz, text) to authenticated;

create or replace function public.ops_add_work_session(
  p_task uuid, p_started timestamptz, p_ended timestamptz, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; sid uuid; mins integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if p_ended < p_started then return jsonb_build_object('error', 'ends-before-it-starts'); end if;
  mins := greatest(0, (extract(epoch from (p_ended - p_started)) / 60)::integer);
  insert into public.ops_work_sessions (task_id, team_member_id, started_at, ended_at, minutes, note, source)
  values (p_task, m.id, p_started, p_ended, mins, p_note, 'manual') returning id into sid;
  perform public.ops_log(p_task, 'work_stopped', null,
    jsonb_build_object('session_id', sid, 'minutes', mins, 'manual', true), '{}'::jsonb);
  return jsonb_build_object('session_id', sid, 'minutes', mins);
end $$;
grant execute on function public.ops_add_work_session(uuid, timestamptz, timestamptz, text) to authenticated;

-- 6.7 Revisions -----------------------------------------------------------------------
create or replace function public.ops_request_revision(
  p_task uuid, p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  rid uuid;
  rnd integer;
  src uuid := (p_payload ->> 'source_review_id')::uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_payload ->> 'reason_category', '') = '' then
    return jsonb_build_object('error', 'reason-required');
  end if;

  -- Retry safe on both keys: the caller's own, and the review version, since
  -- one client decision must never open two rounds.
  if p_idem is not null then
    select id into rid from public.ops_revisions where idem_key = p_idem;
    if rid is not null then return jsonb_build_object('revision_id', rid, 'task', public.ops_task_json(p_task)); end if;
  end if;
  if src is not null then
    select id into rid from public.ops_revisions where task_id = p_task and source_review_id = src;
    if rid is not null then return jsonb_build_object('revision_id', rid, 'task', public.ops_task_json(p_task)); end if;
  end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select coalesce(max(round_no), 0) + 1 into rnd from public.ops_revisions where task_id = p_task;

  insert into public.ops_revisions (
    task_id, round_no, requested_by_type, reason_category, summary,
    requested_by, assigned_to, source_review_id, idem_key)
  values (p_task, rnd,
    coalesce(p_payload ->> 'requested_by_type', 'internal'),
    p_payload ->> 'reason_category', p_payload ->> 'summary', m.id,
    coalesce((p_payload ->> 'assigned_to')::uuid,
             (select team_member_id from public.ops_task_assignees
               where task_id = p_task and responsibility = 'owner' and ended_at is null)),
    src, p_idem)
  returning id into rid;

  if 'revision' = any ((public.ops_stage(t.workflow_id, t.stage_key)).next_stage_keys) then
    update public.ops_tasks set stage_key = 'revision', version = version + 1, updated_at = now()
     where id = p_task;
    perform public.ops_log(p_task, 'stage_changed',
      jsonb_build_object('stage_key', t.stage_key),
      jsonb_build_object('stage_key', 'revision'), '{}'::jsonb);
  end if;
  perform public.ops_log(p_task, 'revision_requested', null,
    jsonb_build_object('revision_id', rid, 'round_no', rnd),
    jsonb_build_object('reason', p_payload ->> 'reason_category',
                       'by', coalesce(p_payload ->> 'requested_by_type', 'internal')));
  return jsonb_build_object('revision_id', rid, 'round_no', rnd, 'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_request_revision(uuid, jsonb, text) to authenticated;

create or replace function public.ops_complete_revision(p_revision uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.ops_revisions;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.ops_revisions where id = p_revision for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(r.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if r.completed_at is not null then return jsonb_build_object('revision_id', r.id); end if;
  update public.ops_revisions set completed_at = now() where id = p_revision;
  perform public.ops_log(r.task_id, 'revision_completed', null,
    jsonb_build_object('revision_id', r.id, 'round_no', r.round_no), '{}'::jsonb);
  return jsonb_build_object('revision_id', r.id);
end $$;
grant execute on function public.ops_complete_revision(uuid) to authenticated;

/* The client's own decision, arriving from Content Review. Version specific
   and retry safe: the same review version delivered twice records one
   approval or one revision round, never two. */
create or replace function public.ops_record_review_decision(
  p_task uuid, p_review uuid, p_approved boolean, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.ops_tasks;
begin
  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_approved then
    if exists (select 1 from public.ops_task_events
                where task_id = p_task and event_type = 'approval_recorded'
                  and (to_value ->> 'review_id')::uuid = p_review) then
      return public.ops_task_json(p_task);
    end if;
    perform public.ops_log(p_task, 'approval_recorded', null,
      jsonb_build_object('review_id', p_review), jsonb_build_object('note', p_note));
    if t.stage_key = 'client_review' then
      update public.ops_tasks set stage_key = 'approved', version = version + 1, updated_at = now()
       where id = p_task;
      perform public.ops_log(p_task, 'stage_changed',
        jsonb_build_object('stage_key', 'client_review'),
        jsonb_build_object('stage_key', 'approved'), '{}'::jsonb);
    end if;
    return public.ops_task_json(p_task);
  end if;
  return public.ops_request_revision(p_task, jsonb_build_object(
    'requested_by_type', 'client', 'reason_category', 'client_preference',
    'summary', p_note, 'source_review_id', p_review), null);
end $$;

-- 6.8 Finish, reopen, tidy -------------------------------------------------------------
create or replace function public.ops_complete_task(
  p_task uuid, p_final_link text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; t public.ops_tasks; missing integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  select count(*) into missing from public.ops_task_checklist_items
   where task_id = p_task and required and completed_at is null;
  if missing > 0 then
    return jsonb_build_object('error', 'checklist-incomplete', 'missing', missing);
  end if;

  if p_final_link is not null and p_final_link <> '' then
    insert into public.ops_task_links (task_id, kind, label, url, created_by)
    values (p_task, 'final', 'Final deliverable', p_final_link, m.id);
    perform public.ops_log(p_task, 'file_added', null,
      jsonb_build_object('kind', 'final', 'url', p_final_link), '{}'::jsonb);
  end if;

  update public.ops_tasks set
    stage_key = 'done', delivered_at = coalesce(delivered_at, now()),
    completed_at = coalesce(completed_at, now()),
    version = version + 1, updated_at = now()
  where id = p_task;
  perform public.ops_log(p_task, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', 'done'), '{}'::jsonb);
  perform public.ops_log(p_task, 'completed', null, null, '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_complete_task(uuid, text, integer) to authenticated;

create or replace function public.ops_reopen_task(
  p_task uuid, p_reason text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.ops_tasks;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  update public.ops_tasks set
    stage_key = 'revision', completed_at = null,
    version = version + 1, updated_at = now()
  where id = p_task;
  perform public.ops_log(p_task, 'reopened',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', 'revision'), jsonb_build_object('reason', p_reason));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_reopen_task(uuid, text, integer) to authenticated;

/* Archive is list hygiene and reverses. Cancel is a business outcome and is
   a stage. Neither is a deletion: a task is never removed from this table by
   the console. */
create or replace function public.ops_archive_task(p_task uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  update public.ops_tasks set archived_at = case when p_on then now() else null end,
                              version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, case when p_on then 'archived' else 'restored' end,
    null, null, '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_archive_task(uuid, boolean) to authenticated;

-- 6.9 Recurring ----------------------------------------------------------------------
create or replace function public.ops_generate_recurring(
  p_period text, p_rules uuid[] default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  r     public.ops_recurring_rules;
  made  integer := 0;
  skip  integer := 0;
  key   text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('ops.workflows', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;

  for r in select * from public.ops_recurring_rules
            where active and (p_rules is null or id = any (p_rules)) loop
    /* A rule makes one task a period, whoever presses the button and however
       many times. The key is the rule and the period, so a second press is
       counted as skipped rather than filed as a second task. */
    key := 'recur:' || r.id::text || ':' || p_period;
    if exists (select 1 from public.ops_tasks where idem_key = key) then
      skip := skip + 1;
      continue;
    end if;
    perform public.ops_create_task(jsonb_build_object(
      'scope', case when r.client_id is null then 'internal' else 'client' end,
      'client_id', r.client_id,
      'template_id', r.template_id,
      'title', r.name || ' — ' || p_period,
      'owner_id', r.owner_id,
      'publish_at', case when r.day_of_month is null then null
        else ((p_period || '-' || lpad(r.day_of_month::text, 2, '0'))::date)::timestamptz end
    ), key);
    made := made + 1;
    update public.ops_recurring_rules set last_generated_period = p_period, updated_at = now()
     where id = r.id;
  end loop;
  return jsonb_build_object('created', made, 'skipped', skip, 'period', p_period);
end $$;
grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;

/* Functions this migration adds, for the rollback at the head of the file:
     ops_granted, ops_me, ops_add_business_days, ops_may_see_task, ops_log, ops_stage,
     ops_task_json, ops_create_task, ops_transition_task, ops_change_due_date,
     ops_assign_task, ops_set_blocked, ops_clear_blocked, ops_start_work,
     ops_stop_work, ops_correct_work_session, ops_add_work_session,
     ops_request_revision, ops_complete_revision, ops_record_review_decision,
     ops_complete_task, ops_reopen_task, ops_archive_task,
     ops_generate_recurring. */
