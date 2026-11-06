-- ===========================================================================
-- REPORT POSTS ON SEVERAL ACCOUNTS (2026-11-06)
-- ===========================================================================
-- WHY: the user, 2026-11-06: "usually one client would have multiple
-- accounts, the linking should match with other accounts postings too.
-- right now i have linked to Instagram but then the linking option is
-- gone." One piece of content goes out on Instagram and Facebook; its task
-- is now linked to each post, one post an account (approved: "ok approve
-- build").
--
-- WHAT IT CHANGES
--   A task takes one live link an account of its report (no longer one in
--   all): `sm_report_post_link` refuses `same-account` (a post of the same
--   account already holds it, `account` named) and `linked` only for a link
--   in another report. The first link keeps the task's state as before
--   (`prev`, `moved`); each further link keeps only its post's typed name,
--   and the task's live date (the earliest post's day) and figures (views
--   and engagements added up over every linked post) are worked out by
--   `sm_report_task_sync(p_task)`, where nothing has moved them since.
--   `sm_report_post_revert` restated: a link taken off while others stand
--   hands the first link's state to the earliest left and works the task
--   out again; the last one puts the task back as before.
--   `sm_report_post_tasks` restated: a task's `linked` means linked in
--   another report; `on` lists the accounts (platform ids) it is linked on
--   in this one; each link carries its post's `platform_id`.
--   `ops_task_report_post` restated: `posts`, every linked post (account,
--   day, address, views), the earliest still `post`.
--   `sm_reports_posts_follow` restated: published, the task takes every
--   linked post's figures added up.
--   The SQL Editor part (`2026-11-06-report-posts-many-accounts-editor.sql`)
--   drops the index that held one link a task; until it runs, a second
--   account's link is refused by that index.
--
-- ORDER: the pages, then this file, then the SQL Editor part. An old page
-- offers no task already linked, as before. Safe to run twice. Rollback:
-- the restatements in REPORT POSTS LINKED TO THEIR TASKS; the index made
-- again (`create unique index sm_report_post_links_task_idx on
-- public.sm_report_post_links (task_id) where unlinked_at is null`) once
-- no task holds two links.
-- ===========================================================================

-- REPORT POSTS ON SEVERAL ACCOUNTS ------------------------------------------

/* A task's live date and figures, worked out from every post it is linked
   to: the earliest post's day, views and engagements added up. A date or
   figures moved by hand since the links set them are left alone. Every
   live link of the task holds the same stamps (`live_set`, `results_at`),
   so whichever is taken off reads them. */
create or replace function public.sm_report_task_sync(p_task uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t public.ops_tasks;
  v_n integer;
  v_day date;
  v_views bigint;
  v_eng bigint;
  v_res boolean;
  v_set timestamptz;
  v_at timestamptz;
  v_prev jsonb;
  v_live timestamptz;
  v_lset boolean;
  v_rset boolean;
  v_rback boolean;
  v_now timestamptz := now();
begin
  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return; end if;
  select count(*), min(q.posted_on), sum(q.views), sum(coalesce(q.engagements, q.interactions)),
         coalesce(bool_or(q.views is not null or coalesce(q.engagements, q.interactions) is not null), false)
    into v_n, v_day, v_views, v_eng, v_res
    from public.sm_report_post_links k
    join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
   where k.task_id = p_task and k.unlinked_at is null;
  if v_n = 0 or v_day is null then return; end if;
  select k.live_set, k.results_at into v_set, v_at
    from public.sm_report_post_links k
   where k.task_id = p_task and k.unlinked_at is null
   order by k.linked_at limit 1;
  select k.prev into v_prev
    from public.sm_report_post_links k
   where k.task_id = p_task and k.unlinked_at is null and k.prev ? 'stage_key'
   order by k.linked_at limit 1;
  v_lset := t.live_at is not distinct from v_set;
  v_rset := v_res and t.result_at is not distinct from v_at;
  /* The figures came from a post now unlinked and none left holds any:
     the task's own figures from before the first link come back. */
  v_rback := not v_res and v_at is not null and t.result_at is not distinct from v_at;
  v_live := case when (t.live_at at time zone 'Asia/Kuala_Lumpur')::date = v_day then t.live_at
                 else (v_day + time '12:00') at time zone 'Asia/Kuala_Lumpur' end;
  update public.ops_tasks set
    live_at = case when v_lset then v_live else live_at end,
    result_views = case when v_rset then least(v_views, 2147483647)::integer
                        when v_rback then (v_prev ->> 'result_views')::integer else result_views end,
    result_engagements = case when v_rset then least(v_eng, 2147483647)::integer
                              when v_rback then (v_prev ->> 'result_engagements')::integer else result_engagements end,
    result_by = case when v_rset then coalesce((public.ops_me()).id, result_by)
                     when v_rback then (v_prev ->> 'result_by')::uuid else result_by end,
    result_at = case when v_rset then v_now
                     when v_rback then (v_prev ->> 'result_at')::timestamptz else result_at end,
    version = version + 1, updated_at = v_now
   where id = t.id;
  update public.sm_report_post_links set
    live_set = case when v_lset then v_live else live_set end,
    results_at = case when v_rset then v_now when v_rback then null else results_at end
   where task_id = p_task and unlinked_at is null;
end $$;
revoke all on function public.sm_report_task_sync(uuid) from public, anon, authenticated;

/* A link taken off ends (kept, with who and when). While the task stays
   linked to another post, the first link's state passes to the earliest
   left and the task's date and figures are worked out again; the last
   link puts back what it changed on the task, where nothing has changed
   it since: the stage it moved, the live date it set, the delay it
   cleared, the figures it took. */
create or replace function public.sm_report_post_revert(p_link uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  l public.sm_report_post_links;
  t public.ops_tasks;
  p jsonb;
  v_back boolean;
  v_next uuid;
begin
  update public.sm_report_post_links set unlinked_at = now(), unlinked_by = (public.ops_me()).id
   where id = p_link and unlinked_at is null
  returning * into l;
  if l.id is null then return; end if;
  p := l.prev;
  select * into t from public.ops_tasks where id = l.task_id for update;
  if t.id is null then return; end if;
  /* The post's name the link took from the task goes back to the one
     typed, where nobody renamed it since. */
  update public.sm_report_posts q set title = p ->> 'post_title'
   where q.id = l.post_id and p ? 'post_title' and q.title is not distinct from nullif(btrim(coalesce(t.content_desc, '')), '');
  select k.id into v_next
    from public.sm_report_post_links k
    join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
   where k.task_id = t.id and k.unlinked_at is null
   order by k.linked_at limit 1;
  if v_next is not null then
    if p ? 'stage_key' then
      update public.sm_report_post_links k
         set prev = (p - 'post_title') || jsonb_build_object('post_title', k.prev -> 'post_title'),
             moved = l.moved, done_at = coalesce(k.done_at, l.done_at)
       where k.id = v_next;
    end if;
    perform public.sm_report_task_sync(t.id);
    perform public.ops_log(t.id, 'report_unlinked', jsonb_build_object('live_at', t.live_at),
      jsonb_build_object('live_at', (select x.live_at from public.ops_tasks x where x.id = t.id)),
      jsonb_build_object('report_id', l.report_id, 'post_id', l.post_id));
    return;
  end if;
  /* The stage goes back only where it still stands where the link put
     it: a task moved by hand since (Completed included) is left there. */
  v_back := l.moved and t.stage_key = 'performance_review'
            and coalesce(p ->> 'stage_key', '') <> '' and t.stage_key is distinct from p ->> 'stage_key';
  update public.ops_tasks set
    stage_key = case when v_back then p ->> 'stage_key' else stage_key end,
    completed_at = case when v_back then (p ->> 'completed_at')::timestamptz else completed_at end,
    blocked_at = case when v_back then (p ->> 'blocked_at')::timestamptz else blocked_at end,
    blocked_category = case when v_back then p ->> 'blocked_category' else blocked_category end,
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
  a public.sm_report_platforms;
  f public.sm_report_post_links;
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
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;

  /* Taking a link off works with the switch off too, so Off can be
     walked back post by post. */
  select * into l from public.sm_report_post_links where post_id = p.id and unlinked_at is null;
  if p_task is null then
    if l.id is not null then
      perform public.sm_report_post_revert(l.id);
      select coalesce(x.code, public.ops_serial(x.task_no)) into v_code from public.ops_tasks x where x.id = l.task_id;
      perform public.sm_report_log(r.id, 'report.saved', coalesce(v_code, 'A task') || ' no longer linked to its post');
    end if;
    return jsonb_build_object('ok', true);
  end if;
  if not public.report_links_on() then return jsonb_build_object('error', 'links-off'); end if;
  if r.kind <> 'social' or r.on_request or r.brand_id is not null or coalesce(c.white_label, false) then
    return jsonb_build_object('error', 'not-linkable');
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
  /* A task's links are one report's: a link in another report is taken
     off there first. */
  select o2.* into o from public.sm_report_post_links k
    join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
    join public.sm_reports o2 on o2.id = k.report_id
   where k.task_id = t.id and k.unlinked_at is null and k.report_id <> r.id
   limit 1;
  if o.id is not null then
    return jsonb_build_object('error', 'linked', 'period', public.sm_period_word(o.period_start, o.period_end));
  end if;
  /* One post an account: another post of this account already holds it. */
  select a2.* into a from public.sm_report_post_links k
    join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
    join public.sm_report_platforms a2 on a2.id = q.platform_id
   where k.task_id = t.id and k.unlinked_at is null and k.report_id = r.id
     and q.platform_id = p.platform_id and q.id <> p.id
   limit 1;
  if a.id is not null then
    return jsonb_build_object('error', 'same-account', 'account', coalesce(nullif(a.account_name, ''), nullif(a.handle, ''), a.platform));
  end if;
  /* What this post held, and a link the task held on a post since
     removed, let go first. */
  if l.id is not null then perform public.sm_report_post_revert(l.id); end if;
  perform public.sm_report_post_revert(k.id) from public.sm_report_post_links k
   where k.task_id = t.id and k.unlinked_at is null
     and not exists (select 1 from public.sm_report_posts q where q.id = k.post_id and q.report_id = k.report_id);
  select * into t from public.ops_tasks where id = p_task;
  v_name := nullif(btrim(coalesce(t.content_desc, '')), '');
  v_code := coalesce(t.code, public.ops_serial(t.task_no));

  /* A task already linked to another account's post: this post joins it,
     and the task's date and figures are worked out over all of them. */
  select k.* into f from public.sm_report_post_links k
    join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
   where k.task_id = t.id and k.unlinked_at is null
   order by k.linked_at limit 1;
  if f.id is not null then
    insert into public.sm_report_post_links (post_id, report_id, task_id, prev, moved, live_set, results_at, linked_by)
    values (p.id, r.id, t.id, jsonb_build_object('post_title', p.title), false, f.live_set, f.results_at, me.id);
    if v_name is not null then
      update public.sm_report_posts set title = v_name where id = p.id;
    end if;
    perform public.sm_report_task_sync(t.id);
    perform public.ops_log(t.id, 'report_linked', jsonb_build_object('live_at', t.live_at),
      jsonb_build_object('live_at', (select x.live_at from public.ops_tasks x where x.id = t.id), 'posted_on', p.posted_on),
      jsonb_build_object('report_id', r.id, 'post_id', p.id));
    perform public.sm_report_log(r.id, 'report.saved',
      v_code || ' linked to its post of ' || public.register_day(p.posted_on) || ' on another account');
    return jsonb_build_object('ok', true, 'id', t.id, 'moved', false, 'extra', true, 'title', v_name, 'live', p.posted_on);
  end if;

  v_was_day := (t.live_at at time zone 'Asia/Kuala_Lumpur')::date;
  v_live := case when v_was_day = p.posted_on then t.live_at
                 else (p.posted_on + time '12:00') at time zone 'Asia/Kuala_Lumpur' end;
  /* A task held (On hold, Blocked, Taken down) stays where it is: only
     the line short of the review moves. */
  v_moved := t.stage_key not in ('performance_review', 'completed', 'on_hold', 'blocked', 'taken_down', 'cancelled')
             and exists (select 1 from public.ops_workflow_stages s
                          where s.workflow_id = t.workflow_id and s.key = 'performance_review');
  v_views := case when p.views is null then null else least(p.views, 2147483647)::integer end;
  v_eng := case when coalesce(p.engagements, p.interactions) is null then null
                else least(coalesce(p.engagements, p.interactions), 2147483647)::integer end;
  v_res := v_views is not null or v_eng is not null;

  insert into public.sm_report_post_links (post_id, report_id, task_id, prev, moved, live_set, results_at, linked_by)
  values (p.id, r.id, t.id, jsonb_build_object(
            'stage_key', t.stage_key, 'completed_at', t.completed_at, 'live_at', t.live_at,
            'delayed_at', t.delayed_at, 'delayed_by', t.delayed_by, 'delayed_reason', t.delayed_reason,
            'delayed_note', t.delayed_note, 'delayed_report', t.delayed_report,
            'result_views', t.result_views, 'result_engagements', t.result_engagements,
            'result_at', t.result_at, 'result_by', t.result_by,
            'blocked_at', t.blocked_at, 'blocked_category', t.blocked_category, 'post_title', p.title),
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

/* What the report's Posts step draws: each post's task with its account,
   and the tasks a post may take (the month's, then any marked delayed; an
   admin or Reports Full Access every content task of the client still open
   or of the last three months), each with the accounts it is linked on in
   this report and whether another report holds it. */
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
      select jsonb_agg(jsonb_build_object('post_id', l.post_id, 'platform_id', q.platform_id, 'task_id', t.id,
               'task_no', t.task_no, 'code', t.code, 'title', t.content_desc, 'stage_key', t.stage_key) order by t.task_no)
        from public.sm_report_post_links l
        join public.sm_report_posts q on q.id = l.post_id and q.report_id = l.report_id
        join public.ops_tasks t on t.id = l.task_id
       where l.report_id = r.id and l.unlinked_at is null), '[]'::jsonb),
    'tasks', case when not v_on then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'task_no', t.task_no, 'code', t.code, 'title', t.content_desc,
               'stage_key', t.stage_key, 'publish_at', t.publish_at, 'live_at', t.live_at,
               'delayed', t.delayed_at is not null, 'month', t.engagement_id is not distinct from e.id and e.id is not null,
               'linked', exists (select 1 from public.sm_report_post_links k
                                   join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
                                  where k.task_id = t.id and k.unlinked_at is null and k.report_id <> r.id),
               'on', coalesce((select jsonb_agg(distinct q.platform_id) from public.sm_report_post_links k
                                 join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
                                where k.task_id = t.id and k.unlinked_at is null and k.report_id = r.id), '[]'::jsonb))
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

/* The task card's line: the Accounts Report posts it is linked to, an
   account each, earliest first (`post`, the earliest, for a page served
   before). */
create or replace function public.ops_task_report_post(p_task uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v jsonb;
begin
  if me.id is null or not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('report_id', r.id, 'status', r.status, 'period_start', r.period_start,
           'period_end', r.period_end, 'posted_on', p.posted_on, 'url', p.url, 'views', p.views,
           'platform', a.platform, 'platform_name', a.platform_name, 'account_name', a.account_name, 'handle', a.handle,
           'may_open', public.allowed('reports', 'view')) order by p.posted_on, a.position), '[]'::jsonb)
    into v
    from public.sm_report_post_links l
    join public.sm_report_posts p on p.id = l.post_id and p.report_id = l.report_id
    join public.sm_report_platforms a on a.id = p.platform_id
    join public.sm_reports r on r.id = l.report_id
    join public.clients c on c.id = r.client_id
   where l.task_id = p_task and l.unlinked_at is null
     and public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view');
  return jsonb_build_object('ok', true, 'post', case when jsonb_array_length(v) > 0 then v -> 0 end, 'posts', v);
end $$;
revoke all on function public.ops_task_report_post(uuid) from public, anon, authenticated;
grant execute on function public.ops_task_report_post(uuid) to authenticated;

/* The report keeps its linked tasks' stage, as it keeps its own report
   task: moved into published, a task at Performance review is Completed
   (its figures taken again, every linked post's added up); moved out of
   published, a task that move completed goes back to Performance review.
   Any other step of the report, or a task moved by hand, is left alone;
   nothing moves while the switch is off. */
create or replace function public.sm_reports_posts_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  l public.sm_report_post_links;
  t public.ops_tasks;
  v_in boolean := new.status = 'published' and old.status is distinct from 'published';
  v_out boolean := old.status = 'published' and new.status is distinct from 'published';
  v_views bigint;
  v_eng bigint;
  v_res boolean;
begin
  if not (v_in or v_out) or not public.report_links_on() then return null; end if;
  for l in select k.* from public.sm_report_post_links k
             join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
            where k.report_id = new.id and k.moved and k.unlinked_at is null loop
    select * into t from public.ops_tasks where id = l.task_id for update;
    if t.id is null then continue; end if;
    if v_in and t.stage_key = 'performance_review' then
      select sum(q.views), sum(coalesce(q.engagements, q.interactions)),
             coalesce(bool_or(q.views is not null or coalesce(q.engagements, q.interactions) is not null), false)
        into v_views, v_eng, v_res
        from public.sm_report_post_links k
        join public.sm_report_posts q on q.id = k.post_id and q.report_id = k.report_id
       where k.task_id = t.id and k.unlinked_at is null;
      update public.ops_tasks set
        stage_key = 'completed', completed_at = coalesce(completed_at, now()),
        result_views = coalesce(least(v_views, 2147483647)::integer, result_views),
        result_engagements = coalesce(least(v_eng, 2147483647)::integer, result_engagements),
        result_at = case when v_res then now() else result_at end,
        version = version + 1, updated_at = now()
       where id = t.id returning result_at into t.result_at;
      update public.sm_report_post_links set done_at = now() where id = l.id;
      if v_res then
        update public.sm_report_post_links set results_at = t.result_at where task_id = t.id and unlinked_at is null;
      end if;
      perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', 'performance_review'),
        jsonb_build_object('stage_key', 'completed'), jsonb_build_object('note', 'Accounts Report published', 'report_id', new.id));
    elsif v_out and l.done_at is not null and t.stage_key = 'completed' then
      update public.ops_tasks set stage_key = 'performance_review', completed_at = null, version = version + 1, updated_at = now()
       where id = t.id;
      update public.sm_report_post_links set done_at = null where id = l.id;
      perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', 'completed'),
        jsonb_build_object('stage_key', 'performance_review'), jsonb_build_object('note', 'Accounts Report no longer published', 'report_id', new.id));
    end if;
  end loop;
  return null;
exception when others then
  raise warning 'sm_reports_posts_follow: %', sqlerrm;
  return null;
end $$;
revoke all on function public.sm_reports_posts_follow() from public, anon, authenticated;

-- END OF REPORT POSTS ON SEVERAL ACCOUNTS -----------------------------------

select public.functions_tidy();
