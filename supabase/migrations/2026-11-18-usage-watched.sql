-- ===========================================================================
-- USAGE AND LIMITS WATCHED (2026-11-18)
-- ===========================================================================
-- WHY: the user, 2026-11-18: "the more important checks would be the usage,
-- the limits, the charges that could incurred". What the portal spends is
-- read in one place, each month against the last, and the admins are told
-- before a plan's limit is reached, never after.
--
-- WHAT IT CHANGES
--   * `usage_report(p_month)` (Business settings at View): the month's use
--     against the month before: the database's size against the plan
--     (`plan_db_mb`, 500, the Free plan) and its five largest tables, AI
--     runs, tokens and estimated US$ (priced as AI usage prices them), emails
--     sent (clients, creators, suppliers, the portal's own), WhatsApp
--     messages, and the last S3 report's files and bytes. A month ahead of
--     this one, or none, is this month.
--   * `usage_watch(p_now)` (pg_cron `usage-watch`, 09:13 MYT daily; no page
--     calls it): on the 1st, each active admin is told last month's use
--     (kind `usage.month`); any day the database passes `plan_db_alert_pct`
--     (80) of the plan, each is told once a month (kind `usage.limit`).
--   * Settings `plan_db_mb` and `plan_db_alert_pct`, seeded once, and taken
--     by `app_settings_set` (Database plan, MB; Database alert, %).
--
-- ORDER: this file (connector), then the page (Settings: Usage). An open page
-- calls nothing new until it is refreshed. Safe to run twice.
--
-- ROLLBACK: drop function usage_report(date), usage_watch(timestamptz);
-- select cron.unschedule('usage-watch'); delete the two settings; run
-- app_settings_set from TERMS BY COMMITMENT again.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select k.key, date '2023-08-14', k.value
  from (values ('plan_db_mb', 500), ('plan_db_alert_pct', 80)) k(key, value)
 where not exists (select 1 from public.app_settings s where s.key = k.key);

/* The plan's two figures are Business settings an admin edits, so the
   one function that sets them takes them (app_settings_set, restated from
   TERMS BY COMMITMENT with the two keys added). */
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
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'plan_db_mb', 'plan_db_alert_pct'];
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
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days') then ' days'
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

create or replace function public.usage_month_of(p_from date, p_to date)
returns jsonb
language sql stable security definer set search_path = public as $$
  /* One month's use, Malaysia's days [p_from, p_to). */
  with a as (
    select count(*) as runs, coalesce(sum(d.input_tokens), 0) as tin, coalesce(sum(d.output_tokens), 0) as tout,
           coalesce(sum((coalesce(d.input_tokens, 0) * coalesce(public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0)
                       + coalesce(d.output_tokens, 0) * coalesce(public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0)) / 1000000.0
                       + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0
                       + case when d.purpose = 'picture' and coalesce(d.model, '') like 'gemini%'
                              then coalesce(public.app_setting('ai_price_image', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0.07) else 0 end), 0) as usd
      from public.ai_drafts d
     where d.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur'
       and d.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur'
  ), m as (
    select (select count(*) from public.client_emails e where e.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and e.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur')
         + (select count(*) from public.creator_emails e where e.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and e.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur')
         + (select count(*) from public.supplier_emails e where e.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and e.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur')
         + (select count(*) from public.system_emails e where e.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and e.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur') as emails,
           (select count(*) from public.wa_outbox w where w.created_at >= p_from::timestamp at time zone 'Asia/Kuala_Lumpur' and w.created_at < p_to::timestamp at time zone 'Asia/Kuala_Lumpur') as whatsapp
  )
  select jsonb_build_object('ai_runs', a.runs, 'ai_tokens_in', a.tin, 'ai_tokens_out', a.tout, 'ai_usd', round(a.usd::numeric, 2),
                            'emails', m.emails, 'whatsapp', m.whatsapp)
    from a, m
$$;
revoke all on function public.usage_month_of(date, date) from public, anon, authenticated;

create or replace function public.usage_report(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_m date;
  v_size bigint := pg_database_size(current_database());
  v_limit numeric;
begin
  if not public.ops_granted('team.settings', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_m := date_trunc('month', least(coalesce(p_month, v_today), v_today))::date;
  v_limit := coalesce(public.app_setting('plan_db_mb', v_today), 500);
  return jsonb_build_object(
    'month', v_m,
    'this', public.usage_month_of(v_m, least((v_m + interval '1 month')::date, v_today + 1)),
    'last', public.usage_month_of((v_m - interval '1 month')::date, v_m),
    'db', jsonb_build_object('bytes', v_size, 'limit_mb', v_limit,
            'alert_pct', coalesce(public.app_setting('plan_db_alert_pct', v_today), 80),
            'pct', round(v_size / (v_limit * 1048576.0) * 100, 1),
            'tables', coalesce((select jsonb_agg(jsonb_build_object('name', t.relname, 'bytes', t.b) order by t.b desc)
                                  from (select c.relname, pg_total_relation_size(c.oid) as b
                                          from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                         where n.nspname = 'public' and c.relkind = 'r'
                                         order by 2 desc limit 5) t), '[]'::jsonb)),
    's3', (select jsonb_build_object('ran_at', s.ran_at, 'files', s.listed, 'bytes', s.listed_bytes)
             from public.s3_sweeps s where coalesce(s.failed, 0) = 0 and s.listed is not null
            order by s.ran_at desc limit 1));
end $$;
grant execute on function public.usage_report(date) to authenticated;

create or replace function public.usage_watch(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (p_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_m date := date_trunc('month', v_today)::date;
  v_last jsonb;
  v_size bigint := pg_database_size(current_database());
  v_limit numeric := coalesce(public.app_setting('plan_db_mb', v_today), 500);
  v_alert numeric := coalesce(public.app_setting('plan_db_alert_pct', v_today), 80);
  v_pct numeric;
  v_told int := 0;
  v_n int;
  v_words text;
begin
  v_pct := round(v_size / (v_limit * 1048576.0) * 100, 1);
  if extract(day from v_today) = 1 then
    v_last := public.usage_month_of((v_m - interval '1 month')::date, v_m);
    v_words := concat_ws(' · ',
      'Database ' || round(v_size / 1048576.0) || ' MB of ' || v_limit || ' MB',
      'AI ' || (v_last ->> 'ai_runs') || case when (v_last ->> 'ai_runs')::int = 1 then ' run' else ' runs' end
            || ', about US$ ' || to_char((v_last ->> 'ai_usd')::numeric, 'FM999,990.00'),
      (v_last ->> 'emails') || case when (v_last ->> 'emails')::int = 1 then ' email' else ' emails' end,
      (v_last ->> 'whatsapp') || ' WhatsApp') || '.';
    insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
    select t.id, 'usage.month', 'Usage for ' || (array['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sept','Oct','Nov','Dec'])[extract(month from (v_m - interval '1 month'))::int] || ' ' || extract(year from (v_m - interval '1 month'))::int, v_words,
           'usage.month.' || to_char(v_m, 'YYYY-MM') || '.' || t.id
      from public.team_members t
     where t.active and t.is_admin
    on conflict (dedupe_key) do nothing;
    get diagnostics v_n = row_count; v_told := v_told + v_n;
  end if;
  if v_pct >= v_alert then
    insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
    select t.id, 'usage.limit', 'Database near its limit',
           'The database holds ' || round(v_size / 1048576.0) || ' MB of the plan''s ' || v_limit || ' MB (' || v_pct || '%).',
           'usage.limit.' || to_char(v_m, 'YYYY-MM') || '.' || t.id
      from public.team_members t
     where t.active and t.is_admin
    on conflict (dedupe_key) do nothing;
    get diagnostics v_n = row_count; v_told := v_told + v_n;
  end if;
  return jsonb_build_object('db_pct', v_pct, 'told', v_told);
end $$;
revoke all on function public.usage_watch(timestamptz) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: usage is not watched until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'usage-watch';
  perform cron.schedule('usage-watch', '13 1 * * *', 'select public.usage_watch()');
end $$;

-- END OF USAGE AND LIMITS WATCHED --------------------------------------------

select public.functions_tidy();
