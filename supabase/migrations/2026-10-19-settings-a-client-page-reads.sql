-- ===========================================================================
-- SETTINGS A CLIENT PAGE READS — app_settings_read answers anyone outside the
-- team only the figures a client page prices with (2026-10-19)
-- ===========================================================================
-- WHY (audit 2026-10-18/19, item 1): `app_settings_read()` is granted to
-- anon, since the client portal, the selection page and the quotation
-- website price with SST and the term percentages, and it answered every
-- Business setting: AI prices, the ad benchmarks, the ringgit to S$ rate,
-- the follow-up limits, the retention months. Only who set each figure and
-- when were hidden.
--
-- WHAT IT CHANGES
--   * Anyone the team does not hold (`is_team()` false: a visitor, a
--     client's contact signed in) is answered `sst_pct` and the six term
--     percentages alone, the keys js/money.js reads on a client page
--     (`taxOf`, `termPct`). The team is answered every key, as before.
--   * Nothing else changes: `today`, `admin` and the shape of the answer.
--
-- ORDER: this file alone, after the pages (no page changes). Safe to run
-- twice. Rollback: run app_settings_read from BUSINESS SETTINGS again.
-- ===========================================================================

create or replace function public.app_settings_read()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_team boolean := public.is_team();
begin
  return jsonb_build_object(
    'today', (now() at time zone 'Asia/Kuala_Lumpur')::date,
    'admin', v_team and public.allowed('admin'),
    'settings', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'from', s.from_date, 'value', s.value,
                   'by', case when v_team then (select t.name from public.team_members t where t.id = s.set_by) end,
                   'at', case when v_team then s.set_at end)
                 order by s.key, s.from_date) from public.app_settings s
                where v_team or s.key in ('sst_pct', 'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24')),
                '[]'::jsonb));
end $$;
grant execute on function public.app_settings_read() to anon, authenticated;
-- END OF SETTINGS A CLIENT PAGE READS ---------------------------------------
select public.functions_tidy();
