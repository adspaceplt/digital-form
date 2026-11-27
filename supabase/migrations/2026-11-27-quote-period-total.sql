-- ===========================================================================
-- PERIOD TOTAL ON A QUOTATION (2026-11-27)
-- ===========================================================================
-- WHY: the user, 2026-11-27, approving "Show totals for the whole period"
-- in Build quote. The tick is kept in the selection (`period_total`), but
-- the quotation link reads the first quotation's selection, so a revision
-- would show the totals its first version chose. The tick now travels
-- with each quotation's own totals.
--
-- WHAT CHANGES
--   * `quote_extras` (restated whole from QUOTATION ADVERTISING PER BRAND):
--     `period_total: true` in the selection sets `period_total: true` in
--     the totals a quotation keeps; any value but true or false is
--     refused `bad-period`.
--
-- ORDER: this file first (connector), then the pages (Pages deploy). Pages
-- served before read the selection as they do now. A quotation made
-- before reads its own selection on the console and its first one on the
-- link, as before. Safe to run twice.
-- ROLLBACK: run `quote_extras` from QUOTATION ADVERTISING PER BRAND again;
-- totals already kept with `period_total` keep it, read or ignored.
-- ===========================================================================

-- PERIOD TOTAL ON A QUOTATION ------------------------------------------------

create or replace function public.quote_extras(p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_pay int;
  v_rows jsonb := '[]'::jsonb;
  v_total numeric := 0;
  r jsonb;
  v_amt numeric;
  v_mo int;
  v_terms jsonb := '[]'::jsonb;
  t jsonb;
  v_valid int;
  v_title text;
  v_nb int;
begin
  /* The quotation's own title (2026-11-16), printed over its lines. */
  if jsonb_typeof(p_sel->'title') is not null and jsonb_typeof(p_sel->'title') <> 'null' then
    if jsonb_typeof(p_sel->'title') <> 'string' or length(btrim(p_sel->>'title')) > 120 then
      return jsonb_build_object('error', 'bad-title');
    end if;
    v_title := nullif(btrim(p_sel->>'title'), '');
  end if;
  -- Payment terms for the whole quotation: NET 7 unless chosen.
  if coalesce(p_sel->>'pay', '') = '' then v_pay := 7;
  elsif p_sel->>'pay' ~ '^\d{1,3}$' then v_pay := (p_sel->>'pay')::int;
  else return jsonb_build_object('error', 'bad-pay'); end if;
  if v_pay not in (7, 14, 30, 60, 90) then return jsonb_build_object('error', 'bad-pay'); end if;
  -- Valid for (2026-11-12): the days chosen in Build quote, else the
  -- Business setting, which the caller reads (`valid_days` left out).
  if coalesce(p_sel->>'valid', '') = '' then v_valid := null;
  elsif p_sel->>'valid' ~ '^\d{1,3}$' and (p_sel->>'valid')::int in (14, 30, 45, 60, 90) then v_valid := (p_sel->>'valid')::int;
  else return jsonb_build_object('error', 'bad-valid'); end if;
  if jsonb_typeof(p_sel->'ads') is not null and jsonb_typeof(p_sel->'ads') <> 'null' then
    /* Six rows a brand (QUOTATION ADVERTISING PER BRAND, 2026-11-26): a
       row of a quotation of brands names its brand's place, one without
       brands names none. */
    v_nb := case when jsonb_typeof(p_sel->'brands') = 'array' then jsonb_array_length(p_sel->'brands') else 0 end;
    if jsonb_typeof(p_sel->'ads') <> 'array' or jsonb_array_length(p_sel->'ads') > 6 * greatest(v_nb, 1) then
      return jsonb_build_object('error', 'bad-ads');
    end if;
    if exists (select 1 from jsonb_array_elements(p_sel->'ads') e
                where jsonb_typeof(e) = 'object' and e ? 'brand' and jsonb_typeof(e->'brand') <> 'null'
                  and (coalesce(e->>'brand', '') !~ '^[0-9]{1,2}$' or (e->>'brand')::int >= v_nb))
       or (select max(n) from (select count(*) n from jsonb_array_elements(p_sel->'ads') e
                                where jsonb_typeof(e) = 'object' group by e->>'brand') g) > 6 then
      return jsonb_build_object('error', 'bad-ads');
    end if;
    for r in select * from jsonb_array_elements(p_sel->'ads') loop
      if jsonb_typeof(r) <> 'object'
         or coalesce(r->>'platform', '') not in ('meta', 'tiktok', 'google', 'xhs', 'youtube', 'linkedin')
         or coalesce(r->>'freq', '') not in ('monthly', 'once')
         or coalesce(r->>'budget', '') !~ '^\d{1,9}(\.\d{1,2})?$' then
        return jsonb_build_object('error', 'bad-ads');
      end if;
      v_amt := (r->>'budget')::numeric;
      if v_amt <= 0 then return jsonb_build_object('error', 'bad-ads'); end if;
      v_mo := null;
      if r->>'freq' = 'monthly' then
        if coalesce(r->>'months', '') !~ '^\d{1,2}$' or (r->>'months')::int not between 1 and 36 then
          return jsonb_build_object('error', 'bad-ads');
        end if;
        v_mo := (r->>'months')::int;
      end if;
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('platform', r->>'platform', 'freq', r->>'freq',
                  'budget', v_amt, 'months', v_mo, 'amount', v_amt * coalesce(v_mo, 1))
                  || case when coalesce(r->>'brand', '') <> '' then jsonb_build_object('brand', (r->>'brand')::int) else '{}'::jsonb end);
      v_total := v_total + v_amt * coalesce(v_mo, 1);
    end loop;
  end if;
  /* The quotation's own terms (2026-11-12), one point a line, after the
     ones it works out: ten at most, 400 characters each. */
  if jsonb_typeof(p_sel->'terms') is not null and jsonb_typeof(p_sel->'terms') <> 'null' then
    if jsonb_typeof(p_sel->'terms') <> 'array' or jsonb_array_length(p_sel->'terms') > 10 then
      return jsonb_build_object('error', 'bad-terms');
    end if;
    for t in select * from jsonb_array_elements(p_sel->'terms') loop
      if jsonb_typeof(t) <> 'string' or length(t #>> '{}') > 400 then return jsonb_build_object('error', 'bad-terms'); end if;
      if btrim(t #>> '{}') <> '' then v_terms := v_terms || jsonb_build_array(btrim(t #>> '{}')); end if;
    end loop;
  end if;
  /* The whole period's totals shown (PERIOD TOTAL ON A QUOTATION): a tick
     the team chose, kept with the totals each page reads. */
  if jsonb_typeof(p_sel->'period_total') is not null and jsonb_typeof(p_sel->'period_total') not in ('boolean', 'null') then
    return jsonb_build_object('error', 'bad-period');
  end if;
  return jsonb_strip_nulls(jsonb_build_object('layout', 2, 'pay_days', v_pay, 'valid_days', v_valid, 'title', v_title,
           'period_total', case when p_sel->>'period_total' = 'true' then true end)) ||
    jsonb_build_object('ads', v_rows, 'ads_total', v_total, 'terms', v_terms);
end $$;
revoke all on function public.quote_extras(jsonb) from public, anon, authenticated;

-- END OF PERIOD TOTAL ON A QUOTATION -----------------------------------------

select public.functions_tidy();
