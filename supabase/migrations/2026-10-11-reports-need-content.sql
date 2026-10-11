-- 2026-10-11 · Monthly reports need planned content (white label exempt).
-- Safe to run twice. Rollback is in the band's head.

-- MONTHLY REPORTS NEED PLANNED CONTENT — a client's own monthly Accounts
-- Report is made only for a month in My Work with content planned (the user,
-- 2026-10-11: "0 planned content only allows advertising report"); a
-- white-label client, its own reports and its brands', is held to neither.
--   1. `sm_reports_month_gate` refuses `no-content` for a client's own
--      Accounts Report, not asked for, from October 2026, whose month holds
--      no planned content; an admin or Reports Full Access is held to it too.
--   2. `ops_engagements_accounts_content` refuses ticking the Accounts
--      report on a month with no planned content (`accounts-needs-content`),
--      checked only where the ticks or the plan change; a new month made
--      with no plan leaves the tick it took from the month before.
--   3. `sm_report_months` adds each month's `planned` and the client's
--      `white_label`, so New report greys a month the rule refuses.
-- Rollback: run sm_reports_month_gate and sm_report_months as the REPORTS ON
-- REQUEST section defines them, then drop the trigger
-- ops_engagements_accounts_content and its function.
create or replace function public.sm_reports_month_gate()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if new.brand_id is not null or new.on_request or new.period_start < date '2026-10-01' or me.id is null then return new; end if;
  if new.kind = 'social'
     and not coalesce((select c.white_label from public.clients c where c.id = new.client_id), false)
     and exists (select 1 from public.ops_engagements e
                  cross join lateral public.ops_month_span(e.period, e.start_day) s
                  where e.client_id = new.client_id and e.status <> 'cancelled'
                    and new.period_end between s.starts and s.ends
                    and coalesce(e.planned_count, 0) = 0) then
    raise exception 'no-content' using errcode = 'P0001';
  end if;
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

create or replace function public.ops_engagements_accounts_content()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not ('social' = any (coalesce(new.reports, '{}'::text[]))) or coalesce(new.planned_count, 0) > 0 then return new; end if;
  if tg_op = 'UPDATE' and new.reports is not distinct from old.reports
     and new.planned_count is not distinct from old.planned_count then return new; end if;
  if coalesce((select c.white_label from public.clients c where c.id = new.client_id), false) then return new; end if;
  /* A new month takes its ticks from the month before: one with no plan
     yet leaves the Accounts Report out rather than failing to be made. */
  if tg_op = 'INSERT' then
    new.reports := array_remove(new.reports, 'social');
    return new;
  end if;
  raise exception using message = jsonb_build_object('error', 'accounts-needs-content')::text;
end $$;
revoke all on function public.ops_engagements_accounts_content() from public, anon, authenticated;

create or replace trigger ops_engagements_accounts_content
  before insert or update on public.ops_engagements
  for each row execute function public.ops_engagements_accounts_content();

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
-- END OF MONTHLY REPORTS NEED PLANNED CONTENT -------------------------------

select public.functions_tidy();
