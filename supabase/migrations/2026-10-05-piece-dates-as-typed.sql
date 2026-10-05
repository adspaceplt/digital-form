-- ===========================================================================
-- PIECE DATES AS TYPED — every piece takes the due date typed on its row,
-- and nothing is worked out for it.
-- 2026-10-05. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two. Runs after TEMPLATE FAMILIES and PIECES AND REPEATS.
--
-- WHAT CHANGED
--   `ops_create_pieces` sends each piece's own `final_due_at` (several
--   pieces once got none) and asks `ops_create_task` to take the dates as
--   given (`dates_as_given`): no due or draft date is worked out from a
--   template's offsets, and plain pieces take no tentative publish day. Four
--   Week 1 reels added on 5 Oct came out due 29 Sept to 2 Oct; a row left
--   blank now reads Not set. A repeat still takes a tentative day to count
--   from. Every other caller of `ops_create_task` is unchanged.
--
-- ROLLBACK
--   Run the TEMPLATE FAMILIES section's ops_create_task and the PIECES AND
--   REPEATS section's ops_create_pieces again.
-- ===========================================================================

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

/* The New sheet's one act: the pieces, each through ops_create_task, and the
   repeat on every one of them, all or none. */
create or replace function public.ops_create_pieces(p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  n      integer;
  pc     jsonb;
  i      integer := 0;
  w      integer;
  k      integer;
  inweek integer;
  per    text;
  first_day date;
  last_off integer;
  spread boolean;
  base   jsonb;
  one    jsonb;
  made   jsonb := '[]'::jsonb;
  rep    jsonb;
  rule   jsonb;
  ids    uuid[] := '{}';
  gen    jsonb := '[]'::jsonb;
  pp     text;
  said   text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_payload -> 'pieces') is distinct from 'array' then
    return jsonb_build_object('error', 'bad-count');
  end if;
  n := jsonb_array_length(p_payload -> 'pieces');
  if n < 1 or n > 60 then return jsonb_build_object('error', 'bad-count'); end if;
  rep := case when jsonb_typeof(p_payload -> 'repeat') = 'object' then p_payload -> 'repeat' end;
  if rep is not null then
    if coalesce(rep ->> 'frequency', '') not in ('weekly', 'monthly', 'custom') then
      return jsonb_build_object('error', 'bad-frequency');
    end if;
    if rep ->> 'frequency' = 'custom' and coalesce((rep ->> 'interval_days')::integer, 0) < 1 then
      return jsonb_build_object('error', 'interval-required');
    end if;
  end if;

  /* What every piece shares: whose it is, what kind, who does it. A piece
     names its own description, format and week; only a sheet's one piece
     carries its own dates and brief. */
  base := jsonb_strip_nulls(jsonb_build_object(
    'scope', p_payload ->> 'scope', 'client_id', p_payload ->> 'client_id',
    'engagement_id', p_payload ->> 'engagement_id',
    'code_period', p_payload ->> 'code_period',
    'task_type', p_payload ->> 'task_type',
    'owner_id', p_payload ->> 'owner_id',
    'priority_level', p_payload -> 'priority_level',
    'complexity', p_payload ->> 'complexity',
    'description', case when n = 1 then p_payload ->> 'description' end));
  per := p_payload ->> 'code_period';
  if per ~ '^\d{4}-\d{2}$' and coalesce(p_payload ->> 'scope', 'client') <> 'internal' then
    first_day := (per || '-01')::date;
    last_off := ((first_day + interval '1 month')::date - first_day) - 1;
  end if;
  /* Only a repeat needs a day to count from; plain pieces take the dates
     typed on their rows and nothing else. */
  spread := first_day is not null and rep is not null;
  base := base || jsonb_build_object('dates_as_given', true);

  begin
    for pc in select x from jsonb_array_elements(p_payload -> 'pieces') x loop
      i := i + 1;
      w := least(5, greatest(1, coalesce((pc ->> 'code_week')::integer, 1)));
      one := base || jsonb_strip_nulls(jsonb_build_object(
        'content_desc', nullif(btrim(coalesce(pc ->> 'content_desc', '')), ''),
        'deliverable_type', nullif(pc ->> 'deliverable_type', ''),
        'code_week', case when first_day is not null then w end));
      /* Every piece carries the due date typed on its row; a sheet's one
         piece carries its draft and publish dates too. */
      one := one || jsonb_strip_nulls(jsonb_build_object(
        'final_due_at', nullif(pc ->> 'final_due_at', '')));
      if n = 1 then
        one := one || jsonb_strip_nulls(jsonb_build_object(
          'publish_at', nullif(pc ->> 'publish_at', ''),
          'first_draft_due_at', nullif(pc ->> 'first_draft_due_at', '')));
      end if;
      /* A tentative day inside the piece's week, the week's pieces spread
         across its seven days, so the calendar has somewhere to put each one
         and a repeat a day to count from; the content meeting fixes the real
         date. Never past the month's last day, which only week 5 reaches. */
      if spread and not (one ? 'publish_at') then
        select count(*) filter (where least(5, greatest(1, coalesce((y ->> 'code_week')::integer, 1))) = w),
               count(*) filter (where least(5, greatest(1, coalesce((y ->> 'code_week')::integer, 1))) = w and o < i)
          into inweek, k
          from jsonb_array_elements(p_payload -> 'pieces') with ordinality as a(y, o);
        one := one || jsonb_build_object('publish_at',
          (first_day + least((w - 1) * 7 + (k * 7) / greatest(inweek, 1), last_off))::timestamptz);
      end if;
      one := public.ops_create_task(one, case when p_idem is null then null else p_idem || ':' || i end);
      if one ? 'error' then raise exception using message = one::text; end if;
      made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'title', one ->> 'title');
      ids := ids || (one ->> 'id')::uuid;
      if rep is not null then
        rule := public.ops_set_recurring((one ->> 'id')::uuid, jsonb_strip_nulls(jsonb_build_object(
          'frequency', rep ->> 'frequency',
          'interval_days', case when rep ->> 'frequency' = 'custom' then rep -> 'interval_days' end,
          'ends_on', nullif(rep ->> 'ends_on', ''),
          'max_count', rep -> 'max_count')));
        if rule ? 'error' then raise exception using message = rule::text; end if;
      end if;
    end loop;
  exception when raise_exception then
    /* A refusal part way leaves nothing behind: the block's writes are
       undone and the refusal is answered as it was given. */
    said := sqlerrm;
    begin
      return said::jsonb;
    exception when others then
      return jsonb_build_object('error', said);
    end;
  end;

  /* What the new rules already owe is made now rather than tomorrow morning. */
  if rep is not null then
    foreach pp in array public.ops_recurring_periods() loop
      gen := gen || public.ops_generate_recurring(pp,
        array(select r.id from public.ops_recurring_rules r where r.active and r.source_task_id = any (ids)));
    end loop;
  end if;
  return jsonb_build_object('count', n, 'tasks', made, 'repeats', gen);
end $$;
grant execute on function public.ops_create_pieces(jsonb, text) to authenticated;

-- END OF PIECE DATES AS TYPED ------------------------------------------------
