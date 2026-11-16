-- ===========================================================================
-- HIRING INTERVIEWS — an invitation of up to three times, the candidate's
-- choice on their own page, and a colleague's approval (2026-11-17, release
-- H2 step B)
-- ===========================================================================
-- WHY (HR-SPEC.md decision 2, the user, 2026-11-16): no slots system. The
-- sender keys up to three times, all within `hiring_invite_days` (3) of each
-- other, in one invitation; the candidate picks one on their page, or asks
-- for other times; a colleague approves before the confirmation is sent: a
-- Google Meet booked on the shared calendar (meet-create), or the office.
-- The candidate is emailed the invitation and the confirmation (hiring-mail).
-- No candidate data goes to AI.
--
-- WHAT IT CHANGES
--   * `hiring_interviews` (RLS on, no policy, no grant): a candidate's
--     invitations, each its times, length, Google Meet or the office, a note
--     to the candidate, its state (invited, picked, none, confirmed,
--     cancelled, replaced), the time picked, who invited and approved, the
--     Meet's link and event, and each email's outcome.
--   * `hiring_invite`, `hiring_interviews_of`, `hiring_interview_cancel`,
--     `hiring_interview_approve` (the part or the candidate's Owner).
--   * `hiring_interview_meet_prepare`, `hiring_interview_set_meet` and
--     `hiring_busy_may` (meet-create's, as the caller).
--   * `hiring_mail_prepare`, `hiring_mail_done` (hiring-mail's, as the
--     caller).
--   * `careers_read` answers the latest invitation; `careers_pick` and
--     `careers_none` (anon) take the candidate's answer, the Owners told.
--   * Business settings `hiring_invite_days` (3) and `hiring_link_days` (30),
--     `app_settings_set` restated whole (TASK DATES IN THE PAST, THE SQL
--     EDITOR PART's) taking both.
--
-- ORDER: this file (connector), then meet-create and hiring-mail deployed,
-- then function hygiene again (`careers_pick`, `careers_none` in
-- `open_to_anon`), then the pages. An old tab never asks these.
-- Safe to run twice. ROLLBACK: drop the table and the functions named above;
-- careers_read and app_settings_set as HIRING and TASK DATES IN THE PAST,
-- THE SQL EDITOR PART left them.
-- ===========================================================================

-- HIRING INTERVIEWS -----------------------------------------------------------

create table if not exists public.hiring_interviews (
  id             uuid primary key default gen_random_uuid(),
  candidate_id   uuid not null references public.hiring_candidates(id) on delete cascade,
  round          int not null default 1 check (round between 1 and 20),
  slots          timestamptz[] not null check (cardinality(slots) between 1 and 3),
  minutes        int not null check (minutes in (30, 45, 60, 90)),
  mode           text not null check (mode in ('online', 'office')),
  note           text check (note is null or char_length(note) <= 500),
  state          text not null default 'invited'
                 check (state in ('invited', 'picked', 'none', 'confirmed', 'cancelled', 'replaced')),
  picked         int check (picked is null or picked between 1 and 3),
  picked_at      timestamptz,
  candidate_note text check (candidate_note is null or char_length(candidate_note) <= 300),
  idem           text unique,
  invited_by     uuid references public.team_members(id) on delete set null,
  invited_at     timestamptz not null default now(),
  approved_by    uuid references public.team_members(id) on delete set null,
  approved_at    timestamptz,
  meeting_link   text check (meeting_link is null or meeting_link ~ '^https://meet\.google\.com/[a-z0-9-]+$'),
  meeting_event_id text,
  invite_mail    text,
  invite_mail_at timestamptz,
  confirm_mail   text,
  confirm_mail_at timestamptz,
  updated_at     timestamptz not null default now()
);
create index if not exists hiring_interviews_candidate_idx on public.hiring_interviews (candidate_id, invited_at desc);
alter table public.hiring_interviews enable row level security;
revoke all on table public.hiring_interviews from public, anon, authenticated;

insert into public.app_settings (key, from_date, value)
select 'hiring_invite_days', date '2023-08-14', 3
 where not exists (select 1 from public.app_settings s where s.key = 'hiring_invite_days');
insert into public.app_settings (key, from_date, value)
select 'hiring_link_days', date '2023-08-14', 30
 where not exists (select 1 from public.app_settings s where s.key = 'hiring_link_days');

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
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days'];
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
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
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
        when v_k in ('health_keep_months', 'health_leaver_months') then ' months'
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

/* One interview as the console reads it. */
create or replace function public.hiring_interview_row(i public.hiring_interviews)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object('id', i.id, 'round', i.round, 'slots', to_jsonb(i.slots), 'minutes', i.minutes,
    'mode', i.mode, 'note', i.note, 'state', i.state, 'picked', i.picked, 'picked_at', i.picked_at,
    'candidate_note', i.candidate_note, 'invited_at', i.invited_at,
    'invited_by', (select t.name from public.team_members t where t.id = i.invited_by),
    'approved_at', i.approved_at, 'approved_by', (select t.name from public.team_members t where t.id = i.approved_by),
    'meeting_link', i.meeting_link, 'invite_mail', i.invite_mail, 'invite_mail_at', i.invite_mail_at,
    'confirm_mail', i.confirm_mail, 'confirm_mail_at', i.confirm_mail_at));
$$;
revoke all on function public.hiring_interview_row(public.hiring_interviews) from public, anon, authenticated;

/* A time in words, Malaysia's: Tue 18 Nov 2026, 2:00pm. */
create or replace function public.hiring_when(p_at timestamptz)
returns text language sql stable set search_path = public as $$
  select to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'Dy') || ' ' || public.register_day((p_at at time zone 'Asia/Kuala_Lumpur')::date)
    || ', ' || ltrim(lower(to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'HH12:MIam')), '0');
$$;
revoke all on function public.hiring_when(timestamptz) from public, anon, authenticated;

/* The Owners of a candidate and the part's holders are told, never its
   name in the notice, the notice opening it. */
create or replace function public.hiring_tell(p_candidate uuid, p_kind text, p_title text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  insert into public.ops_notifications (team_member_id, kind, title, body, link)
  select t.id, p_kind, p_title, p_body, 'https://digital.adspace.me/admin/?s=team&tab=hiring&candidate=' || p_candidate
    from public.team_members t
   where t.active and t.removed_at is null and not t.system and (me.id is null or t.id <> me.id)
     and exists (select 1 from public.hiring_people p where p.candidate_id = p_candidate and p.team_member_id = t.id and p.role = 'owner');
end $$;
revoke all on function public.hiring_tell(uuid, text, text, text) from public, anon, authenticated;

create or replace function public.hiring_invite(p_id uuid, p_slots timestamptz[], p_minutes int, p_mode text, p_note text, p_idem text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_days int := coalesce(public.app_setting('hiring_invite_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 3);
  v_slots timestamptz[];
  v_round int;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_idem, '') !~ '^[A-Za-z0-9-]{8,64}$' then return jsonb_build_object('error', 'bad-request'); end if;
  perform pg_advisory_xact_lock(hashtext('hiring_invite:' || p_idem));
  select * into i from public.hiring_interviews where idem = p_idem;
  if i.id is not null then return jsonb_build_object('ok', true, 'id', i.id, 'again', true); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage in ('hired', 'closed') then return jsonb_build_object('error', 'closed'); end if;
  select array_agg(distinct s order by s) into v_slots from unnest(coalesce(p_slots, '{}')) s where s is not null;
  if v_slots is null or cardinality(v_slots) < 1 or cardinality(v_slots) > 3 then return jsonb_build_object('error', 'bad-slots'); end if;
  if v_slots[1] < now() + interval '1 hour' then return jsonb_build_object('error', 'slot-past'); end if;
  if v_slots[cardinality(v_slots)] > now() + interval '60 days' then return jsonb_build_object('error', 'slot-far'); end if;
  if (v_slots[cardinality(v_slots)] at time zone 'Asia/Kuala_Lumpur')::date - (v_slots[1] at time zone 'Asia/Kuala_Lumpur')::date >= v_days then
    return jsonb_build_object('error', 'slot-window', 'days', v_days);
  end if;
  if coalesce(p_minutes, 0) not in (30, 45, 60, 90) then return jsonb_build_object('error', 'bad-minutes'); end if;
  if coalesce(p_mode, '') not in ('online', 'office') then return jsonb_build_object('error', 'bad-mode'); end if;
  if char_length(coalesce(p_note, '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
  update public.hiring_interviews set state = 'replaced', updated_at = now()
   where candidate_id = c.id and state in ('invited', 'picked', 'none');
  select coalesce(max(round), 0) + 1 into v_round from public.hiring_interviews where candidate_id = c.id and state <> 'replaced';
  insert into public.hiring_interviews (candidate_id, round, slots, minutes, mode, note, idem, invited_by)
  values (c.id, least(v_round, 20), v_slots, p_minutes, p_mode, nullif(btrim(coalesce(p_note, '')), ''), p_idem, me.id)
  returning * into i;
  update public.hiring_candidates set stage = case when stage in ('new', 'pool', 'invited') then 'invited' else stage end,
    last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.invited', cardinality(v_slots) || case when cardinality(v_slots) = 1 then ' time' else ' times' end
    || ' · ' || case p_mode when 'online' then 'Google Meet' else 'At the office' end || ' · ' || p_minutes || ' minutes');
  return jsonb_build_object('ok', true, 'id', i.id);
end $$;
grant execute on function public.hiring_invite(uuid, timestamptz[], int, text, text, text) to authenticated;

create or replace function public.hiring_interviews_of(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if public.hiring_role(p_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(public.hiring_interview_row(i) order by i.invited_at desc)
    from public.hiring_interviews i where i.candidate_id = p_id and i.state <> 'replaced'), '[]'::jsonb));
end $$;
grant execute on function public.hiring_interviews_of(uuid) to authenticated;

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
  update public.hiring_interviews set state = 'cancelled', updated_at = now() where id = i.id;
  perform public.hiring_log(i.candidate_id, 'candidate.interview', 'Interview cancelled');
  return jsonb_build_object('ok', true, 'event', i.meeting_event_id, 'had_meet', i.meeting_event_id is not null);
end $$;
grant execute on function public.hiring_interview_cancel(uuid) to authenticated;

/* A colleague's Approve of the time the candidate picked. */
create or replace function public.hiring_interview_approve(p_interview uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if i.state = 'confirmed' then return jsonb_build_object('ok', true, 'same', true); end if;
  if i.state <> 'picked' or i.picked is null then return jsonb_build_object('error', 'not-picked'); end if;
  if i.slots[i.picked] < now() then return jsonb_build_object('error', 'slot-past'); end if;
  update public.hiring_interviews set state = 'confirmed', approved_by = me.id, approved_at = now(), updated_at = now() where id = i.id;
  update public.hiring_candidates set stage = case when stage in ('new', 'pool', 'invited') then 'interview' else stage end,
    last_step_at = now(), updated_at = now() where id = i.candidate_id;
  perform public.hiring_log(i.candidate_id, 'candidate.interview', 'Interview approved for ' || public.hiring_when(i.slots[i.picked]));
  return jsonb_build_object('ok', true, 'mode', i.mode);
end $$;
grant execute on function public.hiring_interview_approve(uuid) to authenticated;

/* meet-create's, asked as the caller: a confirmed online interview's time. */
create or replace function public.hiring_interview_meet_prepare(p_interview uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare i public.hiring_interviews; c public.hiring_candidates; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if i.state <> 'confirmed' or i.mode <> 'online' or i.picked is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id;
  return jsonb_build_object('id', i.id, 'meeting_at', i.slots[i.picked], 'meeting_minutes', i.minutes,
    'meeting_event_id', i.meeting_event_id, 'meeting_link', i.meeting_link, 'position', c.position);
end $$;
grant execute on function public.hiring_interview_meet_prepare(uuid) to authenticated;

create or replace function public.hiring_interview_set_meet(p_interview uuid, p_link text, p_event text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare i public.hiring_interviews; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if p_link is not null and p_link !~ '^https://meet\.google\.com/[a-z0-9-]+$' then return jsonb_build_object('error', 'bad-link'); end if;
  update public.hiring_interviews set meeting_link = p_link, meeting_event_id = p_event, updated_at = now() where id = i.id;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_interview_set_meet(uuid, text, text) to authenticated;

/* Who may read the shared calendar's online meetings while keying times. */
create or replace function public.hiring_busy_may()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if public.ops_granted('team.hiring', 'work') or exists (select 1 from public.hiring_people p join public.hiring_candidates c on c.id = p.candidate_id
       where p.team_member_id = me.id and p.role = 'owner' and c.removed_at is null) then
    return jsonb_build_object('ok', true);
  end if;
  return jsonb_build_object('error', 'denied');
end $$;
grant execute on function public.hiring_busy_may() to authenticated;

/* hiring-mail's, asked as the caller: what an email to the candidate says. */
create or replace function public.hiring_mail_prepare(p_interview uuid, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_kind = 'invite' and i.state not in ('invited', 'none') then return jsonb_build_object('error', 'not-open'); end if;
  if p_kind = 'confirm' and i.state <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed'); end if;
  if p_kind = 'confirm' and i.mode = 'online' and i.meeting_link is null then return jsonb_build_object('error', 'no-meet'); end if;
  if p_kind not in ('invite', 'confirm') then return jsonb_build_object('error', 'bad-kind'); end if;
  return jsonb_build_object('id', i.id, 'kind', p_kind, 'to', c.email, 'name', c.name, 'position', c.position,
    'key', c.link_key, 'mode', i.mode, 'minutes', i.minutes, 'note', i.note, 'link', i.meeting_link,
    'times', (select jsonb_agg(public.hiring_when(s) order by s) from unnest(i.slots) s),
    'when', case when i.picked is not null then public.hiring_when(i.slots[i.picked]) end,
    'sender', me.name, 'reply_to', me.email);
end $$;
grant execute on function public.hiring_mail_prepare(uuid, text) to authenticated;

create or replace function public.hiring_mail_done(p_interview uuid, p_kind text, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare i public.hiring_interviews; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') or coalesce(p_kind, '') not in ('invite', 'confirm') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if p_kind = 'invite' then update public.hiring_interviews set invite_mail = p_status, invite_mail_at = now(), updated_at = now() where id = i.id;
  else update public.hiring_interviews set confirm_mail = p_status, confirm_mail_at = now(), updated_at = now() where id = i.id; end if;
  perform public.hiring_log(i.candidate_id, 'candidate.email',
    case p_kind when 'invite' then 'Invitation' else 'Confirmation' end || case p_status when 'sent' then ' emailed'
      when 'unknown' then ' emailed, not confirmed' else ' not emailed' || coalesce(': ' || left(p_error, 120), '') end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_mail_done(uuid, text, text, text) to authenticated;

/* The candidate's page, with the latest invitation (restated from HIRING). */
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
  if c.last_step_at + make_interval(days => v_days) <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state <> 'replaced'
   order by invited_at desc limit 1;
  return jsonb_build_object('ok', true, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage in ('new', 'pool') then 'received' else c.stage end, 'received_at', c.created_at,
    'interview', case when i.id is null or i.state = 'cancelled' then null else jsonb_strip_nulls(jsonb_build_object(
      'state', i.state, 'slots', case when i.state = 'invited' then to_jsonb(i.slots) end, 'minutes', i.minutes,
      'mode', i.mode, 'note', i.note, 'at', case when i.picked is not null then i.slots[i.picked] end,
      'link', case when i.state = 'confirmed' then i.meeting_link end)) end);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

/* The candidate's answer: one of the times, or none of them with a note. */
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

-- END OF HIRING INTERVIEWS -----------------------------------------------------

select public.functions_tidy();
