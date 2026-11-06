-- ===========================================================================
-- QUOTATIONS PRICED ON TODAY'S TERMS (2026-11-06)
-- ===========================================================================
-- WHY (the user, 2026-11-06): "Once settings changes the portal quote ...
-- should then apply the latest settings". A term percentage changed in
-- Settings (1 to 3 months 25 -> 15) reached no quotation until the rate
-- card was published again.
--
-- WHAT IT CHANGES
--   `quote_card()` keeps the live version's lines and words, and takes SST
--   and the term percentages in force today (Settings, Money: Tax and
--   terms), so every quotation priced or edited from now reads them. A
--   quotation already kept keeps its figures until it is edited.
--
-- ORDER: this file alone; no page changes for it. Safe to run twice.
--
-- ROLLBACK: restate quote_card() as in 2026-10-14-quotations.sql.
-- ===========================================================================

-- QUOTATIONS PRICED ON TODAY'S TERMS ----------------------------------------

create or replace function public.quote_card()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'version', v.version,
           'snapshot', v.snapshot || jsonb_build_object('settings',
             coalesce(v.snapshot->'settings', '{}'::jsonb) ||
             coalesce((select jsonb_object_agg(k, public.app_setting(k, (now() at time zone 'Asia/Kuala_Lumpur')::date))
                         from unnest(array['sst_pct', 'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24']) k
                        where public.app_setting(k, (now() at time zone 'Asia/Kuala_Lumpur')::date) is not null), '{}'::jsonb)))
    from public.rate_card_versions v
   order by v.published_at desc
   limit 1
$$;
revoke all on function public.quote_card() from public, anon, authenticated;

-- END OF QUOTATIONS PRICED ON TODAY'S TERMS ---------------------------------

select public.functions_tidy();
