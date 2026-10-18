-- ===========================================================================
-- DAYS ON MALAYSIA'S CALENDAR — the three functions that still read a moment on
-- the UTC calendar take Malaysia's day. 2026-10-18. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the logged defects of 2026-10-17, found by the widened
--   Malaysia time guard in tests/sql.js)
--   ops_create_task: a template's due offset counted from the UTC day of
--   now() (no page names a base date), so a task made before 8am MYT was
--   due a day early. It counts from Malaysia's day, held as a stored day
--   (midnight UTC), as before.
--   ops_generate_recurring: a rule whose task has no post date anchored on
--   the UTC day its rule was made, and skipped dates up to that day, so a
--   rule set before 8am MYT ran a day off. Both read Malaysia's day.
--   perf_self_open: the month a colleague joined was the UTC month, so one
--   added before 8am MYT on the 1st could rate the month before. It is
--   Malaysia's month.
--
-- ROLLBACK
--   Run ops_generate_recurring again from PIECES AND REPEATS,
--   ops_create_task from MALAYSIA TIME IN THE DATABASE (2026-10-17) and
--   perf_self_open from PERFORMANCE SELF-RATING (2026-10-07).
-- ===========================================================================

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
  held  integer := 0;
  ccl   uuid;
  mon   public.ops_engagements;
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

    /* A client's repeats wait for the client's month: one that exists, is
       open and has its content meeting set or marked not applicable. Until
       then the rule is held and counted, and a later run makes them. */
    ccl := case when src.id is not null then case when src.scope = 'client' then src.client_id end
                else r.client_id end;
    mon := null;
    if ccl is not null then
      select * into mon from public.ops_engagements x where x.client_id = ccl and x.period = p_period;
      if mon.id is null or mon.status in ('completed', 'cancelled')
         or (mon.meeting_at is null and not mon.meeting_na) then
        held := held + 1;
        continue;
      end if;
    end if;

    /* The dates this rule falls on inside the month. */
    if r.frequency = 'monthly' then
      d := first_day + (least(coalesce(r.day_of_month,
              case when src.publish_at is not null then extract(day from src.publish_at)::integer else 1 end),
              extract(day from last_day)::integer) - 1);
      stepd := null;
    else
      stepd := case when r.frequency = 'weekly' then 7 else greatest(1, coalesce(r.interval_days, 7)) end;
      anchor := coalesce(src.publish_at::date, (r.created_at at time zone 'Asia/Kuala_Lumpur')::date, first_day);
      if anchor > first_day then d := anchor;
      else d := anchor + ((((first_day - anchor) + stepd - 1) / stepd) * stepd); end if;
    end if;

    while d is not null and d <= last_day loop
      if d >= first_day
         /* The task a rule copies is its first occurrence: nothing on or
            before its day is made again. */
         and (src.id is null or d > coalesce(src.publish_at::date, (r.created_at at time zone 'Asia/Kuala_Lumpur')::date))
         and (r.ends_on is null or d <= r.ends_on)
         and (r.max_count is null or r.generated_count < r.max_count) then
        key := 'recur:' || r.id::text || ':' || to_char(d, 'YYYY-MM-DD');
        /* Made once is made: a copy since deleted stays deleted, and a rule
           set again on the same task makes none of its dates twice. */
        if exists (select 1 from public.ops_tasks where idem_key = key)
           or exists (select 1 from public.ops_recurring_made x
                       where x.on_date = d
                         and (x.rule_id = r.id
                              or (r.source_task_id is not null and x.source_task_id = r.source_task_id))) then
          skip := skip + 1;
        else
          wk := coalesce(r.code_week, least(5, ((extract(day from d)::integer - 1) / 7) + 1));
          if src.id is not null then
            one := public.ops_duplicate_task(src.id, jsonb_build_object(
              'keep_desc', true, 'copy_dates', false, 'copy_assignees', true,
              'publish_at', d::timestamptz, 'code_period', p_period, 'code_week', wk,
              'engagement_id', mon.id), key);
          else
            one := public.ops_create_task(jsonb_build_object(
              'scope', case when r.client_id is null then 'internal' else 'client' end,
              'client_id', r.client_id, 'template_id', r.template_id,
              'title', r.name || ' — ' || p_period, 'content_desc', r.name,
              'owner_id', r.owner_id, 'publish_at', d::timestamptz,
              'code_period', p_period, 'code_week', wk, 'engagement_id', mon.id), key);
          end if;
          if one ? 'error' then return one || jsonb_build_object('rule', r.id); end if;
          made := made + 1;
          insert into public.ops_recurring_made (rule_id, source_task_id, on_date)
          values (r.id, r.source_task_id, d) on conflict do nothing;
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
  return jsonb_build_object('created', made, 'skipped', skip, 'held', held, 'period', p_period);
end $$;
grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;

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
             then ((base at time zone 'Asia/Kuala_Lumpur')::date + tpl.due_offset_days)::timestamp at time zone 'UTC'
             when publish is not null and tpl.final_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.final_offset_business_days)
             when tpl.final_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.final_offset_business_days)
        end);
  /* Dates a person typed stand as typed, and a date left blank stays blank:
     nothing is worked out from a template's offsets (the user, 2026-10-05). */
  if coalesce((p_payload ->> 'dates_as_given')::boolean, false) then
    fd := (p_payload ->> 'first_draft_due_at')::timestamptz;
    fin := (p_payload ->> 'final_due_at')::timestamptz;
  end if;
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
                       to_char((now() at time zone 'Asia/Kuala_Lumpur')::date, 'YYYY-MM'));
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

create or replace function public.perf_self_open(p_member uuid, p_period date)
returns text
language sql stable security definer set search_path = public as $$
  select case
    when p_period is null or extract(day from p_period) <> 1 or p_period < date '2026-06-01'
      or p_period >= date_trunc('month', public.perf_today())::date
      then 'bad-month'
    when exists (select 1 from public.perf_reviews r
                  where r.team_member_id = p_member and r.period = p_period and r.status <> 'draft')
      then 'shared'
    when not exists (select 1 from public.perf_reviews r
                      where r.team_member_id = p_member and r.period = p_period)
     and (not coalesce(public.perf_reviewed(p_member), false)
          or p_period < (select date_trunc('month', t.created_at at time zone 'Asia/Kuala_Lumpur')::date
                           from public.team_members t where t.id = p_member))
      then 'not-reviewed'
  end
$$;
revoke all on function public.perf_self_open(uuid, date) from public, anon, authenticated;

-- END OF DAYS ON MALAYSIA'S CALENDAR ----------------------------------------

select public.functions_tidy();
