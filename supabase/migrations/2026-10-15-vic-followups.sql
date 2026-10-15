-- ===========================================================================
-- VIC FOLLOW-UPS — a VIC lead is followed up sooner, and a VIC client's work
-- leads a colleague's task reminders (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15: VIC clients, item 10)
--   A Very Important Client's lead or proposal should not wait as long as
--   any other, and a colleague's reminders should name a VIC client's work
--   first, telling them at once when such a task falls overdue.
--
-- WHAT CHANGED
--   * Two Business settings, seeded once from the start:
--     `vic_lead_followup_hours` (24) and `vic_proposal_followup_days` (7),
--     the follow-up limits a VIC lead and a VIC proposal are read against
--     (Settings, Clients: Follow-up limits, `team.settings`).
--     `app_settings_set` takes them, each filed from and to.
--   * `ops_tasks_nudge()`: a VIC client's tasks are named first and counted
--     apart ("5 tasks need attention: 2 for VIC clients, 2 overdue, …"); a
--     VIC client's task that became overdue after the colleague's last
--     reminder is told at once, inside `task_remind_hours` too, once. The
--     notice about one VIC task is titled VIC by `ops_notifications_vic`.
--
-- ORDER
--   This file, then the pages (`staleH` reads the two settings, falling back
--   on 24 and 7 while they are missing).
--
-- Safe to run twice. Rollback: run AD BENCHMARKS' app_settings_set and TASK
-- REMINDERS' ops_tasks_nudge again; the two setting rows may stay.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select v.key, date '2023-08-14', v.value
  from (values ('vic_lead_followup_hours', 24), ('vic_proposal_followup_days', 7)) as v(key, value)
 where not exists (select 1 from public.app_settings s where s.key = v.key);

/* Business settings take a VIC's follow-up limits. */
create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text; v_pre text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days', 'wa_repeat_hours',
    'bench_cpr_low', 'bench_cpr_mid', 'bench_cpr_high', 'bench_cpr_top', 'bench_msg_min', 'bench_msg_target', 'bench_msg_max',
    'bench_form_min', 'bench_form_target', 'bench_form_max', 'bench_cpm_min', 'bench_cpm_max', 'bench_cpl_rise',
    'bench_reels_share', 'bench_ad_spend_pct', 'bench_adset_daily', 'vic_lead_followup_hours', 'vic_proposal_followup_days'];
  v_moved text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, 2) <> v_v
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k = 'meta_checks' and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k in ('bench_reels_share') and (v_v < 0 or v_v > 100))
       or (v_k = 'bench_ad_spend_pct' and (v_v < 1 or v_v > 100))
       or (v_k = 'bench_cpl_rise' and (v_v < -100 or v_v > 100))
       or (v_k like 'bench_%' and v_k not in ('bench_reels_share', 'bench_ad_spend_pct', 'bench_cpl_rise') and (v_v < 0 or v_v > 10000)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      insert into public.app_settings (key, from_date, value, set_by, set_at)
      values (v_k, p_from, v_v, v_me.id, now())
      on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_name := case v_k when 'lead_followup_hours' then 'A lead waits' when 'proposal_followup_days' then 'A proposal waits'
        when 'vic_lead_followup_hours' then 'A VIC lead waits' when 'vic_proposal_followup_days' then 'A VIC proposal waits'
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 17 months' when 'term_18_23' then '18 to 23 months' when 'term_24' then '24 months and more'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input, a million tokens'
        when 'ai_price_out' then 'AI output, a million tokens' when 'ai_price_search' then 'AI web searches, a thousand' when 'meta_checks' then 'Meta checks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Cost per lead rise a year' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend of the budget' when 'bench_adset_daily' then 'Daily budget an ad set, at least'
        else 'Report due' end;
      v_pre := case when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'quote_valid_days', 'details_form_days') then ' days'
        when v_pre <> '' then '' else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || case when v_k = 'meta_checks' then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k = 'meta_checks' then '' else v_pre ||
              trim(to_char(v_was, 'FM999999990.99'), '.') || v_unit || ' → ' || v_pre ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

/* A VIC client's work first in a colleague's reminders. */
create or replace function public.ops_tasks_nudge(p_at timestamptz default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_at    timestamptz := coalesce(p_at, now());
  v_local timestamp := coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur';
  v_today date := (coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur')::date;
  v_every integer;
  v_start integer;
  m record;
  v_title text;
  v_body text;
  v_parts text[];
  v_last timestamptz;
  n integer := 0;
begin
  v_every := coalesce(public.app_setting('task_remind_hours', v_today), 3)::integer;
  v_start := coalesce(public.app_setting('task_start_days', v_today), 2)::integer;
  if v_every <= 0 or extract(isodow from v_today) > 5
     or extract(hour from v_local) < 10 or extract(hour from v_local) >= 18 then
    return 0;
  end if;
  for m in
    with floors as (
      select workflow_id, min(position) as at
        from public.ops_workflow_stages
       where stage_group = 'client_review'
       group by workflow_id
    ),
    pfloors as (
      select workflow_id,
             coalesce(min(position) filter (where stage_group = 'client_review'),
                      min(position) filter (where stage_group = 'internal_review')) as at
        from public.ops_workflow_stages
       group by workflow_id
    ),
    mine as (
      select a.team_member_id as member, k.id, a.assigned_at, k.priority_level, (c.vic_at is not null) as vic,
             public.ops_serial(k.task_no) || ' · ' || public.ops_title(k) as label,
             coalesce(c.name, 'Internal') as client,
             s.stage_group, s.position, f.at as review_at, pf.at as prio_at,
             public.ops_priority_by(coalesce(k.priority_at, k.created_at), k.priority_level) as prio_by,
             (k.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date as due_day,
             (coalesce(k.current_first_draft_due_at, k.current_final_due_at) at time zone 'Asia/Kuala_Lumpur')::date as first_day
        from public.ops_task_assignees a
        join public.ops_tasks k on k.id = a.task_id
        join public.team_members tm on tm.id = a.team_member_id
        join public.ops_workflow_stages s on s.workflow_id = k.workflow_id and s.key = k.stage_key
        left join public.clients c on c.id = k.client_id
        left join floors f on f.workflow_id = k.workflow_id
        left join pfloors pf on pf.workflow_id = k.workflow_id
       where a.responsibility = 'owner' and a.ended_at is null
         and tm.active and not coalesce(tm.system, false)
         and k.completed_at is null and k.cancelled_at is null and k.archived_at is null
         and coalesce(s.stage_group, '') <> 'cancelled'
    ),
    sorted as (
      select x.*,
             (x.prio_by is not null and (x.prio_at is null or x.position < x.prio_at
                                         or x.stage_group in ('kiv', 'blocked'))) as prio_runs,
             (x.review_at is null or x.position < x.review_at) as short_of_review
        from mine x
    ),
    sized as (
      select y.*,
             /* When it became overdue: the earlier of its priority's deadline
                and the end of its due day. */
             least(case when y.prio_runs and y.prio_by < v_at then y.prio_by end,
                   case when y.due_day < v_today and y.short_of_review
                        then (y.due_day + 1)::timestamp at time zone 'Asia/Kuala_Lumpur' end) as late_at,
             case
        when (y.due_day < v_today and y.short_of_review) or (y.prio_runs and y.prio_by < v_at) then 1
        when y.prio_runs and y.priority_level = 1 then 2
        when (y.due_day = v_today and y.short_of_review)
          or (y.prio_runs and (y.prio_by at time zone 'Asia/Kuala_Lumpur')::date = v_today) then 3
        when v_start > 0 and y.stage_group in ('intake', 'ready')
          and ((y.first_day is not null and y.first_day <= v_today + v_start)
            or (y.first_day is null and y.assigned_at <= v_at - make_interval(days => v_start))) then 4
      end as bucket
        from sorted y
    )
    select z.member,
           count(*) as total,
           count(*) filter (where z.bucket = 1) as late,
           count(*) filter (where z.bucket = 2) as urgent,
           count(*) filter (where z.bucket = 3) as today,
           count(*) filter (where z.bucket = 4) as idle,
           count(*) filter (where z.vic) as vic,
           max(z.late_at) filter (where z.vic and z.bucket = 1) as vic_late_at,
           (array_agg(z.id order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_id,
           (array_agg(z.bucket order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_bucket,
           (array_agg(z.client order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_client,
           (array_agg(z.prio_by order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_by,
           (array_agg(z.label order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1:3] as labels
      from sized z
     where z.bucket is not null
     group by z.member
     order by z.member
  loop
    /* Within the window nothing is sent, but a VIC client's task that has
       become overdue since this colleague's last reminder is told at once. */
    select max(o.created_at) into v_last from public.ops_notifications o
     where o.team_member_id = m.member and o.kind = 'tasks.nudge';
    if v_last > v_at - make_interval(mins => v_every * 60 - 10)
       and (m.vic_late_at is null or m.vic_late_at <= v_last) then
      continue;
    end if;
    if m.total = 1 then
      v_title := m.labels[1] || case m.first_bucket when 1 then ' is overdue.' when 2 then ' is Urgent.'
                                                  when 3 then ' is due today.' else ' has not started.' end;
      v_body := m.first_client || case when m.first_bucket = 2 and m.first_by is not null then
        ' · deliver by ' || to_char(m.first_by at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam') || ', ' ||
        public.register_day((m.first_by at time zone 'Asia/Kuala_Lumpur')::date) || '.' else '' end;
    else
      v_parts := array_remove(array[
        case when m.vic > 0 then m.vic || ' for VIC clients' end,
        case when m.late > 0 then m.late || ' overdue' end,
        case when m.urgent > 0 then m.urgent || ' Urgent' end,
        case when m.today > 0 then m.today || ' due today' end,
        case when m.idle > 0 then m.idle || ' not started' end], null);
      v_title := m.total || ' tasks need attention: ' || array_to_string(v_parts, ', ') || '.';
      v_body := array_to_string(m.labels, '; ') ||
                case when m.total > 3 then '; and ' || (m.total - 3) || ' more.' else '.' end;
    end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, created_at, dedupe_key)
    values (m.member, case when m.total = 1 then m.first_id end, 'tasks.nudge', v_title, v_body, v_at,
            'tasks.nudge.' || m.member || '.' || to_char(v_local, 'YYYY-MM-DD-HH24'))
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.ops_tasks_nudge(timestamptz) from public, anon, authenticated;

-- END OF VIC FOLLOW-UPS -------------------------------------------------------
select public.functions_tidy();
