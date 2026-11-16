-- ===========================================================================
-- CLIENT PAGES READ THE S$ RATE — app_settings_read answers `fx_sgd` to
-- anyone, so a quotation downloaded from /quote/ states its approx. S$
-- (2026-11-17)
-- ===========================================================================
-- WHY (the Business settings audit, 2026-11-16): a Singapore lead billed in
-- RM reads its total's S$ beside it (`ADspaceMoney.approx`, at `fx_sgd`). The
-- console's copy of the quotation PDF printed it; the prospect's own
-- download from /quote/ did not, since `app_settings_read()` answered
-- anyone outside the team SST and the term percentages alone (SETTINGS A
-- CLIENT PAGE READS). The rate is the one printed on every such PDF, so it
-- is no secret.
--
-- WHAT IT CHANGES
--   * Anyone the team does not hold is answered `fx_sgd` beside `sst_pct`
--     and the six term percentages. Nothing else changes.
--
-- ORDER: this file alone (no page changes). Safe to run twice.
-- ROLLBACK: run app_settings_read from SETTINGS A CLIENT PAGE READS again.
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
                where v_team or s.key in ('sst_pct', 'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'fx_sgd')),
                '[]'::jsonb));
end $$;
grant execute on function public.app_settings_read() to anon, authenticated;
-- END OF CLIENT PAGES READ THE S$ RATE --------------------------------------
select public.functions_tidy();
