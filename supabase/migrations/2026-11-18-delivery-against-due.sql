-- ===========================================================================
-- DELIVERY AGAINST THE DUE DATE (2026-11-18)
-- ===========================================================================
-- WHY: the user, 2026-11-18: "under team members performance we could gauge
-- using those metrics … how long its completed, how long its delayed, how
-- usually its early"; targets 85% on time or early and under 1 day late on
-- average; highlight the slowest and most delayed. On time alone said
-- nothing of how early, how late or how long work takes.
--
-- WHAT IT CHANGES
--   * `ops_timeliness(p_from, p_to)` (My Work: Reports granted, client scope):
--     every piece of work delivered in the period against its due date,
--     Malaysia's day: a content or everyday task when it first reached
--     client review (else when it was done), a month's Advertising or Social
--     Media report when it was marked sent (else when its task was done).
--     Work still undelivered past its due date counts late, by the days so
--     far. Early, on the day and late; the lateness over all work due (a day
--     early counts nought), and the average days late and early;
--     turnaround from the day a task was made, or a report's period ended,
--     as the median and the slowest 10%. For the team, by kind and by month;
--     by colleague and the most delayed work at My Work: All tasks.
--     Video scripts and Content Review have no tasks and are not counted.
--   * Settings `timely_pct` (85) and `timely_late_days` (1), seeded once and
--     taken by `app_settings_set` (On time target, %; Lateness target, days).
--
-- ORDER: this file (connector), then the pages. An open page calls nothing
-- new until it is refreshed. Safe to run twice.
--
-- ROLLBACK: drop function ops_timeliness(timestamptz, timestamptz); delete
-- the two settings; run app_settings_set from USAGE AND LIMITS WATCHED again.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select k.key, date '2023-08-14', k.value
  from (values ('timely_pct', 85), ('timely_late_days', 1)) k(key, value)
 where not exists (select 1 from public.app_settings s where s.key = k.key);

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
    'bench_reels_share', 'bench_ad_spend_pct', 'bench_adset_daily', 'vic_lead_followup_hours', 'vic_proposal_followup_days', 'fx_sgd',
    'health_keep_months', 'health_leaver_months', 'abroad_days', 'abroad_remind_hours', 'analytics_from',
    'analytics_change_pct', 'analytics_churn_pct', 'quote_reply_days', 'quote_wa_day', 'client_email_on', 'ai_price_image', 'report_post_links',
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'plan_db_mb', 'plan_db_alert_pct',
    'timely_pct', 'timely_late_days'];
  v_moved text[] := '{}';
  v_drop boolean; v_fw text; v_fv text;
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
    if round(v_v, case when v_k = 'fx_sgd' then 4 else 2 end) <> v_v
       or (v_k = 'fx_sgd' and (v_v < 0.5 or v_v > 10))
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k in ('meta_checks', 'client_email_on', 'report_post_links') and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'task_past_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_invite_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_link_days' and (v_v < 7 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_pool_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_keep_months' and (v_v < 1 or v_v > 36 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_mb' and (v_v < 100 or v_v > 1000000 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_alert_pct' and (v_v < 10 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_late_days' and (v_v < 0 or v_v > 30 or round(v_v, 1) <> v_v))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'quote_reply_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k in ('creator_pay_days_myr', 'creator_pay_days_other') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k = 'quote_wa_day' and (v_v < 0 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'health_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'health_leaver_months' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_from' and (v_v < 202308 or v_v > 209912 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 12))
       or (v_k = 'analytics_change_pct' and (v_v < 1 or v_v > 50 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_churn_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
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
      /* A planned change saved back to the value in force the day before is
         withdrawn: its row goes, rather than a second row restating it. */
      v_drop := p_from > v_today
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date = p_from)
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date < p_from)
        and public.app_setting(v_k, p_from - 1) = v_v;
      if v_drop then
        delete from public.app_settings s where s.key = v_k and s.from_date = p_from;
      else
        insert into public.app_settings (key, from_date, value, set_by, set_at)
        values (v_k, p_from, v_v, v_me.id, now())
        on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      end if;
      v_name := case v_k when 'lead_followup_hours' then 'Lead follow-up limit' when 'proposal_followup_days' then 'Proposal follow-up limit'
        when 'vic_lead_followup_hours' then 'VIC lead follow-up limit' when 'vic_proposal_followup_days' then 'VIC proposal follow-up limit'
        when 'sst_pct' then 'SST' when 'term_1_3' then 'Under 3 months' when 'term_4_5' then '3-month commitment'
        when 'term_6_11' then '6-month commitment' when 'term_12_23' then '12-month commitment' when 'term_18_23' then '18-month commitment' when 'term_24' then '24-month commitment'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input price per million tokens'
        when 'ai_price_out' then 'AI output price per million tokens' when 'ai_price_search' then 'AI web search price per thousand searches' when 'ai_price_image' then 'AI price per scene picture' when 'meta_checks' then 'Meta checks' when 'client_email_on' then 'Send by email' when 'report_post_links' then 'Posts linked to tasks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
        when 'plan_db_mb' then 'Database plan' when 'plan_db_alert_pct' then 'Database alert'
        when 'timely_pct' then 'On time target' when 'timely_late_days' then 'Lateness target'
        when 'creator_pay_days_myr' then 'Creator payment in MYR' when 'creator_pay_days_other' then 'Creator payment in other currencies'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'quote_wa_day' then 'Website quotations on WhatsApp'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Yearly rise in cost per lead' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend share of the budget' when 'bench_adset_daily' then 'Minimum daily budget per ad set'
        when 'fx_sgd' then 'Singapore dollar rate'
        when 'health_keep_months' then 'Health check-ins kept' when 'health_leaver_months' then 'Leavers'' health data kept'
        when 'abroad_days' then 'Overseas approval' when 'abroad_remind_hours' then 'Overseas reminder'
        when 'analytics_from' then 'Analytics counts from'
        when 'analytics_change_pct' then 'Analytics change threshold' when 'analytics_churn_pct' then 'Analytics quarterly churn alert'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' per S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours', 'abroad_remind_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days') then ' days'
        when v_k in ('quote_reply_days', 'creator_pay_days_myr', 'creator_pay_days_other') then ' working days'
        when v_k = 'quote_wa_day' then ' per day'
        when v_k = 'plan_db_mb' then ' MB'
        when v_k in ('health_keep_months', 'hiring_pool_months', 'hiring_keep_months', 'health_leaver_months') then ' months'
        when v_pre <> '' then '' else '%' end;
      v_fw := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then case when v_was = 1 then 'On' else 'Off' end
              when v_k = 'analytics_from' then coalesce(substr(public.register_day(to_date(v_was::bigint::text, 'YYYYMM')), 3), 'not set') else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') end;
      v_fv := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then case when v_v = 1 then 'On' else 'Off' end
              when v_k = 'analytics_from' then substr(public.register_day(to_date(v_v::bigint::text, 'YYYYMM')), 3) else v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              case when v_drop then v_name || ': planned change withdrawn · ' || v_fw || ' from ' || public.register_day(p_from) ||
                ', stays ' || v_fv else
              case when v_k = 'analytics_from' then v_name || ': ' || v_fw || ' → ' || v_fv || ' · from ' || public.register_day(p_from) else
              v_name || ': ' || case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then '' else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') || ' → ' || v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end end end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

create or replace function public.ops_timeliness(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  out jsonb;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_from date;
  v_to date;
  v_live boolean;
  v_all boolean := public.ops_granted('ops.all', 'view');
begin
  if not public.ops_granted('ops.reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '800 days' then
    return jsonb_build_object('error', 'bad-range');
  end if;
  v_from := (p_from at time zone 'Asia/Kuala_Lumpur')::date;
  v_to := ((p_to - interval '1 microsecond') at time zone 'Asia/Kuala_Lumpur')::date;
  v_live := p_to >= now() - interval '10 minutes';

  with
  base as (
    select t.id, t.task_no, t.title, t.client_id, t.created_at, t.completed_at, t.engagement_id,
           (t.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date as due_d,
           case t.source_type when 'report_ads' then 'ads' when 'report_social' then 'social'
                else case when w.key = 'task' then 'task' else 'content' end end as kind,
           (select a.team_member_id from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc limit 1) as owner_id,
           (select min(e.created_at) from public.ops_task_events e
              join public.ops_workflow_stages s on s.workflow_id = t.workflow_id and s.key = e.to_value ->> 'stage_key'
             where e.task_id = t.id and e.event_type = 'stage_changed' and s.stage_group = 'client_review') as review_at
      from public.ops_tasks t
      join public.ops_workflows w on w.id = t.workflow_id
     where t.cancelled_at is null and t.archived_at is null
       and t.created_at < p_to
       and (t.completed_at is null or t.completed_at >= p_from - interval '120 days')
       and public.ops_task_in_scope(t.id)
  ),
  /* A month's report is delivered the day it was marked sent: the first
     version sent of the month's own report (never one on request). */
  rep as (
    select b.id, min(r.sent_on) as sent_on, max(s.ends) as span_end
      from base b
      join public.ops_engagements e on e.id = b.engagement_id
      cross join lateral public.ops_month_span(e.period, e.start_day) s
      left join public.sm_reports r
        on r.client_id = b.client_id and r.kind = b.kind and r.brand_id is null and not r.on_request
       and r.period_end between s.starts and s.ends and r.sent_on is not null
     where b.kind in ('ads', 'social')
     group by b.id
  ),
  items as (
    select b.*,
           case when b.kind in ('ads', 'social') then coalesce(rp.sent_on, (b.completed_at at time zone 'Asia/Kuala_Lumpur')::date)
                else (coalesce(b.review_at, b.completed_at) at time zone 'Asia/Kuala_Lumpur')::date end as done_d,
           case when b.kind in ('ads', 'social') then rp.span_end
                else (b.created_at at time zone 'Asia/Kuala_Lumpur')::date end as start_d
      from base b
      left join rep rp on rp.id = b.id
  ),
  meas as (
    select x.*,
           case when x.due_d is null then null when x.diff < 0 then 'early' when x.diff = 0 then 'day' else 'late' end as said,
           to_char(coalesce(x.done_d, x.due_d), 'YYYY-MM') as mon,
           case when not x.open and x.start_d is not null then greatest(x.done_d - x.start_d, 0) end as turn
      from (
        select i.*, i.done_d - i.due_d as diff, false as open
          from items i
         where i.done_d between v_from and v_to
        union all
        /* Not delivered and past its due date: late by the days so far. */
        select i.*, v_today - i.due_d as diff, true as open
          from items i
         where i.done_d is null and i.due_d is not null and i.due_d < v_today
           and (i.due_d between v_from and v_to or v_live)
      ) x
  ),
  agg as (
    select grouping(m.owner_id) as g_o, grouping(m.kind) as g_k, grouping(m.mon) as g_m,
           m.owner_id, m.kind, m.mon,
           jsonb_build_object(
             'n', count(m.said),
             'early', count(*) filter (where m.said = 'early'),
             'on_day', count(*) filter (where m.said = 'day'),
             'late', count(*) filter (where m.said = 'late'),
             'late_open', count(*) filter (where m.said = 'late' and m.open),
             'delivered', count(*) filter (where not m.open),
             'late_days', round(avg(m.diff) filter (where m.said = 'late'), 1),
             'lateness', round(avg(greatest(m.diff, 0)) filter (where m.said is not null), 1),
             'lead_days', round(avg(-m.diff) filter (where m.said = 'early'), 1),
             'turn_days', round((percentile_cont(0.5) within group (order by m.turn))::numeric, 1),
             'turn_p90', round((percentile_cont(0.9) within group (order by m.turn))::numeric, 1)) as f
      from meas m
     group by grouping sets ((), (m.owner_id), (m.kind), (m.mon))
  )
  select jsonb_build_object(
           'from', p_from, 'to', p_to,
           'target', jsonb_build_object('pct', coalesce(public.app_setting('timely_pct', v_today), 85),
                                        'late_days', coalesce(public.app_setting('timely_late_days', v_today), 1)),
           'team', coalesce((select a.f from agg a where a.g_o = 1 and a.g_k = 1 and a.g_m = 1), '{}'::jsonb),
           'kinds', coalesce((select jsonb_agg(a.f || jsonb_build_object('kind', a.kind) order by a.kind)
                                from agg a where a.g_k = 0), '[]'::jsonb),
           'months', coalesce((select jsonb_agg(a.f || jsonb_build_object('month', a.mon) order by a.mon)
                                 from agg a where a.g_m = 0), '[]'::jsonb),
           'people', case when v_all then coalesce((
               select jsonb_agg(a.f || jsonb_build_object('team_member_id', a.owner_id, 'name', coalesce(tm.name, 'Unassigned'))
                                order by coalesce(tm.name, 'Unassigned'))
                 from agg a left join public.team_members tm on tm.id = a.owner_id
                where a.g_o = 0), '[]'::jsonb) end,
           'worst', case when v_all then coalesce((
               select jsonb_agg(q.x order by q.d desc, q.due) from (
                 select jsonb_build_object('task_id', m.id, 'task_no', m.task_no, 'title', m.title,
                          'client', c.name, 'owner', tm.name, 'owner_id', m.owner_id, 'kind', m.kind,
                          'due', m.due_d, 'delivered', m.done_d, 'open', m.open, 'days', m.diff) as x,
                        m.diff as d, m.due_d as due
                   from meas m
                   left join public.clients c on c.id = m.client_id
                   left join public.team_members tm on tm.id = m.owner_id
                  where m.said = 'late'
                  order by m.diff desc, m.due_d
                  limit 8) q), '[]'::jsonb) end)
    into out;
  return out;
end $$;
revoke all on function public.ops_timeliness(timestamptz, timestamptz) from public, anon;
grant execute on function public.ops_timeliness(timestamptz, timestamptz) to authenticated;

-- END OF DELIVERY AGAINST THE DUE DATE ---------------------------------------

select public.functions_tidy();
