-- ===========================================================================
-- ADDRESSES LET GO (2026-11-25)
-- ===========================================================================
-- WHY (the review of everything merged since 15 Nov, approved by the user
-- on 2026-11-25): three tables holding a caller's address never let a row
-- go, against the 30-day promise in STANDARD.md (Retention): /feedback/'s
-- and /quote/'s hourly counts (`feedback_hits`, `quote_hits`) and
-- /verify/'s name check (`verify_name_caller_tries`). And the two functions
-- the one-time report picture move used (`report-thumbs-move`, removed from
-- the repository on 2026-11-24) are read by nothing.
--
-- WHAT CHANGES
--   * `privacy_retention` (restated whole from QUOTATION COPIER'S
--     ADDRESS KEPT 30 DAYS) also deletes an hourly count a day after its hour, and a
--     name check's count 30 days after it began, once it holds no lock;
--     its answer names the three counts.
--   * `sm_report_thumb_set(text, uuid, text)` and
--     `sm_report_thumb_versions(integer)` are dropped (the service role's
--     alone; nothing in the repository calls either).
--
-- ORDER: this file alone (connector); no page reads either. Safe to run
-- twice.
-- ROLLBACK: run `privacy_retention` from QUOTATION COPIER'S ADDRESS KEPT 30
-- DAYS, and
-- `sm_report_thumb_versions` from REPORT PICTURES ON S3 and
-- `sm_report_thumb_set` from its band after it, again.
-- ===========================================================================

-- ADDRESSES LET GO -------------------------------------------------------------

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0; v_vt integer := 0; v_vd integer := 0; v_vc integer := 0; v_hm integer := 0; v_qc integer := 0;
  v_fh integer := 0; v_qh integer := 0; v_vn integer := 0;
  v_today date := (p_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_keep integer := coalesce(public.app_setting('health_keep_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 24)::integer;
  v_left integer := coalesce(public.app_setting('health_leaver_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 6)::integer;
  v_gone uuid[];
begin
  update public.wa_outbox o
     set to_number = '', to_name = null, params = '[]'::jsonb, button = null
   where o.created_at < p_now - interval '12 months'
     and o.state not in ('queued', 'sending')
     and (o.to_number <> '' or o.to_name is not null or o.params <> '[]'::jsonb or o.button is not null);
  get diagnostics v_wa = row_count;
  delete from public.activity_log a where a.created_at < p_now - interval '3 years';
  get diagnostics v_act = row_count;
  delete from public.health_checkins k where k.half < v_today - make_interval(months => v_keep);
  get diagnostics v_hc = row_count;
  delete from public.health_moods k where k.period_start < v_today - make_interval(months => v_keep);
  get diagnostics v_hm = row_count;
  v_hc := v_hc + v_hm;
  select coalesce(array_agg(m.id), '{}') into v_gone from public.team_members m
   where not m.active and coalesce(m.removed_at, m.expired_at) < p_now - make_interval(months => v_left);
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
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt, 'verify_tries_removed', v_vt, 'verify_detail_tries_removed', v_vd,
    'verify_checks_removed', v_vc, 'quotation_copiers_cleared', v_qc, 'feedback_hits_removed', v_fh, 'quote_hits_removed', v_qh,
    'verify_name_tries_removed', v_vn);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;

drop function if exists public.sm_report_thumb_set(text, uuid, text);
drop function if exists public.sm_report_thumb_versions(integer);

-- END OF ADDRESSES LET GO ------------------------------------------------------

select public.functions_tidy();
