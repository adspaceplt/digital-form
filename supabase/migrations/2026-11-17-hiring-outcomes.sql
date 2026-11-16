-- ===========================================================================
-- HIRING OUTCOMES — scores per position, the decision, the talent pool and
-- the candidate's data kept for a time (2026-11-17, release H2 step C)
-- ===========================================================================
-- WHY (HR-SPEC.md decisions 3, 13; PDPA 2010): everyone on a candidate scores
-- them against the position's scorecard; the part or the Owner decides
-- Proceed, Keep in talent pool or Not proceed (and may reopen it); a
-- candidate kept in the pool is asked on their page to agree, and is kept
-- `hiring_pool_months` (12) from their agreement, then removed; one not
-- agreeing within the link's days, and a closed or removed candidate after
-- `hiring_keep_months` (12), are removed the same way. A removed candidate's
-- CV file is queued for the console to take out of Storage (SQL cannot).
--
-- WHAT IT CHANGES
--   * `hiring_scorecards` (a position's criteria, Standard for any other),
--     `hiring_scores` (a colleague's scores a candidate), `hiring_files_gone`
--     (RLS on, no policy, no grant).
--   * `hiring_candidates` gains the outcome, its note, who and when, the
--     pool's consent and end, and the outcome email's state.
--   * `hiring_scorecards_list`, `hiring_scorecard_save`,
--     `hiring_scorecard_delete`, `hiring_outcome_of`, `hiring_score_save`,
--     `hiring_score_remove`, `hiring_decide`, `hiring_outcome_mail_prepare`,
--     `hiring_outcome_mail_done`, `hiring_files_gone_list`,
--     `hiring_files_gone_done`; anon `careers_pool`; `careers_read` restated
--     with the outcome; `hiring_retention` (pg_cron `hiring-retention`,
--     03:50 MYT daily).
--   * Business settings `hiring_pool_months` (12), `hiring_keep_months` (12),
--     `app_settings_set` restated whole.
--
-- ORDER: this file (connector), then hiring-mail deployed, then the pages.
-- Safe to run twice. ROLLBACK: unschedule `hiring-retention`, drop the three
-- tables, the new columns and functions; careers_read and app_settings_set
-- as HIRING INTERVIEWS left them.
-- ===========================================================================

-- HIRING OUTCOMES -------------------------------------------------------------

create table if not exists public.hiring_scorecards (
  id         uuid primary key default gen_random_uuid(),
  position   text not null check (char_length(position) between 2 and 80),
  criteria   jsonb not null check (jsonb_typeof(criteria) = 'array' and jsonb_array_length(criteria) between 3 and 8),
  standard   boolean not null default false,
  updated_by uuid references public.team_members(id) on delete set null,
  updated_at timestamptz not null default now()
);
create unique index if not exists hiring_scorecards_position_idx on public.hiring_scorecards (lower(position));
create unique index if not exists hiring_scorecards_standard_idx on public.hiring_scorecards (standard) where standard;
alter table public.hiring_scorecards enable row level security;
revoke all on table public.hiring_scorecards from public, anon, authenticated;
insert into public.hiring_scorecards (position, criteria, standard)
select 'Standard', '["Communication", "Relevant skills", "Experience", "Attitude", "Fit with the team"]'::jsonb, true
 where not exists (select 1 from public.hiring_scorecards s where s.standard);

create table if not exists public.hiring_scores (
  candidate_id   uuid not null references public.hiring_candidates(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  scores         jsonb not null,
  recommend      text not null check (recommend in ('proceed', 'pool', 'not')),
  note           text check (note is null or char_length(note) <= 1000),
  updated_at     timestamptz not null default now(),
  primary key (candidate_id, team_member_id)
);
alter table public.hiring_scores enable row level security;
revoke all on table public.hiring_scores from public, anon, authenticated;

create table if not exists public.hiring_files_gone (
  path       text primary key,
  queued_at  timestamptz not null default now()
);
alter table public.hiring_files_gone enable row level security;
revoke all on table public.hiring_files_gone from public, anon, authenticated;

alter table public.hiring_candidates add column if not exists outcome text check (outcome is null or outcome in ('proceed', 'pool', 'not'));
alter table public.hiring_candidates add column if not exists outcome_note text check (outcome_note is null or char_length(outcome_note) <= 1000);
alter table public.hiring_candidates add column if not exists outcome_by uuid references public.team_members(id) on delete set null;
alter table public.hiring_candidates add column if not exists outcome_at timestamptz;
alter table public.hiring_candidates add column if not exists pool_consent text check (pool_consent is null or pool_consent in ('asked', 'yes', 'no'));
alter table public.hiring_candidates add column if not exists pool_until timestamptz;
alter table public.hiring_candidates add column if not exists outcome_mail text;
alter table public.hiring_candidates add column if not exists outcome_mail_at timestamptz;

insert into public.app_settings (key, from_date, value)
select 'hiring_pool_months', date '2023-08-14', 12
 where not exists (select 1 from public.app_settings s where s.key = 'hiring_pool_months');
insert into public.app_settings (key, from_date, value)
select 'hiring_keep_months', date '2023-08-14', 12
 where not exists (select 1 from public.app_settings s where s.key = 'hiring_keep_months');

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
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months'];
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
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 17 months' when 'term_18_23' then '18 to 23 months' when 'term_24' then '24 months and more'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input price per million tokens'
        when 'ai_price_out' then 'AI output price per million tokens' when 'ai_price_search' then 'AI web search price per thousand searches' when 'ai_price_image' then 'AI price per scene picture' when 'meta_checks' then 'Meta checks' when 'client_email_on' then 'Send by email' when 'report_post_links' then 'Posts linked to tasks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
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
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

/* The scorecard a candidate is scored on: their position's, else Standard. */
create or replace function public.hiring_scorecard_for(p_position text)
returns public.hiring_scorecards language sql stable security definer set search_path = public as $$
  select * from public.hiring_scorecards s
   where lower(s.position) = lower(btrim(coalesce(p_position, ''))) or s.standard
   order by s.standard limit 1;
$$;
revoke all on function public.hiring_scorecard_for(text) from public, anon, authenticated;

create or replace function public.hiring_scorecards_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'position', s.position,
    'criteria', s.criteria, 'standard', s.standard, 'updated_at', s.updated_at) order by s.standard desc, lower(s.position))
    from public.hiring_scorecards s), '[]'::jsonb));
end $$;
grant execute on function public.hiring_scorecards_list() to authenticated;

create or replace function public.hiring_scorecard_save(p_id uuid, p_position text, p_criteria jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s public.hiring_scorecards;
  v_pos text := regexp_replace(btrim(coalesce(p_position, '')), '\s+', ' ', 'g');
  v_crit jsonb;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_criteria) is distinct from 'array' then return jsonb_build_object('error', 'bad-criteria'); end if;
  select coalesce(jsonb_agg(to_jsonb(x.t) order by x.n), '[]'::jsonb) into v_crit
    from (select regexp_replace(btrim(e.v), '\s+', ' ', 'g') t, e.n from jsonb_array_elements_text(p_criteria) with ordinality e(v, n)
           where btrim(e.v) <> '') x;
  if jsonb_array_length(v_crit) < 3 or jsonb_array_length(v_crit) > 8
     or exists (select 1 from jsonb_array_elements_text(v_crit) c where char_length(c) < 2 or char_length(c) > 60)
     or (select count(distinct lower(c)) from jsonb_array_elements_text(v_crit) c) <> jsonb_array_length(v_crit) then
    return jsonb_build_object('error', 'bad-criteria');
  end if;
  if p_id is not null then
    select * into s from public.hiring_scorecards where id = p_id for update;
    if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if s.standard then v_pos := s.position; end if;
  end if;
  if char_length(v_pos) < 2 or char_length(v_pos) > 80 then return jsonb_build_object('error', 'bad-position'); end if;
  if exists (select 1 from public.hiring_scorecards x where lower(x.position) = lower(v_pos) and x.id is distinct from p_id) then
    return jsonb_build_object('error', 'taken');
  end if;
  if s.id is null then
    insert into public.hiring_scorecards (position, criteria, updated_by) values (v_pos, v_crit, me.id) returning * into s;
  else
    update public.hiring_scorecards set position = v_pos, criteria = v_crit, updated_by = me.id, updated_at = now() where id = s.id returning * into s;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.email, 'team.changed', 'Interview scorecards', s.position || ': ' || (select string_agg(c, ', ') from jsonb_array_elements_text(s.criteria) c));
  return jsonb_build_object('ok', true, 'id', s.id);
end $$;
grant execute on function public.hiring_scorecard_save(uuid, text, jsonb) to authenticated;

create or replace function public.hiring_scorecard_delete(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); s public.hiring_scorecards;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.hiring_scorecards where id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if s.standard then return jsonb_build_object('error', 'standard'); end if;
  delete from public.hiring_scorecards where id = s.id;
  insert into public.activity_log (actor, action, subject, detail) values (me.email, 'team.changed', 'Interview scorecards', s.position || ' deleted');
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_scorecard_delete(uuid) to authenticated;

/* A candidate's scorecard, every score on them, the averages and the
   decision; anyone on the candidate reads it. */
create or replace function public.hiring_outcome_of(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  s public.hiring_scorecards;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  s := public.hiring_scorecard_for(c.position);
  return jsonb_build_object('ok', true, 'role', v_role,
    'scorecard', jsonb_build_object('position', s.position, 'criteria', s.criteria, 'standard', s.standard),
    'scores', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'mine', t.id = me.id, 'scores', x.scores,
        'recommend', x.recommend, 'note', x.note, 'updated_at', x.updated_at,
        'total', (select round(avg((v.value)::numeric), 1) from jsonb_each_text(x.scores) v)) order by (t.id <> me.id), x.updated_at)
      from public.hiring_scores x join public.team_members t on t.id = x.team_member_id where x.candidate_id = c.id), '[]'::jsonb),
    'outcome', jsonb_strip_nulls(jsonb_build_object('outcome', c.outcome, 'note', c.outcome_note, 'at', c.outcome_at,
      'by', (select t.name from public.team_members t where t.id = c.outcome_by), 'pool_consent', c.pool_consent,
      'pool_until', c.pool_until, 'mail', c.outcome_mail, 'mail_at', c.outcome_mail_at)));
end $$;
grant execute on function public.hiring_outcome_of(uuid) to authenticated;

create or replace function public.hiring_score_save(p_id uuid, p_scores jsonb, p_recommend text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  s public.hiring_scorecards;
  v_clean jsonb := '{}'::jsonb;
  v_name text;
  v_was public.hiring_scores;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.stage in ('hired', 'closed') then return jsonb_build_object('error', 'closed'); end if;
  if coalesce(p_recommend, '') not in ('proceed', 'pool', 'not') then return jsonb_build_object('error', 'bad-recommend'); end if;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  if jsonb_typeof(p_scores) is distinct from 'object' then return jsonb_build_object('error', 'bad-score'); end if;
  s := public.hiring_scorecard_for(c.position);
  for v_name in select jsonb_array_elements_text(s.criteria) loop
    if jsonb_typeof(p_scores -> v_name) is distinct from 'number' or (p_scores ->> v_name)::numeric not in (1, 2, 3, 4, 5) then
      return jsonb_build_object('error', 'incomplete', 'criterion', v_name);
    end if;
    v_clean := v_clean || jsonb_build_object(v_name, (p_scores ->> v_name)::int);
  end loop;
  select * into v_was from public.hiring_scores where candidate_id = c.id and team_member_id = me.id;
  insert into public.hiring_scores (candidate_id, team_member_id, scores, recommend, note, updated_at)
  values (c.id, me.id, v_clean, p_recommend, nullif(btrim(coalesce(p_note, '')), ''), now())
  on conflict (candidate_id, team_member_id) do update set scores = excluded.scores, recommend = excluded.recommend,
    note = excluded.note, updated_at = now();
  perform public.hiring_log(c.id, 'candidate.scored', case when v_was.candidate_id is null then 'Scores added' else 'Scores changed' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_score_save(uuid, jsonb, text, text) to authenticated;

create or replace function public.hiring_score_remove(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); x public.hiring_scores;
begin
  if public.hiring_role(p_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from public.hiring_scores where candidate_id = p_id and team_member_id = me.id returning * into x;
  if x.candidate_id is null then return jsonb_build_object('error', 'not-found'); end if;
  perform public.hiring_log(p_id, 'candidate.scored', 'Scores removed');
  return jsonb_build_object('ok', true, 'scores', x.scores, 'recommend', x.recommend, 'note', x.note);
end $$;
grant execute on function public.hiring_score_remove(uuid) to authenticated;

/* The part's or the Owner's decision: Proceed, Keep in talent pool, Not
   proceed, or Reopen (the way back). */
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
      pool_consent = null, pool_until = null, outcome_mail = null, outcome_mail_at = null, last_step_at = now(), updated_at = now()
     where id = c.id;
    perform public.hiring_log(c.id, 'candidate.decided', 'Reopened');
    return jsonb_build_object('ok', true, 'was', c.outcome, 'note', c.outcome_note);
  end if;
  if c.outcome = p_outcome then return jsonb_build_object('ok', true, 'same', true); end if;
  update public.hiring_candidates set
    stage = case p_outcome when 'proceed' then 'offer' when 'pool' then 'pool' else 'closed' end,
    outcome = p_outcome, outcome_note = nullif(btrim(coalesce(p_note, '')), ''), outcome_by = me.id, outcome_at = now(),
    pool_consent = case when p_outcome = 'pool' then 'asked' end, pool_until = null, outcome_mail = null, outcome_mail_at = null,
    last_step_at = now(), updated_at = now()
   where id = c.id;
  update public.hiring_interviews set state = 'cancelled', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state in ('invited', 'picked', 'none');
  perform public.hiring_log(c.id, 'candidate.decided',
    case p_outcome when 'proceed' then 'Proceed' when 'pool' then 'Keep in talent pool' else 'Not proceed' end);
  return jsonb_build_object('ok', true, 'was', c.outcome, 'email', p_outcome in ('pool', 'not'));
end $$;
grant execute on function public.hiring_decide(uuid, text, text) to authenticated;

/* hiring-mail's, asked as the caller: the email a decision sends. */
create or replace function public.hiring_outcome_mail_prepare(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
begin
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.outcome not in ('pool', 'not') then return jsonb_build_object('error', 'no-email'); end if;
  return jsonb_build_object('id', c.id, 'kind', c.outcome, 'to', c.email, 'name', c.name, 'position', c.position, 'key', c.link_key,
    'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12),
    'sender', me.name, 'reply_to', me.email);
end $$;
grant execute on function public.hiring_outcome_mail_prepare(uuid) to authenticated;

create or replace function public.hiring_outcome_mail_done(p_id uuid, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_role text := public.hiring_role(p_id);
begin
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-request'); end if;
  update public.hiring_candidates set outcome_mail = p_status, outcome_mail_at = now(), updated_at = now() where id = p_id;
  perform public.hiring_log(p_id, 'candidate.email', 'Decision' || case p_status when 'sent' then ' emailed'
    when 'unknown' then ' emailed, not confirmed' else ' not emailed' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_outcome_mail_done(uuid, text, text) to authenticated;

/* The candidate's page, with the latest invitation and the decision
   (restated from HIRING INTERVIEWS). */
create or replace function public.careers_read(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  i public.hiring_interviews;
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
  return jsonb_build_object('ok', true, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage = 'new' or (c.stage = 'pool' and c.outcome is null) then 'received' else c.stage end, 'received_at', c.created_at,
    'pool', case when c.stage = 'pool' and c.outcome = 'pool' then jsonb_strip_nulls(jsonb_build_object('consent', c.pool_consent,
      'until', c.pool_until, 'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12))) end,
    'interview', case when i.id is null or i.state = 'cancelled' or c.stage in ('pool', 'closed') then null else jsonb_strip_nulls(jsonb_build_object(
      'state', i.state, 'slots', case when i.state = 'invited' then to_jsonb(i.slots) end, 'minutes', i.minutes,
      'mode', i.mode, 'note', i.note, 'at', case when i.picked is not null then i.slots[i.picked] end,
      'link', case when i.state = 'confirmed' then i.meeting_link end)) end);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

/* The candidate's answer to the talent pool: kept for the pool's months
   from today, or closed. */
create or replace function public.careers_pool(p_key text, p_yes boolean)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
  v_months int := coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' or p_yes is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null for update;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() then return jsonb_build_object('error', 'expired'); end if;
  if c.stage <> 'pool' or c.pool_consent is distinct from 'asked' then return jsonb_build_object('error', 'not-open'); end if;
  if p_yes then
    update public.hiring_candidates set pool_consent = 'yes', pool_until = now() + make_interval(months => v_months),
      last_step_at = now(), updated_at = now() where id = c.id;
  else
    update public.hiring_candidates set pool_consent = 'no', stage = 'closed', last_step_at = now(), updated_at = now() where id = c.id;
  end if;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (c.id, 'Candidate page', 'candidate.decided', case when p_yes then 'Agreed to the talent pool' else 'Declined the talent pool' end);
  perform public.hiring_tell(c.id, 'hiring.pool', case when p_yes then 'A candidate agreed to the talent pool' else 'A candidate declined the talent pool' end,
    c.position || '.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_pool(text, boolean) from public;
grant execute on function public.careers_pool(text, boolean) to anon, authenticated;

/* A candidate's data kept for a time (PDPA 2010): the talent pool's months
   from agreement, a pool answer not given within the link's days, a closed
   or removed candidate's keep months. Their CV files wait for the console. */
create or replace function public.hiring_retention()
returns integer language plpgsql volatile security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days int := coalesce(public.app_setting('hiring_link_days', v_today)::int, 30);
  v_keep int := coalesce(public.app_setting('hiring_keep_months', v_today)::int, 12);
  v_n int;
begin
  with gone as (
    delete from public.hiring_candidates c
     where c.stage <> 'hired' and (
           (c.stage = 'pool' and c.pool_consent = 'yes' and c.pool_until < now())
        or (c.stage = 'pool' and c.pool_consent = 'asked' and c.outcome_at + make_interval(days => v_days) < now())
        or (c.stage = 'closed' and coalesce(c.outcome_at, c.updated_at) + make_interval(months => v_keep) < now())
        or (c.removed_at is not null and c.removed_at + make_interval(months => v_keep) < now()))
    returning c.cv_path)
  insert into public.hiring_files_gone (path) select g.cv_path from gone g where g.cv_path is not null
  on conflict (path) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.hiring_retention() from public, anon, authenticated;

create or replace function public.hiring_files_gone_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'paths', coalesce((select jsonb_agg(f.path order by f.queued_at) from
    (select * from public.hiring_files_gone order by queued_at limit 100) f), '[]'::jsonb));
end $$;
grant execute on function public.hiring_files_gone_list() to authenticated;

create or replace function public.hiring_files_gone_done(p_paths text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_n int;
begin
  if not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  delete from public.hiring_files_gone where path = any(coalesce(p_paths, '{}'));
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'done', v_n);
end $$;
grant execute on function public.hiring_files_gone_done(text[]) to authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: candidates are not removed in their time until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'hiring-retention';
  perform cron.schedule('hiring-retention', '50 19 * * *', 'select public.hiring_retention()');
end $$;

-- END OF HIRING OUTCOMES -------------------------------------------------------

select public.functions_tidy();
