-- ===========================================================================
-- PASSCODE TRIES ARE KEPT FOR A TIME — privacy_retention removes a caller's
-- address against a link once it has been quiet 30 days (2026-10-18)
-- ===========================================================================
-- WHY (audit 2026-10-18, item 14): `link_tries` keeps each caller's address
-- for every link they typed a passcode on, and nothing ever removed a row,
-- so the addresses were kept for good (PDPA 2010: kept no longer than
-- needed).
--
-- WHAT IT CHANGES
--   * `privacy_retention` (the 2nd of each month) also removes each row
--     whose last try and last opening are over 30 days old and whose lock
--     has ended, answering `link_tries_removed`. An address that opened the
--     link within 30 days is kept: the link's own lock spares it.
--   * Everything else it does is HEALTH DATA KEPT FOR A TIME's, unchanged.
--
-- ORDER: this file, in the SQL Editor as one run (the connector holds a
-- statement holding `delete`); it stands in for HEALTH DATA KEPT FOR A
-- TIME's `privacy_retention` where that has not been run. Safe to run twice.
-- Rollback: run HEALTH DATA KEPT FOR A TIME's `privacy_retention` again.
-- ===========================================================================

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0;
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
  select coalesce(array_agg(m.id), '{}') into v_gone from public.team_members m
   where not m.active and coalesce(m.removed_at, m.expired_at) < p_now - make_interval(months => v_left);
  if array_length(v_gone, 1) > 0 then
    delete from public.health_checkins k where k.team_member_id = any(v_gone);
    get diagnostics v_hl = row_count;
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
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;
-- END OF PASSCODE TRIES ARE KEPT FOR A TIME ---------------------------------

select public.functions_tidy();
