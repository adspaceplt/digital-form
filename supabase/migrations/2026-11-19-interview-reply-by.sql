-- ===========================================================================
-- INTERVIEW REPLY-BY (2026-11-19)
-- ===========================================================================
-- WHY: the user, 2026-11-19: "the interview request would expire 3 days if
-- they never respond right? ... never inform them in the email how long
-- should they respond?" Asked and answered the same day: three days, a
-- setting; when it passes, the invitation expires and the team is told.
--
-- WHAT IT CHANGES
--   * `hiring_reply_days` (3, 1 to 14): Business settings, Hiring: Time
--     limits (Interview reply time), taken by `app_settings_set`.
--   * `hiring_interviews.reply_by`: stamped as an invitation is made
--     (trigger `hiring_interviews_reply_by`), the earlier of the invitation
--     plus the setting's days and the last time offered; invitations still
--     open are stamped from their own invitation.
--   * The state `expired`: `hiring_interviews_expire()` (pg_cron
--     `hiring-interview-expire`, every fifteen minutes) moves an invitation
--     past its reply-by from Invited to Expired, files it on the candidate
--     and tells the Owners in the bell (`hiring.expired`). Until the job
--     runs, `hiring_interview_row`, `careers_read`, `careers_pick`,
--     `careers_none` and `hiring_mail_prepare` read a passed reply-by as
--     expired themselves, so a time is never chosen after it.
--   * `careers_read` and `hiring_mail_prepare` answer `reply_by`: the
--     candidate's page and the invitation email state it.
--
-- ORDER: this file, then the pages, then hiring-mail (the invitation names
-- the date). An old page meets `expired` as an interview it does not know
-- and draws it as one waiting; an old hiring-mail sends no reply-by line.
-- Safe to run twice.
--
-- ROLLBACK: unschedule `hiring-interview-expire`; drop the trigger, its
-- function and `hiring_interviews_expire()`; set expired rows back to
-- invited; restore the state check without `expired`; run the five
-- functions from HIRING: INTERVIEWS, HIRING OFFERS AND CONTRACTS and
-- ACCESS CLEAN-UP again; `app_settings_set` from STAGE MOVES DATED; delete
-- the setting. The column may stay.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'hiring_reply_days', date '2023-08-14', 3
 where not exists (select 1 from public.app_settings s where s.key = 'hiring_reply_days');

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
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days'];
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

alter table public.hiring_interviews add column if not exists reply_by timestamptz;
alter table public.hiring_interviews drop constraint if exists hiring_interviews_state_check;
alter table public.hiring_interviews add constraint hiring_interviews_state_check
  check (state in ('invited', 'picked', 'none', 'confirmed', 'cancelled', 'replaced', 'expired'));

/* The reply-by date of an invitation: the setting's days after it was made,
   or the last time offered where that comes first. */
create or replace function public.hiring_reply_by(p_invited timestamptz, p_slots timestamptz[])
returns timestamptz language sql stable security definer set search_path = public as $$
  select least(p_invited + make_interval(days => coalesce(public.app_setting('hiring_reply_days',
           (p_invited at time zone 'Asia/Kuala_Lumpur')::date)::int, 3)),
         (select max(s) from unnest(p_slots) s));
$$;
revoke all on function public.hiring_reply_by(timestamptz, timestamptz[]) from public, anon, authenticated;

create or replace function public.hiring_interviews_reply_by()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.reply_by is null then new.reply_by := public.hiring_reply_by(new.invited_at, new.slots); end if;
  return new;
end $$;
revoke all on function public.hiring_interviews_reply_by() from public, anon, authenticated;
drop trigger if exists hiring_interviews_reply_by on public.hiring_interviews;
create trigger hiring_interviews_reply_by before insert on public.hiring_interviews
  for each row execute function public.hiring_interviews_reply_by();

update public.hiring_interviews set reply_by = public.hiring_reply_by(invited_at, slots) where reply_by is null;

/* An invitation's state as the reader meets it: one past its reply-by is
   expired before the job has moved it. */
create or replace function public.hiring_interview_state(i public.hiring_interviews)
returns text language sql stable set search_path = public as $$
  select case when i.state = 'invited' and i.reply_by <= now() then 'expired' else i.state end;
$$;
revoke all on function public.hiring_interview_state(public.hiring_interviews) from public, anon, authenticated;

create or replace function public.hiring_interview_row(i public.hiring_interviews)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object('id', i.id, 'round', i.round, 'slots', to_jsonb(i.slots), 'minutes', i.minutes,
    'mode', i.mode, 'note', i.note, 'state', public.hiring_interview_state(i), 'picked', i.picked, 'picked_at', i.picked_at,
    'candidate_note', i.candidate_note, 'invited_at', i.invited_at, 'reply_by', i.reply_by,
    'invited_by', (select t.name from public.team_members t where t.id = i.invited_by),
    'approved_at', i.approved_at, 'approved_by', (select t.name from public.team_members t where t.id = i.approved_by),
    'meeting_link', i.meeting_link, 'invite_mail', i.invite_mail, 'invite_mail_at', i.invite_mail_at,
    'confirm_mail', i.confirm_mail, 'confirm_mail_at', i.confirm_mail_at));
$$;
revoke all on function public.hiring_interview_row(public.hiring_interviews) from public, anon, authenticated;

/* Every fifteen minutes: an invitation past its reply-by with no time
   chosen expires, filed on the candidate, its Owners told. */
create or replace function public.hiring_interviews_expire()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    update public.hiring_interviews i set state = 'expired', updated_at = now()
      from public.hiring_candidates c
     where c.id = i.candidate_id and i.state = 'invited' and i.reply_by <= now()
    returning i.candidate_id, c.position, i.reply_by
  loop
    perform public.hiring_log(r.candidate_id, 'candidate.interview', 'Invitation expired: no time chosen by ' || public.hiring_when(r.reply_by));
    perform public.hiring_tell(r.candidate_id, 'hiring.expired', 'An interview invitation expired',
      r.position || '. No time was chosen by ' || public.hiring_when(r.reply_by) || '. Invite again from the candidate''s Interview tab.');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.hiring_interviews_expire() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: invitations expire as they are read until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'hiring-interview-expire';
  perform cron.schedule('hiring-interview-expire', '*/15 * * * *', 'select public.hiring_interviews_expire()');
end $$;

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
      'link', case when i.state = 'confirmed' then i.meeting_link end)) end,
    'docs', case when c.stage in ('offer', 'hired') then coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', d.id, 'kind', d.kind,
        'serial', d.serial, 'state', case when d.state = 'sent' and d.reply_by <= now() then 'expired' else d.state end,
        'sent_at', d.sent_at, 'reply_by', d.reply_by, 'signed_at', d.signed_at)) order by d.sent_at)
      from public.hiring_docs d where d.candidate_id = c.id and d.state in ('sent', 'signed', 'confirmed', 'declined')), '[]'::jsonb) end);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

create or replace function public.careers_pick(p_key text, p_slot int)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null for update;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state = 'invited'
   order by invited_at desc limit 1 for update;
  if i.id is null then return jsonb_build_object('error', 'not-open'); end if;
  if i.reply_by <= now() then return jsonb_build_object('error', 'reply-passed'); end if;
  if p_slot is null or p_slot < 1 or p_slot > cardinality(i.slots) then return jsonb_build_object('error', 'bad-slot'); end if;
  if i.slots[p_slot] < now() then return jsonb_build_object('error', 'slot-past'); end if;
  update public.hiring_interviews set state = 'picked', picked = p_slot, picked_at = now(), updated_at = now() where id = i.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = c.id;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (c.id, 'Candidate page', 'candidate.interview', 'Time chosen: ' || public.hiring_when(i.slots[p_slot]));
  perform public.hiring_tell(c.id, 'hiring.picked', 'A candidate chose an interview time',
    c.position || ' · ' || public.hiring_when(i.slots[p_slot]) || '. Approve it to send the confirmation.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_pick(text, int) from public;
grant execute on function public.careers_pick(text, int) to anon, authenticated;

create or replace function public.careers_none(p_key text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  if char_length(coalesce(p_note, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null for update;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state = 'invited'
   order by invited_at desc limit 1 for update;
  if i.id is null then return jsonb_build_object('error', 'not-open'); end if;
  if i.reply_by <= now() then return jsonb_build_object('error', 'reply-passed'); end if;
  update public.hiring_interviews set state = 'none', candidate_note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now() where id = i.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = c.id;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (c.id, 'Candidate page', 'candidate.interview', 'Other times asked for');
  perform public.hiring_tell(c.id, 'hiring.none', 'A candidate asked for other interview times',
    c.position || '. Send new times from the candidate''s Interview tab.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_none(text, text) from public;
grant execute on function public.careers_none(text, text) to anon, authenticated;

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
  if p_kind not in ('invite', 'confirm') then return jsonb_build_object('error', 'bad-kind'); end if;
  return jsonb_build_object('id', i.id, 'kind', p_kind, 'to', c.email, 'name', c.name, 'position', c.position,
    'key', c.link_key, 'mode', i.mode, 'minutes', i.minutes, 'note', i.note, 'link', i.meeting_link,
    'times', (select jsonb_agg(public.hiring_when(s) order by s) from unnest(i.slots) s),
    'when', case when i.picked is not null then public.hiring_when(i.slots[i.picked]) end,
    'reply_by', case when p_kind = 'invite' and i.state = 'invited' then public.hiring_when(i.reply_by) end,
    'sender', me.name, 'reply_to', me.email);
end $$;

select public.functions_tidy();
