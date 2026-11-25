-- ===========================================================================
-- QUOTATION COPIER'S ADDRESS KEPT 30 DAYS (2026-11-25)
-- ===========================================================================
-- WHY: the copier's address (QUOTATION COPIER'S OPENING) is personal data
-- kept for one purpose, PDPA 2010: it is cleared 30 days after the copy, as
-- a link passcode's caller address is.
--
-- WHAT CHANGES
--   * `privacy_retention`: clears `quotation_link_copies.ip` 30 days after
--     its copy, counted as `quotation_copiers_cleared`. Restated from its
--     last section with that step alone added.
--
-- ORDER: after QUOTATION COPIER'S OPENING. Run whole in the SQL Editor (the
-- function holds the connector's stop words). Safe to run twice.
-- ROLLBACK: run `privacy_retention` from its last section before this one.
-- ===========================================================================

-- QUOTATION COPIER'S ADDRESS KEPT 30 DAYS --------------------------------------

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0; v_vt integer := 0; v_vd integer := 0; v_vc integer := 0; v_hm integer := 0; v_qc integer := 0;
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
  -- And where a colleague copied a quotation's link, 30 days after the copy
  -- (QUOTATION COPIER'S OPENING, 2026-11-25).
  update public.quotation_link_copies c set ip = null where c.ip is not null and c.at < p_now - interval '30 days';
  get diagnostics v_qc = row_count;
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt, 'verify_tries_removed', v_vt, 'verify_detail_tries_removed', v_vd,
    'verify_checks_removed', v_vc, 'quotation_copiers_cleared', v_qc);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;

-- END OF QUOTATION COPIER'S ADDRESS KEPT 30 DAYS -------------------------------

select public.functions_tidy();
