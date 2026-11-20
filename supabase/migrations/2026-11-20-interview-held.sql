-- ===========================================================================
-- INTERVIEW HELD (2026-11-20)
-- ===========================================================================
-- WHY: the user, 2026-11-20: a step between the interview and the decision.
-- An Owner (or the Hiring part) marks a confirmed interview held; the
-- candidate is thanked and told by when ADspace will inform them of the
-- outcome; the Owners are reminded before that date; the date can be moved,
-- the candidate told again; any decision clears it.
--
-- WHAT IT CHANGES
--   * `hiring_decision_days` (7, 1 to 30 working days): Business settings,
--     Hiring: Time limits (Decision time), taken by `app_settings_set`.
--   * `hiring_interviews.held_at`, `held_by`, `held_mail`, `held_mail_at`;
--     `hiring_candidates.decide_by`, `decide_note`, `decide_soon_at`,
--     `decide_due_at` (each reminder's send, cleared when the date moves),
--     `decide_moved_at` (the date last changed, so Email again sends the
--     new date's email).
--   * `hiring_workday_add(p_day, p_n)`: a day n working days on (or back),
--     Monday to Friday, never a public holiday; `hiring_decide_by_at(p_at,
--     p_n)`: the end of that working day, 6:00pm Malaysia time.
--   * `hiring_decide_by_suggest()`: the default decision-by and the latest
--     allowed (30 working days), for the question's prefill.
--   * `hiring_interview_held(p_interview, p_decide_by)` and
--     `hiring_decide_by_change(p_interview, p_decide_by, p_note)`: the part
--     or the Owner; `past`, `too-far`, `not-yet` (the interview has not
--     started), `not-confirmed`, `held` / `not-held`, `decided`, `too-long`.
--   * `hiring_interview_cancel` refuses a held interview (`held`).
--   * `hiring_decide`: any decision, and Reopen, clears the decision-by and
--     its reminders.
--   * `hiring_mail_prepare` / `hiring_mail_done` take `held` (the thank-you
--     and the decision date) and `moved` (the new date and its note);
--     `system_emails` files `hiring_held` and `hiring_moved`.
--   * `hiring_interview_row` and `careers_read` answer the held interview
--     and its decision-by; the candidate's page states the date.
--   * `hiring_decide_remind()` (pg_cron `hiring-decide-remind`, 8:30am
--     MYT): two working days before the decision-by and on its morning, each
--     once, the Owners told (`hiring.decide_soon`, `hiring.decide_due`),
--     never the candidate's name.
--
-- ORDER: this file, then hiring-mail (the new kinds), then the pages. An
-- old page never asks the new functions and reads a held interview as
-- confirmed; an old hiring-mail refuses the two new kinds (`bad-request`),
-- so the page says the email was not sent and offers Email again.
-- Safe to run twice.
--
-- ROLLBACK: unschedule `hiring-decide-remind`; drop `hiring_decide_remind`,
-- `hiring_interview_held`, `hiring_decide_by_change`,
-- `hiring_decide_by_suggest`, `hiring_decide_by_at`, `hiring_workday_add`;
-- run `hiring_decide` from HIRING RECORDS HELD, `hiring_interview_cancel`
-- and `hiring_mail_done` from HIRING INTERVIEWS, and `hiring_mail_prepare`,
-- `hiring_interview_row`, `careers_read` and `app_settings_set` from
-- INTERVIEW REPLY-BY again; restore the `system_emails` kind check without
-- the two kinds; delete the setting. The columns may stay.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'hiring_decision_days', date '2023-08-14', 7
 where not exists (select 1 from public.app_settings s where s.key = 'hiring_decision_days');

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
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'hiring_decision_days'];
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
       or (v_k = 'hiring_reply_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_decision_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
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
        when 'stage_back_days' then 'Past dates on stage moves'
        when 'hiring_reply_days' then 'Interview reply time'
        when 'hiring_decision_days' then 'Decision time'
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
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days', 'hiring_reply_days') then ' days'
        when v_k in ('quote_reply_days', 'creator_pay_days_myr', 'creator_pay_days_other', 'hiring_decision_days') then ' working days'
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

alter table public.hiring_interviews add column if not exists held_at timestamptz;
alter table public.hiring_interviews add column if not exists held_by uuid references public.team_members(id) on delete set null;
alter table public.hiring_interviews add column if not exists held_mail text;
alter table public.hiring_interviews add column if not exists held_mail_at timestamptz;
alter table public.hiring_candidates add column if not exists decide_by timestamptz;
alter table public.hiring_candidates add column if not exists decide_note text check (decide_note is null or char_length(decide_note) <= 500);
alter table public.hiring_candidates add column if not exists decide_soon_at timestamptz;
alter table public.hiring_candidates add column if not exists decide_due_at timestamptz;
alter table public.hiring_candidates add column if not exists decide_moved_at timestamptz;

/* The two new emails are filed for Messages' Email log as the others. */
do $$
begin
  if to_regclass('public.system_emails') is not null then
    alter table public.system_emails drop constraint if exists system_emails_kind_check;
    alter table public.system_emails add constraint system_emails_kind_check
      check (kind in ('hiring_invite', 'hiring_confirm', 'hiring_pool', 'hiring_not', 'hiring_doc',
                      'hiring_code', 'invite_team', 'invite_client', 'hiring_held', 'hiring_moved'));
  end if;
end $$;

/* A day n working days after p_day (before it, n below nought): Monday to
   Friday, never a day on the public holidays list. */
create or replace function public.hiring_workday_add(p_day date, p_n int)
returns date language plpgsql stable security definer set search_path = public as $$
declare
  v_at   date := p_day;
  v_left int := abs(coalesce(p_n, 0));
  v_step int := case when coalesce(p_n, 0) < 0 then -1 else 1 end;
begin
  while v_left > 0 loop
    v_at := v_at + v_step;
    if extract(isodow from v_at) < 6 and not exists (select 1 from public.public_holidays h where h.day = v_at) then
      v_left := v_left - 1;
    end if;
  end loop;
  return v_at;
end $$;
revoke all on function public.hiring_workday_add(date, int) from public, anon, authenticated;

/* The end of the working day n working days after a moment: 6:00pm,
   Malaysia time. n null is the setting in force that day. */
create or replace function public.hiring_decide_by_at(p_at timestamptz, p_n int)
returns timestamptz language sql stable security definer set search_path = public as $$
  select (public.hiring_workday_add((p_at at time zone 'Asia/Kuala_Lumpur')::date,
           coalesce(p_n, public.app_setting('hiring_decision_days', (p_at at time zone 'Asia/Kuala_Lumpur')::date)::int, 7))
          + time '18:00') at time zone 'Asia/Kuala_Lumpur';
$$;
revoke all on function public.hiring_decide_by_at(timestamptz, int) from public, anon, authenticated;

/* What Interview held and Change decision date open on: the setting's
   date, and the latest allowed (30 working days on). */
create or replace function public.hiring_decide_by_suggest()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'at', public.hiring_decide_by_at(now(), null), 'latest', public.hiring_decide_by_at(now(), 30),
    'days', coalesce(public.app_setting('hiring_decision_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 7));
end $$;
grant execute on function public.hiring_decide_by_suggest() to authenticated;

/* Interview held: the part's or the Owner's, once the confirmed
   interview's time has begun and before a decision. The decision-by is
   the setting's working days on unless another moment is given. */
create or replace function public.hiring_interview_held(p_interview uuid, p_decide_by timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
  v_at timestamptz;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id for update;
  if i.held_at is not null then return jsonb_build_object('ok', true, 'same', true, 'decide_by', c.decide_by); end if;
  if i.state <> 'confirmed' or i.picked is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  if c.outcome is not null or c.stage <> 'interview' then return jsonb_build_object('error', 'decided'); end if;
  if i.slots[i.picked] > now() then return jsonb_build_object('error', 'not-yet'); end if;
  v_at := coalesce(p_decide_by, public.hiring_decide_by_at(now(), null));
  if v_at <= now() then return jsonb_build_object('error', 'past'); end if;
  if v_at > public.hiring_decide_by_at(now(), 30) then return jsonb_build_object('error', 'too-far'); end if;
  update public.hiring_interviews set held_at = now(), held_by = me.id, held_mail = null, held_mail_at = null, updated_at = now() where id = i.id;
  update public.hiring_candidates set decide_by = v_at, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null,
    last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.interview', 'Interview held. Decision due ' || public.hiring_when(v_at));
  return jsonb_build_object('ok', true, 'decide_by', v_at);
end $$;
grant execute on function public.hiring_interview_held(uuid, timestamptz) to authenticated;

/* Change decision date: a new moment, ahead and within 30 working days,
   and an optional note to the candidate; the reminders start again. */
create or replace function public.hiring_decide_by_change(p_interview uuid, p_decide_by timestamptz, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id for update;
  if i.held_at is null or c.decide_by is null then return jsonb_build_object('error', 'not-held'); end if;
  if c.outcome is not null then return jsonb_build_object('error', 'decided'); end if;
  if p_decide_by is null or p_decide_by <= now() then return jsonb_build_object('error', 'past'); end if;
  if p_decide_by > public.hiring_decide_by_at(now(), 30) then return jsonb_build_object('error', 'too-far'); end if;
  if char_length(coalesce(p_note, '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
  if p_decide_by = c.decide_by and nullif(btrim(coalesce(p_note, '')), '') is not distinct from c.decide_note then
    return jsonb_build_object('ok', true, 'same', true, 'decide_by', c.decide_by);
  end if;
  update public.hiring_candidates set decide_by = p_decide_by, decide_note = nullif(btrim(coalesce(p_note, '')), ''),
    decide_soon_at = null, decide_due_at = null, decide_moved_at = now(), last_step_at = now(), updated_at = now() where id = c.id;
  update public.hiring_interviews set held_mail = null, held_mail_at = null, updated_at = now() where id = i.id;
  perform public.hiring_log(c.id, 'candidate.interview', 'Decision date changed from ' || public.hiring_when(c.decide_by) ||
    ' to ' || public.hiring_when(p_decide_by));
  return jsonb_build_object('ok', true, 'was', c.decide_by, 'decide_by', p_decide_by);
end $$;
grant execute on function public.hiring_decide_by_change(uuid, timestamptz, text) to authenticated;

/* Each morning at 8:30 (MYT): two working days before a decision-by, and
   on its day, its Owners are told once each; a decision clears both. */
create or replace function public.hiring_decide_remind()
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  n int := 0;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_day date;
begin
  for r in
    select c.id, c.position, c.decide_by, c.decide_soon_at, c.decide_due_at from public.hiring_candidates c
     where c.decide_by is not null and c.outcome is null and c.removed_at is null and c.stage = 'interview'
     for update
  loop
    v_day := (r.decide_by at time zone 'Asia/Kuala_Lumpur')::date;
    if v_today = v_day and r.decide_due_at is null then
      update public.hiring_candidates set decide_due_at = now() where id = r.id;
      perform public.hiring_tell(r.id, 'hiring.decide_due', 'A hiring decision is due today',
        'Decide on the ' || r.position || ' candidate by ' || public.hiring_when(r.decide_by) || ' on the Scores tab.');
      n := n + 1;
    elsif v_today < v_day and v_today >= public.hiring_workday_add(v_day, -2) and r.decide_soon_at is null then
      update public.hiring_candidates set decide_soon_at = now() where id = r.id;
      perform public.hiring_tell(r.id, 'hiring.decide_soon', 'A hiring decision is due in two working days',
        'Decide on the ' || r.position || ' candidate by ' || public.hiring_when(r.decide_by) || ' on the Scores tab.');
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.hiring_decide_remind() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: the decision reminders wait until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'hiring-decide-remind';
  perform cron.schedule('hiring-decide-remind', '30 0 * * *', 'select public.hiring_decide_remind()');
end $$;

create or replace function public.hiring_interview_row(i public.hiring_interviews)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object('id', i.id, 'round', i.round, 'slots', to_jsonb(i.slots), 'minutes', i.minutes,
    'mode', i.mode, 'note', i.note, 'state', public.hiring_interview_state(i), 'picked', i.picked, 'picked_at', i.picked_at,
    'candidate_note', i.candidate_note, 'invited_at', i.invited_at, 'reply_by', i.reply_by,
    'invited_by', (select t.name from public.team_members t where t.id = i.invited_by),
    'approved_at', i.approved_at, 'approved_by', (select t.name from public.team_members t where t.id = i.approved_by),
    'meeting_link', i.meeting_link, 'invite_mail', i.invite_mail, 'invite_mail_at', i.invite_mail_at,
    'confirm_mail', i.confirm_mail, 'confirm_mail_at', i.confirm_mail_at,
    'held_at', i.held_at, 'held_by', (select t.name from public.team_members t where t.id = i.held_by),
    'held_mail', i.held_mail, 'held_mail_at', i.held_mail_at,
    'decide_by', (select c.decide_by from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null),
    'decide_note', (select c.decide_note from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null),
    'decide_moved', (select true from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null and c.decide_moved_at is not null)));
$$;
revoke all on function public.hiring_interview_row(public.hiring_interviews) from public, anon, authenticated;

create or replace function public.hiring_interview_cancel(p_interview uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare i public.hiring_interviews; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if i.state in ('cancelled', 'replaced') then return jsonb_build_object('ok', true, 'same', true); end if;
  if i.held_at is not null then return jsonb_build_object('error', 'held'); end if;
  update public.hiring_interviews set state = 'cancelled', updated_at = now() where id = i.id;
  perform public.hiring_log(i.candidate_id, 'candidate.interview', 'Interview cancelled');
  return jsonb_build_object('ok', true, 'event', i.meeting_event_id, 'had_meet', i.meeting_event_id is not null);
end $$;
grant execute on function public.hiring_interview_cancel(uuid) to authenticated;

create or replace function public.hiring_mail_done(p_interview uuid, p_kind text, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare i public.hiring_interviews; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') or coalesce(p_kind, '') not in ('invite', 'confirm', 'held', 'moved') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if p_kind = 'invite' then update public.hiring_interviews set invite_mail = p_status, invite_mail_at = now(), updated_at = now() where id = i.id;
  elsif p_kind = 'confirm' then update public.hiring_interviews set confirm_mail = p_status, confirm_mail_at = now(), updated_at = now() where id = i.id;
  else update public.hiring_interviews set held_mail = p_status, held_mail_at = now(), updated_at = now() where id = i.id; end if;
  perform public.hiring_log(i.candidate_id, 'candidate.email',
    case p_kind when 'invite' then 'Invitation' when 'confirm' then 'Confirmation'
      when 'held' then 'Decision date' else 'New decision date' end || case p_status when 'sent' then ' emailed'
      when 'unknown' then ' emailed, not confirmed' else ' not emailed' || coalesce(': ' || left(p_error, 120), '') end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_mail_done(uuid, text, text, text) to authenticated;

/* The part's or the Owner's decision: Proceed, Keep in talent pool, Not
   proceed, or Reopen (the way back). Any outcome but Proceed withdraws
   the documents still waiting on the candidate's answer. Every one,
   Reopen too, clears the decision-by and its reminders (INTERVIEW HELD). */
create or replace function public.hiring_decide(p_id uuid, p_outcome text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  v_back text;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_outcome, '') not in ('proceed', 'pool', 'not', 'reopen') then return jsonb_build_object('error', 'bad-outcome'); end if;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage = 'hired' then return jsonb_build_object('error', 'closed'); end if;
  if p_outcome = 'reopen' then
    if c.outcome is null then return jsonb_build_object('ok', true, 'same', true); end if;
    v_back := case when exists (select 1 from public.hiring_interviews i where i.candidate_id = c.id and i.state = 'confirmed') then 'interview'
      when exists (select 1 from public.hiring_interviews i where i.candidate_id = c.id and i.state in ('invited', 'picked', 'none')) then 'invited'
      else 'new' end;
    update public.hiring_candidates set stage = v_back, outcome = null, outcome_note = null, outcome_by = null, outcome_at = null,
      pool_consent = null, pool_until = null, outcome_mail = null, outcome_mail_at = null,
      decide_by = null, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null, last_step_at = now(), updated_at = now()
     where id = c.id;
    update public.hiring_docs set state = 'withdrawn', updated_at = now() where candidate_id = c.id and state = 'sent';
    perform public.hiring_log(c.id, 'candidate.decided', 'Reopened');
    return jsonb_build_object('ok', true, 'was', c.outcome, 'note', c.outcome_note);
  end if;
  if c.outcome = p_outcome then return jsonb_build_object('ok', true, 'same', true); end if;
  update public.hiring_candidates set
    stage = case p_outcome when 'proceed' then 'offer' when 'pool' then 'pool' else 'closed' end,
    outcome = p_outcome, outcome_note = nullif(btrim(coalesce(p_note, '')), ''), outcome_by = me.id, outcome_at = now(),
    pool_consent = case when p_outcome = 'pool' then 'asked' end, pool_until = null, outcome_mail = null, outcome_mail_at = null,
    decide_by = null, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null,
    last_step_at = now(), updated_at = now()
   where id = c.id;
  update public.hiring_interviews set state = 'cancelled', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state in ('invited', 'picked', 'none');
  update public.hiring_docs set state = 'withdrawn', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state = 'sent';
  perform public.hiring_log(c.id, 'candidate.decided',
    case p_outcome when 'proceed' then 'Proceed' when 'pool' then 'Keep in talent pool' else 'Not proceed' end);
  return jsonb_build_object('ok', true, 'was', c.outcome, 'email', p_outcome in ('pool', 'not'));
end $$;
grant execute on function public.hiring_decide(uuid, text, text) to authenticated;

create or replace function public.careers_read(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_state text;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() and not (c.stage = 'pool' and c.pool_consent = 'yes') then
    return jsonb_build_object('error', 'expired');
  end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state <> 'replaced'
   order by invited_at desc limit 1;
  v_state := case when i.id is null then null else public.hiring_interview_state(i) end;
  return jsonb_build_object('ok', true, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage = 'new' or (c.stage = 'pool' and c.outcome is null) then 'received' else c.stage end, 'received_at', c.created_at,
    'pool', case when c.stage = 'pool' and c.outcome = 'pool' then jsonb_strip_nulls(jsonb_build_object('consent', c.pool_consent,
      'until', c.pool_until, 'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12))) end,
    'interview', case when i.id is null or i.state = 'cancelled' or c.stage in ('pool', 'closed') then null else jsonb_strip_nulls(jsonb_build_object(
      'state', v_state, 'slots', case when v_state = 'invited' then to_jsonb(i.slots) end, 'minutes', i.minutes,
      'mode', i.mode, 'note', i.note, 'at', case when i.picked is not null then i.slots[i.picked] end,
      'reply_by', case when v_state = 'invited' then i.reply_by end,
      'link', case when i.state = 'confirmed' and i.held_at is null then i.meeting_link end,
      'held', case when i.held_at is not null then true end,
      'decide_by', case when i.held_at is not null and c.outcome is null then c.decide_by end)) end,
    'docs', case when c.stage in ('offer', 'hired') then coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', d.id, 'kind', d.kind,
        'serial', d.serial, 'state', case when d.state = 'sent' and d.reply_by <= now() then 'expired' else d.state end,
        'sent_at', d.sent_at, 'reply_by', d.reply_by, 'signed_at', d.signed_at)) order by d.sent_at)
      from public.hiring_docs d where d.candidate_id = c.id and d.state in ('sent', 'signed', 'confirmed', 'declined')), '[]'::jsonb) end);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

create or replace function public.hiring_mail_prepare(p_interview uuid, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
begin
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  select * into i from public.hiring_interviews where id = p_interview;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_kind = 'invite' and public.hiring_interview_state(i) not in ('invited', 'none') then return jsonb_build_object('error', 'not-open'); end if;
  if p_kind = 'confirm' and i.state <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed'); end if;
  if p_kind = 'confirm' and i.mode = 'online' and i.meeting_link is null then return jsonb_build_object('error', 'no-meet'); end if;
  if p_kind in ('held', 'moved') and (i.held_at is null or c.decide_by is null or c.outcome is not null) then
    return jsonb_build_object('error', 'not-held');
  end if;
  if p_kind not in ('invite', 'confirm', 'held', 'moved') then return jsonb_build_object('error', 'bad-kind'); end if;
  return jsonb_build_object('id', i.id, 'kind', p_kind, 'to', c.email, 'name', c.name, 'position', c.position,
    'key', c.link_key, 'mode', i.mode, 'minutes', i.minutes, 'note', i.note, 'link', i.meeting_link,
    'times', (select jsonb_agg(public.hiring_when(s) order by s) from unnest(i.slots) s),
    'when', case when i.picked is not null then public.hiring_when(i.slots[i.picked]) end,
    'reply_by', case when p_kind = 'invite' and i.state = 'invited' then public.hiring_when(i.reply_by) end,
    'decide_by', case when p_kind in ('held', 'moved') then public.hiring_when(c.decide_by) end,
    'decide_note', case when p_kind = 'moved' then c.decide_note end,
    'sender', me.name, 'reply_to', me.email);
end $$;

-- END OF INTERVIEW HELD ----------------------------------------------------

select public.functions_tidy();
