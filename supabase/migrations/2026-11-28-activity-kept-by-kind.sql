-- ===========================================================================
-- ACTIVITY KEPT BY KIND (2026-11-28)
-- ===========================================================================
-- WHY (the user, 2026-11-28: "ok go", "keep 7 only and keep every 5
-- minutes"): the Activity record kept every entry three years, so its
-- everyday steps (a report saved 1,133 times, stage moves, messages sent)
-- stood beside the entries a dispute or an audit reads. A routine entry is
-- now kept for months, a key one for years; the scheduled jobs' history
-- for a week; every Activity list opens on its last 7 days; and a
-- candidate's decision email waits a minute for Undo, its wake every five
-- minutes (the user, through the coordinator, 2026-11-28).
--
-- WHAT CHANGES
--   * Five settings, seeded once (`app_settings`, from 14 Aug 2023):
--     `activity_window_days` 7 (1 to 90, what every Activity list shows
--     first), `activity_routine_months` 3 (1 to 36),
--     `activity_keep_months` 36 (12 to 120), `jobs_keep_days` 7 (1 to 90),
--     Settings, Security, Activity history; `send_undo_seconds` 60 (10 to
--     300), Settings, Messages, Undo before sending, the one window every
--     email a colleague's act queues waits for Undo (`team.settings`);
--     taken by `app_settings_set` (restated from CREATOR BILL ON
--     COMPLETED with the five keys).
--   * `activity_routine(p_action)`: true for the routine tags, false for
--     every other (key, the safe side). The console's `ACTION_ROUTINE`
--     (js/admin.js, beside `ACTION_LABEL`) is the same list
--     (`tests/actkeepsql.js`). A helper: no page calls it. The setting
--     names it files call the two kinds routine and important.
--   * `privacy_retention` (restated from RETENTION AND JOBS HELD) deletes a
--     routine entry after the routine months and every entry after the key
--     months, answering `activity_routine_removed` beside
--     `activity_removed` (the two together).
--   * `jobs_prune` (restated from UNREAD NOTICES PRUNED) keeps the job
--     history `jobs_keep_days`, 14 before; notices as before.
--   * `hiring_outcome_mail_queue` (restated from DECISION EMAILS QUEUED)
--     dates the email `send_undo_seconds` on (30 seconds before) and
--     answers `seconds`.
--   * pg_cron `hiring-outcome-mail` every five minutes (`*/5 * * * *`), so
--     a decision email goes between one and six minutes after it.
--
-- ORDER: this file (connector), then the pages (Activity history, Undo
-- before sending, every history opening on its last days, the minute's
-- Undo bar). An old page meanwhile reads all rows as before, and its Undo
-- bar shuts after 30 seconds while the email waits the minute: Reopen on
-- the decision still cancels it; nothing older than three months stands today, so the
-- first nightly run removes none.
-- Safe to run twice.
-- ROLLBACK: run `privacy_retention` from RETENTION AND JOBS HELD, `jobs_prune`
-- from UNREAD NOTICES PRUNED, `hiring_outcome_mail_queue` from DECISION
-- EMAILS QUEUED and `app_settings_set` from CREATOR BILL ON COMPLETED
-- again, and schedule `hiring-outcome-mail` at `* * * * *`;
-- `activity_routine` and the five settings may stay. An entry removed is
-- not brought back (the nightly dumps hold it 90 days).
-- ===========================================================================

-- ACTIVITY KEPT BY KIND ------------------------------------------------------

insert into public.app_settings (key, from_date, value)
select 'activity_routine_months', date '2023-08-14', 3
 where not exists (select 1 from public.app_settings s where s.key = 'activity_routine_months');
insert into public.app_settings (key, from_date, value)
select 'activity_keep_months', date '2023-08-14', 36
 where not exists (select 1 from public.app_settings s where s.key = 'activity_keep_months');
insert into public.app_settings (key, from_date, value)
select 'jobs_keep_days', date '2023-08-14', 7
 where not exists (select 1 from public.app_settings s where s.key = 'jobs_keep_days');
insert into public.app_settings (key, from_date, value)
select 'activity_window_days', date '2023-08-14', 7
 where not exists (select 1 from public.app_settings s where s.key = 'activity_window_days');
insert into public.app_settings (key, from_date, value)
select 'send_undo_seconds', date '2023-08-14', 60
 where not exists (select 1 from public.app_settings s where s.key = 'send_undo_seconds');

/* The routine tags: the everyday steps kept for the routine months. Every
   other tag, a new one included, is key. */
create or replace function public.activity_routine(p_action text)
returns boolean
language sql immutable parallel safe set search_path = public as $$
  select coalesce(p_action in (
    'assistant.call', 'assistant.campaign', 'assistant.meeting', 'assistant.report',
    'assistant.schedule', 'assistant.set', 'assistant.task', 'assistant.whatsapp', 'campaign.bulk',
    'campaign.closed', 'campaign.dates', 'campaign.file_added', 'campaign.file_hidden',
    'campaign.file_shown', 'campaign.keyed', 'campaign.offered', 'campaign.opened', 'campaign.qc',
    'campaign.rated', 'campaign.results', 'campaign.stage', 'campaign.task_linked',
    'campaign.task_unlinked', 'campaign.unkeyed', 'campaign.unoffered', 'campaign.whatsapp',
    'client.action_done', 'client.action_reopened', 'client.drive', 'client.handles',
    'client.review_on', 'client.stage', 'client.touch', 'client.touch_edited',
    'client.touch_restored', 'creator.links', 'creator.links_restored', 'creator.links_self',
    'document.verified', 'drive.imported', 'email.sent', 'ops.trip_closed', 'post.added',
    'post.edited', 'quotation.opened', 'reapproval.requested', 'report.ai_drafted',
    'report.ai_failed', 'report.audited', 'report.confirmed', 'report.created',
    'report.reassigned', 'report.returned', 'report.revised', 'report.saved', 'report.submitted',
    'script.created', 'script.saved', 'script.shot', 'set.created', 'set.month', 'set.published',
    'set.renamed', 'set.task_linked', 'set.task_unlinked', 'set.withdrawn', 'wa.sent'
  ), false)
$$;
revoke all on function public.activity_routine(text) from public, anon, authenticated;

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0; v_vt integer := 0; v_vd integer := 0; v_vc integer := 0; v_hm integer := 0; v_qc integer := 0;
  v_fh integer := 0; v_qh integer := 0; v_vn integer := 0;
  v_today date := (p_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_keep integer := coalesce(public.app_setting('health_keep_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 24)::integer;
  v_left integer := coalesce(public.app_setting('health_leaver_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 6)::integer;
  v_act_routine integer := greatest(coalesce(public.app_setting('activity_routine_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 3)::integer, 1);
  v_act_keep integer := greatest(coalesce(public.app_setting('activity_keep_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 36)::integer, 12);
  v_act_r integer := 0;
  v_gone uuid[];
begin
  update public.wa_outbox o
     set to_number = '', to_name = null, params = '[]'::jsonb, button = null
   where o.created_at < p_now - interval '12 months'
     and o.state not in ('queued', 'sending')
     and (o.to_number <> '' or o.to_name is not null or o.params <> '[]'::jsonb or o.button is not null);
  get diagnostics v_wa = row_count;
  /* The Activity record by kind (ACTIVITY KEPT BY KIND, 2026-11-28): a
     routine entry (`activity_routine`) after the routine months, every
     entry after the key months, each a setting. */
  delete from public.activity_log a
   where public.activity_routine(a.action) and a.created_at < p_now - make_interval(months => v_act_routine);
  get diagnostics v_act_r = row_count;
  delete from public.activity_log a where a.created_at < p_now - make_interval(months => v_act_keep);
  get diagnostics v_act = row_count;
  v_act := v_act + v_act_r;
  delete from public.health_checkins k where k.half < v_today - make_interval(months => v_keep);
  get diagnostics v_hc = row_count;
  delete from public.health_moods k where k.period_start < v_today - make_interval(months => v_keep);
  get diagnostics v_hm = row_count;
  v_hc := v_hc + v_hm;
  select coalesce(array_agg(m.id), '{}') into v_gone from public.team_members m
   where not m.active and coalesce(m.removed_at, m.expired_at, m.inactive_at) < p_now - make_interval(months => v_left);
  if array_length(v_gone, 1) > 0 then
    delete from public.health_checkins k where k.team_member_id = any(v_gone);
    get diagnostics v_hl = row_count;
    delete from public.health_moods k where k.team_member_id = any(v_gone);
    get diagnostics v_hm = row_count;
    v_hl := v_hl + v_hm;
    delete from public.health_talks t where t.team_member_id = any(v_gone) or t.with_id = any(v_gone);
    delete from public.health_log l where l.team_member_id = any(v_gone);
    delete from public.health_consents c where c.team_member_id = any(v_gone);
  end if;
  -- A caller's address against a link's passcode, once it has had nothing
  -- to say for 30 days and holds no lock (audit 2026-10-18, item 14).
  delete from public.link_tries t
   where greatest(t.last_at, coalesce(t.ok_at, t.last_at)) < p_now - interval '30 days'
     and coalesce(t.locked_until, t.last_at) < p_now;
  get diagnostics v_lt = row_count;
  -- A caller's address against /verify/, once its hour began 30 days ago.
  delete from public.verify_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vt = row_count;
  -- And against /verify/'s details (VERIFY DETAILS, 2026-11-20).
  delete from public.verify_detail_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vd = row_count;
  -- And a check's address hash, 30 days after its day; the document's
  -- total stays (VERIFY CHECKS COUNTED, 2026-11-21).
  delete from public.verify_checks v where v.day < v_today - 30;
  get diagnostics v_vc = row_count;
  -- A caller's hourly count on /feedback/ and /quote/, a day after its
  -- hour (ADDRESSES LET GO, 2026-11-25): the count is read for the hour
  -- alone, so nothing older is needed.
  delete from public.feedback_hits h where h.hour < (p_now at time zone 'Asia/Kuala_Lumpur') - interval '1 day';
  get diagnostics v_fh = row_count;
  delete from public.quote_hits h where h.hour < (p_now at time zone 'Asia/Kuala_Lumpur') - interval '1 day';
  get diagnostics v_qh = row_count;
  -- And against /verify/'s name check, once its count began 30 days ago
  -- and it holds no lock.
  delete from public.verify_name_caller_tries v
   where v.since < p_now - interval '30 days'
     and coalesce(v.locked_until, v.since) < p_now;
  get diagnostics v_vn = row_count;
  -- And where a colleague copied a quotation's link, 30 days after the copy
  -- (QUOTATION COPIER'S OPENING, 2026-11-25).
  update public.quotation_link_copies c set ip = null where c.ip is not null and c.at < p_now - interval '30 days';
  get diagnostics v_qc = row_count;
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act, 'activity_routine_removed', v_act_r,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt, 'verify_tries_removed', v_vt, 'verify_detail_tries_removed', v_vd,
    'verify_checks_removed', v_vc, 'quotation_copiers_cleared', v_qc, 'feedback_hits_removed', v_fh, 'quote_hits_removed', v_qh,
    'verify_name_tries_removed', v_vn);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;

create or replace function public.jobs_prune(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_runs integer := 0; v_notes integer := 0;
  v_days integer := greatest(coalesce(public.app_setting('jobs_keep_days', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 7)::integer, 1);
begin
  if to_regclass('cron.job_run_details') is not null then
    delete from cron.job_run_details d where d.end_time < p_now - make_interval(days => v_days);
    get diagnostics v_runs = row_count;
  end if;
  /* A colleague's notice (notice_id) stays: Notices read its copies. */
  delete from public.ops_notifications n
   where n.notice_id is null
     and ((n.read_at is not null and n.created_at < p_now - interval '90 days')
       or (n.read_at is null and n.created_at < p_now - interval '180 days'));
  get diagnostics v_notes = row_count;
  return jsonb_build_object('job_runs', v_runs, 'notices', v_notes);
end $$;
revoke all on function public.jobs_prune(timestamptz) from public, anon, authenticated;

/* The decision's email, queued for the drain once Undo's window passes
   (`send_undo_seconds`, 60). */
create or replace function public.hiring_outcome_mail_queue(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_role text := public.hiring_role(p_id); c public.hiring_candidates;
  v_secs integer := greatest(coalesce(public.app_setting('send_undo_seconds', (now() at time zone 'Asia/Kuala_Lumpur')::date), 60)::integer, 10);
begin
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.outcome is null or c.outcome not in ('pool', 'not') then return jsonb_build_object('error', 'no-email'); end if;
  if c.outcome_mail in ('sent', 'sending') then return jsonb_build_object('ok', true, 'same', true); end if;
  update public.hiring_candidates set outcome_mail = 'queued', outcome_mail_at = null,
    outcome_mail_due = now() + make_interval(secs => v_secs), updated_at = now() where id = c.id;
  return jsonb_build_object('ok', true, 'due', now() + make_interval(secs => v_secs), 'seconds', v_secs);
end $$;
revoke all on function public.hiring_outcome_mail_queue(uuid) from public, anon;
grant execute on function public.hiring_outcome_mail_queue(uuid) to authenticated;

/* The five settings are ones the Business settings sheets take too,
   restated whole from CREATOR BILL ON COMPLETED with the keys added. */
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
    'analytics_change_pct', 'analytics_churn_pct', 'quote_reply_days', 'quote_details_days', 'quote_details_close_days', 'quote_wa_day', 'client_email_on', 'ai_price_image', 'report_post_links', 'creator_bill_on_completed',
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'feedback_quiet_months', 'plan_db_mb', 'plan_db_alert_pct',
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'hiring_decision_days', 'verify_code_from',
    'work_start', 'work_end', 'work_lunch_min', 'work_weekend',
    'health_cap_default', 'health_near_pct', 'health_task_hours', 'health_remind_days', 'health_alert',
    'outstation_office_lat', 'outstation_office_lng', 'outstation_accuracy_m', 'outstation_keep_months',
    'outstation_office_radius_m', 'outstation_remind_hours',
    'reveal_seconds', 'ad_prepay_pct', 'ad_credit_fee_pct',
    'activity_routine_months', 'activity_keep_months', 'jobs_keep_days', 'activity_window_days', 'send_undo_seconds'];
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
       or (v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert', 'creator_bill_on_completed') and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'task_past_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_invite_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_link_days' and (v_v < 7 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_pool_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'ad_prepay_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'ad_credit_fee_pct' and (v_v < 0 or v_v > 100))
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
       or (v_k = 'quote_details_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k = 'quote_details_close_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k in ('creator_pay_days_myr', 'creator_pay_days_other') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k = 'quote_wa_day' and (v_v < 0 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'health_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'health_leaver_months' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'activity_routine_months' and (v_v < 1 or v_v > 36 or v_v <> trunc(v_v)))
       or (v_k = 'activity_keep_months' and (v_v < 12 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'jobs_keep_days' and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'activity_window_days' and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'send_undo_seconds' and (v_v < 10 or v_v > 300 or v_v <> trunc(v_v)))
       or (v_k = 'health_cap_default' and (v_v < 1 or v_v > 80 or v_v <> trunc(v_v)))
       or (v_k = 'health_near_pct' and (v_v < 50 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'health_task_hours' and (v_v < 0.5 or v_v > 40 or v_v * 2 <> trunc(v_v * 2)))
       or (v_k = 'health_remind_days' and (v_v < 0 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_office_lat' and (v_v < -90 or v_v > 90))
       or (v_k = 'outstation_office_lng' and (v_v < -180 or v_v > 180))
       or (v_k = 'outstation_accuracy_m' and (v_v < 5 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_office_radius_m' and (v_v < 20 or v_v > 1000 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_remind_hours' and (v_v < 1 or v_v > 12 or v_v <> trunc(v_v)))
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
        when 'ai_price_out' then 'AI output price per million tokens' when 'ai_price_search' then 'AI web search price per thousand searches' when 'ai_price_image' then 'AI price per scene picture' when 'meta_checks' then 'Meta checks' when 'client_email_on' then 'Send by email' when 'report_post_links' then 'Posts linked to tasks' when 'creator_bill_on_completed' then 'Bill creators on Completed'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'feedback_quiet_months' then 'Feedback last requested within' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
        when 'quote_details_days' then 'Details reply within' when 'quote_details_close_days' then 'Close after Reply by'
        when 'plan_db_mb' then 'Database plan' when 'plan_db_alert_pct' then 'Database alert'
        when 'timely_pct' then 'On time or early target' when 'timely_late_days' then 'Average lateness target'
        when 'stage_back_days' then 'Past dates on stage moves'
        when 'hiring_reply_days' then 'Interview reply time'
        when 'session_idle_days' then 'Signed-in devices'
        when 'reveal_seconds' then 'Hidden personal details'
        when 'hiring_decision_days' then 'Decision time'
        when 'creator_pay_days_myr' then 'Creator payment in MYR' when 'creator_pay_days_other' then 'Creator payment in other currencies'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'quote_wa_day' then 'Quotation portal on WhatsApp'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Yearly rise in cost per lead' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend share of the budget' when 'bench_adset_daily' then 'Minimum daily budget per ad set'
        when 'fx_sgd' then 'Singapore dollar rate'
        when 'activity_routine_months' then 'Routine activity kept' when 'activity_keep_months' then 'Important activity kept'
        when 'jobs_keep_days' then 'Automatic run history kept' when 'activity_window_days' then 'Activity lists show'
        when 'send_undo_seconds' then 'Undo before an email sends'
        when 'health_keep_months' then 'Health check-ins kept' when 'health_leaver_months' then 'Leavers'' health data kept'
        when 'health_cap_default' then 'Health default weekly capacity' when 'health_near_pct' then 'Health near capacity'
        when 'health_task_hours' then 'Health default hours per task' when 'health_remind_days' then 'Health check-in reminder'
        when 'health_alert' then 'Health heavy workload notice'
        when 'outstation_office_lat' then 'Office latitude' when 'outstation_office_lng' then 'Office longitude'
        when 'outstation_accuracy_m' then 'Location accuracy limit' when 'outstation_keep_months' then 'Outstation trips kept'
        when 'outstation_office_radius_m' then 'Office radius' when 'outstation_remind_hours' then 'Reminder for open trips'
        when 'abroad_days' then 'Overseas approval' when 'abroad_remind_hours' then 'Overseas reminder'
        when 'analytics_from' then 'Analytics counts from'
        when 'verify_code_from' then 'Document IDs printed from'
        when 'ad_prepay_pct' then 'Next month''s budget requested at' when 'ad_credit_fee_pct' then 'Agency Credit Term Fee'
        when 'work_start' then 'Working hours start' when 'work_end' then 'Working hours end'
        when 'work_lunch_min' then 'Lunch' when 'work_weekend' then 'Saturday and Sunday'
        when 'analytics_change_pct' then 'Analytics change threshold' when 'analytics_churn_pct' then 'Analytics quarterly churn alert'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' per S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours', 'abroad_remind_hours', 'health_cap_default', 'health_task_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'quote_details_close_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'health_remind_days', 'jobs_keep_days', 'activity_window_days') then ' days'
        when v_k in ('quote_reply_days', 'quote_details_days', 'creator_pay_days_myr', 'creator_pay_days_other', 'hiring_decision_days') then ' working days'
        when v_k = 'quote_wa_day' then ' per day'
        when v_k = 'plan_db_mb' then ' MB'
        when v_k = 'work_lunch_min' then ' minutes'
        when v_k in ('reveal_seconds', 'send_undo_seconds') then ' seconds'
        when v_k in ('outstation_accuracy_m', 'outstation_office_radius_m') then ' m'
        when v_k = 'outstation_remind_hours' then ' hours'
        when v_k in ('outstation_office_lat', 'outstation_office_lng') then ''
        when v_k in ('health_keep_months', 'hiring_pool_months', 'hiring_keep_months', 'feedback_quiet_months', 'health_leaver_months', 'outstation_keep_months', 'activity_routine_months', 'activity_keep_months') then ' months'
        when v_pre <> '' then '' else '%' end;
      v_fw := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert', 'creator_bill_on_completed') then case when v_was = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then coalesce(public.work_hours_word(v_k, v_was), 'not set')
              when v_k = 'analytics_from' then coalesce(substr(public.register_day(to_date(v_was::bigint::text, 'YYYYMM')), 3), 'not set')
              when v_k = 'verify_code_from' then coalesce(public.register_day(to_date(v_was::bigint::text, 'YYYYMMDD')), 'not set') else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit, 'not set') end;
      v_fv := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert', 'creator_bill_on_completed') then case when v_v = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then public.work_hours_word(v_k, v_v)
              when v_k = 'analytics_from' then substr(public.register_day(to_date(v_v::bigint::text, 'YYYYMM')), 3)
              when v_k = 'verify_code_from' then public.register_day(to_date(v_v::bigint::text, 'YYYYMMDD')) else v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              case when v_drop then v_name || ': planned change withdrawn · ' || v_fw || ' from ' || public.register_day(p_from) ||
                ', stays ' || v_fv else
              case when v_k in ('analytics_from', 'verify_code_from') or (v_k like 'work\_%' and v_k <> 'work_lunch_min') then v_name || ': ' || v_fw || ' → ' || v_fv || ' · from ' || public.register_day(p_from) else
              v_name || ': ' || case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert', 'creator_bill_on_completed') then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert', 'creator_bill_on_completed') then '' else coalesce(v_pre ||
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

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then return; end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'hiring-outcome-mail';
  perform cron.schedule('hiring-outcome-mail', '*/5 * * * *', 'select public.hiring_outcome_mail_kick()');
end $$;

-- END OF ACTIVITY KEPT BY KIND -----------------------------------------------

select public.functions_tidy();
