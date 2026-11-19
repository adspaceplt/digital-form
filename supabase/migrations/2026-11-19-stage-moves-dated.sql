-- ===========================================================================
-- STAGE MOVES DATED WHEN THEY HAPPENED (2026-11-19)
-- ===========================================================================
-- WHY: the user, 2026-11-19: a stage move records the moment it is pressed,
-- so work moved in the portal days after it happened reads late on the
-- Dashboard, in the delivery report and in the performance review ("stages
-- MUST move on the same day same spot same schedule as it auto records on
-- the date"); a move asks its day, today prefilled ("expectations vs
-- actual"). Decided the same day: up to 7 days back, a Business setting;
-- anyone who may move the task; an admin corrects a past move.
--
-- WHAT IT CHANGES
--   * `ops_task_events.recorded_at`: when a row was written. `created_at`
--     stays when it happened, which every figure already reads (on time,
--     delivered, the delivery report, the performance review), so none of
--     them is restated. Rows before this file are taken as recorded when
--     they happened.
--   * Setting `stage_back_days` (7; 0 to 30, 0 turns dating back off),
--     taken by `app_settings_set` (Stage moves dated back, days).
--   * `ops_transition_task_on(p_task, p_next, p_on, …)`: a move on a day
--     before today (Malaysia). Today's, or none, is `ops_transition_task`
--     itself. The day is `future-day` past today, `too-early` before the
--     setting's window (with `days`), `before-last` before the task's last
--     move or its making (with `day`); taken at 18:00 that day, a second
--     after the last move where that day holds it. It makes the move through
--     `ops_transition_task` unchanged, every refusal its own, then dates the
--     rows that move wrote (the move, a skip, delivered, completed; `dated`
--     in the move's detail) and the task's stamps it set (Draft in,
--     delivered, completed, cancelled).
--   * `ops_task_move_redate(p_event, p_on)`: a stage move dated again.
--     Its colleague within the window, or `ops.override` (an admin) any day
--     between the moves either side of it; the rows of the same move and
--     the task's stamps it set follow; filed on the task as `move_dated`
--     (from and to). `not-found`, `denied`, `not-yours`, `future-day`,
--     `too-early`, `before-last`, `after-next`.
--
-- ORDER: this file (it adds only), then the pages. An open page calls
-- `ops_transition_task` as before until it is refreshed. Safe to run twice.
--
-- ROLLBACK: drop function ops_task_move_redate(uuid, date);
-- drop function ops_transition_task_on(uuid, text, date, integer, text, uuid, text);
-- delete from app_settings where key = 'stage_back_days'; run
-- app_settings_set from DELIVERY AGAINST THE DUE DATE again; the column may
-- stay (nothing reads it but these two).
-- ===========================================================================

alter table public.ops_task_events add column if not exists recorded_at timestamptz;
update public.ops_task_events set recorded_at = created_at where recorded_at is null;
alter table public.ops_task_events alter column recorded_at set default now();
alter table public.ops_task_events alter column recorded_at set not null;

insert into public.app_settings (key, from_date, value)
select 'stage_back_days', date '2023-08-14', 7
 where not exists (select 1 from public.app_settings s where s.key = 'stage_back_days');

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
    'timely_pct', 'timely_late_days', 'stage_back_days'];
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
       or (v_k = 'stage_back_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
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
        when 'timely_pct' then 'On time or early target' when 'timely_late_days' then 'Average lateness target'
        when 'stage_back_days' then 'Stage moves dated back'
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
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days') then ' days'
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

/* The window and the bounds a day given for a stage move is held to: none
   past today, none before the setting's window, none before the task's
   previous move (or its making). Answers the moment to stamp, or a refusal. */
create or replace function public.ops_move_day(p_task uuid, p_on date, p_after timestamptz, p_window boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_back integer := coalesce(public.app_setting('stage_back_days', v_today), 7)::integer;
  v_floor timestamptz;
  v_at timestamptz;
begin
  if p_on > v_today then return jsonb_build_object('error', 'future-day'); end if;
  if p_window and p_on < v_today - v_back then
    return jsonb_build_object('error', 'too-early', 'days', v_back);
  end if;
  select greatest(t.created_at, coalesce(p_after, t.created_at)) into v_floor
    from public.ops_tasks t where t.id = p_task;
  if v_floor is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_on < (v_floor at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'before-last',
      'day', public.register_day((v_floor at time zone 'Asia/Kuala_Lumpur')::date));
  end if;
  v_at := (p_on + time '18:00') at time zone 'Asia/Kuala_Lumpur';
  if v_at <= v_floor then v_at := v_floor + interval '1 second'; end if;
  return jsonb_build_object('at', v_at);
end $$;
revoke all on function public.ops_move_day(uuid, date, timestamptz, boolean) from public, anon, authenticated;

create or replace function public.ops_transition_task_on(
  p_task uuid, p_next text, p_on date, p_version integer default null, p_note text default null,
  p_assignee uuid default null, p_skip_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_last timestamptz;
  v_day jsonb;
  v_at timestamptz;
  v_out jsonb;
begin
  if p_on is null or p_on = v_today then
    return public.ops_transition_task(p_task, p_next, p_version, p_note, p_assignee, p_skip_reason);
  end if;
  if public.ops_me().id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select max(e.created_at) into v_last from public.ops_task_events e
   where e.task_id = p_task and e.event_type = 'stage_changed';
  v_day := public.ops_move_day(p_task, p_on, v_last, true);
  if v_day ? 'error' then return v_day; end if;
  v_at := (v_day ->> 'at')::timestamptz;
  v_out := public.ops_transition_task(p_task, p_next, p_version, p_note, p_assignee, p_skip_reason);
  if v_out ? 'error' then return v_out; end if;
  /* The rows this move wrote, in this transaction, take its day. */
  update public.ops_task_events e
     set created_at = v_at,
         detail = case when e.event_type = 'stage_changed'
                       then e.detail || jsonb_build_object('dated', p_on) else e.detail end
   where e.task_id = p_task and e.recorded_at = now()
     and e.event_type in ('stage_changed', 'stage_skipped', 'delivered', 'completed');
  update public.ops_tasks t set
    first_draft_submitted_at = case when t.first_draft_submitted_at = now() then v_at else t.first_draft_submitted_at end,
    delivered_at = case when t.delivered_at = now() then v_at else t.delivered_at end,
    completed_at = case when t.completed_at = now() then v_at else t.completed_at end,
    cancelled_at = case when t.cancelled_at = now() then v_at else t.cancelled_at end
   where t.id = p_task;
  return public.ops_task_json(p_task);
end $$;

create or replace function public.ops_task_move_redate(p_event uuid, p_on date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  ev     public.ops_task_events;
  v_admin boolean;
  v_prev timestamptz;
  v_next timestamptz;
  v_day  jsonb;
  v_at   timestamptz;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_back integer := coalesce(public.app_setting('stage_back_days', v_today), 7)::integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into ev from public.ops_task_events e where e.id = p_event and e.event_type = 'stage_changed';
  if ev.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(ev.task_id) or not public.allowed('ops', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  v_admin := public.ops_granted('ops.override', 'work');
  /* A colleague dates again a move of their own made inside the window; an
     admin any move. */
  if not v_admin and (ev.actor_id is distinct from m.id
       or (ev.recorded_at at time zone 'Asia/Kuala_Lumpur')::date < v_today - v_back) then
    return jsonb_build_object('error', 'not-yours');
  end if;
  perform 1 from public.ops_tasks t where t.id = ev.task_id for update;
  select max(e.created_at) into v_prev from public.ops_task_events e
   where e.task_id = ev.task_id and e.event_type = 'stage_changed' and e.created_at < ev.created_at;
  select min(e.created_at) into v_next from public.ops_task_events e
   where e.task_id = ev.task_id and e.event_type = 'stage_changed' and e.created_at > ev.created_at;
  v_day := public.ops_move_day(ev.task_id, p_on, v_prev, not v_admin);
  if v_day ? 'error' then return v_day; end if;
  v_at := (v_day ->> 'at')::timestamptz;
  if v_next is not null and v_at >= v_next then
    if p_on > (v_next at time zone 'Asia/Kuala_Lumpur')::date then
      return jsonb_build_object('error', 'after-next',
        'day', public.register_day((v_next at time zone 'Asia/Kuala_Lumpur')::date));
    end if;
    v_at := v_next - interval '1 second';
  end if;
  if v_at = ev.created_at then return public.ops_task_json(ev.task_id); end if;
  /* The rows of the same move (one press, one recorded moment) and the
     task's stamps it set follow it. */
  update public.ops_tasks t set
    first_draft_submitted_at = case when t.first_draft_submitted_at = ev.created_at then v_at else t.first_draft_submitted_at end,
    delivered_at = case when t.delivered_at = ev.created_at then v_at else t.delivered_at end,
    completed_at = case when t.completed_at = ev.created_at then v_at else t.completed_at end,
    cancelled_at = case when t.cancelled_at = ev.created_at then v_at else t.cancelled_at end
   where t.id = ev.task_id;
  update public.ops_task_events e
     set created_at = v_at,
         detail = case when e.id = ev.id then e.detail || jsonb_build_object('dated', p_on) else e.detail end
   where e.task_id = ev.task_id and e.recorded_at = ev.recorded_at and e.created_at = ev.created_at
     and e.event_type in ('stage_changed', 'stage_skipped', 'delivered', 'completed');
  perform public.ops_log(ev.task_id, 'move_dated',
    jsonb_build_object('at', ev.created_at, 'event', ev.id),
    jsonb_build_object('at', v_at, 'stage_key', ev.to_value ->> 'stage_key'), '{}'::jsonb);
  return public.ops_task_json(ev.task_id);
end $$;

-- END OF STAGE MOVES DATED WHEN THEY HAPPENED ----------------------------------

select public.functions_tidy();
