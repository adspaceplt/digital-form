-- ===========================================================================
-- MONTH REPORTS — a client's month says which reports it owes (Accounts,
-- Advertising, both or none) and on which day it starts; each report ticked
-- is a task in the month, due seven days after the month ends.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `ops_engagements.reports` (`social` the Accounts report, `ads` the
--      Advertising report; empty for a client owed neither) and
--      `ops_engagements.start_day` (1 to 28; a month starting on the 16th
--      runs to the 15th of the next). A new month takes both from the
--      client's month before unless it names them, so a change of start day
--      carries forward from the month it is made on, never backwards.
--   2. `ops_month_span(period, day)`: the first and last day of a month.
--   3. `ops_engagement_sync_reports(month)`: each report ticked has one live
--      task on the everyday workflow, named Accounts report or Advertising
--      report, its format Report, its owner the month's manager, due at
--      23:59 MYT seven days after the month's last day (`source_type`
--      `report_social` / `report_ads`). A report unticked cancels its task
--      while it is still To do and keeps one already started. A start day
--      moved moves an open task's due date, filed as a date change.
--   4. `ops_engagement_upsert` takes `reports` and `start_day` and syncs.
--
-- ROLLBACK
--   Run the READINESS IS THE FIRST MONTH'S section's ops_engagement_upsert
--   again, remove the functions ops_engagement_sync_reports(uuid) and
--   ops_month_span(text, integer), then
--   alter table public.ops_engagements drop column if exists reports,
--     drop column if exists start_day;
-- ===========================================================================

alter table public.ops_engagements add column if not exists reports text[] not null default '{}';
alter table public.ops_engagements add column if not exists start_day smallint not null default 1;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ops_engagements_reports_check') then
    alter table public.ops_engagements add constraint ops_engagements_reports_check
      check (reports <@ array['social', 'ads']::text[]);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ops_engagements_start_day_check') then
    alter table public.ops_engagements add constraint ops_engagements_start_day_check
      check (start_day between 1 and 28);
  end if;
end $$;

-- The first and last day of a month that starts on `p_day`.
create or replace function public.ops_month_span(p_period text, p_day integer)
returns table (starts date, ends date)
language sql immutable set search_path = public as $$
  select d, (d + interval '1 month')::date - 1
    from (select make_date(split_part(p_period, '-', 1)::integer, split_part(p_period, '-', 2)::integer,
                           greatest(1, least(28, coalesce(p_day, 1)))) as d) x
$$;
revoke all on function public.ops_month_span(text, integer) from public, anon, authenticated;

-- One live task a report the month asks for; a report no longer asked for
-- cancels its task while it is still To do.
create or replace function public.ops_engagement_sync_reports(p_engagement uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  k text;
  v_ends date;
  v_due timestamptz;
  t public.ops_tasks;
  v_first text;
  res jsonb;
  made integer := 0;
  gone integer := 0;
begin
  select * into e from public.ops_engagements where id = p_engagement;
  if e.id is null or e.status in ('completed', 'cancelled') then
    return jsonb_build_object('made', 0, 'cancelled', 0);
  end if;
  select s.ends into v_ends from public.ops_month_span(e.period, e.start_day) s;
  v_due := ((v_ends + 7)::timestamp + time '23:59') at time zone 'Asia/Kuala_Lumpur';
  foreach k in array array['social', 'ads'] loop
    if k = any (e.reports) then
      if not exists (select 1 from public.ops_tasks x
                      where x.engagement_id = e.id and x.source_type = 'report_' || k
                        and x.cancelled_at is null and x.archived_at is null) then
        res := public.ops_create_task(jsonb_build_object(
          'engagement_id', e.id, 'scope', 'client', 'client_id', e.client_id,
          'workflow_key', 'task', 'task_type', 'engagement', 'deliverable_type', 'report',
          'content_desc', case k when 'social' then 'Accounts report' else 'Advertising report' end,
          'code_period', e.period, 'final_due_at', v_due, 'source_type', 'report_' || k,
          'owner_id', e.manager_id, 'manager_id', e.manager_id));
        if res ? 'error' then
          raise exception 'report-task: %', res ->> 'error' using errcode = 'P0001';
        end if;
        made := made + 1;
      else
        for t in select * from public.ops_tasks x
                  where x.engagement_id = e.id and x.source_type = 'report_' || k
                    and x.cancelled_at is null and x.archived_at is null and x.completed_at is null
                    and x.current_final_due_at is distinct from v_due loop
          update public.ops_tasks set current_final_due_at = v_due, updated_at = now(), version = version + 1
           where id = t.id;
          perform public.ops_log(t.id, 'due_changed',
            jsonb_build_object('kind', 'final', 'value', t.current_final_due_at),
            jsonb_build_object('kind', 'final', 'value', v_due),
            jsonb_build_object('reason', 'scope_change', 'note', 'The month''s start day moved.'));
        end loop;
      end if;
    else
      for t in select * from public.ops_tasks x
                where x.engagement_id = e.id and x.source_type = 'report_' || k
                  and x.cancelled_at is null and x.archived_at is null and x.completed_at is null loop
        select s.key into v_first from public.ops_workflow_stages s
         where s.workflow_id = t.workflow_id order by s.position limit 1;
        if t.stage_key = v_first then
          update public.ops_tasks set stage_key = 'cancelled', cancelled_at = now(), updated_at = now(),
                 version = version + 1
           where id = t.id;
          perform public.ops_log(t.id, 'stage_changed', jsonb_build_object('stage_key', t.stage_key),
            jsonb_build_object('stage_key', 'cancelled'),
            jsonb_build_object('note', 'The month no longer asks for this report.'));
          gone := gone + 1;
        end if;
      end loop;
    end if;
  end loop;
  return jsonb_build_object('made', made, 'cancelled', gone);
end $$;
revoke all on function public.ops_engagement_sync_reports(uuid) from public, anon, authenticated;

/* One a client a month. A second call for the same month edits the one row
   rather than making a second. The two checks are onboarding, so they are
   seeded on the client's first month and on no later one. The reports a
   month owes and its start day come from the month before unless named. */
create or replace function public.ops_engagement_upsert(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  cid uuid;
  per text;
  eid uuid;
  k text;
  fresh boolean := false;
  prev public.ops_engagements;
  v_day integer;
  v_reports text[];
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  if cid is null or not exists (select 1 from public.clients where id = cid) then
    return jsonb_build_object('error', 'client-required');
  end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  if p_payload ? 'start_day' and (nullif(p_payload ->> 'start_day', '') is null
     or (p_payload ->> 'start_day') !~ '^\d{1,2}$' or (p_payload ->> 'start_day')::integer not between 1 and 28) then
    return jsonb_build_object('error', 'bad-start-day');
  end if;
  if p_payload ? 'reports' then
    if jsonb_typeof(p_payload -> 'reports') <> 'array' then return jsonb_build_object('error', 'bad-reports'); end if;
    select coalesce(array_agg(distinct x), '{}') into v_reports from jsonb_array_elements_text(p_payload -> 'reports') x;
    if not (v_reports <@ array['social', 'ads']::text[]) then return jsonb_build_object('error', 'bad-reports'); end if;
  end if;

  select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
  if eid is null then
    select * into prev from public.ops_engagements o
     where o.client_id = cid and o.period < per order by o.period desc limit 1;
    v_day := coalesce((p_payload ->> 'start_day')::integer, prev.start_day, 1);
    v_reports := coalesce(v_reports, prev.reports, '{}');
    insert into public.ops_engagements (client_id, period, manager_id, planned_count, drive_url, created_by,
                                        reports, start_day)
    values (cid, per, coalesce((p_payload ->> 'manager_id')::uuid, m.id),
            coalesce((p_payload ->> 'planned_count')::integer, 0),
            nullif(p_payload ->> 'drive_url', ''), m.id, v_reports, v_day)
    on conflict (client_id, period) do nothing
    returning id into eid;
    /* Somebody else made it between the read and the write: theirs stands. */
    if eid is null then
      select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
    else
      fresh := true;
    end if;
  end if;
  if fresh then
    if not exists (select 1 from public.ops_engagements o where o.client_id = cid and o.id <> eid) then
    foreach k in array array['onboarding', 'pre_ads'] loop
      insert into public.ops_engagement_checks (engagement_id, key) values (eid, k)
      on conflict do nothing;
    end loop;
    end if;
    perform public.ops_engagement_log(eid, 'created', p_payload - 'client_id');
  else
    if not public.ops_may_see_engagement(eid) then return jsonb_build_object('error', 'denied'); end if;
    /* Asked for with nothing to change, the month is answered as it stands:
       a task made for a month joins it without editing it. */
    if (p_payload - 'client_id' - 'period') = '{}'::jsonb then
      return public.ops_engagement_json(eid) || jsonb_build_object('created', false);
    end if;
    update public.ops_engagements set
      manager_id = coalesce((p_payload ->> 'manager_id')::uuid, manager_id),
      planned_count = coalesce((p_payload ->> 'planned_count')::integer, planned_count),
      drive_url = case when p_payload ? 'drive_url' then nullif(p_payload ->> 'drive_url', '') else drive_url end,
      reports = coalesce(v_reports, reports),
      start_day = coalesce((p_payload ->> 'start_day')::integer, start_day),
      updated_at = now(), version = version + 1
    where id = eid;
    perform public.ops_engagement_log(eid, 'edited', p_payload - 'client_id' - 'period');
  end if;
  perform public.ops_engagement_sync_reports(eid);
  return public.ops_engagement_json(eid) || jsonb_build_object('created', fresh);
end $$;
grant execute on function public.ops_engagement_upsert(jsonb) to authenticated;

-- END OF MONTH REPORTS -------------------------------------------------------
