-- ===========================================================================
-- THE OPERATIONS SYSTEM, PHASE 4 — the monthly engagement, the task's name,
-- who the work is for, and the hand from one person to the next.
-- 2026-09-23. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS ADDS, AND WHAT IT LEAVES ALONE.
--
--   A task is for a client, a lead or nobody (`scope`), and the link is the
--   permanent record id: a client that later becomes a past client keeps
--   every task it ever had, because nothing here reads the client's current
--   stage to decide whose a task is. The stage is checked ONCE, when the task
--   is created, and never again.
--
--   A task keeps its serial (`T1001`) as its identity. Its NAME is a code and
--   an editable description: `2609W103 Raya carousel`, where 2609 is the
--   content month, W1 the planned publishing week and 03 the running number
--   for that client for the whole month. The code is generated under a lock
--   and never changes; the description is the team's to edit; the serial is
--   what history and references point at.
--
--   An engagement is one client's work for one month: the manager, how many
--   deliverables were agreed (typed, never derived from the contract, because
--   contract quantities change between renewals), the onboarding checklist,
--   the content meeting, and the tasks generated under it.
--
--   Existing tasks are not rewritten. They gain a description equal to their
--   old title, a task type of ad hoc, and no code; their workflow, stage,
--   events and assignments are untouched. The two seeded workflows are
--   retired for NEW tasks only and every task already on them carries on.
--
-- Rollback (in this order; the data in the new columns and tables is lost,
-- nothing that existed before is touched):
--   drop function if exists public.ops_engagement_set_status(uuid, text, integer);
--   drop function if exists public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean);
--   drop function if exists public.ops_engagement_set_check(uuid, text, text, uuid, text);
--   drop function if exists public.ops_engagement_upsert(jsonb);
--   drop function if exists public.ops_engagement_json(uuid);
--   drop function if exists public.ops_may_see_engagement(uuid);
--   drop function if exists public.ops_generate_month(jsonb, boolean, text);
--   drop function if exists public.ops_set_recurring(uuid, jsonb);
--   drop function if exists public.ops_duplicate_task(uuid, jsonb, text);
--   drop function if exists public.ops_set_content_desc(uuid, text, integer);
--   drop function if exists public.ops_transition_task(uuid, text, integer, text, uuid, text);
--   drop function if exists public.ops_next_seq(uuid, text);
--   drop function if exists public.ops_code_of(text, integer, integer);
--   drop function if exists public.ops_scope_error(text, uuid);
--   drop function if exists public.ops_title(public.ops_tasks);
--   drop table if exists public.ops_engagement_events;
--   drop table if exists public.ops_engagement_checks;
--   alter table public.ops_tasks drop column if exists engagement_id;
--   drop table if exists public.ops_engagements;
--   alter table public.ops_tasks drop column if exists task_type, drop column if exists code,
--     drop column if exists code_period, drop column if exists code_week,
--     drop column if exists code_seq, drop column if exists content_desc,
--     drop column if exists manager_id;
--   alter table public.ops_recurring_rules drop column if exists source_task_id,
--     drop column if exists interval_days, drop column if exists ends_on,
--     drop column if exists max_count, drop column if exists generated_count,
--     drop column if exists code_week, drop column if exists created_by;
--   alter table public.client_services drop column if exists term_pct;
--   then re-apply supabase/migrations/2026-09-19-operations-system.sql for
--   ops_create_task, ops_transition_task and ops_generate_recurring, the
--   phase 3 file for ops_log, the delete file for ops_delete_task, and the
--   term adjustment file for issue_letter and get_portal.
-- ===========================================================================

-- 9.1 The term adjustment carries its own percentage ----------------------------
/* The tick stays (`term_adjust`); beside it the percentage that tick applies,
   prefilled from the rate card for the term and editable on the line. Stored
   on the line and copied into the letter's snapshot, so a later rate card
   never moves a figure a client was already quoted. A line ticked before this
   column existed carries null, which money.js reads as the card the line was
   quoted under. */
alter table public.client_services add column if not exists term_pct numeric(6,2);

-- 9.2 The task: scope, type, name, engagement, manager ---------------------------
alter table public.ops_tasks drop constraint if exists ops_tasks_scope_check;
alter table public.ops_tasks add constraint ops_tasks_scope_check
  check (scope in ('client', 'lead', 'internal'));
alter table public.ops_tasks drop constraint if exists ops_tasks_client_scope;
alter table public.ops_tasks add constraint ops_tasks_client_scope
  check (scope = 'internal' or client_id is not null);

alter table public.ops_tasks add column if not exists task_type text not null default 'adhoc';
alter table public.ops_tasks drop constraint if exists ops_tasks_type_check;
alter table public.ops_tasks add constraint ops_tasks_type_check
  check (task_type in ('engagement', 'adhoc', 'goodwill', 'special'));
alter table public.ops_tasks add column if not exists code         text;
alter table public.ops_tasks add column if not exists code_period  text;
alter table public.ops_tasks add column if not exists code_week    smallint;
alter table public.ops_tasks add column if not exists code_seq     smallint;
alter table public.ops_tasks add column if not exists content_desc text;
alter table public.ops_tasks add column if not exists manager_id   uuid references public.team_members(id);

/* One code a client a month, whatever two sessions try at once: the lock in
   ops_next_seq is what stops them both reading 04 as free, and this index is
   what refuses the second one if anything ever bypasses the lock. Internal
   tasks carry no code. */
create unique index if not exists ops_tasks_code_idx
  on public.ops_tasks (coalesce(client_id, '00000000-0000-0000-0000-000000000000'::uuid), code_period, code_seq)
  where code_seq is not null;
create index if not exists ops_tasks_client_period_idx on public.ops_tasks (client_id, code_period);

/* Existing tasks keep their title as the editable description and their
   creator as their manager. No code is invented for them: a sequence nobody
   planned is not a plan. Guarded on the column being empty, so a second run
   cannot overwrite a description somebody has since edited. */
update public.ops_tasks set content_desc = title
 where content_desc is null and code is null;
update public.ops_tasks set manager_id = created_by
 where manager_id is null and created_by is not null;

-- 9.3 The engagement: one client's work for one month --------------------------
create table if not exists public.ops_engagements (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references public.clients(id) on delete cascade,
  period           text not null,
  manager_id       uuid references public.team_members(id),
  planned_count    integer not null default 0,
  drive_url        text,
  status           text not null default 'planning',
  meeting_at       timestamptz,
  meeting_channel  text,
  meeting_owner_id uuid references public.team_members(id),
  meeting_note     text,
  meeting_na       boolean not null default false,
  created_by       uuid references public.team_members(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  version          integer not null default 1,
  constraint ops_engagements_period_check check (period ~ '^\d{4}-\d{2}$'),
  constraint ops_engagements_status_check
    check (status in ('planning', 'ready', 'in_production', 'completed', 'cancelled')),
  constraint ops_engagements_channel_check
    check (meeting_channel is null or meeting_channel in ('onsite', 'google_meet', 'zoom', 'other'))
);
create unique index if not exists ops_engagements_client_period_idx
  on public.ops_engagements (client_id, period);

alter table public.ops_tasks add column if not exists engagement_id
  uuid references public.ops_engagements(id) on delete set null;
create index if not exists ops_tasks_engagement_idx on public.ops_tasks (engagement_id);

/* The onboarding and readiness list belongs to the engagement, not to every
   task: thirteen questions asked once a month, each with an owner and a state
   a person can act on. */
create table if not exists public.ops_engagement_checks (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.ops_engagements(id) on delete cascade,
  key           text not null,
  state         text not null default 'not_started',
  owner_id      uuid references public.team_members(id),
  note          text,
  updated_by    uuid references public.team_members(id),
  updated_at    timestamptz not null default now(),
  constraint ops_engagement_checks_state_check
    check (state in ('not_started', 'waiting_client', 'in_progress', 'ready', 'na'))
);
create unique index if not exists ops_engagement_checks_key_idx
  on public.ops_engagement_checks (engagement_id, key);

/* Append only, like the task's own events: who changed what on the
   engagement, and when. */
create table if not exists public.ops_engagement_events (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.ops_engagements(id) on delete cascade,
  event_type    text not null,
  actor_id      uuid references public.team_members(id),
  actor_email   text,
  detail        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists ops_engagement_events_idx
  on public.ops_engagement_events (engagement_id, created_at desc);

-- 9.4 A recurring rule can start from any task ----------------------------------
alter table public.ops_recurring_rules alter column template_id drop not null;
alter table public.ops_recurring_rules add column if not exists source_task_id
  uuid references public.ops_tasks(id) on delete set null;
alter table public.ops_recurring_rules add column if not exists interval_days   integer;
alter table public.ops_recurring_rules add column if not exists ends_on         date;
alter table public.ops_recurring_rules add column if not exists max_count       integer;
alter table public.ops_recurring_rules add column if not exists generated_count integer not null default 0;
alter table public.ops_recurring_rules add column if not exists code_week       smallint;
alter table public.ops_recurring_rules add column if not exists created_by      uuid references public.team_members(id);
alter table public.ops_recurring_rules drop constraint if exists ops_recurring_rules_freq_check;
alter table public.ops_recurring_rules add constraint ops_recurring_rules_freq_check
  check (frequency in ('weekly', 'monthly', 'custom'));
/* One live rule a source task, so setting it twice edits the one rule. */
create unique index if not exists ops_recurring_source_idx
  on public.ops_recurring_rules (source_task_id) where source_task_id is not null and active;

-- 9.5 The content workflow, and the two seeded ones retired for new work ---------
/* Seeded once, on a database that has none. The stages are the brief's:
   nine on the line and three beside it. Skipping a step the deliverable does
   not need is allowed and recorded (see ops_transition_task), so the
   adjacency here is the ordinary path, not the only one. */
do $$
declare w uuid;
begin
  if exists (select 1 from public.ops_workflows where key = 'content') then return; end if;
  insert into public.ops_workflows (key, name, description)
  values ('content', 'Content deliverable',
          'Planning, the content meeting, production, review and publishing.')
  returning id into w;
  insert into public.ops_workflow_stages
    (workflow_id, key, label, position, stage_group, is_active_work, is_waiting,
     is_review, is_terminal, wip_guidance, next_stage_keys) values
    (w, 'planning',          'Planning',                  1, 'intake',          false, false, false, false, null, array['meeting_scheduled','ready','on_hold','cancelled']),
    (w, 'meeting_scheduled', 'Content meeting scheduled', 2, 'intake',          false, true,  false, false, null, array['ready','planning','on_hold','cancelled']),
    (w, 'ready',             'Ready for production',      3, 'ready',           false, false, false, false, null, array['in_production','planning','blocked','on_hold','cancelled']),
    (w, 'in_production',     'In production',             4, 'active',          true,  false, false, false, 6,    array['internal_review','ready','blocked','on_hold','cancelled']),
    (w, 'internal_review',   'Internal quality review',   5, 'internal_review', false, true,  true,  false, 8,    array['client_review','changes_requested','in_production','blocked']),
    (w, 'client_review',     'Client review',             6, 'client_review',   false, true,  true,  false, null, array['approved','changes_requested','blocked','on_hold']),
    (w, 'changes_requested', 'Changes requested',         7, 'revision',        true,  false, false, false, null, array['in_production','internal_review','client_review','approved','blocked']),
    (w, 'approved',          'Approved',                  8, 'approved',        false, false, false, false, null, array['published','changes_requested']),
    (w, 'published',         'Published',                 9, 'done',            false, false, false, true,  null, array['changes_requested']),
    (w, 'blocked',           'Blocked',                  10, 'blocked',         false, true,  false, false, null, array['ready','in_production','internal_review','client_review','changes_requested','cancelled']),
    (w, 'on_hold',           'On hold',                  11, 'waiting',         false, true,  false, false, null, array['planning','ready','in_production','client_review','cancelled']),
    (w, 'cancelled',         'Cancelled',                12, 'cancelled',       false, false, false, true,  null, array['planning']);
end $$;

/* Retired for new tasks (decided with the user, 2026-09-23). A task already
   on either carries on exactly as it was: its stages, gates and events are
   untouched, and nothing reads `active` when moving it. */
update public.ops_workflows set active = false, updated_at = now()
 where key in ('general', 'video') and active;

-- 9.6 Reading the new tables ----------------------------------------------------
alter table public.ops_engagements enable row level security;
alter table public.ops_engagement_checks enable row level security;
alter table public.ops_engagement_events enable row level security;

/* An engagement is read by whoever manages it or created it, by anybody who
   may see a task inside it, and by the team queue. Select and nothing else:
   every write below is a function. */
create or replace function public.ops_may_see_engagement(p_engagement uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when not public.allowed('ops', 'view') then false
    when public.ops_granted('ops.all', 'view') then true
    else exists (
      select 1 from public.ops_engagements e
       where e.id = p_engagement
         and (e.manager_id = (select id from public.ops_me())
              or e.created_by = (select id from public.ops_me())
              or exists (select 1 from public.ops_tasks t
                          where t.engagement_id = e.id and public.ops_may_see_task(t.id))))
  end
$$;
grant execute on function public.ops_may_see_engagement(uuid) to authenticated;

drop policy if exists ops_engagements_read on public.ops_engagements;
create policy ops_engagements_read on public.ops_engagements
  for select to authenticated using (public.ops_may_see_engagement(id));
drop policy if exists ops_engagement_checks_read on public.ops_engagement_checks;
create policy ops_engagement_checks_read on public.ops_engagement_checks
  for select to authenticated using (public.ops_may_see_engagement(engagement_id));
drop policy if exists ops_engagement_events_read on public.ops_engagement_events;
create policy ops_engagement_events_read on public.ops_engagement_events
  for select to authenticated using (public.ops_may_see_engagement(engagement_id));
grant select on public.ops_engagements, public.ops_engagement_checks,
                public.ops_engagement_events to authenticated;
/* A rule is read by whoever may see the task it was set on, as well as by
   the templates part it always answered to. */
drop policy if exists ops_recurring_rules_read on public.ops_recurring_rules;
create policy ops_recurring_rules_read on public.ops_recurring_rules
  for select to authenticated using (
    public.ops_granted('ops.workflows', 'view')
    or (source_task_id is not null and public.ops_may_see_task(source_task_id)));

-- 9.7 The name ----------------------------------------------------------------
/* What a task is called on every screen and in every notification: the code
   and the description where it has a code, the old title where it does not.
   One definition, so the page, the bell and the activity record cannot name
   the same task three ways. */
create or replace function public.ops_title(t public.ops_tasks)
returns text
language sql immutable as $$
  select case
    when coalesce(t.code, '') = '' then coalesce(nullif(t.content_desc, ''), t.title, '')
    else btrim(t.code || ' ' || coalesce(t.content_desc, ''))
  end
$$;

/* YYMM + W + week + the running number, two digits. */
create or replace function public.ops_code_of(p_period text, p_week integer, p_seq integer)
returns text
language sql immutable as $$
  select substr(p_period, 3, 2) || substr(p_period, 6, 2) || 'W' || p_week::text || lpad(p_seq::text, 2, '0')
$$;

/* The next running number for a client and a month. The advisory lock is
   what makes two sessions generating for the same client and month queue
   behind each other rather than both reading the same gap as free; the
   unique index on the table is the backstop. Internal tasks carry no code,
   so the null client key is never reached from ops_create_task. */
create or replace function public.ops_next_seq(p_client uuid, p_period text)
returns integer
language plpgsql as $$
declare n integer;
begin
  perform pg_advisory_xact_lock(hashtext('ops_code:' || coalesce(p_client::text, 'internal') || ':' || p_period));
  select coalesce(max(code_seq), 0) + 1 into n from public.ops_tasks
   where coalesce(client_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = coalesce(p_client, '00000000-0000-0000-0000-000000000000'::uuid)
     and code_period = p_period;
  return n;
end $$;

/* Whose the task may be, checked ONCE at creation and never again: a client
   that later becomes a past client keeps its tasks. Client means a client
   that is engaged now (active, or paused); lead means a record that has not
   yet become one. */
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
  if p_scope = 'client' and st not in ('active', 'paused') then return 'client-not-active'; end if;
  if p_scope = 'lead' and st not in ('lead', 'contacted', 'proposal') then return 'not-a-lead'; end if;
  return null;
end $$;

-- 9.8 Create --------------------------------------------------------------------
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
  scope text;
  ttype text;
  cid   uuid;
  bad   text;
  descr text;
  period text;
  week  integer;
  seq   integer;
  code  text;
  title text;
  first_stage text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  scope := coalesce(p_payload ->> 'scope', 'client');
  cid := (p_payload ->> 'client_id')::uuid;
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;

  ttype := coalesce(p_payload ->> 'task_type', 'adhoc');
  if ttype not in ('engagement', 'adhoc', 'goodwill', 'special') then
    return jsonb_build_object('error', 'bad-task-type');
  end if;

  /* The description is the team's to edit and may start blank on a task that
     carries a code; a task with no code is named by its description alone, so
     there it is required. `title` is accepted from older callers as the
     description. */
  descr := nullif(btrim(coalesce(p_payload ->> 'content_desc', p_payload ->> 'title', '')), '');

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
  end if;
  /* New work goes on the content workflow. A caller may still name another
     (a template's own, or one somebody adds), and a task already on a retired
     workflow is never moved. */
  wf := coalesce((p_payload ->> 'workflow_id')::uuid, tpl.workflow_id,
                 (select id from public.ops_workflows where key = 'content' and active),
                 (select id from public.ops_workflows where active order by created_at limit 1));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  select key into first_stage from public.ops_workflow_stages
   where workflow_id = wf order by position limit 1;

  publish := (p_payload ->> 'publish_at')::timestamptz;
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
  if fd is not null and fin is not null and not public.ops_due_order_ok(fd, fin) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  /* The name. The month is the content month (the scheduled publish date's,
     else the one the caller names, else this one); the week is the planned
     publishing week, chosen by the caller and prefilled by the page from the
     date; the running number is the client's for the month. Generated once,
     under the lock, and never rewritten: a publish date that moves later
     leaves the name as it was, because the name is a label and not a fact
     about the date. */
  if scope <> 'internal' then
    period := coalesce(nullif(p_payload ->> 'code_period', ''),
                       case when publish is not null then to_char(publish, 'YYYY-MM') end,
                       to_char(now(), 'YYYY-MM'));
    if period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
    week := coalesce((p_payload ->> 'code_week')::integer,
                     case when publish is not null
                          then least(5, ((extract(day from publish)::integer - 1) / 7) + 1) end,
                     1);
    if week < 1 or week > 5 then return jsonb_build_object('error', 'bad-week'); end if;
    seq := public.ops_next_seq(cid, period);
    code := public.ops_code_of(period, week, seq);
    title := btrim(code || ' ' || coalesce(descr, ''));
  else
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
  end if;

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality,
    task_type, code, code_period, code_week, code_seq, content_desc,
    engagement_id, manager_id, parent_task_id)
  values (
    scope, cid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, coalesce(first_stage, 'intake'),
    title, p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'other'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'),
    ttype, code, period, week, seq, descr,
    (p_payload ->> 'engagement_id')::uuid,
    coalesce((p_payload ->> 'manager_id')::uuid, m.id),
    (p_payload ->> 'parent_task_id')::uuid)
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

  -- The template's checklist, or the one the caller hands over (a duplicate
  -- carries its source's labels, unticked), in the order stated.
  for item in select * from jsonb_array_elements(
      coalesce(p_payload -> 'checklist', tpl.checklist, '[]'::jsonb)) loop
    i := i + 1;
    insert into public.ops_task_checklist_items (task_id, label, position)
    values (tid, item #>> '{}', i);
  end loop;

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
    jsonb_build_object('title', title, 'code', code,
                       'first_draft_due_at', fd, 'final_due_at', fin),
    case when (p_payload ->> 'duplicated_from') is null then '{}'::jsonb
         else jsonb_build_object('duplicated_from', p_payload ->> 'duplicated_from') end);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

-- 9.9 The description is edited; the code and the serial never are --------------
create or replace function public.ops_set_content_desc(
  p_task uuid, p_desc text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
  d text;
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
  d := nullif(btrim(coalesce(p_desc, '')), '');
  if d is null and coalesce(t.code, '') = '' then
    return jsonb_build_object('error', 'title-required');
  end if;
  if d is not distinct from t.content_desc then return public.ops_task_json(p_task); end if;
  update public.ops_tasks
     set content_desc = d,
         title = case when coalesce(code, '') = '' then d else btrim(code || ' ' || coalesce(d, '')) end,
         version = version + 1, updated_at = now()
   where id = p_task;
  perform public.ops_log(p_task, 'renamed',
    jsonb_build_object('content_desc', t.content_desc),
    jsonb_build_object('content_desc', d), '{}'::jsonb);
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_set_content_desc(uuid, text, integer) to authenticated;

-- 9.10 Move a stage, hand it on, and skip what the deliverable does not need ------
/* The signature grows by two, so the four-argument one goes first: with both
   present PostgREST cannot tell a call that names four arguments from one
   that names four and leaves two to their defaults. */
drop function if exists public.ops_transition_task(uuid, text, integer, text);
create or replace function public.ops_transition_task(
  p_task uuid, p_next text, p_version integer default null, p_note text default null,
  p_assignee uuid default null, p_skip_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cur public.ops_workflow_stages;
  nxt public.ops_workflow_stages;
  sk  public.ops_workflow_stages;
  eng public.ops_engagements;
  has_owner boolean;
  has_draft boolean;
  has_final boolean;
  was_owner uuid;
  side text[] := array['blocked', 'waiting', 'kiv', 'cancelled'];
  skipping boolean := false;
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
  if t.stage_key = p_next then return public.ops_task_json(p_task); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  if not (p_next = any (cur.next_stage_keys)) then
    /* A step the deliverable does not need is skipped, forward along the
       line, with a reason on the record: who skipped it and why is written
       against every stage that was passed over. Nothing beside the line can
       be skipped into or out of, and nothing is skipped backwards. */
    if not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.position > cur.position then
      if nullif(btrim(coalesce(p_skip_reason, '')), '') is null then
        return jsonb_build_object('error', 'skip-reason-required');
      end if;
      skipping := true;
    else
      return jsonb_build_object('error', 'bad-transition',
        'allowed', to_jsonb(cur.next_stage_keys));
    end if;
  end if;

  -- What each gate needs before it opens.
  has_owner := exists (select 1 from public.ops_task_assignees
                        where task_id = p_task and responsibility = 'owner' and ended_at is null)
               or p_assignee is not null;
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
  /* Production waits on the engagement: planning marked complete, and the
     content meeting held or marked not applicable. A task with no engagement
     (ad hoc, internal) has nothing to wait on. */
  if p_next = 'in_production' and t.engagement_id is not null then
    select * into eng from public.ops_engagements where id = t.engagement_id;
    if eng.status = 'planning' then return jsonb_build_object('error', 'planning-incomplete'); end if;
    if not (eng.meeting_na or (eng.meeting_at is not null and eng.meeting_at <= now())) then
      return jsonb_build_object('error', 'meeting-required');
    end if;
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
  if p_next = 'published' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;

  /* The hand to the next person, recorded on the move: the previous owner
     ends, the new one begins, and the event names both with the stage it
     happened at. Work level, because handing the work on is part of doing
     it; reassigning a task without moving it stays Manage. */
  if p_assignee is not null then
    select team_member_id into was_owner from public.ops_task_assignees
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    if p_assignee is distinct from was_owner then
      if not exists (select 1 from public.team_members where id = p_assignee and active) then
        return jsonb_build_object('error', 'no-such-person');
      end if;
      update public.ops_task_assignees set ended_at = now()
       where task_id = p_task and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, p_assignee, 'owner', m.id);
      perform public.ops_log(p_task, 'assignment_changed',
        jsonb_build_object('owner_id', was_owner),
        jsonb_build_object('owner_id', p_assignee),
        jsonb_build_object('handover', true, 'stage_key', p_next, 'from_stage_key', t.stage_key));
    end if;
  end if;

  if skipping then
    for sk in select * from public.ops_workflow_stages
               where workflow_id = t.workflow_id
                 and position > cur.position and position < nxt.position
                 and not (stage_group = any (side))
               order by position loop
      perform public.ops_log(p_task, 'stage_skipped',
        jsonb_build_object('stage_key', sk.key), jsonb_build_object('stage_key', p_next),
        jsonb_build_object('reason', btrim(p_skip_reason)));
    end loop;
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
    (case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end)
    || (case when skipping then jsonb_build_object('skip_reason', btrim(p_skip_reason)) else '{}'::jsonb end));
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
grant execute on function public.ops_transition_task(uuid, text, integer, text, uuid, text) to authenticated;

-- 9.11 Duplicate ----------------------------------------------------------------
/* A copy is a new task with a new code: the planning fields travel, the
   history does not. Dates and assignees travel only where the caller says
   so; the description travels only where the caller says so; comments,
   events, sessions and review records never travel. */
create or replace function public.ops_duplicate_task(
  p_task uuid, p_opts jsonb default '{}'::jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  s   public.ops_tasks;
  owner uuid;
  payload jsonb;
  made jsonb;
  c   uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.ops_tasks where id = p_task;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce((p_opts ->> 'copy_assignees')::boolean, false) then
    select team_member_id into owner from public.ops_task_assignees
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
  end if;

  payload := jsonb_build_object(
    'scope', s.scope, 'client_id', s.client_id, 'campaign_id', s.campaign_id,
    'template_id', s.template_id, 'workflow_id', s.workflow_id,
    'task_type', s.task_type, 'deliverable_type', s.deliverable_type,
    'engagement_id', coalesce((p_opts ->> 'engagement_id')::uuid, s.engagement_id),
    'manager_id', s.manager_id,
    'priority_level', s.priority_level, 'complexity', s.complexity,
    'estimate_minutes', s.estimate_minutes,
    'description', s.description, 'remarks', s.remarks,
    'language_codes', to_jsonb(s.language_codes),
    'content_desc', case when coalesce((p_opts ->> 'keep_desc')::boolean, false) then s.content_desc else null end,
    'code_period', coalesce(nullif(p_opts ->> 'code_period', ''), s.code_period),
    'code_week', coalesce((p_opts ->> 'code_week')::integer, s.code_week),
    'owner_id', owner,
    'parent_task_id', s.id,
    'duplicated_from', s.id,
    'checklist', coalesce((select jsonb_agg(label order by position)
                             from public.ops_task_checklist_items where task_id = p_task), '[]'::jsonb));
  if coalesce((p_opts ->> 'copy_dates')::boolean, false) then
    payload := payload || jsonb_build_object(
      'publish_at', coalesce((p_opts ->> 'publish_at')::timestamptz, s.publish_at),
      'first_draft_due_at', s.current_first_draft_due_at,
      'final_due_at', s.current_final_due_at);
  elsif (p_opts ->> 'publish_at') is not null then
    payload := payload || jsonb_build_object('publish_at', (p_opts ->> 'publish_at')::timestamptz);
  end if;
  /* A copy of a task on a retired workflow starts on the live one: the
     retired pair is for the tasks already on them and nothing new. */
  if not exists (select 1 from public.ops_workflows where id = s.workflow_id and active) then
    payload := payload - 'workflow_id' - 'template_id';
  end if;

  made := public.ops_create_task(payload, p_idem);
  if made ? 'error' then return made; end if;

  if coalesce((p_opts ->> 'copy_assignees')::boolean, false) then
    for c in select team_member_id from public.ops_task_assignees
              where task_id = p_task and responsibility = 'contributor' and ended_at is null loop
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values ((made ->> 'id')::uuid, c, 'contributor', m.id) on conflict do nothing;
    end loop;
  end if;
  return made;
end $$;
grant execute on function public.ops_duplicate_task(uuid, jsonb, text) to authenticated;

-- 9.12 A month of content at once ------------------------------------------------
/* The operator types the count; nothing is read off the service contract,
   because contract quantities change between renewals and a number nobody
   confirmed is a number nobody planned. `weeks` is how many go in each
   publishing week (four or five figures); with none given the count is spread
   over four. The running numbers are the client's for the month, so twelve
   tasks over four weeks are 01 to 12 whatever week each lands in. A dry run
   answers with the codes that would be made and writes nothing. */
create or replace function public.ops_generate_month(
  p_payload jsonb, p_dry_run boolean default false, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  cid    uuid;
  per    text;
  n      integer;
  weeks  integer[];
  bad    text;
  eng    uuid;
  k      integer;
  w      integer;
  seq    integer;
  seqs   integer;
  made   jsonb := '[]'::jsonb;
  one    jsonb;
  key    text;
  scope  text;
  first_day date;
  publish timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  n := coalesce((p_payload ->> 'count')::integer, 0);
  scope := coalesce(p_payload ->> 'scope', 'client');
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  if n < 1 or n > 60 then return jsonb_build_object('error', 'bad-count'); end if;

  if (p_payload -> 'weeks') is not null and jsonb_typeof(p_payload -> 'weeks') = 'array' then
    select array_agg(x::integer) into weeks from jsonb_array_elements_text(p_payload -> 'weeks') x;
    if array_length(weeks, 1) < 1 or array_length(weeks, 1) > 5 then
      return jsonb_build_object('error', 'bad-weeks');
    end if;
    if (select sum(v) from unnest(weeks) v) <> n then return jsonb_build_object('error', 'weeks-do-not-add-up'); end if;
  else
    weeks := array[n / 4, n / 4, n / 4, n - 3 * (n / 4)];
  end if;

  /* The same press twice is one month, not two. */
  if not p_dry_run and p_idem is not null then
    if exists (select 1 from public.ops_tasks where idem_key = 'month:' || p_idem || ':1') then
      return jsonb_build_object('error', 'already-generated');
    end if;
  end if;

  first_day := (per || '-01')::date;
  /* One lock for the whole run, taken before anything is read: two operators
     generating the same month queue here, so the second sees the first's
     engagement and the first's numbers rather than racing both. */
  perform pg_advisory_xact_lock(hashtext('ops_code:' || cid::text || ':' || per));
  if not p_dry_run then
    eng := coalesce((p_payload ->> 'engagement_id')::uuid,
                    (select e.id from public.ops_engagements e where e.client_id = cid and e.period = per));
    if eng is null then
      eng := (public.ops_engagement_upsert(jsonb_build_object(
                'client_id', cid, 'period', per, 'planned_count', n,
                'manager_id', coalesce((p_payload ->> 'manager_id')::uuid, m.id))) ->> 'id')::uuid;
    else
      update public.ops_engagements set planned_count = greatest(planned_count, n), updated_at = now()
       where id = eng and planned_count < n;
    end if;
  end if;

  /* One lock for the whole month, so the preview and the run see the same
     next number and two operators generating for one client queue. */
  seq := public.ops_next_seq(cid, per) - 1;
  seqs := 0;
  for w in 1 .. array_length(weeks, 1) loop
    for k in 1 .. coalesce(weeks[w], 0) loop
      seq := seq + 1;
      seqs := seqs + 1;
      /* A tentative date on the Monday of the week, so the calendar has
         somewhere to put it; the meeting fixes the real one. */
      publish := (first_day + ((w - 1) * 7))::timestamptz;
      if p_dry_run then
        made := made || jsonb_build_object('code', public.ops_code_of(per, w, seq), 'week', w, 'seq', seq);
      else
        key := case when p_idem is null then null else 'month:' || p_idem || ':' || seqs::text end;
        one := public.ops_create_task(jsonb_build_object(
          'scope', scope, 'client_id', cid, 'engagement_id', eng,
          'task_type', coalesce(p_payload ->> 'task_type', 'engagement'),
          'deliverable_type', p_payload ->> 'deliverable_type',
          'priority_level', (p_payload ->> 'priority_level')::integer,
          'complexity', p_payload ->> 'complexity',
          'owner_id', (p_payload ->> 'owner_id')::uuid,
          'manager_id', (p_payload ->> 'manager_id')::uuid,
          'code_period', per, 'code_week', w,
          'publish_at', publish), key);
        if one ? 'error' then return one; end if;
        made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'week', w, 'seq', seq);
      end if;
    end loop;
  end loop;
  return jsonb_build_object('engagement_id', eng, 'period', per, 'count', seqs,
                            'tasks', made, 'dry_run', p_dry_run);
end $$;
grant execute on function public.ops_generate_month(jsonb, boolean, text) to authenticated;

-- 9.13 Recurring, from any task ------------------------------------------------
/* Setting the rule is the task owner's act (Work). One live rule a task. */
create or replace function public.ops_set_recurring(p_task uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
  r public.ops_recurring_rules;
  freq text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  select * into r from public.ops_recurring_rules where source_task_id = p_task and active;
  if coalesce((p_payload ->> 'active')::boolean, true) = false then
    if r.id is not null then
      update public.ops_recurring_rules set active = false, updated_at = now() where id = r.id;
      perform public.ops_log(p_task, 'recurrence_off', null, null, '{}'::jsonb);
    end if;
    return jsonb_build_object('ok', true, 'active', false);
  end if;

  freq := coalesce(p_payload ->> 'frequency', 'monthly');
  if freq not in ('weekly', 'monthly', 'custom') then return jsonb_build_object('error', 'bad-frequency'); end if;
  if freq = 'custom' and coalesce((p_payload ->> 'interval_days')::integer, 0) < 1 then
    return jsonb_build_object('error', 'interval-required');
  end if;

  if r.id is null then
    insert into public.ops_recurring_rules
      (name, client_id, template_id, owner_id, frequency, day_of_month, source_task_id,
       interval_days, ends_on, max_count, code_week, created_by)
    values (public.ops_title(t), t.client_id, t.template_id,
            (select team_member_id from public.ops_task_assignees
              where task_id = p_task and responsibility = 'owner' and ended_at is null),
            freq, (p_payload ->> 'day_of_month')::integer, p_task,
            (p_payload ->> 'interval_days')::integer, (p_payload ->> 'ends_on')::date,
            (p_payload ->> 'max_count')::integer, coalesce((p_payload ->> 'code_week')::integer, t.code_week),
            m.id)
    returning * into r;
    perform public.ops_log(p_task, 'recurrence_set', null, to_jsonb(r) - 'id', '{}'::jsonb);
  else
    update public.ops_recurring_rules set
      frequency = freq, day_of_month = (p_payload ->> 'day_of_month')::integer,
      interval_days = (p_payload ->> 'interval_days')::integer,
      ends_on = (p_payload ->> 'ends_on')::date, max_count = (p_payload ->> 'max_count')::integer,
      code_week = coalesce((p_payload ->> 'code_week')::integer, r.code_week),
      updated_at = now()
    where id = r.id returning * into r;
    perform public.ops_log(p_task, 'recurrence_set', null, to_jsonb(r) - 'id', '{}'::jsonb);
  end if;
  return to_jsonb(r);
end $$;
grant execute on function public.ops_set_recurring(uuid, jsonb) to authenticated;

/* Every occurrence due in a month, once. The key is the rule and the
   occurrence date, so a run pressed twice — or by two people — files the
   same occurrence once, and the unique index on `idem_key` is what says so
   if two runs race. A rule set on a task copies that task; an older rule set
   on a template creates from the template as it always did. */
create or replace function public.ops_generate_recurring(
  p_period text, p_rules uuid[] default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  r     public.ops_recurring_rules;
  src   public.ops_tasks;
  made  integer := 0;
  skip  integer := 0;
  key   text;
  first_day date;
  last_day date;
  anchor date;
  d     date;
  stepd integer;
  one   jsonb;
  wk    integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  first_day := (p_period || '-01')::date;
  last_day := (first_day + interval '1 month' - interval '1 day')::date;

  for r in select * from public.ops_recurring_rules
            where active and (p_rules is null or id = any (p_rules))
              and (source_task_id is null or public.ops_may_see_task(source_task_id)) loop
    if r.source_task_id is not null then
      select * into src from public.ops_tasks where id = r.source_task_id;
    else
      src := null;
    end if;

    /* The dates this rule falls on inside the month. */
    if r.frequency = 'monthly' then
      d := first_day + (least(coalesce(r.day_of_month,
              case when src.publish_at is not null then extract(day from src.publish_at)::integer else 1 end),
              extract(day from last_day)::integer) - 1);
      stepd := null;
    else
      stepd := case when r.frequency = 'weekly' then 7 else greatest(1, coalesce(r.interval_days, 7)) end;
      anchor := coalesce(src.publish_at::date, r.created_at::date, first_day);
      if anchor > first_day then d := anchor;
      else d := anchor + ((((first_day - anchor) + stepd - 1) / stepd) * stepd); end if;
    end if;

    while d is not null and d <= last_day loop
      if d >= first_day
         and (r.ends_on is null or d <= r.ends_on)
         and (r.max_count is null or r.generated_count < r.max_count) then
        key := 'recur:' || r.id::text || ':' || to_char(d, 'YYYY-MM-DD');
        if exists (select 1 from public.ops_tasks where idem_key = key) then
          skip := skip + 1;
        else
          wk := coalesce(r.code_week, least(5, ((extract(day from d)::integer - 1) / 7) + 1));
          if src.id is not null then
            one := public.ops_duplicate_task(src.id, jsonb_build_object(
              'keep_desc', true, 'copy_dates', false, 'copy_assignees', true,
              'publish_at', d::timestamptz, 'code_period', p_period, 'code_week', wk,
              'engagement_id', (select id from public.ops_engagements
                                 where client_id = src.client_id and period = p_period)), key);
          else
            one := public.ops_create_task(jsonb_build_object(
              'scope', case when r.client_id is null then 'internal' else 'client' end,
              'client_id', r.client_id, 'template_id', r.template_id,
              'title', r.name || ' — ' || p_period, 'content_desc', r.name,
              'owner_id', r.owner_id, 'publish_at', d::timestamptz,
              'code_period', p_period, 'code_week', wk), key);
          end if;
          if one ? 'error' then return one || jsonb_build_object('rule', r.id); end if;
          made := made + 1;
          update public.ops_recurring_rules
             set generated_count = generated_count + 1, last_generated_period = p_period, updated_at = now()
           where id = r.id;
          r.generated_count := r.generated_count + 1;
        end if;
      end if;
      exit when stepd is null;
      d := d + stepd;
    end loop;
  end loop;
  return jsonb_build_object('created', made, 'skipped', skip, 'period', p_period);
end $$;
grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;

-- 9.14 The engagement's own writes ----------------------------------------------
create or replace function public.ops_engagement_json(p_engagement uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(e) || jsonb_build_object(
    'checks', coalesce((select jsonb_agg(to_jsonb(c) order by c.key)
                          from public.ops_engagement_checks c where c.engagement_id = e.id), '[]'::jsonb),
    'task_count', (select count(*) from public.ops_tasks t
                    where t.engagement_id = e.id and t.archived_at is null))
  from public.ops_engagements e where e.id = p_engagement
$$;
grant execute on function public.ops_engagement_json(uuid) to authenticated;

create or replace function public.ops_engagement_log(p_engagement uuid, p_type text, p_detail jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  insert into public.ops_engagement_events (engagement_id, event_type, actor_id, actor_email, detail)
  values (p_engagement, p_type, m.id, m.email, coalesce(p_detail, '{}'::jsonb));
end $$;

/* One a client a month. A second call for the same month edits the one row
   rather than making a second; the thirteen checks are seeded on creation
   and never re-seeded. */
create or replace function public.ops_engagement_upsert(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  cid uuid;
  per text;
  eid uuid;
  k text;
  fresh boolean := false;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  if cid is null or not exists (select 1 from public.clients where id = cid) then
    return jsonb_build_object('error', 'client-required');
  end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;

  select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
  if eid is null then
    insert into public.ops_engagements (client_id, period, manager_id, planned_count, drive_url, created_by)
    values (cid, per, coalesce((p_payload ->> 'manager_id')::uuid, m.id),
            coalesce((p_payload ->> 'planned_count')::integer, 0),
            nullif(p_payload ->> 'drive_url', ''), m.id)
    on conflict (client_id, period) do nothing
    returning id into eid;
    /* Somebody else made it between the read and the write: theirs stands. */
    if eid is null then
      select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
    else
      fresh := true;
    end if;
  end if;
  if fresh then
    foreach k in array array['client_name', 'legal_name', 'brand_name', 'brand_profile',
                             'social_profiles', 'client_info', 'platform_ready',
                             'platform_setup', 'platform_create', 'partner_access_requested',
                             'partner_access_received', 'pre_ads_required', 'pre_ads_completed'] loop
      insert into public.ops_engagement_checks (engagement_id, key) values (eid, k)
      on conflict do nothing;
    end loop;
    perform public.ops_engagement_log(eid, 'created', p_payload - 'client_id');
  else
    if not public.ops_may_see_engagement(eid) then return jsonb_build_object('error', 'denied'); end if;
    update public.ops_engagements set
      manager_id = coalesce((p_payload ->> 'manager_id')::uuid, manager_id),
      planned_count = coalesce((p_payload ->> 'planned_count')::integer, planned_count),
      drive_url = case when p_payload ? 'drive_url' then nullif(p_payload ->> 'drive_url', '') else drive_url end,
      updated_at = now(), version = version + 1
    where id = eid;
    perform public.ops_engagement_log(eid, 'edited', p_payload - 'client_id' - 'period');
  end if;
  return public.ops_engagement_json(eid) || jsonb_build_object('created', fresh);
end $$;
grant execute on function public.ops_engagement_upsert(jsonb) to authenticated;

create or replace function public.ops_engagement_set_check(
  p_engagement uuid, p_key text, p_state text, p_owner uuid default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; was text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_state not in ('not_started', 'waiting_client', 'in_progress', 'ready', 'na') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  select state into was from public.ops_engagement_checks
   where engagement_id = p_engagement and key = p_key;
  if was is null then return jsonb_build_object('error', 'no-such-check'); end if;
  update public.ops_engagement_checks
     set state = p_state, owner_id = coalesce(p_owner, owner_id),
         note = case when p_note is null then note else nullif(btrim(p_note), '') end,
         updated_by = m.id, updated_at = now()
   where engagement_id = p_engagement and key = p_key;
  perform public.ops_engagement_log(p_engagement, 'check_changed',
    jsonb_build_object('key', p_key, 'from', was, 'to', p_state, 'owner_id', p_owner));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_check(uuid, text, text, uuid, text) to authenticated;

/* The content meeting. When it is first put in the diary the date is today
   or later; once it has been held the record stays as it was, because a past
   meeting is a fact and not a mistake. Not applicable is its own answer. */
create or replace function public.ops_engagement_set_meeting(
  p_engagement uuid, p_at timestamptz, p_channel text default null,
  p_owner uuid default null, p_note text default null, p_na boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce(p_na, false) then
    update public.ops_engagements set meeting_na = true, meeting_note = coalesce(p_note, meeting_note),
           updated_at = now(), version = version + 1 where id = p_engagement;
    perform public.ops_engagement_log(p_engagement, 'meeting_na', jsonb_build_object('note', p_note));
    return public.ops_engagement_json(p_engagement);
  end if;
  if p_at is null then return jsonb_build_object('error', 'no-date'); end if;
  if p_channel is not null and p_channel not in ('onsite', 'google_meet', 'zoom', 'other') then
    return jsonb_build_object('error', 'bad-channel');
  end if;
  if e.meeting_at is null and p_at::date < current_date then
    return jsonb_build_object('error', 'meeting-in-past');
  end if;
  update public.ops_engagements set
    meeting_at = p_at, meeting_channel = coalesce(p_channel, meeting_channel),
    meeting_owner_id = coalesce(p_owner, meeting_owner_id, m.id),
    meeting_note = case when p_note is null then meeting_note else nullif(btrim(p_note), '') end,
    meeting_na = false, updated_at = now(), version = version + 1
  where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'meeting_set',
    jsonb_build_object('at', p_at, 'channel', p_channel, 'owner_id', p_owner, 'was', e.meeting_at));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean) to authenticated;

/* Ready is a claim about the checklist and the meeting, so the database
   checks both before it lets the word stand. */
create or replace function public.ops_engagement_set_status(
  p_engagement uuid, p_status text, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('planning', 'ready', 'in_production', 'completed', 'cancelled') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> e.version then
    return jsonb_build_object('error', 'stale', 'engagement', public.ops_engagement_json(p_engagement));
  end if;
  if p_status in ('ready', 'in_production') and e.status = 'planning' then
    if exists (select 1 from public.ops_engagement_checks
                where engagement_id = p_engagement
                  and state in ('not_started', 'waiting_client', 'in_progress')) then
      return jsonb_build_object('error', 'checklist-open');
    end if;
    if not (e.meeting_na or (e.meeting_at is not null and e.meeting_at <= now())) then
      return jsonb_build_object('error', 'meeting-required');
    end if;
  end if;
  update public.ops_engagements set status = p_status, updated_at = now(), version = version + 1
   where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'status_changed',
    jsonb_build_object('from', e.status, 'to', p_status));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_status(uuid, text, integer) to authenticated;

-- 9.15 The name everywhere the task is named ------------------------------------
/* Phase 3's ops_log, with the notification naming the task by its name and
   its serial. Nothing else in it changes. */
create or replace function public.ops_log(
  p_task uuid, p_type text, p_from jsonb, p_to jsonb, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  t      public.ops_tasks;
  owner  uuid;
  who    text;
  body   text;
  st     public.ops_workflow_stages;
begin
  m := public.ops_me();
  insert into public.ops_task_events (task_id, event_type, actor_id, actor_email,
                                      from_value, to_value, detail)
  values (p_task, p_type, m.id, m.email, p_from, p_to, coalesce(p_detail, '{}'::jsonb));

  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return; end if;
  who := coalesce(nullif(m.name, ''), m.email, 'Somebody');

  if p_type = 'assignment_changed' then
    owner := (p_to ->> 'owner_id')::uuid;
    if owner is not null and owner is distinct from m.id then
      perform public.ops_notify(owner, p_task, 'assigned',
        'T' || t.task_no || ' · ' || public.ops_title(t),
        case when coalesce((p_detail ->> 'handover')::boolean, false)
             then 'Handed to you by ' || who || ' at ' ||
                  coalesce((public.ops_stage(t.workflow_id, p_detail ->> 'stage_key')).label, p_detail ->> 'stage_key') || '.'
             else 'Assigned to you by ' || who || '.' end,
        'assigned:' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
    end if;
    return;
  end if;

  select team_member_id into owner from public.ops_task_assignees
   where task_id = p_task and responsibility = 'owner' and ended_at is null
   limit 1;
  if owner is null or owner = m.id then return; end if;

  if p_type = 'stage_changed' then
    st := public.ops_stage(t.workflow_id, p_to ->> 'stage_key');
    body := 'Moved to ' || coalesce(st.label, p_to ->> 'stage_key') || ' by ' || who || '.';
  elsif p_type = 'due_changed' then
    body := 'The ' || case when p_to ->> 'kind' = 'final' then 'final' else 'first draft' end
      || ' date moved to ' || to_char((p_to ->> 'value')::timestamptz, 'DD Mon YYYY')
      || ' by ' || who || '.';
  elsif p_type = 'blocked' then
    body := 'Marked blocked by ' || who || ': '
      || coalesce(p_detail ->> 'category', 'reason not given') || '.';
  elsif p_type = 'unblocked' then
    body := 'Unblocked by ' || who || '.';
  elsif p_type = 'revision_requested' then
    body := 'A revision was requested by ' || who || '.';
  elsif p_type = 'approval_recorded' then
    body := 'A review decision was recorded by ' || who || '.';
  elsif p_type = 'reopened' then
    body := 'Reopened by ' || who || '.';
  elsif p_type = 'cancelled' then
    body := 'Cancelled by ' || who || '.';
  else
    return;
  end if;

  perform public.ops_notify(owner, p_task, p_type,
    'T' || t.task_no || ' · ' || public.ops_title(t), body,
    p_type || ':' || p_task::text || ':' || owner::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
end $$;

/* The deletion names the task the way every screen does. */
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
  if not public.allowed('ops', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce(p_confirm, '') <> 'T' || t.task_no::text then
    return jsonb_build_object('error', 'confirm-required');
  end if;

  select c.name into cl from public.clients c where c.id = t.client_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'ops.deleted',
          'T' || t.task_no::text,
          public.ops_title(t) ||
          coalesce(' · ' || cl, case when t.scope = 'internal' then ' · Internal' else '' end) ||
          coalesce(' · ' || nullif(btrim(p_reason), ''), ''));

  delete from public.ops_tasks where id = p_task;
  return jsonb_build_object('deleted', true, 'task_no', t.task_no);
end $$;
grant execute on function public.ops_delete_task(uuid, text, text) to authenticated;

-- END OF PHASE 4 -----------------------------------------------------------

-- 9.16 The letter and the client's page carry the percentage --------------------
-- Copied from supabase/schema.sql byte for byte; tests/sql.js compares them.

create or replace function public.issue_letter(
  p_client    uuid,
  p_services  uuid[],
  p_idem      text,
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false,
  /* A reference somebody typed. Blank is the ordinary case and the counter
     below makes the number; where one is typed it is checked against every
     document that stands and the counter is not advanced, so filling a gap
     by hand never costs the next letter its place in the sequence. */
  p_serial    text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  ct     public.client_contacts%rowtype;
  me     public.team_members%rowtype;
  v_ym   text;
  v_seq  int;
  v_try  int;
  v_no   text;
  v_id   uuid;
  v_lines jsonb;
  v_n    int;
  v_bad  int;
  v_old  public.client_documents%rowtype;
begin
  if not public.allowed('clients.documents') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if p_client is null or p_services is null or array_length(p_services, 1) is null then
    return jsonb_build_object('error', 'no-lines');
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;

  -- The Client ID is what the serial is built from, so there is no letter
  -- without one. Staff enter it on the record; nothing invents it. A typed
  -- reference needs no code, because nothing is being built.
  v_no := nullif(btrim(coalesce(p_serial, '')), '');
  if v_no is null and coalesce(btrim(cl.client_code), '') = '' then
    return jsonb_build_object('error', 'no-client-code');
  end if;

  -- The same submission, pressed twice, is one letter. Answered before any
  -- number is reserved, so a double click cannot spend a serial either.
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.client_documents
      where client_id = p_client and idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
    end if;
  end if;

  -- A typed reference is checked before anything is written: the same shape
  -- the Register accepts, and refused where a document still holds it.
  if v_no is not null then
    if v_no !~ '^[A-Za-z0-9/._-]{3,40}$' then
      return jsonb_build_object('error', 'serial-shape');
    end if;
    if public.serial_taken(v_no) then
      return jsonb_build_object('error', 'serial-taken');
    end if;
  end if;

  -- Every id must be this client's own live line, and in a state this letter
  -- may carry: To quote always, Confirmed only on a deliberate renewal.
  select count(*) into v_bad from unnest(p_services) s(id)
    left join public.client_services cs
      on cs.id = s.id and cs.client_id = p_client and cs.archived_at is null
    where cs.id is null
       or (cs.state = 'confirmed' and not p_renewal)
       or cs.state not in ('quoted', 'confirmed');
  if v_bad > 0 then return jsonb_build_object('error', 'bad-lines'); end if;

  -- A line already on a live letter is not offered again by accident. The way
  -- through is to void that letter, or to name it as the one being replaced.
  select count(*) into v_bad
    from public.client_document_services m
    join public.client_documents d on d.id = m.document_id
   where m.service_id = any(p_services)
     and d.voided_at is null
     and d.superseded_by is null
     and d.verified_at is null
     and (p_replaces is null or d.id <> p_replaces);
  if v_bad > 0 then return jsonb_build_object('error', 'already-quoted'); end if;

  if p_replaces is not null then
    select * into v_old from public.client_documents
      where id = p_replaces and client_id = p_client;
    if v_old.id is null then return jsonb_build_object('error', 'no-replaces'); end if;
    if v_old.verified_at is not null then return jsonb_build_object('error', 'replaces-verified'); end if;
  end if;

  select * into ct from public.client_contacts
    where client_id = p_client and archived_at is null
    order by (id = cl.bill_contact_id) desc, is_primary desc, name limit 1;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  -- A letter is signed by a person. issued_by is this row's name, so a team
  -- row named "Superadmin" printed that word under ADSPACE PLT on a client's
  -- letterhead. Refuse rather than draw a permission as a signatory.
  if not public.issuer_name_ok(me.name) then
    return jsonb_build_object('error', 'issuer-name', 'name', coalesce(me.name, ''));
  end if;

  -- The snapshot is built from the stored rows, never from what the browser
  -- sent: the words on a letter are the words the record held at that moment.
  select jsonb_agg(jsonb_build_object(
           'label', cs.label, 'unit', coalesce(cs.unit, ''), 'note', coalesce(cs.note, ''),
           'detail', coalesce(cs.detail, ''), 'state', cs.state,
           'qty', cs.qty, 'rate', cs.rate,
           'tenure', greatest(1, coalesce(cs.tenure, 1)),
           'start_on', coalesce(cs.start_on, ''),
           -- The line's own answer to whether its term prices it. Written into
           -- the snapshot because the letter is redrawn from it, and a letter
           -- must print the same figure every time it is drawn. A snapshot
           -- taken before this key existed carries none, which money.js reads
           -- as on, so those letters redraw as they were issued.
           'term_adjust', coalesce(cs.term_adjust, false),
           -- And the percentage that tick applies, so a later rate card can
           -- never move a figure this letter printed. Null on a line quoted
           -- before the column existed, which money.js reads as that card.
           'term_pct', cs.term_pct,
           'tax', cl.sst_applies is not false,
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;

  -- A typed reference spends no sequence number: the counter is the office's
  -- record of how many letters it has issued this month, and a person filling
  -- a gap by hand has not issued one more.
  if v_no is null then
    -- The month is Malaysian, because the office that numbers the letter is.
    v_ym := to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');

    -- The counter still advances on every automatic issue, and the upsert's
    -- row lock is what makes the scan below safe: a second issuer blocks here
    -- until the first has committed its letter, so the two never read the same
    -- gap as free. What the counter gives is a bound to scan within, not the
    -- number itself.
    insert into public.client_document_seq (client_id, ym, next_val)
         values (p_client, v_ym, 2)
    on conflict (client_id, ym)
      do update set next_val = public.client_document_seq.next_val + 1
      returning next_val - 1 into v_seq;

    -- The lowest free slot, not the counter's own value. A deleted letter
    -- releases its reference (serial_taken stopped counting deletions on
    -- 2026-09-20), and without this the automatic path still counted upward
    -- past the gap: a client whose first two letters were issued in testing
    -- and deleted started at 03 for ever. The counter is at least the number
    -- of letters issued this month, so a free slot exists at or below it
    -- unless somebody has typed references over the same range by hand; the
    -- cap covers that and refuses rather than looping.
    --
    -- Two digits is the floor, not the ceiling: the hundredth letter of a month
    -- widens to three rather than wrapping. Not lpad(): Postgres pads AND
    -- truncates to the width it is given, so lpad('100', 2, '0') is '10' and the
    -- hundredth letter would collide with the tenth.
    v_try := 1;
    loop
      v_no := 'AQL/' || cl.client_code || '/' || v_ym ||
              case when v_try < 100 then lpad(v_try::text, 2, '0') else v_try::text end;
      exit when not public.serial_taken(v_no);
      v_try := v_try + 1;
      if v_try > greatest(v_seq, 1) + 200 then
        return jsonb_build_object('error', 'no-serial');
      end if;
    end loop;
  end if;

  insert into public.client_documents
    (client_id, kind, number, issued_at, market, subtotal, tax, total,
     bill_to, lines, issued_by, client_code, idem_key)
  values
    (p_client, 'offer', v_no, (timezone('Asia/Kuala_Lumpur', now()))::date,
     coalesce(cl.market, 'MY'),
     round(coalesce(p_subtotal, 0), 2), round(coalesce(p_tax, 0), 2), round(coalesce(p_total, 0), 2),
     jsonb_build_object(
       'name', coalesce(cl.name, ''), 'legal_name', coalesce(cl.legal_name, ''),
       'address', coalesce(cl.billing_address, ''), 'regno', coalesce(cl.company_no, ''),
       'regno_old', coalesce(cl.company_no_old, ''), 'tin', coalesce(cl.tin, ''),
       'sst_no', coalesce(cl.sst_no, ''), 'sst_applies', cl.sst_applies is not false,
       'contact', coalesce(ct.name, ''), 'contact_role', coalesce(ct.role, ''),
       'phone', coalesce(ct.phone, ''), 'email', coalesce(ct.email, ''),
       'finance_email', coalesce(cl.finance_email, ''),
       'client_code', cl.client_code,
       'owner', coalesce(p_deal ->> 'owner', ''), 'source', coalesce(p_deal ->> 'source', ''),
       'industry', coalesce(p_deal ->> 'industry', ''), 'stage', coalesce(p_deal ->> 'stage', ''),
       'enquiry', coalesce(p_deal ->> 'enquiry', '')),
     v_lines, coalesce(me.name, who), cl.client_code, nullif(btrim(p_idem), ''))
  returning id into v_id;

  insert into public.client_document_services (document_id, service_id)
    select v_id, s.id from unnest(p_services) s(id)
    on conflict do nothing;

  if p_replaces is not null then
    update public.client_documents set superseded_by = v_id where id = p_replaces;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.superseded', cl.name, v_old.number || ' replaced by ' || v_no);
  end if;

  select count(*) into v_n from public.client_document_services where document_id = v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.issued', cl.name, v_no || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end);

  return jsonb_build_object('ok', true, 'id', v_id, 'number', v_no);
exception
  when unique_violation then
    -- Two presses that raced past the idempotency read: the loser reads the
    -- winner's letter back rather than making a second one.
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.client_documents
        where client_id = p_client and idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
      end if;
    end if;
    -- A typed reference two people sent at once: the loser is told the
    -- reference is spent rather than that "two letters were issued at once",
    -- which names a cause they cannot act on.
    if nullif(btrim(coalesce(p_serial, '')), '') is not null then
      return jsonb_build_object('error', 'serial-taken');
    end if;
    return jsonb_build_object('error', 'clash');
end $$;

create or replace function public.get_portal(p_client uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  cid uuid;
  cl  public.clients%rowtype;
  me  public.client_contacts%rowtype;
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select p into cid from public.portal_clients() p
    order by (p = p_client) desc nulls last limit 1;
  if cid is null then return jsonb_build_object('error', 'no-access'); end if;
  select * into cl from public.clients where id = cid;
  select * into me from public.client_contacts
    where client_id = cid and portal_access and archived_at is null and lower(email) = who
    order by is_primary desc limit 1;

  return jsonb_build_object(
    'clients', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
      from public.clients c where c.id in (select public.portal_clients())), '[]'::jsonb),
    'client', jsonb_build_object(
      'id', cl.id, 'name', cl.name, 'legal_name', cl.legal_name, 'company_no', cl.company_no,
      'billing_address', cl.billing_address, 'market', coalesce(cl.market, 'MY'),
      'sst_applies', coalesce(cl.sst_applies, true), 'stage', cl.stage, 'owner', cl.owner,
      'industry', cl.industry, 'website', cl.website, 'logo_url', cl.logo_url),
    'me', jsonb_build_object('id', me.id, 'name', me.name, 'email', me.email),
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'role', k.role, 'phone', k.phone,
        'email', k.email, 'is_primary', k.is_primary, 'portal_access', k.portal_access)
        order by k.is_primary desc, k.name)
      from public.client_contacts k where k.client_id = cid and k.archived_at is null), '[]'::jsonb),
    'services', coalesce((
      -- `term_adjust` travels with the line, because the client's page works
      -- the figure out the same way the console and the letter do and must
      -- never print a different one.
      select jsonb_agg(jsonb_build_object('id', s.id, 'label', s.label, 'unit', s.unit, 'qty', s.qty,
        'rate', s.rate, 'tenure', s.tenure, 'start_on', s.start_on, 'state', s.state, 'note', s.note,
        'term_adjust', coalesce(s.term_adjust, false), 'term_pct', s.term_pct)
        order by s.created_at)
      from public.client_services s
      where s.client_id = cid and s.archived_at is null and s.state in ('quoted', 'confirmed')), '[]'::jsonb),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'number', d.number,
        'issued_at', d.issued_at, 'market', d.market, 'subtotal', d.subtotal, 'tax', d.tax,
        'total', d.total, 'bill_to', d.bill_to, 'lines', d.lines, 'issued_by', d.issued_by)
        order by d.created_at desc)
      from public.client_documents d where d.client_id = cid and d.voided_at is null), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'service_label', r.service_label,
        'note', r.note, 'state', r.state, 'fee', r.fee, 'reply', r.reply,
        'created_at', r.created_at, 'withdrawn_at', r.withdrawn_at)
        order by r.created_at desc)
      from public.client_requests r where r.client_id = cid), '[]'::jsonb),
    'review', case
      when cl.review_hidden is not true
       and exists (select 1 from public.batches b where b.client_id = cid and b.published)
      then jsonb_build_object('token', cl.access_token) end,
    'campaigns', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'title_zh', m.title_zh,
        'state', m.state, 'deadline', m.deadline, 'token', m.access_token)
        order by m.created_at desc)
      from public.campaigns m where m.client_id = cid and m.state <> 'draft'), '[]'::jsonb),
    'access', coalesce((
      select jsonb_agg(jsonb_build_object('name', k.name, 'email', k.email) order by k.is_primary desc, k.name)
      from public.client_contacts k
      where k.client_id = cid and k.archived_at is null and k.portal_access), '[]'::jsonb)
  );
end $$;
