-- ===========================================================================
-- REPORTS OWED — the reports a content month asks for, and where each one
-- stands, for the Overview's Reports card.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-07: "some clients are not monthly
-- engagement ... show only those have content month")
--   1. `sm_reports_owed(p_period)`: for a content month ('YYYY-MM'; last
--      month in Malaysia when none is given), every report a client's month
--      asks for (its Reports ticks) and every report made for that month
--      that no tick asked for, each with its stage: none (not started),
--      draft, review, confirmed or published; the brand of a white-label
--      report; the report task and who it is assigned to; the due time (the
--      task's, else `report_due_days` after the month's last day, 23:59
--      MYT); and late once that time has passed short of published. A
--      report belongs to the month whose span holds its last day, else to
--      the calendar month of its last day. Reports at Full Access, and only
--      the clients the caller may see (`client_row_seen`).
--
-- ROLLBACK (in the SQL Editor)
--   drop function if exists public.sm_reports_owed(text);
-- ===========================================================================

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
       and public.client_row_seen(c.stage, c.owner, 'view')
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
         where y.client_id = e.client_id and y.kind = k and y.period_end between e.starts and e.ends
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
     where not (y.id = any (v_seen))
       and coalesce((select x.period from public.ops_engagements x
                      cross join lateral public.ops_month_span(x.period, x.start_day) s
                      where x.client_id = y.client_id and x.status <> 'cancelled'
                        and y.period_end between s.starts and s.ends
                      order by x.period desc limit 1),
                    to_char(y.period_end, 'YYYY-MM')) = v_period
       and public.client_row_seen(c.stage, c.owner, 'view')
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

-- END OF REPORTS OWED ---------------------------------------------------------
