-- ===========================================================================
-- A REPORT BEGINS IN ITS MONTH — a month's report is started from the month
-- in My Work that asks for it, and a draft taken away puts its task back.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-09: "if no content month completed, then the option
--   to create that specific month would be greyed out". The loop is month
--   (its Reports ticks) → report task → report → the task follows it.
--   1. `sm_report_months(p_client, p_kind)`: the client's months in My Work
--      (not cancelled), newest first, each with its span, whether it asks
--      for the kind, and the report already made for it (no white-label
--      brand); and whether the reader may start one outside them
--      (`may_override`: an admin or Reports Full Access). Reports View, in
--      the colleague's client scope. New report offers these months, the
--      period being the month's own span (a month starting on the 16th
--      runs to the 15th), and greys a month that does not ask.
--   2. Trigger `sm_reports_month_gate` (before insert on `sm_reports`): a
--      report from October 2026 on, with no white-label brand, is refused
--      `month-gate` unless a month in My Work whose span holds its last day
--      asks for its kind, or the colleague is an admin or holds Reports
--      Full Access (the same people Submit lets past the month's gate). The
--      SQL editor (no colleague) passes.
--   3. `sm_reports_task_reset` (after a report row goes): a draft report
--      taken away puts its month's task back to To do, filed "Report
--      deleted", unless the task is finished. Its trigger statement names
--      the event, so it is applied on its own (CLAUDE.md §3).
--
-- ROLLBACK
--   Drop the triggers sm_reports_task_reset and sm_reports_month_gate on
--   public.sm_reports, then the functions sm_reports_task_reset(),
--   sm_reports_month_gate() and sm_report_months(uuid, text).
-- ===========================================================================

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
  if not public.client_row_seen(c.stage, c.owner, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage'),
    'months', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'period', e.period, 'start_day', e.start_day,
               'starts', s.starts, 'ends', s.ends, 'status', e.status,
               'asks', p_kind = any (coalesce(e.reports, '{}'::text[])),
               'report', (select r.id from public.sm_reports r
                           where r.client_id = e.client_id and r.kind = p_kind and r.brand_id is null
                             and r.period_end between s.starts and s.ends
                           order by r.period_start desc limit 1))
             order by e.period desc)
        from public.ops_engagements e
       cross join lateral public.ops_month_span(e.period, e.start_day) s
       where e.client_id = p_client and e.status <> 'cancelled'), '[]'::jsonb));
end $$;

create or replace function public.sm_reports_month_gate()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if new.brand_id is not null or new.period_start < date '2026-10-01' or me.id is null then return new; end if;
  if coalesce(me.is_admin, false) or me.role = 'admin' or public.allowed('reports', 'manage') then return new; end if;
  if exists (select 1 from public.ops_engagements e
              cross join lateral public.ops_month_span(e.period, e.start_day) s
              where e.client_id = new.client_id and e.status <> 'cancelled'
                and new.period_end between s.starts and s.ends
                and new.kind = any (coalesce(e.reports, '{}'::text[]))) then
    return new;
  end if;
  raise exception 'month-gate' using errcode = 'P0001';
end $$;
revoke all on function public.sm_reports_month_gate() from public, anon, authenticated;

create or replace trigger sm_reports_month_gate
  before insert on public.sm_reports
  for each row execute function public.sm_reports_month_gate();

create or replace function public.sm_reports_task_reset()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t public.ops_tasks;
begin
  if old.brand_id is not null or old.status <> 'draft' then return null; end if;
  select x.* into t from public.ops_tasks x
    join public.ops_engagements e on e.id = x.engagement_id
   cross join lateral public.ops_month_span(e.period, e.start_day) s
   where e.client_id = old.client_id and e.status <> 'cancelled'
     and old.period_end between s.starts and s.ends
     and x.source_type = 'report_' || old.kind
     and x.cancelled_at is null and x.archived_at is null
   order by e.period desc, x.created_at desc limit 1
   for update of x;
  if t.id is null or t.completed_at is not null or t.stage_key = 'todo' then return null; end if;
  update public.ops_tasks set stage_key = 'todo', version = version + 1, updated_at = now(),
         blocked_at = null, blocked_category = null
   where id = t.id;
  perform public.ops_log(t.id, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', 'todo'),
    jsonb_build_object('note', 'Report deleted', 'report_id', old.id));
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_task_reset() from public, anon, authenticated;

create or replace trigger sm_reports_task_reset
  after delete on public.sm_reports
  for each row execute function public.sm_reports_task_reset();

-- END OF A REPORT BEGINS IN ITS MONTH ----------------------------------------

select public.functions_tidy();
