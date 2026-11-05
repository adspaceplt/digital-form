-- ===========================================================================
-- REPORT POSTS LINKED TO THEIR TASKS (2026-11-06)
-- ===========================================================================
-- WHY: the user, 2026-11-06: a post added to the Accounts Report with its
-- figures is linked to the My Work task it came from (2610W4_ABContent), so
-- the post takes the task's name, the task takes the post's real day as the
-- day it went live ("the report is accurate … the work task is inaccurate
-- alr even though 14 oct the task owner marked live"), moves to Performance
-- review, and to Completed once the report is published. A post that slipped
-- is marked delayed and linked in the next month's report. The report keeps
-- the task's stage as it keeps its own report task, by itself, and a person
-- may still move the task by hand. White label is left out (its accounts are
-- not ADspace's). A Business setting turns the whole of it off.
--
-- WHAT IT CHANGES
--   `report_post_links` (0 Off, 1 On, from a day; seeded On), read by
--   `report_links_on()`, set by `report_links_set(p_on)` (team.settings,
--   filed under Settings); `app_settings_set` takes the key too, in the
--   SQL Editor part (2026-11-06-report-posts-linked-to-tasks-editor.sql).
--   `sm_report_post_links` (RLS on, no policy, no grant): a post and its
--   task, one task a post and one post a task, with what the link changed
--   (`prev`, `moved`, `live_set`, `results_at`) so taking it off puts the
--   task back. It is not a column of the post, so a report's snapshot (what
--   the client portal reads) never carries it.
--   `sm_report_post_link(p_post, p_task)`: Reports Work, a draft monthly
--   Accounts Report of a client in scope at Work, not white label; the task
--   a content task of the client, of the report's month or marked delayed
--   (an admin or Reports Full Access: any of the client's content tasks);
--   the post dated (`links-off`, `not-draft`, `not-linkable`, `no-date`,
--   `not-in-month`, `linked`). It sets the task's live date to the post's
--   day (kept where it is that day), clears its delay, takes its views and
--   engagements from the post, moves it to Performance review where its
--   workflow holds the stage and the task stands short of it, names the post
--   by the task's description, and files both sides. p_task null takes the
--   link off: the task goes back to what it held where nothing has moved
--   it since, and the link is kept, ended (`unlinked_at`). A post removed leaves its link
--   counting for nothing, and the task free to be linked again.
--   `sm_report_post_tasks(p_report)`: the links and the tasks a post may
--   take. `ops_task_report_post(p_task)`: the task card's line.
--   Trigger `sm_reports_posts_follow`: a report published moves its linked
--   tasks from Performance review to Completed (and takes the figures
--   again); a report back from published moves them back.
--   `sm_report_gate`: with links on, a planned post counts once it is linked
--   to a post and holds its Draft due, Due date and Post date; a task not
--   linked is named `link` in `lacking` with its stage. Off, the rule of
--   2026-11-05 stands. A white-label report is held to neither.
--   `sm_report_post_delay`: refuses `posted` for a task already counted, by
--   whichever rule is on.
--
-- ORDER: the pages, then this file (an old page reads the gate as before;
-- it draws no Link task). Safe to run twice. Rollback: the setting Off
-- (Settings, Reports, report_links_set(false)), which returns every count
-- to the rule of 2026-11-05; the table may stay.
-- ===========================================================================

-- REPORT POSTS LINKED TO THEIR TASKS ---------------------------------------

insert into public.app_settings (key, from_date, value)
select 'report_post_links', date '2023-08-14', 1
 where not exists (select 1 from public.app_settings s where s.key = 'report_post_links');

create or replace function public.report_links_on()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.app_setting('report_post_links', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) = 1
$$;
revoke all on function public.report_links_on() from public, anon, authenticated;

create or replace function public.report_links_set(p_on boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_was  numeric;
  v_to   numeric := case when coalesce(p_on, false) then 1 else 0 end;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_was := public.app_setting('report_post_links', v_today);
  if v_was is not distinct from v_to then return jsonb_build_object('ok', true); end if;
  insert into public.app_settings (key, from_date, value, set_by, set_at)
  values ('report_post_links', v_today, v_to, me.id, now())
  on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Settings',
          'Posts linked to tasks: ' || case when v_was = 1 then 'On' else 'Off' end || ' → ' ||
          case when v_to = 1 then 'On' else 'Off' end || ' · from ' || public.register_day(v_today));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.report_links_set(boolean) from public, anon, authenticated;
grant execute on function public.report_links_set(boolean) to authenticated;

create table if not exists public.sm_report_post_links (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null,
  report_id    uuid not null,
  task_id      uuid not null,
  prev         jsonb not null default '{}'::jsonb,
  moved        boolean not null default false,
  live_set     timestamptz,
  results_at   timestamptz,
  linked_by    uuid,
  linked_at    timestamptz not null default now(),
  unlinked_at  timestamptz,
  unlinked_by  uuid
);
create unique index if not exists sm_report_post_links_task_idx on public.sm_report_post_links (task_id) where unlinked_at is null;
create unique index if not exists sm_report_post_links_post_idx on public.sm_report_post_links (post_id) where unlinked_at is null;
create index if not exists sm_report_post_links_report_idx on public.sm_report_post_links (report_id);
alter table public.sm_report_post_links enable row level security;
revoke all on public.sm_report_post_links from public, anon, authenticated;

/* A link taken off ends (kept, with who and when) and puts back what it
   changed on the task, where nothing has changed it since: the stage it
   moved, the live date it set, the delay it cleared, the figures it took.
   A post removed leaves its link standing on nothing: it counts for
   nothing, and the task is free to be linked again. */
create or replace function public.sm_report_post_revert(p_link uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  l public.sm_report_post_links;
  t public.ops_tasks;
  p jsonb;
  v_back boolean;
begin
  update public.sm_report_post_links set unlinked_at = now(), unlinked_by = (public.ops_me()).id
   where id = p_link and unlinked_at is null
  returning * into l;
  if l.id is null then return; end if;
  p := l.prev;
  select * into t from public.ops_tasks where id = l.task_id for update;
  if t.id is null then return; end if;
  v_back := l.moved and t.stage_key in ('performance_review', 'completed')
            and coalesce(p ->> 'stage_key', '') <> '' and t.stage_key is distinct from p ->> 'stage_key';
  update public.ops_tasks set
    stage_key = case when v_back then p ->> 'stage_key' else stage_key end,
    completed_at = case when v_back then (p ->> 'completed_at')::timestamptz else completed_at end,
    live_at = case when live_at is not distinct from l.live_set then (p ->> 'live_at')::timestamptz else live_at end,
    delayed_at = case when delayed_at is null then (p ->> 'delayed_at')::timestamptz else delayed_at end,
    delayed_by = case when delayed_at is null then (p ->> 'delayed_by')::uuid else delayed_by end,
    delayed_reason = case when delayed_at is null then p ->> 'delayed_reason' else delayed_reason end,
    delayed_note = case when delayed_at is null then p ->> 'delayed_note' else delayed_note end,
    delayed_report = case when delayed_at is null then (p ->> 'delayed_report')::uuid else delayed_report end,
    result_views = case when result_at is not distinct from l.results_at then (p ->> 'result_views')::integer else result_views end,
    result_engagements = case when result_at is not distinct from l.results_at then (p ->> 'result_engagements')::integer else result_engagements end,
    result_by = case when result_at is not distinct from l.results_at then (p ->> 'result_by')::uuid else result_by end,
    result_at = case when result_at is not distinct from l.results_at then (p ->> 'result_at')::timestamptz else result_at end,
    version = version + 1, updated_at = now()
   where id = t.id;
  if v_back then
    perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', t.stage_key),
      jsonb_build_object('stage_key', p ->> 'stage_key'),
      jsonb_build_object('note', 'Unlinked from its Accounts Report post', 'report_id', l.report_id));
  end if;
  perform public.ops_log(t.id, 'report_unlinked', jsonb_build_object('live_at', t.live_at),
    jsonb_build_object('live_at', case when t.live_at is not distinct from l.live_set then p ->> 'live_at' else to_jsonb(t.live_at) #>> '{}' end),
    jsonb_build_object('report_id', l.report_id));
end $$;
revoke all on function public.sm_report_post_revert(uuid) from public, anon, authenticated;

/* The link a task holds on a post still in its report. */
create or replace function public.sm_report_task_linked(p_task uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sm_report_post_links l
                   join public.sm_report_posts p on p.id = l.post_id and p.report_id = l.report_id
                  where l.task_id = p_task and l.unlinked_at is null)
$$;
revoke all on function public.sm_report_task_linked(uuid) from public, anon, authenticated;

create or replace function public.sm_report_post_link(p_post uuid, p_task uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  p public.sm_report_posts;
  r public.sm_reports;
  c public.clients;
  e public.ops_engagements;
  t public.ops_tasks;
  l public.sm_report_post_links;
  o public.sm_reports;
  v_code text;
  v_live timestamptz;
  v_moved boolean;
  v_views integer;
  v_eng integer;
  v_res boolean;
  v_name text;
  v_was_day date;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into p from public.sm_report_posts where id = p_post;
  if p.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.sm_reports where id = p.report_id for update;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.report_links_on() then return jsonb_build_object('error', 'links-off'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  if r.kind <> 'social' or r.on_request or r.brand_id is not null or coalesce(c.white_label, false) then
    return jsonb_build_object('error', 'not-linkable');
  end if;

  select * into l from public.sm_report_post_links where post_id = p.id and unlinked_at is null;
  if p_task is null then
    if l.id is not null then
      perform public.sm_report_post_revert(l.id);
      select coalesce(x.code, public.ops_serial(x.task_no)) into v_code from public.ops_tasks x where x.id = l.task_id;
      perform public.sm_report_log(r.id, 'report.saved', coalesce(v_code, 'A task') || ' no longer linked to its post');
    end if;
    return jsonb_build_object('ok', true);
  end if;
  if l.task_id = p_task then return jsonb_build_object('ok', true, 'id', p_task); end if;

  if p.posted_on is null then return jsonb_build_object('error', 'no-date'); end if;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null or t.client_id is distinct from r.client_id or t.cancelled_at is not null or t.archived_at is not null
     or coalesce(t.source_type, '') in ('report_social', 'report_ads') then
    return jsonb_build_object('error', 'not-in-month');
  end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = r.client_id and x.status <> 'cancelled'
     and r.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  /* The month's own posts, a post marked delayed from an earlier month;
     an admin or Reports Full Access any of the client's posts. */
  if not ((e.id is not null and t.engagement_id = e.id) or t.delayed_at is not null
          or coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage')) then
    return jsonb_build_object('error', 'not-in-month');
  end if;
  if public.sm_report_task_linked(t.id) then
    select o2.* into o from public.sm_report_post_links k join public.sm_reports o2 on o2.id = k.report_id
     where k.task_id = t.id and k.unlinked_at is null;
    return jsonb_build_object('error', 'linked', 'period', public.sm_period_word(o.period_start, o.period_end));
  end if;
  /* One task a post, one post a task: what this post held, and a link the
     task held on a post since removed, let go first. */
  if l.id is not null then perform public.sm_report_post_revert(l.id); end if;
  perform public.sm_report_post_revert(k.id) from public.sm_report_post_links k where k.task_id = t.id and k.unlinked_at is null;
  select * into t from public.ops_tasks where id = p_task;

  v_was_day := (t.live_at at time zone 'Asia/Kuala_Lumpur')::date;
  v_live := case when v_was_day = p.posted_on then t.live_at
                 else (p.posted_on + time '12:00') at time zone 'Asia/Kuala_Lumpur' end;
  v_moved := t.stage_key not in ('performance_review', 'completed')
             and exists (select 1 from public.ops_workflow_stages s
                          where s.workflow_id = t.workflow_id and s.key = 'performance_review');
  v_views := least(p.views, 2147483647)::integer;
  v_eng := least(coalesce(p.engagements, p.interactions), 2147483647)::integer;
  v_res := v_views is not null or v_eng is not null;
  v_name := nullif(btrim(coalesce(t.content_desc, '')), '');

  insert into public.sm_report_post_links (post_id, report_id, task_id, prev, moved, live_set, results_at, linked_by)
  values (p.id, r.id, t.id, jsonb_build_object(
            'stage_key', t.stage_key, 'completed_at', t.completed_at, 'live_at', t.live_at,
            'delayed_at', t.delayed_at, 'delayed_by', t.delayed_by, 'delayed_reason', t.delayed_reason,
            'delayed_note', t.delayed_note, 'delayed_report', t.delayed_report,
            'result_views', t.result_views, 'result_engagements', t.result_engagements,
            'result_at', t.result_at, 'result_by', t.result_by),
          v_moved, v_live, case when v_res then now() end, me.id);
  update public.ops_tasks set
    live_at = v_live,
    stage_key = case when v_moved then 'performance_review' else stage_key end,
    completed_at = case when v_moved then null else completed_at end,
    blocked_at = case when v_moved then null else blocked_at end,
    blocked_category = case when v_moved then null else blocked_category end,
    delayed_at = null, delayed_by = null, delayed_reason = null, delayed_note = null, delayed_report = null,
    result_views = case when v_res then v_views else result_views end,
    result_engagements = case when v_res then v_eng else result_engagements end,
    result_at = case when v_res then now() else result_at end,
    result_by = case when v_res then me.id else result_by end,
    version = version + 1, updated_at = now()
   where id = t.id;
  if v_name is not null then
    update public.sm_report_posts set title = v_name where id = p.id;
  end if;

  v_code := coalesce(t.code, public.ops_serial(t.task_no));
  if v_moved then
    perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', t.stage_key),
      jsonb_build_object('stage_key', 'performance_review'),
      jsonb_build_object('note', 'Linked to its Accounts Report post', 'report_id', r.id));
  end if;
  perform public.ops_log(t.id, 'report_linked', jsonb_build_object('live_at', t.live_at),
    jsonb_build_object('live_at', v_live, 'posted_on', p.posted_on), jsonb_build_object('report_id', r.id, 'post_id', p.id));
  perform public.sm_report_log(r.id, 'report.saved',
    v_code || ' linked to its post of ' || public.register_day(p.posted_on)
    || case when v_was_day is not null and v_was_day <> p.posted_on
            then ' · date it went live ' || public.register_day(v_was_day) || ' → ' || public.register_day(p.posted_on) else '' end);
  return jsonb_build_object('ok', true, 'id', t.id, 'moved', v_moved, 'title', v_name,
    'was_live', v_was_day, 'live', p.posted_on);
end $$;
revoke all on function public.sm_report_post_link(uuid, uuid) from public, anon, authenticated;
grant execute on function public.sm_report_post_link(uuid, uuid) to authenticated;

/* What the report's Posts step draws: each post's task, and the tasks a
   post may take (the month's, then any marked delayed; an admin or Reports
   Full Access every content task of the client still open or of the last
   three months). */
create or replace function public.sm_report_post_tasks(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  e public.ops_engagements;
  v_all boolean;
  v_on boolean := public.report_links_on();
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.kind <> 'social' or r.on_request or r.brand_id is not null or coalesce(c.white_label, false) then
    return jsonb_build_object('ok', true, 'on', v_on, 'applies', false, 'links', '[]'::jsonb, 'tasks', '[]'::jsonb);
  end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = r.client_id and x.status <> 'cancelled'
     and r.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  v_all := coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage');
  return jsonb_build_object('ok', true, 'on', v_on, 'applies', true,
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('post_id', l.post_id, 'task_id', t.id, 'task_no', t.task_no, 'code', t.code,
               'title', t.content_desc, 'stage_key', t.stage_key) order by t.task_no)
        from public.sm_report_post_links l
        join public.sm_report_posts q on q.id = l.post_id and q.report_id = l.report_id
        join public.ops_tasks t on t.id = l.task_id
       where l.report_id = r.id and l.unlinked_at is null), '[]'::jsonb),
    'tasks', case when not v_on then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'task_no', t.task_no, 'code', t.code, 'title', t.content_desc,
               'stage_key', t.stage_key, 'publish_at', t.publish_at, 'live_at', t.live_at,
               'delayed', t.delayed_at is not null, 'month', t.engagement_id is not distinct from e.id and e.id is not null,
               'linked', public.sm_report_task_linked(t.id))
               order by (t.engagement_id is not distinct from e.id and e.id is not null) desc, t.task_no)
        from public.ops_tasks t
       where t.client_id = r.client_id and t.cancelled_at is null and t.archived_at is null
         and coalesce(t.source_type, '') not in ('report_social', 'report_ads')
         and t.publish_at is not null
         and ((e.id is not null and t.engagement_id = e.id) or t.delayed_at is not null
              or (v_all and (t.completed_at is null or t.publish_at > now() - interval '3 months')))), '[]'::jsonb) end);
end $$;
revoke all on function public.sm_report_post_tasks(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_post_tasks(uuid) to authenticated;

/* The task card's line: the Accounts Report post it is linked to. */
create or replace function public.ops_task_report_post(p_task uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v jsonb;
begin
  if me.id is null or not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select jsonb_build_object('report_id', r.id, 'status', r.status, 'period_start', r.period_start, 'period_end', r.period_end,
           'posted_on', p.posted_on, 'url', p.url, 'views', p.views, 'may_open', public.allowed('reports', 'view'))
    into v
    from public.sm_report_post_links l
    join public.sm_report_posts p on p.id = l.post_id and p.report_id = l.report_id
    join public.sm_reports r on r.id = l.report_id
   where l.task_id = p_task and l.unlinked_at is null;
  return jsonb_build_object('ok', true, 'post', v);
end $$;
revoke all on function public.ops_task_report_post(uuid) from public, anon, authenticated;
grant execute on function public.ops_task_report_post(uuid) to authenticated;

/* The report keeps its linked tasks' stage, as it keeps its own report
   task: published, Completed (the figures taken again as published);
   anywhere else, Performance review. A task moved by hand off those two is
   left where it is. */
create or replace function public.sm_reports_posts_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  l public.sm_report_post_links;
  t public.ops_tasks;
  p public.sm_report_posts;
  v_to text := case when new.status = 'published' then 'completed' else 'performance_review' end;
  v_res boolean;
begin
  if new.status is not distinct from old.status then return null; end if;
  for l in select k.* from public.sm_report_post_links k
             join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
            where k.report_id = new.id and k.moved and k.unlinked_at is null loop
    select * into t from public.ops_tasks where id = l.task_id for update;
    if t.id is null or t.stage_key not in ('performance_review', 'completed') then continue; end if;
    select * into p from public.sm_report_posts where id = l.post_id;
    v_res := v_to = 'completed' and (p.views is not null or coalesce(p.engagements, p.interactions) is not null);
    update public.ops_tasks set
      stage_key = v_to,
      completed_at = case when v_to = 'completed' then coalesce(completed_at, now()) else null end,
      result_views = case when v_res then least(p.views, 2147483647)::integer else result_views end,
      result_engagements = case when v_res then least(coalesce(p.engagements, p.interactions), 2147483647)::integer else result_engagements end,
      result_at = case when v_res then now() else result_at end,
      version = version + 1, updated_at = now()
     where id = t.id;
    if v_res then update public.sm_report_post_links set results_at = now() where id = l.id; end if;
    if t.stage_key is distinct from v_to then
      perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', t.stage_key),
        jsonb_build_object('stage_key', v_to),
        jsonb_build_object('note', case when v_to = 'completed' then 'Accounts Report published' else 'Accounts Report back in draft' end,
                           'report_id', new.id));
    end if;
  end loop;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_posts_follow() from public, anon, authenticated;
create or replace trigger sm_reports_posts_follow after update of status on public.sm_reports
  for each row execute function public.sm_reports_posts_follow();

create or replace function public.sm_report_gate(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  e public.ops_engagements;
  task public.ops_tasks;
  v_starts date;
  v_ends date;
  v_due timestamptz;
  v_made integer := 0;
  v_posted integer := 0;
  v_delayed integer := 0;
  v_lacking jsonb := '[]'::jsonb;
  v_missing text[] := '{}';
  v_links boolean := public.report_links_on();
  v_wl boolean;
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.period_start < date '2026-10-01' or r.on_request then
    return jsonb_build_object('applies', false, 'ok', true, 'missing', '[]'::jsonb, 'on_request', r.on_request);
  end if;
  /* A white-label report's accounts are not ADspace's: no post is held
     to it (2026-11-06). */
  v_wl := r.brand_id is not null or coalesce(c.white_label, false);
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = r.client_id and x.status <> 'cancelled'
     and r.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then
    v_missing := v_missing || 'no-month'::text;
    v_due := ((r.period_end + public.app_setting('report_due_days', r.period_end)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  else
    select s.starts, s.ends into v_starts, v_ends from public.ops_month_span(e.period, e.start_day) s;
    v_due := ((v_ends + public.app_setting('report_due_days', v_ends)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
    if not (r.kind = any (e.reports)) then
      v_missing := v_missing || 'not-ticked'::text;
    else
      select * into task from public.ops_tasks x
       where x.engagement_id = e.id and x.source_type = 'report_' || r.kind
         and x.cancelled_at is null and x.archived_at is null
       order by x.created_at desc limit 1;
      if task.id is null then
        v_missing := v_missing || 'no-task'::text;
      else
        v_due := coalesce(task.current_final_due_at, v_due);
      end if;
    end if;
    select count(*) into v_made from public.ops_tasks x
     where x.engagement_id = e.id and x.cancelled_at is null and x.archived_at is null
       and coalesce(x.source_type, '') not in ('report_social', 'report_ads');
    /* Planned content holds an Accounts Report alone (2026-11-02). A post
       counts once it is linked to its post in a report and holds its dates
       (2026-11-06), or, with links off, once it has gone live and holds
       every date (2026-11-05). A post marked delayed counts too. */
    if r.kind = 'social' then
      if v_made < e.planned_count then v_missing := v_missing || 'content'::text; end if;
      if not v_wl then
        select count(*) filter (where k.counted), count(*) filter (where not k.counted and k.delayed)
          into v_posted, v_delayed
          from (select x.delayed_at is not null as delayed,
                       x.current_first_draft_due_at is not null and x.current_final_due_at is not null and x.publish_at is not null
                       and case when v_links then public.sm_report_task_linked(x.id)
                                else x.stage_key in ('live', 'performance_review', 'completed') and x.live_at is not null end as counted
                  from public.ops_tasks x
                 where x.engagement_id = e.id and x.cancelled_at is null and x.archived_at is null
                   and coalesce(x.source_type, '') not in ('report_social', 'report_ads')) k;
        if v_posted + v_delayed < e.planned_count then v_missing := v_missing || 'posted'::text; end if;
        if v_posted < e.planned_count then
          select coalesce(jsonb_agg(l.j order by l.n), '[]'::jsonb) into v_lacking from (
            select x.task_no as n, jsonb_build_object('id', x.id, 'task_no', x.task_no, 'code', x.code,
                     'stage_key', x.stage_key,
                     'delayed', x.delayed_at is not null, 'delayed_reason', x.delayed_reason, 'delayed_note', x.delayed_note,
                     'needs', to_jsonb(array_remove(array[
                       case when v_links and not public.sm_report_task_linked(x.id) then 'link' end,
                       case when not v_links and x.stage_key not in ('live', 'performance_review', 'completed') then 'stage' end,
                       case when x.current_first_draft_due_at is null then 'draft' end,
                       case when x.current_final_due_at is null then 'due' end,
                       case when x.publish_at is null then 'post' end,
                       case when not v_links and x.live_at is null then 'live' end], null))) as j
              from public.ops_tasks x
             where x.engagement_id = e.id and x.cancelled_at is null and x.archived_at is null
               and coalesce(x.source_type, '') not in ('report_social', 'report_ads')
               and not (x.current_first_draft_due_at is not null and x.current_final_due_at is not null and x.publish_at is not null
                        and case when v_links then public.sm_report_task_linked(x.id)
                                 else x.stage_key in ('live', 'performance_review', 'completed') and x.live_at is not null end)
             order by x.task_no limit 20) l;
        end if;
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'applies', true, 'ok', cardinality(v_missing) = 0, 'missing', to_jsonb(v_missing),
    'month', case when e.id is null then null else jsonb_build_object(
               'id', e.id, 'period', e.period, 'start_day', e.start_day, 'starts', v_starts, 'ends', v_ends,
               'reports', to_jsonb(e.reports)) end,
    'planned', coalesce(e.planned_count, 0), 'made', v_made, 'posted', v_posted, 'delayed', v_delayed, 'lacking', v_lacking,
    'links', v_links and not v_wl, 'white_label', v_wl,
    'task', case when task.id is null then null else jsonb_build_object(
              'id', task.id, 'task_no', task.task_no, 'stage_key', task.stage_key) end,
    'due', v_due, 'late', now() > v_due,
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'));
end $$;
revoke all on function public.sm_report_gate(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_gate(uuid) to authenticated;

/* Mark delay (2026-11-05), restated: a task already counted (linked, with
   links on; live with every date, with links off) is not marked. */
create or replace function public.sm_report_post_delay(p_report uuid, p_task uuid, p_reason text, p_note text default null, p_on boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  e public.ops_engagements;
  t public.ops_tasks;
  v_owner uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_word text;
  v_counted boolean;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = r.client_id and x.status <> 'cancelled'
     and r.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null or e.id is null or r.kind <> 'social' or t.engagement_id is distinct from e.id
     or t.cancelled_at is not null or t.archived_at is not null
     or coalesce(t.source_type, '') in ('report_social', 'report_ads') then
    return jsonb_build_object('error', 'not-in-month');
  end if;
  if not coalesce(p_on, true) then
    if t.delayed_at is null then return jsonb_build_object('ok', true, 'id', t.id); end if;
    update public.ops_tasks set delayed_at = null, delayed_by = null, delayed_reason = null, delayed_note = null,
           delayed_report = null, version = version + 1, updated_at = now()
     where id = t.id;
    perform public.ops_log(t.id, 'delay_cleared', jsonb_build_object('reason', t.delayed_reason), '{}'::jsonb,
      jsonb_build_object('report_id', r.id));
    perform public.sm_report_log(r.id, 'report.saved', coalesce(t.code, public.ops_serial(t.task_no)) || ' no longer marked delayed');
    return jsonb_build_object('ok', true, 'id', t.id);
  end if;
  v_counted := t.current_first_draft_due_at is not null and t.current_final_due_at is not null and t.publish_at is not null
     and case when public.report_links_on() then public.sm_report_task_linked(t.id)
              else t.stage_key in ('live', 'performance_review', 'completed') and t.live_at is not null end;
  if v_counted then
    return jsonb_build_object('error', 'posted');
  end if;
  v_word := case p_reason when 'client_request' then 'Client request' when 'scope_change' then 'Scope change'
    when 'capacity' then 'Internal capacity' when 'pending_assets' then 'Pending assets'
    when 'pending_confirmation' then 'Pending confirmation' end;
  if v_word is null then return jsonb_build_object('error', 'bad-reason'); end if;
  if char_length(coalesce(v_note, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  update public.ops_tasks set delayed_at = now(), delayed_by = me.id, delayed_reason = p_reason, delayed_note = v_note,
         delayed_report = r.id, version = version + 1, updated_at = now()
   where id = t.id;
  perform public.ops_log(t.id, 'delayed', '{}'::jsonb,
    jsonb_build_object('reason', p_reason, 'note', v_note), jsonb_build_object('report_id', r.id));
  perform public.sm_report_log(r.id, 'report.saved',
    coalesce(t.code, public.ops_serial(t.task_no)) || ' marked delayed: ' || v_word || coalesce(' · ' || v_note, ''));
  select a.team_member_id into v_owner from public.ops_task_assignees a
   where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null limit 1;
  if v_owner is not null and v_owner <> me.id then
    perform public.ops_notify(v_owner, t.id, 'delayed', public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
      'Marked delayed in the Accounts Report by ' || coalesce(nullif(me.name, ''), me.email) || ': ' || v_word || '.',
      'delayed:' || t.id::text || ':' || v_owner::text || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI'));
  end if;
  return jsonb_build_object('ok', true, 'id', t.id);
end $$;
revoke all on function public.sm_report_post_delay(uuid, uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.sm_report_post_delay(uuid, uuid, text, text, boolean) to authenticated;

-- END OF REPORT POSTS LINKED TO THEIR TASKS --------------------------------

select public.functions_tidy();
