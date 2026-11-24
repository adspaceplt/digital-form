-- ===========================================================================
-- TONE SWEEP 8 (2026-11-24)
-- ===========================================================================
-- WHY: a second reader went through every word merged since tone sweep 7
-- (814 lines; the user, 2026-11-25: "run a tone sweep once everything is
-- completed ... since last build"). The database's own words follow the
-- pages' in the same release.
--
-- WHAT IT CHANGES (words only; no stored key, refusal or rule moves)
--   * `quote_change_request`: the team's notice reads Send by {day}
--     ({Weekday}), {time}, as the website quotation's notice does.
--   * `campaign_options_posted_mail`: a creator's payment notice reads Pay
--     by {day} ({Weekday}).
--   * `app_settings_set`: the Activity record names feedback_quiet_months
--     Feedback last requested within, as Settings does.
--   * The performance review email's Chinese subject reads 服务表现评估,
--     where the team has not edited it.
--
-- ORDER: the pages first, then this file. A notice already sent keeps its
-- words.
-- Rollback: run the bands each function was last restated in again
-- (WEBSITE QUOTATION FINDS ITS CLIENT, SAVED WHOLE AND TOLD, PERSONAL DETAILS
-- REVEALED) and the
-- update below in reverse. Safe to run twice.
-- ===========================================================================

create or replace function public.quote_change_request(p_key text, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  o jsonb := public.quote_change_open(p_key);
  q public.quotations;
  cl public.clients;
  c jsonb;
  v_fx numeric;
  v_sel jsonb;
  v_p jsonb;
  v_now timestamptz := now();
  v_body text;
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  select * into cl from public.clients where id = q.client_id;
  if p_sel is null then
    if q.change_requested_at is null then return jsonb_build_object('ok', true, 'again', true); end if;
    update public.quotations set change_request = null, change_requested_at = null where id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.quotation', q.brand, q.ref || ' · changes withdrawn on the quotation link');
    return jsonb_build_object('ok', true);
  end if;
  if q.selection ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  if q.change_requested_at > v_now - interval '1 minute' then return jsonb_build_object('error', 'recent'); end if;
  c := public.quote_change_snap(q);
  if c is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := (c->>'fx')::numeric;
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_sel := public.quote_change_sel(q.selection, p_sel, c->'snap');
  if v_sel ? 'error' then return v_sel; end if;
  -- Unchanged whatever order the platforms were held in.
  if (v_sel - 'platforms') = (q.selection - 'platforms')
     and (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from jsonb_array_elements_text(coalesce(v_sel->'platforms', '[]'::jsonb)) x)
       = (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from jsonb_array_elements_text(coalesce(q.selection->'platforms', '[]'::jsonb)) x) then
    return jsonb_build_object('error', 'unchanged');
  end if;
  v_p := public.quote_fx_out(public.quote_compose(c->'snap', v_sel, q.source <> 'website'), v_fx);
  if v_p ? 'error' then return jsonb_build_object('error', v_p->>'error'); end if;
  update public.quotations
     set change_request = jsonb_build_object('selection', v_sel,
           'month', v_p->'totals'->'month'->'incl', 'once', v_p->'totals'->'once'->'incl', 'version', c->>'version'),
         change_requested_at = v_now, reply_due = public.quote_reply_by(v_now)
   where id = q.id
   returning * into q;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation website', 'client.quotation', q.brand, q.ref || ' · changes requested on the quotation link');
  v_body := q.ref || coalesce(' · ' || coalesce(q.totals->>'currency', 'RM') || ' ' ||
              to_char((v_p->'totals'->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', '')
            || ' · Send by ' || public.register_day((q.reply_due at time zone 'Asia/Kuala_Lumpur')::date)
            || ' (' || trim(to_char(q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMDay')) || '), ' ||
            lower(to_char(q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam'));
  -- Who prepared it and the person in charge are told; where neither is
  -- here, the team who work leads.
  if public.quote_sign_member(q.made_by) is null and public.quote_sign_member(cl.owner) is null then
    perform public.quote_tell(q.client_id, 'quote.changes', 'Changes requested · ' || q.brand, v_body,
      q.id::text || ':' || v_now::text);
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(cl.owner)],
      'quote.changes', 'Changes requested · ' || q.brand, v_body, q.client_id, q.id::text || ':' || v_now::text);
  end if;
  return jsonb_build_object('ok', true, 'reply_due', q.reply_due);
end $$;
revoke all on function public.quote_change_request(text, jsonb) from public;
grant execute on function public.quote_change_request(text, jsonb) to anon, authenticated;

create or replace function public.campaign_options_posted_mail()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.creators; m public.campaigns; v_ref text;
begin
  if new.state is distinct from 'posted' or old.state in ('posted', 'completed') then return null; end if;
  -- Told once a booking: a revert and a second move into Posted tell nobody again.
  if exists (select 1 from public.creator_emails e where e.option_id = new.id and e.purpose in ('request', 'posted')) then return null; end if;
  begin
    perform public.creator_mail_job('request', new.id);
    perform public.creator_mail_job('posted', new.id);
    select * into c from public.creators x where x.id = new.creator_id;
    select * into m from public.campaigns x where x.id = new.campaign_id;
    v_ref := public.creator_job_ref(new.id);
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    select tm.id, 'creator.payment', 'Creator payment request · ' || coalesce(v_ref, c.name),
           c.name || ' · ' || coalesce(m.title, '') || coalesce(' · Pay by ' || public.register_day(new.pay_by) || ' (' || trim(to_char(new.pay_by, 'FMDay')) || ')', ''),
           'https://digital.adspace.me/admin/?s=campaigns&tab=payments&row=' || new.id,
           'creator.payment:' || new.id || ':' || tm.id
      from public.team_members tm
     where tm.active and tm.removed_at is null and not coalesce(tm.system, false)
       and public.allowed_of(tm.id, 'campaigns.pay', 'work')
    on conflict (dedupe_key) do nothing;
  exception when others then
    return null;
  end;
  return null;
end $$;
revoke all on function public.campaign_options_posted_mail() from public, anon, authenticated;
create or replace trigger campaign_options_posted_mail after update of state on public.campaign_options
  for each row execute function public.campaign_options_posted_mail();

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
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'feedback_quiet_months', 'plan_db_mb', 'plan_db_alert_pct',
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'hiring_decision_days', 'verify_code_from',
    'work_start', 'work_end', 'work_lunch_min', 'work_weekend',
    'health_cap_default', 'health_near_pct', 'health_task_hours', 'health_remind_days', 'health_alert',
    'outstation_office_lat', 'outstation_office_lng', 'outstation_accuracy_m', 'outstation_keep_months',
    'reveal_seconds'];
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
    if round(v_v, case when v_k = 'fx_sgd' then 4 when v_k in ('outstation_office_lat', 'outstation_office_lng') then 6 else 2 end) <> v_v
       or (v_k = 'fx_sgd' and (v_v < 0.5 or v_v > 10))
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'task_past_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_invite_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_link_days' and (v_v < 7 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_pool_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'feedback_quiet_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_keep_months' and (v_v < 1 or v_v > 36 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_mb' and (v_v < 100 or v_v > 1000000 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_alert_pct' and (v_v < 10 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_late_days' and (v_v < 0 or v_v > 30 or round(v_v, 1) <> v_v))
       or (v_k = 'stage_back_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_reply_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'session_idle_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'reveal_seconds' and (v_v < 10 or v_v > 600 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_decision_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'quote_reply_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k in ('creator_pay_days_myr', 'creator_pay_days_other') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k = 'quote_wa_day' and (v_v < 0 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'health_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'health_leaver_months' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'health_cap_default' and (v_v < 1 or v_v > 80 or v_v <> trunc(v_v)))
       or (v_k = 'health_near_pct' and (v_v < 50 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'health_task_hours' and (v_v < 0.5 or v_v > 40 or v_v * 2 <> trunc(v_v * 2)))
       or (v_k = 'health_remind_days' and (v_v < 0 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_office_lat' and (v_v < -90 or v_v > 90))
       or (v_k = 'outstation_office_lng' and (v_v < -180 or v_v > 180))
       or (v_k = 'outstation_accuracy_m' and (v_v < 5 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_from' and (v_v < 202308 or v_v > 209912 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 12))
       or (v_k = 'verify_code_from' and (v_v < 20230814 or v_v > 20991231 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 31 or mod(trunc(v_v / 100), 100) not between 1 and 12))
       or (v_k in ('work_start', 'work_end') and (v_v < 0 or v_v > 2345 or v_v <> trunc(v_v) or mod(v_v, 100) not in (0, 15, 30, 45)))
       or (v_k = 'work_lunch_min' and (v_v < 0 or v_v > 180 or v_v <> trunc(v_v) or mod(v_v, 15) <> 0))
       or (v_k = 'work_weekend' and v_v not in (0, 1, 2))
       or (v_k = 'analytics_change_pct' and (v_v < 1 or v_v > 50 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_churn_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k in ('bench_reels_share') and (v_v < 0 or v_v > 100))
       or (v_k = 'bench_ad_spend_pct' and (v_v < 1 or v_v > 100))
       or (v_k = 'bench_cpl_rise' and (v_v < -100 or v_v > 100))
       or (v_k like 'bench_%' and v_k not in ('bench_reels_share', 'bench_ad_spend_pct', 'bench_cpl_rise') and (v_v < 0 or v_v > 10000)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  /* A working day ends after it starts, as the two stand on the From day. */
  if (p_values ? 'work_start' or p_values ? 'work_end')
     and coalesce((p_values ->> 'work_end')::numeric, public.app_setting('work_end', p_from))
      <= coalesce((p_values ->> 'work_start')::numeric, public.app_setting('work_start', p_from)) then
    return jsonb_build_object('error', 'bad-hours');
  end if;
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
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'feedback_quiet_months' then 'Feedback last requested within' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
        when 'plan_db_mb' then 'Database plan' when 'plan_db_alert_pct' then 'Database alert'
        when 'timely_pct' then 'On time or early target' when 'timely_late_days' then 'Average lateness target'
        when 'stage_back_days' then 'Past dates on stage moves'
        when 'hiring_reply_days' then 'Interview reply time'
        when 'session_idle_days' then 'Signed-in devices'
        when 'reveal_seconds' then 'Hidden personal details'
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
        when 'health_cap_default' then 'Health default weekly capacity' when 'health_near_pct' then 'Health near capacity'
        when 'health_task_hours' then 'Health default hours per task' when 'health_remind_days' then 'Health check-in reminder'
        when 'health_alert' then 'Health heavy workload notice'
        when 'outstation_office_lat' then 'Office latitude' when 'outstation_office_lng' then 'Office longitude'
        when 'outstation_accuracy_m' then 'Location accuracy limit' when 'outstation_keep_months' then 'Outstation trips kept'
        when 'abroad_days' then 'Overseas approval' when 'abroad_remind_hours' then 'Overseas reminder'
        when 'analytics_from' then 'Analytics counts from'
        when 'verify_code_from' then 'Document IDs printed from'
        when 'work_start' then 'Working hours start' when 'work_end' then 'Working hours end'
        when 'work_lunch_min' then 'Lunch' when 'work_weekend' then 'Saturday and Sunday'
        when 'analytics_change_pct' then 'Analytics change threshold' when 'analytics_churn_pct' then 'Analytics quarterly churn alert'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' per S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours', 'abroad_remind_hours', 'health_cap_default', 'health_task_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'health_remind_days') then ' days'
        when v_k in ('quote_reply_days', 'creator_pay_days_myr', 'creator_pay_days_other', 'hiring_decision_days') then ' working days'
        when v_k = 'quote_wa_day' then ' per day'
        when v_k = 'plan_db_mb' then ' MB'
        when v_k = 'work_lunch_min' then ' minutes'
        when v_k = 'reveal_seconds' then ' seconds'
        when v_k = 'outstation_accuracy_m' then ' m'
        when v_k in ('outstation_office_lat', 'outstation_office_lng') then ''
        when v_k in ('health_keep_months', 'hiring_pool_months', 'hiring_keep_months', 'feedback_quiet_months', 'health_leaver_months', 'outstation_keep_months') then ' months'
        when v_pre <> '' then '' else '%' end;
      v_fw := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then case when v_was = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then coalesce(public.work_hours_word(v_k, v_was), 'not set')
              when v_k = 'analytics_from' then coalesce(substr(public.register_day(to_date(v_was::bigint::text, 'YYYYMM')), 3), 'not set')
              when v_k = 'verify_code_from' then coalesce(public.register_day(to_date(v_was::bigint::text, 'YYYYMMDD')), 'not set') else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit, 'not set') end;
      v_fv := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then case when v_v = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then public.work_hours_word(v_k, v_v)
              when v_k = 'analytics_from' then substr(public.register_day(to_date(v_v::bigint::text, 'YYYYMM')), 3)
              when v_k = 'verify_code_from' then public.register_day(to_date(v_v::bigint::text, 'YYYYMMDD')) else v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              case when v_drop then v_name || ': planned change withdrawn · ' || v_fw || ' from ' || public.register_day(p_from) ||
                ', stays ' || v_fv else
              case when v_k in ('analytics_from', 'verify_code_from') or (v_k like 'work\_%' and v_k <> 'work_lunch_min') then v_name || ': ' || v_fw || ' → ' || v_fv || ' · from ' || public.register_day(p_from) else
              v_name || ': ' || case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then '' else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit, 'not set') || ' → ' || v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end end end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

update public.feedback_email_templates
   set subject = '服务表现评估 · ADspace'
 where kind = 'review' and lang = 'zh' and subject = '绩效评估 · ADspace';

-- END OF TONE SWEEP 8 --------------------------------------------------------

select public.functions_tidy();
