-- ============================================================================
-- ACCESS SECURITY FIXES (2026-11-17)
-- ============================================================================
-- The user, 2026-11-17 (decision 6 of the access restructure: "6 ok"):
--   1. A user group is made, changed and deleted by an admin alone. Team
--      Full Access no longer edits a group (`roles_admin` asks `allowed('admin')`,
--      `team_roles_admin_guard` refuses anyone else, `admin-only`). The super
--      admin's own rules stand.
--   2. Own clients only is matched by the colleague's id, never their name:
--      `clients.owner_id` is stamped by trigger `client_owner_id_stamp` from
--      the Person in charge (the colleague of that name not removed, active
--      first), kept while that colleague holds the name, and read by
--      `client_row_seen_by(stage, owner, owner_id, sales_by, level)`. A
--      newcomer sharing a removed colleague's name no longer sees the
--      clients still named after them. A rename is carried by id
--      (`team_members_rename_owner`).
-- Safe to run twice. Rollback: restore `client_row_seen_by(text, text, uuid,
-- text)` and its callers from the band before this one, `roles_admin` at
-- `allowed('team', 'manage')`, and drop the column and its trigger.
-- The old four-argument rule and the unused three-argument one are dropped
-- by 2026-11-17-access-security-fixes-editor.sql (the SQL Editor's).

-- 1. Groups: an admin's alone. ---------------------------------------------

alter policy roles_admin on public.team_roles
  using (public.allowed('admin')) with check (public.allowed('admin'));

create or replace function public.team_roles_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if who = '' or pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  /* A group made admin, an admin group made plain, made or deleted: the
     super admin's alone. */
  if not public.team_super_ok() and (
       (tg_op = 'INSERT' and (coalesce(new.is_admin, false) or new.slug = 'admin'))
    or (tg_op = 'DELETE' and (coalesce(old.is_admin, false) or old.slug = 'admin'))
    or (tg_op = 'UPDATE' and coalesce(new.is_admin, false) is distinct from coalesce(old.is_admin, false))) then
    raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin makes or removes an admin group.';
  end if;
  /* Every other group, its access and its granted parts: an admin's. */
  if not public.allowed('admin') then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes a user group.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
revoke all on function public.team_roles_admin_guard() from public, anon, authenticated;

-- 2. Own clients by the colleague's id. ------------------------------------

alter table public.clients add column if not exists owner_id uuid references public.team_members(id) on delete set null;
create index if not exists clients_owner_id_idx on public.clients (owner_id);

create or replace function public.client_owner_id_of(p_owner text)
returns uuid language sql stable security definer set search_path = public as $$
  select t.id from public.team_members t
   where nullif(btrim(coalesce(p_owner, '')), '') is not null
     and lower(btrim(t.name)) = lower(btrim(p_owner)) and t.removed_at is null
   order by t.active desc, t.created_at desc
   limit 1
$$;
revoke all on function public.client_owner_id_of(text) from public, anon, authenticated;

/* Named so it runs before `client_scope_guard`, which reads it. */
create or replace function public.client_owner_id_stamp()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if nullif(btrim(coalesce(new.owner, '')), '') is null then
    new.owner_id := null;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.owner is not distinct from old.owner and new.owner_id is not distinct from old.owner_id
     and new.owner_id is not null then
    return new;
  end if;
  /* An id is kept only while that colleague holds the name written. */
  if new.owner_id is not null and exists (select 1 from public.team_members t
       where t.id = new.owner_id and lower(btrim(t.name)) = lower(btrim(new.owner))) then
    return new;
  end if;
  new.owner_id := public.client_owner_id_of(new.owner);
  return new;
end $$;
revoke all on function public.client_owner_id_stamp() from public, anon, authenticated;
create or replace trigger client_owner_id_stamp before insert or update of owner, owner_id on public.clients
  for each row execute function public.client_owner_id_stamp();

update public.clients c set owner_id = public.client_owner_id_of(c.owner)
 where c.owner_id is null and nullif(btrim(coalesce(c.owner, '')), '') is not null;

/* The scope rule, by the colleague's id. */
create or replace function public.client_row_seen_by(p_stage text, p_owner text, p_owner_id uuid, p_sales_by uuid, p_level text)
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
    if p_sales_by is not null and p_sales_by = t.id then return true; end if;
    if nullif(btrim(coalesce(p_owner, '')), '') is null then
      return coalesce(band = 'clients.leads', false);
    end if;
    return p_owner_id is not null and p_owner_id = t.id;
  end if;
  return true;
end $$;
revoke all on function public.client_row_seen_by(text, text, uuid, uuid, text) from public, anon, authenticated;

create or replace function public.client_seen(p_client uuid, p_level text default 'view')
returns boolean language plpgsql security definer stable set search_path = public as $$
declare
  st text;
  ow text;
  oi uuid;
  sb uuid;
begin
  if p_client is null then return true; end if;
  select c.stage, c.owner, c.owner_id, c.sales_by into st, ow, oi, sb from public.clients c where c.id = p_client;
  if not found then return true; end if;
  return public.client_row_seen_by(st, ow, oi, sb, p_level);
end $$;

/* A rename is carried onto the clients the colleague holds by id; a client
   named after them before the id was kept is carried by name. */
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
            where c.owner_id = new.id
               or (c.owner_id is null and lower(btrim(coalesce(c.owner, ''))) = v_old)
            order by c.id loop
    update public.clients c set owner = v_new, owner_id = new.id where c.id = r.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (v_by, 'client.edited', r.name, 'Person in charge: ' || btrim(old.name) || ' to ' || v_new);
  end loop;
  for r in select g.id, g.title from public.campaigns g where lower(btrim(coalesce(g.owner, ''))) = v_old order by g.id loop
    update public.campaigns g set owner = v_new where g.id = r.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (v_by, 'campaign.edited', r.title, 'Person in charge: ' || btrim(old.name) || ' to ' || v_new);
  end loop;
  return new;
end $$;
revoke all on function public.team_members_rename_owner() from public, anon, authenticated;

-- 3. Every reader of the rule passes the id. -------------------------------

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
     and public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view');
  return jsonb_build_object('ok', true, 'post', case when jsonb_array_length(v) > 0 then v -> 0 end, 'posts', v);
end $$;

create or replace function public.sm_report_audit_last(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  a public.sm_report_audits;
  v_print text;
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_print := public.sm_report_meta_print(p_id);
  select * into a from public.sm_report_audits x
   where x.report_id = p_id and x.version_no = r.version_no
   order by x.read_at desc, x.id desc limit 1;
  return jsonb_build_object(
    'needed', public.sm_report_audit_needed(p_id),
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin',
    'blocks', public.sm_report_audit_blocks(p_id, null),
    'running', public.sm_report_running(p_id),
    'counts_from', r.period_end + 1,
    'held', exists (select 1 from public.sm_report_audits x where x.report_id = p_id and x.version_no = r.version_no),
    'print_since', (select min(x.read_at) from public.sm_report_audits x
                     where x.report_id = p_id and x.version_no = r.version_no and x.print = v_print),
    'print_moved', exists (select 1 from public.sm_report_audits x
                            where x.report_id = p_id and x.version_no = r.version_no and x.print is distinct from v_print),
    'last', case when a.id is null then null else jsonb_build_object(
      'at', a.read_at, 'by', a.by_name, 'outcome', a.outcome, 'rows', a.diffs, 'note', a.note,
      'current', a.print is not distinct from v_print) end);
end $$;

create or replace function public.sm_report_audit_save(p_id uuid, p_outcome text, p_rows jsonb default '[]'::jsonb,
                                                       p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  prev public.sm_report_audits;
  v_rows jsonb := coalesce(p_rows, '[]'::jsonb);
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_print text;
  v_id uuid;
  v_at timestamptz;
  v_word text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_outcome, '') not in ('match', 'mismatch', 'unavailable', 'override') then
    return jsonb_build_object('error', 'bad-outcome');
  end if;
  if jsonb_typeof(v_rows) is distinct from 'array' or jsonb_array_length(v_rows) > 500 or length(v_rows::text) > 200000 then
    return jsonb_build_object('error', 'bad-rows');
  end if;
  if p_outcome = 'match' then v_rows := '[]'::jsonb; end if;
  if p_outcome = 'mismatch' and jsonb_array_length(v_rows) = 0 then return jsonb_build_object('error', 'bad-rows'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not (r.status = 'draft' or (r.kind = 'ads' and r.status in ('review', 'confirmed'))) then
    return jsonb_build_object('error', 'not-open', 'status', r.status);
  end if;
  if not public.sm_report_audit_needed(p_id) then return jsonb_build_object('error', 'not-linked'); end if;
  select * into prev from public.sm_report_audits x
   where x.report_id = p_id and x.version_no = r.version_no
   order by x.read_at desc, x.id desc limit 1;
  if p_outcome = 'override' then
    if not (coalesce(me.is_admin, false) or me.role = 'admin') then return jsonb_build_object('error', 'denied'); end if;
    if prev.id is null or prev.outcome <> 'unavailable' then return jsonb_build_object('error', 'not-unavailable'); end if;
    if v_note is null then return jsonb_build_object('error', 'reason-required'); end if;
    v_rows := '[]'::jsonb;
  end if;
  if p_outcome = 'match' then v_note := null; end if;
  v_note := left(v_note, 500);
  v_print := public.sm_report_meta_print(p_id);
  if prev.id is not null and p_outcome <> 'override' and prev.outcome = p_outcome
     and prev.print is not distinct from v_print and prev.diffs = v_rows and prev.note is not distinct from v_note then
    update public.sm_report_audits set read_at = now(), by_id = me.id, by_name = me.name where id = prev.id
    returning id, read_at into v_id, v_at;
    return jsonb_build_object('ok', true, 'id', v_id, 'at', v_at, 'outcome', p_outcome, 'again', true);
  end if;
  insert into public.sm_report_audits (report_id, version_no, by_id, by_name, outcome, print, diffs, note)
  values (p_id, r.version_no, me.id, me.name, p_outcome, v_print, v_rows, v_note)
  returning id, read_at into v_id, v_at;
  if prev.id is null or prev.outcome <> p_outcome or p_outcome = 'override' then
    v_word := case p_outcome
      when 'match' then 'Against Meta: matches'
      when 'mismatch' then 'Against Meta: ' || jsonb_array_length(v_rows) || ' to fix'
      when 'unavailable' then 'Against Meta: not checked, Meta unavailable'
      else 'Against Meta: not checked, Meta unavailable · Reason: ' || v_note end;
    perform public.sm_report_log(p_id, 'report.audited', 'Report audit · ' || v_word);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'at', v_at, 'outcome', p_outcome);
end $$;

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
  if not public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
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

create or replace function public.sm_report_history(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rep public.sm_reports;
  cl public.clients;
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into rep from public.sm_reports where id = p_id;
  if rep.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into cl from public.clients where id = rep.client_id;
  if not public.client_row_seen_by(cl.stage, cl.owner, cl.owner_id, cl.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object('actor', a.actor, 'action', a.action, 'subject', a.subject,
             'detail', a.detail, 'created_at', a.created_at) order by a.created_at desc)
      from (select * from public.activity_log x where x.ref = p_id order by x.created_at desc limit 500) a
  ), '[]'::jsonb));
end $$;

create or replace function public.sm_report_months(p_client uuid, p_kind text default 'social')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.clients;
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_kind, '') not in ('social', 'ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'),
    'white_label', coalesce(c.white_label, false),
    'months', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'period', e.period, 'start_day', e.start_day,
               'starts', s.starts, 'ends', s.ends, 'status', e.status,
               'asks', p_kind = any (coalesce(e.reports, '{}'::text[])),
               'planned', coalesce(e.planned_count, 0),
               'report', (select r.id from public.sm_reports r
                           where r.client_id = e.client_id and r.kind = p_kind and r.brand_id is null
                             and not r.on_request and r.period_end between s.starts and s.ends
                           order by r.period_start desc limit 1))
             order by e.period desc)
        from public.ops_engagements e
       cross join lateral public.ops_month_span(e.period, e.start_day) s
       where e.client_id = p_client and e.status <> 'cancelled'), '[]'::jsonb));
end $$;

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
  if not public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'work') then return jsonb_build_object('error', 'denied'); end if;
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
  if not public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'work') then return jsonb_build_object('error', 'denied'); end if;
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
  if not public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
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

create or replace function public.sm_reports_owed(p_period text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_period   text := coalesce(nullif(btrim(p_period), ''),
                       to_char(date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') - interval '1 month', 'YYYY-MM'));
  v_items    jsonb := '[]'::jsonb;
  v_seen     uuid[] := '{}';
  v_task     uuid;
  v_tdue     timestamptz;
  v_assignee text;
  v_due      timestamptz;
  v_found    boolean;
  e          record;
  k          text;
  r          record;
begin
  if not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if v_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then return jsonb_build_object('error', 'bad-period'); end if;

  -- Every report a month of the period asks for, found or not started.
  for e in
    select x.id, x.client_id, x.reports, s.starts, s.ends, c.name as client_name, c.slug as client_slug
      from public.ops_engagements x
      join public.clients c on c.id = x.client_id
     cross join lateral public.ops_month_span(x.period, x.start_day) s
     where x.period = v_period and x.status <> 'cancelled' and cardinality(x.reports) > 0
       and public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view')
     order by c.name
  loop
    foreach k in array e.reports loop
      v_task := null; v_tdue := null; v_assignee := null;
      select x.id, x.current_final_due_at, m.name into v_task, v_tdue, v_assignee
        from public.ops_tasks x
        left join public.ops_task_assignees a
          on a.task_id = x.id and a.responsibility = 'owner' and a.ended_at is null
        left join public.team_members m on m.id = a.team_member_id
       where x.engagement_id = e.id and x.source_type = 'report_' || k
         and x.cancelled_at is null and x.archived_at is null
       order by x.created_at desc limit 1;
      v_due := coalesce(v_tdue,
        ((e.ends + public.app_setting('report_due_days', e.ends)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur');
      v_found := false;
      for r in
        select y.id, y.status, y.sent_on, b.name as brand_name
          from public.sm_reports y
          left join public.client_brands b on b.id = y.brand_id
         where y.client_id = e.client_id and y.kind = k and not y.on_request
           and y.period_end between e.starts and e.ends
         order by b.name nulls first, y.period_start
      loop
        v_found := true;
        v_seen := v_seen || r.id;
        v_items := v_items || jsonb_build_object(
          'client_id', e.client_id, 'client', e.client_name, 'slug', e.client_slug, 'kind', k,
          'brand', r.brand_name, 'report_id', r.id, 'status', r.status, 'sent_on', r.sent_on,
          'asked', true, 'task_id', v_task, 'assignee', v_assignee, 'due', v_due,
          'late', r.status <> 'published' and now() > v_due);
      end loop;
      if not v_found then
        v_items := v_items || jsonb_build_object(
          'client_id', e.client_id, 'client', e.client_name, 'slug', e.client_slug, 'kind', k,
          'brand', null, 'report_id', null, 'status', 'none', 'sent_on', null,
          'asked', true, 'task_id', v_task, 'assignee', v_assignee, 'due', v_due, 'late', now() > v_due);
      end if;
    end loop;
  end loop;

  -- Every report made for the period that no month's tick asked for: it
  -- belongs to the month whose span holds its last day, else to the
  -- calendar month of that day.
  for r in
    select y.id, y.client_id, y.kind, y.status, y.sent_on, y.period_end,
           c.name as client_name, c.slug as client_slug, b.name as brand_name
      from public.sm_reports y
      join public.clients c on c.id = y.client_id
      left join public.client_brands b on b.id = y.brand_id
     where not (y.id = any (v_seen)) and not y.on_request
       and coalesce((select x.period from public.ops_engagements x
                      cross join lateral public.ops_month_span(x.period, x.start_day) s
                      where x.client_id = y.client_id and x.status <> 'cancelled'
                        and y.period_end between s.starts and s.ends
                      order by x.period desc limit 1),
                    to_char(y.period_end, 'YYYY-MM')) = v_period
       and public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view')
     order by c.name, y.kind, b.name nulls first
  loop
    v_due := ((r.period_end + public.app_setting('report_due_days', r.period_end)::integer)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
    v_items := v_items || jsonb_build_object(
      'client_id', r.client_id, 'client', r.client_name, 'slug', r.client_slug, 'kind', r.kind,
      'brand', r.brand_name, 'report_id', r.id, 'status', r.status, 'sent_on', r.sent_on,
      'asked', false, 'task_id', null, 'assignee', null, 'due', v_due,
      'late', r.status <> 'published' and now() > v_due);
  end loop;

  return jsonb_build_object('period', v_period, 'items', v_items);
end $$;

create or replace function public.vic_clients()
returns table (client_id uuid, name text, since timestamptz, by_name text, note text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.vic_at, t.name, c.vic_note
    from public.clients c
    left join public.team_members t on t.id = c.vic_by
   where c.vic_at is not null
     and (public.ops_me()).id is not null
     and (public.client_row_seen_by(c.stage, c.owner, c.owner_id, c.sales_by, 'view')
          or exists (select 1 from public.ops_tasks k
                       join public.ops_task_assignees a on a.task_id = k.id and a.ended_at is null
                      where k.client_id = c.id and a.team_member_id = (public.ops_me()).id))
$$;

create or replace function public.client_scope_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  kind text := tg_argv[0];
  col  text := tg_argv[1];
  o jsonb;
  n jsonb := to_jsonb(new);
begin
  if pg_trigger_depth() > 1 or public.client_scope_free('work') then return new; end if;
  if tg_op = 'UPDATE' and tg_table_name = 'sm_report_versions'
     and coalesce(current_setting('adspace.keep_file', true), '') = 'on' then
    return new;
  end if;
  -- `team_hand_over` moving the person in charge (HAND-OVER TAKES CLIENTS).
  if tg_op = 'UPDATE' and tg_table_name in ('clients', 'campaigns')
     and coalesce(current_setting('adspace.team_owner', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    o := to_jsonb(old);
    if (kind = 'self' and not public.client_row_seen_by(o ->> 'stage', o ->> 'owner', (o ->> 'owner_id')::uuid, (o ->> 'sales_by')::uuid, 'work'))
       or (kind <> 'self' and not public.client_scope_ok(kind, (o ->> col)::uuid, 'work')) then
      raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
    end if;
  end if;
  if (kind = 'self' and not public.client_row_seen_by(n ->> 'stage', n ->> 'owner', (n ->> 'owner_id')::uuid, (n ->> 'sales_by')::uuid, 'work'))
     or (kind <> 'self' and not public.client_scope_ok(kind, (n ->> col)::uuid, 'work')) then
    raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
  end if;
  return new;
end $$;

create or replace function public.client_scope_removal()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  kind text := tg_argv[0];
  col  text := tg_argv[1];
  o jsonb := to_jsonb(old);
begin
  if pg_trigger_depth() > 1 or public.client_scope_free('manage') then return old; end if;
  if (kind = 'self' and not public.client_row_seen_by(o ->> 'stage', o ->> 'owner', (o ->> 'owner_id')::uuid, (o ->> 'sales_by')::uuid, 'manage'))
     or (kind <> 'self' and not public.client_scope_ok(kind, (o ->> col)::uuid, 'manage')) then
    raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
  end if;
  return old;
end $$;

-- END OF ACCESS SECURITY FIXES ---------------------------------------------

select public.functions_tidy();
