-- ===========================================================================
-- TEMPLATE FAMILIES — a deliverable's format fills the task from its family.
-- 2026-09-28. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-09-28: "When creating Reels up to 30s / 60s
-- it should then come out using the Reels template already right. Else I'd
-- be doing double triple works"; then "Each must be unique unless u make it
-- like product variants, the variants is the hours ... checklist its the
-- same for Reels ... same goes to Graphics (Static, GIF, Carousel)"):
--   1. `ops_template_variants`: a format (the rate card's key: reels_30,
--      static, …) belongs to one template, its family, with the hours that
--      variant takes. A format is unique across every family.
--   2. `ops_create_task`: with no template named, the family owning the
--      chosen format fills the task: its checklist, complexity, draft and
--      final offsets and owner, and the variant's hours. The task stays on
--      the workflow the caller asked for (a content deliverable is never
--      moved to the everyday workflow by its family), and a family's "due N
--      days after" is not used: a deliverable's dates come from its month.
--      New task, Bulk add and repeats all create through this function.
--   3. `ops_save_template` takes `variants` ([{format, estimate_minutes}])
--      and replaces the family's set; a format another family holds is
--      refused (`format-taken`, naming the family).
--   4. First run only (while no variant exists), the team's templates become
--      families as agreed: Reel → Reels (30s 3h, 60s 4h, 120s 5h), Static
--      post → Graphics (Static 1h, GIF 2h, Carousel 2h; the export line
--      names the FB and IG sizes), Report (1h). Short video and Carousel,
--      now variants of those families, are set inactive; nothing is deleted.
--
-- ROLLBACK
--   Re-run ops_create_task from EVERY TASK IN A CONFIRMED MONTH and
--   ops_save_template from its section, then
--   drop table if exists public.ops_template_variants;
-- ===========================================================================

create table if not exists public.ops_template_variants (
  id               uuid primary key default gen_random_uuid(),
  template_id      uuid not null references public.ops_task_templates(id) on delete cascade,
  format           text not null unique,
  estimate_minutes integer check (estimate_minutes is null or estimate_minutes between 1 and 6000),
  created_at       timestamptz not null default now()
);
alter table public.ops_template_variants enable row level security;
drop policy if exists ops_template_variants_read on public.ops_template_variants;
create policy ops_template_variants_read on public.ops_template_variants
  for select to authenticated using (public.allowed('ops', 'view'));

create or replace function public.ops_create_task(p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  tpl   public.ops_task_templates;
  fam   public.ops_template_variants;
  byfmt boolean := false;
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
  cper  text;
  week  integer;
  seq   integer;
  code  text;
  title text;
  first_stage text;
  wkey  text;
  base  timestamptz;
  eng   public.ops_engagements;
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
  /* A task linked to a month's engagement takes the client from it: the
     person names the month once and the client comes with it. */
  if (p_payload ->> 'engagement_id') is not null then
    select * into eng from public.ops_engagements where id = (p_payload ->> 'engagement_id')::uuid;
    if eng.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if cid is null then cid := eng.client_id; scope := 'client'; end if;
  end if;
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
    descr := coalesce(descr, nullif(btrim(coalesce(tpl.default_title, tpl.name, '')), ''));
  end if;
  /* No template named: the family that owns the chosen format fills the task
     (its checklist, complexity, draft and final offsets, owner) and the
     format's own variant its hours (TEMPLATE FAMILIES, 2026-09-28). */
  if tpl.id is null and nullif(p_payload ->> 'deliverable_type', '') is not null then
    select v.* into fam from public.ops_template_variants v
      join public.ops_task_templates t on t.id = v.template_id and t.active
     where v.format = p_payload ->> 'deliverable_type';
    if fam.id is not null then
      select * into tpl from public.ops_task_templates where id = fam.template_id;
      byfmt := true;
    end if;
  end if;
  /* New work goes on the content workflow. A caller may still name another
     (a template's own, or one somebody adds), and a task already on a retired
     workflow is never moved. */
  wf := coalesce((p_payload ->> 'workflow_id')::uuid,
                 (select id from public.ops_workflows where key = p_payload ->> 'workflow_key' and active),
                 case when byfmt then null else tpl.workflow_id end,
                 (select id from public.ops_workflows where key = 'content' and active),
                 (select id from public.ops_workflows where active order by created_at limit 1));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  select key into first_stage from public.ops_workflow_stages
   where workflow_id = wf order by position limit 1;
  select key into wkey from public.ops_workflows where id = wf;

  publish := (p_payload ->> 'publish_at')::timestamptz;
  fd := coalesce((p_payload ->> 'first_draft_due_at')::timestamptz,
        case when publish is not null and tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.first_draft_offset_business_days)
             when tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.first_draft_offset_business_days)
        end);
  /* A template's due date is a number of calendar days from the day the
     work is made for (the base date the caller names, else today). */
  base := coalesce((p_payload ->> 'base_date')::timestamptz, now());
  fin := coalesce((p_payload ->> 'final_due_at')::timestamptz,
        case when tpl.due_offset_days is not null and not byfmt
             then date_trunc('day', base) + make_interval(days => tpl.due_offset_days)
             when publish is not null and tpl.final_offset_business_days is not null
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
  if wkey = 'task' then
    /* An everyday task is named by what it is. It carries no content code,
       because the code numbers a client's deliverables for the month and a
       task is not one; the content month is kept where it is known, so the
       task can be grouped with the month it belongs to. */
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
    period := coalesce(nullif(p_payload ->> 'code_period', ''), eng.period);
  elsif scope <> 'internal' then
    period := coalesce(nullif(p_payload ->> 'code_period', ''),
                       case when publish is not null then to_char(publish, 'YYYY-MM') end,
                       to_char(now(), 'YYYY-MM'));
    if period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
    /* A client's deliverable belongs to a month the team has planned: one
       that exists, is still open, and has its content meeting set or marked
       not applicable. The same three refusals Bulk add gives. */
    if scope = 'client' then
      cper := period;
      if eng.id is null or eng.period <> cper then
        select * into eng from public.ops_engagements x where x.client_id = cid and x.period = cper;
      end if;
      if eng.id is null then return jsonb_build_object('error', 'no-month'); end if;
      if eng.status in ('completed', 'cancelled') then return jsonb_build_object('error', 'month-closed'); end if;
      if eng.meeting_at is null and not eng.meeting_na then
        return jsonb_build_object('error', 'month-not-confirmed');
      end if;
    end if;
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
    coalesce((p_payload ->> 'estimate_minutes')::integer, fam.estimate_minutes, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'),
    ttype, code, period, week, seq, descr,
    coalesce(eng.id, (p_payload ->> 'engagement_id')::uuid),
    coalesce((p_payload ->> 'manager_id')::uuid, m.id),
    (p_payload ->> 'parent_task_id')::uuid)
  returning id into tid;

  /* Every task has an owner from the moment it exists: the one named, the
     template's, or else whoever made it. */
  owner := coalesce((p_payload ->> 'owner_id')::uuid, tpl.default_owner_id, m.id);
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

create or replace function public.ops_save_template(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m    public.team_members;
  nm   text;
  wf   uuid;
  tid  uuid;
  other text;
  fmt  text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('ops.workflows', 'work') then return jsonb_build_object('error', 'denied'); end if;
  nm := nullif(btrim(coalesce(p_payload ->> 'name', '')), '');
  if nm is null then return jsonb_build_object('error', 'name-required'); end if;
  if exists (select 1 from public.ops_task_templates
              where lower(name) = lower(nm) and id is distinct from p_id) then
    return jsonb_build_object('error', 'name-taken');
  end if;
  /* The formats this family serves, when the page sends them: each format
     belongs to one family, so a format another holds is refused by name. */
  if jsonb_typeof(p_payload -> 'variants') = 'array' then
    for fmt in select v ->> 'format' from jsonb_array_elements(p_payload -> 'variants') v loop
      if fmt is null or fmt !~ '^[a-z0-9_]{1,40}$' then return jsonb_build_object('error', 'bad-format'); end if;
    end loop;
    if (select count(*) from jsonb_array_elements(p_payload -> 'variants'))
       <> (select count(distinct v ->> 'format') from jsonb_array_elements(p_payload -> 'variants') v) then
      return jsonb_build_object('error', 'bad-format');
    end if;
    select t.name into other from public.ops_template_variants x
      join public.ops_task_templates t on t.id = x.template_id
     where x.template_id is distinct from p_id
       and x.format in (select v ->> 'format' from jsonb_array_elements(p_payload -> 'variants') v)
     limit 1;
    if other is not null then return jsonb_build_object('error', 'format-taken', 'family', other); end if;
  end if;
  wf := coalesce((select id from public.ops_workflows where key = coalesce(p_payload ->> 'workflow_key', 'task')),
                 (select id from public.ops_workflows where key = 'task'));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  if p_id is null then
    insert into public.ops_task_templates (name, deliverable_type, workflow_id, default_title,
      default_owner_id, due_offset_days, default_estimate_minutes, checklist, active)
    values (nm, coalesce(nullif(p_payload ->> 'deliverable_type', ''), 'other'), wf,
      nullif(btrim(coalesce(p_payload ->> 'default_title', '')), ''),
      (p_payload ->> 'default_owner_id')::uuid,
      (p_payload ->> 'due_offset_days')::integer,
      (p_payload ->> 'default_estimate_minutes')::integer,
      coalesce(p_payload -> 'checklist', '[]'::jsonb),
      coalesce((p_payload ->> 'active')::boolean, true))
    returning id into tid;
  else
    update public.ops_task_templates set
      name = nm,
      deliverable_type = coalesce(nullif(p_payload ->> 'deliverable_type', ''), deliverable_type),
      workflow_id = wf,
      default_title = nullif(btrim(coalesce(p_payload ->> 'default_title', '')), ''),
      default_owner_id = (p_payload ->> 'default_owner_id')::uuid,
      due_offset_days = (p_payload ->> 'due_offset_days')::integer,
      default_estimate_minutes = (p_payload ->> 'default_estimate_minutes')::integer,
      checklist = coalesce(p_payload -> 'checklist', '[]'::jsonb),
      active = coalesce((p_payload ->> 'active')::boolean, active),
      updated_at = now()
    where id = p_id
    returning id into tid;
    if tid is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if jsonb_typeof(p_payload -> 'variants') = 'array' then
    delete from public.ops_template_variants v where v.template_id = tid;
    insert into public.ops_template_variants (template_id, format, estimate_minutes)
    select tid, v ->> 'format', nullif(v ->> 'estimate_minutes', '')::integer
      from jsonb_array_elements(p_payload -> 'variants') v;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('variants', coalesce((
            select jsonb_agg(jsonb_build_object('format', v.format, 'estimate_minutes', v.estimate_minutes) order by v.format)
              from public.ops_template_variants v where v.template_id = x.id), '[]'::jsonb))
            from public.ops_task_templates x where x.id = tid);
end $$;
grant execute on function public.ops_save_template(uuid, jsonb) to authenticated;

-- The team's templates as families, once.
do $$
declare reels uuid; graphics uuid; rep uuid;
begin
  if exists (select 1 from public.ops_template_variants) then return; end if;
  select id into reels from public.ops_task_templates where lower(name) in ('reels', 'reel')
   order by (lower(name) = 'reels') desc limit 1;
  select id into graphics from public.ops_task_templates where lower(name) in ('graphics', 'static post')
   order by (lower(name) = 'graphics') desc limit 1;
  select id into rep from public.ops_task_templates where lower(name) = 'report' limit 1;
  if reels is not null then
    update public.ops_task_templates set name = 'Reels', updated_at = now()
     where id = reels and name = 'Reel'
       and not exists (select 1 from public.ops_task_templates where lower(name) = 'reels');
    insert into public.ops_template_variants (template_id, format, estimate_minutes)
    values (reels, 'reels_30', 180), (reels, 'reels_60', 240), (reels, 'reels_120', 300)
    on conflict (format) do nothing;
    update public.ops_task_templates set active = false, updated_at = now()
     where name = 'Short video' and active;
  end if;
  if graphics is not null then
    update public.ops_task_templates
       set name = 'Graphics',
           checklist = '["Proof-read", "Exported in 1080 * 1080 & 1350 * 1080 (FB+IG sizes)", "Working files saved to [Internal] folder"]'::jsonb,
           updated_at = now()
     where id = graphics and name = 'Static post'
       and not exists (select 1 from public.ops_task_templates where lower(name) = 'graphics');
    insert into public.ops_template_variants (template_id, format, estimate_minutes)
    values (graphics, 'static', 60), (graphics, 'gif', 120), (graphics, 'carousel', 120)
    on conflict (format) do nothing;
    update public.ops_task_templates set active = false, updated_at = now()
     where name = 'Carousel' and active;
  end if;
  if rep is not null then
    insert into public.ops_template_variants (template_id, format, estimate_minutes)
    values (rep, 'report', 60) on conflict (format) do nothing;
  end if;
end $$;

-- END OF TEMPLATE FAMILIES --------------------------------------------------
