-- ===========================================================================
-- AUDIT FIXES, THIRD BATCH (2026-11-15)
-- ===========================================================================
-- WHY: the whole-portal audit of 2026-11-15 (the user approved every fix).
--
-- WHAT IT CHANGES
--   * `ops_report_of`: On time counts a task's first entry into client review
--     alone; a return after a revision was counted again, late, in its own
--     period. (`perf_ops_rate` already reads the first entry.)
--   * `ops_create_task`, `video_script_new`: the key a press sends is locked
--     before it is looked up, so two presses at once make one row.
--   * `quote_sign_code`: ten codes an hour from one address across every
--     quotation, beside five an hour a quotation (`too-many`); the address
--     (`quote_sign_codes.caller_ip`, from `request_ip()`, which quote-request
--     relays) is let go after an hour, at the next request.
--   * `demo_set`: a new demo PIN is 6 to 8 digits; one held before keeps
--     opening.
--   * Trigger `campaign_options_approval_gate`: a booking reaches Scheduled
--     from Submitted, Client review or Changes requested only on a live
--     approval (its latest decision not taken back is `approved`), refused
--     `needs-approval`; a move back from Posted or Completed is untouched.
--
-- ORDER: the pages (they say the refusals in words), this file, then
-- quote-request (it relays the caller's address; until then every code is
-- counted against no address and only the five a quotation hold).
-- Safe to run twice.
--
-- ROLLBACK: run the five functions' previous definitions from schema.sql at
-- the commit before this file, then:
-- drop trigger campaign_options_approval_gate on public.campaign_options;
-- drop function public.campaign_options_approval_gate();
-- (the caller_ip column and its index may stay; nothing else reads them)
-- ===========================================================================

-- AUDIT FIXES, THIRD BATCH ----------------------------------------------------

alter table public.quote_sign_codes add column if not exists caller_ip text;
create index if not exists quote_sign_codes_caller_idx on public.quote_sign_codes (caller_ip, created_at desc)
  where caller_ip is not null;

create or replace function public.ops_report_of(
  p_from  timestamptz,
  p_to    timestamptz,
  p_light boolean)
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
  /* Where a priority's deadline is met (2026-10-11): client review, else the
     workflow's first review (an everyday task's Review). */
  pfloors as (
    select workflow_id,
           coalesce(min(position) filter (where stage_group = 'client_review'),
                    min(position) filter (where stage_group = 'internal_review')) as at
      from public.ops_workflow_stages
     group by workflow_id
  ),
  live as (
    select t.*, s.label as stage_label, s.position as stage_position,
           s.stage_group, f.at as review_at,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by, pf.at as prio_at
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.workflow_id = t.workflow_id and s.key = t.stage_key
      left join floors f on f.workflow_id = t.workflow_id
      left join pfloors pf on pf.workflow_id = t.workflow_id
     where t.completed_at is null and t.cancelled_at is null
       and t.archived_at is null
       /* Client scope: a colleague on Own clients only reads the work of
          the clients they hold, and their own tasks always (2026-10-18). */
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
       where not p_light
       group by stage_key, stage_label, stage_position, stage_group
    ) q
  ),

  /* 2. WHAT IS LATE. Past the commitment and still short of client review,
        or past a priority's deadline and short of its review (On hold and
        Blocked still count): whichever comes first (the user, 2026-10-11).
        The same rule the queue row draws, stated once more here because a
        report a page computes for itself is a second definition. */
  late_now as (
    select l.*,
           (l.current_final_due_at is not null and (l.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date
            and (l.review_at is null or l.stage_position < l.review_at)) as due_late,
           (l.prio_by is not null and l.prio_by < now()
            and (l.prio_at is null or l.stage_position < l.prio_at or l.stage_group in ('kiv', 'blocked'))) as prio_late
      from live l
  ),
  late as (
    select jsonb_agg(x order by x ->> 'due_at') as j from (
      select jsonb_build_object(
               'task_id', l.id, 'task_no', l.task_no, 'title', l.title,
               'client', c.name, 'stage', l.stage_label,
               'due_at', case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                              then l.prio_by else l.current_final_due_at end,
               'days_over', greatest(case when l.due_late then (now() at time zone 'Asia/Kuala_Lumpur')::date - (l.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date end,
                                     case when l.prio_late then floor(extract(epoch from (now() - l.prio_by)) / 86400)::int end),
               'over_minutes', case when l.prio_late then floor(extract(epoch from (now() - l.prio_by)) / 60)::int end,
               'owner', (select tm.name
                           from public.ops_task_assignees a
                           join public.team_members tm on tm.id = a.team_member_id
                          where a.task_id = l.id and a.responsibility = 'owner'
                            and a.ended_at is null
                          limit 1)) as x
        from late_now l
        left join public.clients c on c.id = l.client_id
       where (l.due_late or l.prio_late) and not p_light
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
       and public.ops_task_in_scope(t.id)
       /* Only a span entered in the period is counted, and its end is the
          task's next event, never an earlier one: what came before the
          period is not read (2026-10-18). */
       and e.created_at >= p_from
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
       where not p_light
       group by stage_key
    ) q
  ),

  /* 4. WAS IT THERE ON TIME. Of the tasks that reached client review inside
        the period, how many got there on or before the date they were owed;
        the work still late is counted beside them (`late_open`).
        Replanning is counted beside it and never folded into it: an extension
        that moves the date would otherwise erase the miss it was granted for,
        and a rate that cannot be missed is not a measurement. */
  /* A task's FIRST entry into client review ever, counted in the period it
     fell in: its return after a revision is never counted again, in its own
     period or a later one (audit 2026-11-15). */
  reached as (
    select f.* from (
      select distinct on (e.task_id)
             e.task_id, e.created_at as at, t.current_final_due_at as due,
             public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
             (t.original_final_due_at is distinct from t.current_final_due_at) as replanned
        from public.ops_task_events e
        join public.ops_tasks t on t.id = e.task_id
        join public.ops_workflow_stages w
          on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
       where e.event_type = 'stage_changed'
         and w.stage_group = 'client_review'
         and public.ops_task_in_scope(t.id)
         and e.created_at < p_to
       order by e.task_id, e.created_at
    ) f
     where f.at >= p_from
  ),
  /* Work still short of its review and past its deadline is a miss too
     (2026-10-19, the user: "there are late tasks yet showing 100% on time
     delivery"): counted in the period its first missed deadline fell in,
     and in any period that runs to now (its end within ten minutes of now:
     the page names the moment it asks), where it is still late. A task
     counted as reached in the period is not counted again. */
  late_open as (
    select l.id
      from late_now l
     where (l.due_late or l.prio_late)
       and not exists (select 1 from reached r where r.task_id = l.id)
       and (case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                 then l.prio_by else l.current_final_due_at end) < p_to
       and ((case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                  then l.prio_by else l.current_final_due_at end) >= p_from
            or p_to >= now() - interval '10 minutes')
  ),
  on_time as (
    select jsonb_build_object(
             'reached', count(*),
             'met', count(*) filter (where (due is null or (at at time zone 'Asia/Kuala_Lumpur')::date <= (due at time zone 'Asia/Kuala_Lumpur')::date)
                                       and (prio_by is null or at <= prio_by)),
             'missed', count(*) filter (where not ((due is null or (at at time zone 'Asia/Kuala_Lumpur')::date <= (due at time zone 'Asia/Kuala_Lumpur')::date)
                                                 and (prio_by is null or at <= prio_by))),
             'late_open', (select count(*) from late_open),
             'replanned', count(*) filter (where replanned)) as j
      from reached
  ),
  /* 4b. POSTED ON TIME (2026-10-19). Of the content whose post date fell in
         the period and has passed (Malaysia's day), or which went live, how
         much went live by its post date. Client approval counts here, as it
         does for the client; on-time delivery above is the team's own. */
  posted as (
    select jsonb_build_object(
             'due', count(*),
             'met', count(*) filter (where t.live_at is not null
                                       and (t.live_at at time zone 'Asia/Kuala_Lumpur')::date
                                           <= (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date)) as j
      from public.ops_tasks t
     where t.publish_at >= p_from and t.publish_at < p_to
       and t.cancelled_at is null and t.archived_at is null
       and (t.live_at is not null
            or (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date)
       and exists (select 1 from public.ops_workflow_stages s
                    where s.workflow_id = t.workflow_id and s.stage_group = 'live')
       and public.ops_task_in_scope(t.id)
  ),

  /* 5. BY PERSON. The foundation of a KPI and not a KPI: what somebody
        finished in the window, how much of it was on time, and how long their
        work took end to end. No ranking and no score — a number a person can
        check is worth more than a league table nobody trusts. */
  done as (
    select t.id, t.created_at, t.completed_at as ended,
           t.current_final_due_at as due,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
           /* When a priority's deadline was met: the first move into its
              review or beyond (never On hold, Blocked or Cancelled). */
           (select min(e.created_at)
              from public.ops_task_events e
              join public.ops_workflow_stages w
                on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
              join pfloors pf on pf.workflow_id = t.workflow_id
             where e.task_id = t.id and e.event_type = 'stage_changed'
               and w.position >= pf.at and w.stage_group not in ('kiv', 'blocked', 'cancelled')) as met_at,
           /* When it reached client review (2026-10-22, OVW-2): the day the
              due date is owed at, as the on-time ring reads it. */
           (select min(e.created_at)
              from public.ops_task_events e
              join public.ops_workflow_stages w
                on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
             where e.task_id = t.id and e.event_type = 'stage_changed'
               and w.stage_group = 'client_review') as review_at,
           (select a.team_member_id
              from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc
             limit 1) as owner_id
      from public.ops_tasks t
     where t.completed_at is not null
       and t.completed_at >= p_from and t.completed_at < p_to
       and public.ops_task_in_scope(t.id)
  ),
  by_person as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', d.owner_id,
               'name', coalesce(tm.name, 'Nobody'),
               'completed', count(*),
               'on_time', count(*) filter (where (d.due is null
                                                 or (coalesce(d.review_at, d.met_at, d.ended) at time zone 'Asia/Kuala_Lumpur')::date
                                                    <= (d.due at time zone 'Asia/Kuala_Lumpur')::date)
                                         and (d.prio_by is null or coalesce(d.met_at, d.ended) <= d.prio_by)),
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
                     (l.due_late or l.prio_late) as is_late
                from late_now l) o
        left join public.team_members tm on tm.id = o.owner_id
       where public.ops_granted('ops.all', 'view') and not p_light
       group by o.owner_id, tm.name
    ) q
  )

  select jsonb_build_object(
           'from', p_from, 'to', p_to,
           'running',    coalesce((select j from running), '[]'::jsonb),
           'late',       coalesce((select j from late), '[]'::jsonb),
           'stage_time', coalesce((select j from stage_time), '[]'::jsonb),
           'on_time',    coalesce((select j from on_time), '{}'::jsonb),
           'posted',     coalesce((select j from posted), '{}'::jsonb),
           'by_person',  coalesce((select j from by_person), '[]'::jsonb),
           'open_by_person', case when public.ops_granted('ops.all', 'view')
                                  then coalesce((select j from open_by_person), '[]'::jsonb) end)
    into out;

  return out;
end $$;
revoke all on function public.ops_report_of(timestamptz, timestamptz, boolean) from public, anon;
grant execute on function public.ops_report_of(timestamptz, timestamptz, boolean) to authenticated;

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

  -- The same press twice is one task, two presses at once included: the
  -- key's lock is taken before it is looked up (audit 2026-11-15).
  if p_idem is not null then
    perform pg_advisory_xact_lock(hashtext('ops_create_task:' || p_idem));
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

create or replace function public.video_script_new(p_client uuid, p_period text, p_kind text default null,
                                                   p_from uuid default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  f      public.video_scripts;
  v_cl   public.clients;
  v_kind text;
  v_per  text;
  v_seq  integer;
  v_eng  uuid;
  v_id   uuid;
  v_new  public.video_scripts;
begin
  if me.id is null or not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if nullif(btrim(coalesce(p_idem, '')), '') is not null then
    -- Two presses at once are one script: the key's lock first (audit 2026-11-15).
    perform pg_advisory_xact_lock(hashtext('video_script_new:' || p_idem));
    select s.id into v_id from public.video_scripts s where s.idem_key = p_idem;
    if v_id is not null then return jsonb_build_object('ok', true, 'id', v_id, 'again', true); end if;
  end if;
  if p_from is not null then
    select * into f from public.video_scripts s where s.id = p_from;
    if f.id is null or (p_client is not null and p_client <> f.client_id) then
      return jsonb_build_object('error', 'not-found');
    end if;
  end if;
  select * into v_cl from public.clients c where c.id = coalesce(f.client_id, p_client);
  if v_cl.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(v_cl.id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  v_per := coalesce(nullif(btrim(coalesce(p_period, '')), ''), f.period);
  if v_per is null or v_per !~ '^\d{4}-(0[1-9]|1[0-2])$' or v_per not between '2023-08' and '2099-12' then
    return jsonb_build_object('error', 'bad-period');
  end if;
  v_kind := coalesce(nullif(btrim(coalesce(p_kind, '')), ''), f.kind, 'scenes');
  if v_kind not in ('scenes', 'products', 'story') then return jsonb_build_object('error', 'bad-kind'); end if;
  perform pg_advisory_xact_lock(hashtext('video_script:' || v_cl.id::text || ':' || v_per));
  select min(g) into v_seq from generate_series(1, 99) g
   where not exists (select 1 from public.video_scripts s where s.client_id = v_cl.id and s.period = v_per and s.seq = g);
  if v_seq is null then return jsonb_build_object('error', 'too-many'); end if;
  select e.id into v_eng from public.ops_engagements e where e.client_id = v_cl.id and e.period = v_per limit 1;
  insert into public.video_scripts (client_id, period, seq, engagement_id, kind, platform, language, shoot_on,
                                    shoot_time, venue, duration_minutes, cast_names, aspect, length_seconds, brief,
                                    idem_key, created_by, created_by_name, updated_by_name)
  values (v_cl.id, v_per, v_seq, v_eng, v_kind, f.platform, f.language, f.shoot_on, f.shoot_time, f.venue,
          f.duration_minutes, f.cast_names, f.aspect, f.length_seconds, coalesce(f.brief, '{}'::jsonb),
          nullif(btrim(coalesce(p_idem, '')), ''), me.id, me.name, me.name)
  returning * into v_new;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.created', v_cl.name,
          public.video_script_label(v_new) || ' · '
          || case v_kind when 'scenes' then 'Detailed scenes' when 'products' then 'Products and scenes'
                         else 'Story and voice-over' end
          || case when f.id is not null then ' · header from ' || f.code else '' end);
  return jsonb_build_object('ok', true, 'id', v_new.id, 'code', v_new.code, 'period', v_per, 'seq', v_seq);
end $$;
revoke all on function public.video_script_new(uuid, text, text, uuid, text) from public, anon;
grant execute on function public.video_script_new(uuid, text, text, uuid, text) to authenticated;

create or replace function public.quote_sign_code(p_key text, p_payload jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  o   jsonb := public.quote_sign_open(p_key);
  q   public.quotations;
  pl  jsonb := coalesce(p_payload, '{}'::jsonb);
  c1  jsonb; c2 jsonb; c3 jsonb;
  v_code text;
  v_id uuid;
  v_ip text := nullif(public.request_ip(), '');
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  -- Read again once the row is held: a colleague's Mark signed, Cancel or
  -- revision meanwhile is seen (audit 2026-11-04).
  o := public.quote_sign_open(p_key);
  if o ? 'error' then return o; end if;
  if (o->>'id')::uuid is distinct from q.id then return jsonb_build_object('error', 'not-found'); end if;
  c1 := public.quote_sign_company(pl->'company'); if c1 ? 'error' then return c1; end if;
  c2 := public.quote_sign_contact(pl->'contact'); if c2 ? 'error' then return c2; end if;
  c3 := public.quote_sign_signer(pl->'signer', pl->'signature'); if c3 ? 'error' then return c3; end if;
  if coalesce(pl->>'agree', '') <> 'true' then return jsonb_build_object('error', 'bad-agree'); end if;
  if (select count(*) from public.quote_sign_codes s
       where s.quotation_id = q.id and s.created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('error', 'too-many');
  end if;
  -- And ten an hour from one address, across every quotation (audit
  -- 2026-11-15): the address is kept an hour at most, let go at the next
  -- request after it.
  update public.quote_sign_codes s set caller_ip = null
   where s.caller_ip is not null and s.created_at < now() - interval '1 hour';
  if v_ip is not null and (select count(*) from public.quote_sign_codes s
       where s.caller_ip = v_ip and s.created_at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('error', 'too-many');
  end if;
  v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.quote_sign_codes (quotation_id, code_hash, email, payload, expires_at, caller_ip)
  values (q.id, crypt(v_code, gen_salt('bf', 6)), c2->'contact'->>'email',
          jsonb_build_object('company', c1->'company', 'contact', c2->'contact', 'signer', c3->'signer', 'signature', c3->'signature'),
          now() + interval '15 minutes', v_ip)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'code', v_code, 'email', c2->'contact'->>'email', 'ref', q.ref,
    'name', btrim(coalesce(c2->'contact'->>'salutation', '') || ' ' || (c2->'contact'->>'name')));
end $$;
revoke all on function public.quote_sign_code(text, jsonb) from public, anon, authenticated;
grant execute on function public.quote_sign_code(text, jsonb) to service_role;

create or replace function public.demo_set(p_on boolean, p_pin text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me public.team_members;
  v_was boolean;
  v_pin text := btrim(coalesce(p_pin, ''));
  v_held boolean;
  v_bits text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  -- A new PIN is 6 to 8 digits (audit 2026-11-15); one of 4 or 5 set
  -- before keeps opening (`demo_pin_ok`).
  if v_pin <> '' and v_pin !~ '^[0-9]{6,8}$' then return jsonb_build_object('error', 'bad-pin'); end if;
  v_held := exists (select 1 from public.app_secrets s where s.key = 'demo_pin' and coalesce(s.value, '') <> '');
  if coalesce(p_on, false) and v_pin = '' and not v_held then return jsonb_build_object('error', 'no-pin'); end if;
  v_was := coalesce((select f.on_now from public.app_flags f where f.key = 'demo'), false);
  if v_pin <> '' then
    insert into public.app_secrets (key, value) values ('demo_pin', crypt(v_pin, gen_salt('bf', 8)))
    on conflict (key) do update set value = excluded.value, updated_at = now();
    v_bits := v_bits || 'PIN changed'::text;
    -- A new PIN starts every count afresh: the wrong tries a guesser or a
    -- mistyping colleague left no longer lock it (review 2026-10-29, 14).
    update public.link_tries set fails = 0, locked_until = null, strikes = 0, struck_until = null
     where kind = 'demo' and (fails > 0 or locked_until is not null or strikes > 0);
    update public.link_attempts set fails = 0, locked_until = null
     where kind = 'demo' and (fails > 0 or locked_until is not null);
  end if;
  if v_was is distinct from coalesce(p_on, false) then
    v_bits := array['Demo access: ' || case when v_was then 'On' else 'Off' end || ' → ' || case when p_on then 'On' else 'Off' end] || v_bits;
  end if;
  insert into public.app_flags as f (key, on_now, set_by, set_at)
  values ('demo', coalesce(p_on, false), coalesce(v_me.name, v_me.email), now())
  on conflict (key) do update set on_now = excluded.on_now,
    set_by = case when f.on_now is distinct from excluded.on_now or v_pin <> '' then excluded.set_by else f.set_by end,
    set_at = case when f.on_now is distinct from excluded.on_now or v_pin <> '' then excluded.set_at else f.set_at end;
  if array_length(v_bits, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(v_me.name, v_me.email, 'admin'), 'team.changed', 'Demo access', array_to_string(v_bits, ' · '));
  end if;
  return public.demo_state();
end $$;
revoke all on function public.demo_set(boolean, text) from public, anon;
grant execute on function public.demo_set(boolean, text) to authenticated;

create or replace function public.campaign_options_approval_gate()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.state = 'scheduled' and old.state in ('submitted', 'reviewing', 'changes')
     and coalesce((select r.decision from public.option_reviews r
                    where r.option_id = new.id and r.undone_at is null
                    order by r.created_at desc, r.id desc limit 1), '') <> 'approved' then
    raise exception 'needs-approval: Scheduled needs the client''s approval'
      using errcode = '23514', hint = 'needs-approval';
  end if;
  return new;
end $$;
revoke all on function public.campaign_options_approval_gate() from public, anon, authenticated;
create or replace trigger campaign_options_approval_gate
  before update of state on public.campaign_options
  for each row execute function public.campaign_options_approval_gate();

-- END OF AUDIT FIXES, THIRD BATCH ---------------------------------------------

select public.functions_tidy();
