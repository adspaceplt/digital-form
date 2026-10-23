-- ===========================================================================
-- SALES BY — a client records who brought it in, and a colleague who sees
-- their own clients only sees the clients they brought in too (2026-10-23)
-- ===========================================================================
-- WHY (the user, 2026-10-23: a sales executive in business development
-- whose group sees its own clients only "noticed that … the clients that
-- they handled have alr been handed over to other team members (for
-- operations and executions works) and hence unable to view it", then "Add
-- a Sales by field" and "Same as their group allows"): Own clients only
-- read the Person in charge alone, which moves to the colleague who runs
-- the work once a client is won.
--
-- WHAT IT CHANGES
--   * `clients.sales_by` (a colleague, `team_members(id)`): who brought the
--     client in, apart from Person in charge. Read with every client read
--     (granted with the record's columns), written with the client.
--     Trigger `clients_sales_by_guard`: a signed-in colleague puts
--     themselves, or nobody, on a client they add, and only Clients Full
--     Access names anyone else or changes it after (`sales-by`).
--   * `client_row_seen_by(stage, owner, sales_by, level)`: the scope rule,
--     where Own clients only now holds a client the colleague is Person in
--     charge of or brought in (Sales by), plus a lead nobody holds; the
--     band of the stage and the level asked are read as before, so the
--     group's own levels apply. `client_row_seen(stage, owner, level)`
--     stays, reading no Sales by.
--   * The rule's readers take it: `client_seen` (every client_scope
--     policy, through `client_scope_ok`), `client_scope_guard`,
--     `client_scope_removal`, `sm_report_gate`, `sm_reports_owed`,
--     `sm_report_months`, `sm_report_audit_save`, `sm_report_audit_last`
--     and `vic_clients`, each otherwise as its last definition.
--
-- ORDER: this file, then the pages. An old page never sends the column.
-- Safe to run twice. Rollback: run the earlier definitions of the nine
-- functions in supabase/schema.sql again (each before this band); the
-- column and the guard may stay.
-- ===========================================================================

alter table public.clients add column if not exists sales_by uuid references public.team_members(id);
grant select (sales_by) on table public.clients to authenticated;
grant insert (sales_by) on table public.clients to authenticated;
grant update (sales_by) on table public.clients to authenticated;
create index if not exists clients_sales_by_idx on public.clients (sales_by);

/* Who brought a client in is set by them on a client they add, else at
   Clients Full Access. A function's own write (a cascade, the quotation
   website's lead) and the connector pass. */
create or replace function public.clients_sales_by_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_me public.team_members;
begin
  if pg_trigger_depth() > 1 or auth.jwt() is null then return new; end if;
  if tg_op = 'UPDATE' and new.sales_by is not distinct from old.sales_by then return new; end if;
  v_me := public.ops_me();
  if v_me.id is null or public.allowed('clients', 'manage') then return new; end if;
  if tg_op = 'INSERT' and (new.sales_by is null or new.sales_by = v_me.id) then return new; end if;
  raise exception 'Sales by is set at Clients Full Access.' using errcode = '42501', hint = 'sales-by';
end $$;
revoke all on function public.clients_sales_by_guard() from public, anon, authenticated;
create or replace trigger clients_sales_by_guard before insert or update of sales_by on public.clients
  for each row execute function public.clients_sales_by_guard();

/* The scope rule, with who brought the client in. */
create or replace function public.client_row_seen_by(p_stage text, p_owner text, p_sales_by uuid, p_level text)
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
    return lower(btrim(p_owner)) = lower(btrim(coalesce(t.name, '')));
  end if;
  return true;
end $$;
revoke all on function public.client_row_seen_by(text, text, uuid, text) from public, anon, authenticated;

create or replace function public.client_seen(p_client uuid, p_level text default 'view')
returns boolean language plpgsql security definer stable set search_path = public as $$
declare
  st text;
  ow text;
  sb uuid;
begin
  if p_client is null then return true; end if;
  select c.stage, c.owner, c.sales_by into st, ow, sb from public.clients c where c.id = p_client;
  if not found then return true; end if;
  return public.client_row_seen_by(st, ow, sb, p_level);
end $$;
revoke all on function public.client_seen(uuid, text) from public, anon, authenticated;

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
  if tg_op = 'UPDATE' then
    o := to_jsonb(old);
    if (kind = 'self' and not public.client_row_seen_by(o ->> 'stage', o ->> 'owner', (o ->> 'sales_by')::uuid, 'work'))
       or (kind <> 'self' and not public.client_scope_ok(kind, (o ->> col)::uuid, 'work')) then
      raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
    end if;
  end if;
  if (kind = 'self' and not public.client_row_seen_by(n ->> 'stage', n ->> 'owner', (n ->> 'sales_by')::uuid, 'work'))
     or (kind <> 'self' and not public.client_scope_ok(kind, (n ->> col)::uuid, 'work')) then
    raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
  end if;
  return new;
end $$;
revoke all on function public.client_scope_guard() from public, anon, authenticated;

create or replace function public.client_scope_removal()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  kind text := tg_argv[0];
  col  text := tg_argv[1];
  o jsonb := to_jsonb(old);
begin
  if pg_trigger_depth() > 1 or public.client_scope_free('manage') then return old; end if;
  if (kind = 'self' and not public.client_row_seen_by(o ->> 'stage', o ->> 'owner', (o ->> 'sales_by')::uuid, 'manage'))
     or (kind <> 'self' and not public.client_scope_ok(kind, (o ->> col)::uuid, 'manage')) then
    raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
  end if;
  return old;
end $$;
revoke all on function public.client_scope_removal() from public, anon, authenticated;

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
  v_missing text[] := '{}';
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.period_start < date '2026-10-01' or r.on_request then
    return jsonb_build_object('applies', false, 'ok', true, 'missing', '[]'::jsonb, 'on_request', r.on_request);
  end if;
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
    if v_made < e.planned_count then v_missing := v_missing || 'content'::text; end if;
  end if;
  return jsonb_build_object(
    'applies', true, 'ok', cardinality(v_missing) = 0, 'missing', to_jsonb(v_missing),
    'month', case when e.id is null then null else jsonb_build_object(
               'id', e.id, 'period', e.period, 'start_day', e.start_day, 'starts', v_starts, 'ends', v_ends,
               'reports', to_jsonb(e.reports)) end,
    'planned', coalesce(e.planned_count, 0), 'made', v_made,
    'task', case when task.id is null then null else jsonb_build_object(
              'id', task.id, 'task_no', task.task_no, 'stage_key', task.stage_key) end,
    'due', v_due, 'late', now() > v_due,
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'));
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
       and public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view')
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
       and public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view')
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
revoke all on function public.sm_reports_owed(text) from public, anon, authenticated;
grant execute on function public.sm_reports_owed(text) to authenticated;

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
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
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
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
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
revoke all on function public.sm_report_audit_save(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.sm_report_audit_save(uuid, text, jsonb, text) to authenticated;

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
  if not public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
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
revoke all on function public.sm_report_audit_last(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_audit_last(uuid) to authenticated;

create or replace function public.vic_clients()
returns table (client_id uuid, name text, since timestamptz, by_name text, note text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.vic_at, t.name, c.vic_note
    from public.clients c
    left join public.team_members t on t.id = c.vic_by
   where c.vic_at is not null
     and (public.ops_me()).id is not null
     and (public.client_row_seen_by(c.stage, c.owner, c.sales_by, 'view')
          or exists (select 1 from public.ops_tasks k
                       join public.ops_task_assignees a on a.task_id = k.id and a.ended_at is null
                      where k.client_id = c.id and a.team_member_id = (public.ops_me()).id))
$$;
revoke all on function public.vic_clients() from public, anon;
grant execute on function public.vic_clients() to authenticated;

-- END OF SALES BY ---------------------------------------------------------

select public.functions_tidy();
