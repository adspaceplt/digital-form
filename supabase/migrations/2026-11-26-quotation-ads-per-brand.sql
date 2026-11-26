-- ===========================================================================
-- QUOTATION ADVERTISING PER BRAND (2026-11-26)
-- ===========================================================================
-- WHY: the user, 2026-11-26, approving Build quote's brand cards: "ad budget
-- per brand". A quotation of several brands sets each brand's advertising
-- budget inside its own card.
--
-- WHAT CHANGES
--   * `quote_extras` (restated whole from QUOTATION LINES OF OUR OWN): an advertising
--     row may name its brand's place (`brand`, 0 to the brands less one),
--     kept on the row it answers; six rows a brand, a quotation without
--     brands six as before and naming none (`bad-ads`).
--   * `quotation_cycle_lines` (restated whole from QUOTATION BRANDS ON SERVICE
--     LINES AND INVOICES):
--     a budget row of a quotation of two brands or more is invoiced as
--     `{brand} · Advertising budget · {platform}` through
--     `quote_line_label`, as a brand's service lines are.
--
-- ORDER: this file first (connector), then the pages (Pages deploy). An old
-- tab meanwhile sends rows naming no brand, priced as before. The new
-- pages before this file would be refused `bad-ads` where a row names its
-- brand, so this file goes first. Safe to run twice.
-- ROLLBACK: run `quote_extras` and `quotation_cycle_lines` from their
-- earlier bands again; rows already kept with a brand are read as before
-- (the brand ignored).
-- ===========================================================================

-- QUOTATION ADVERTISING PER BRAND ----------------------------------------------

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
  return jsonb_strip_nulls(jsonb_build_object('layout', 2, 'pay_days', v_pay, 'valid_days', v_valid, 'title', v_title)) ||
    jsonb_build_object('ads', v_rows, 'ads_total', v_total, 'terms', v_terms);
end $$;
revoke all on function public.quote_extras(jsonb) from public, anon, authenticated;

create or replace function public.quotation_cycle_lines(p_id uuid, p_cycle int, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  v_out jsonb := '[]'::jsonb;
  e jsonb;
  v_months int; v_month boolean; v_pct numeric; v_rate numeric; v_unit numeric;
  v_sst numeric; v_tax text; v_sku text;
  g record; v_last int; v_amt numeric; v_q numeric;
begin
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null then return v_out; end if;
  if p_kind = 'budget' then
    for e in select x from jsonb_array_elements(coalesce(q.totals->'ads', '[]'::jsonb)) x loop
      v_month := coalesce(e->>'freq', 'monthly') = 'monthly';
      v_months := greatest(1, coalesce((e->>'months')::int, 1));
      if (v_month and p_cycle <= v_months) or (not v_month and p_cycle = 1) then
        v_unit := round(coalesce((e->>'budget')::numeric, (e->>'amount')::numeric, 0), 2);
        if v_unit > 0 then
          -- a brand's own budget named after its brand (QUOTATION ADVERTISING PER BRAND)
          v_out := v_out || jsonb_build_object('label', public.quote_line_label(q.totals, jsonb_build_object('brand', e->'brand', 'label', 'Advertising budget · ' ||
            case lower(coalesce(e->>'platform', '')) when 'meta' then 'Meta' when 'tiktok' then 'TikTok' when 'google' then 'Google'
              when 'xhs' then 'rednote' when 'rednote' then 'rednote' else initcap(coalesce(e->>'platform', 'Other')) end)),
            'qty', 1, 'unit', v_unit, 'sst', 0);
        end if;
      end if;
    end loop;
    return v_out;
  end if;
  for e in select x from jsonb_array_elements(coalesce(q.lines, '[]'::jsonb)) x loop
    if coalesce((e->>'in_plan')::boolean, false) then continue; end if;
    v_month := e->>'basis' = 'month';
    v_months := greatest(1, coalesce((e->>'months')::int, (q.totals->>'term')::int, 1));
    if not ((v_month and p_cycle <= v_months) or (not v_month and p_cycle = 1)) then continue; end if;
    v_rate := coalesce((e->>'rate')::numeric, 0);
    v_pct := case when v_month then coalesce((e->>'pct')::numeric, (q.totals->>'term_pct')::numeric, 0) else 0 end;
    v_unit := round(v_rate * (1 + v_pct / 100), 2);
    v_sst := coalesce((e->>'tax_pct')::numeric, (e->>'sst')::numeric, (q.totals->>'sst_pct')::numeric, 0);
    v_tax := null;
    if coalesce(e->>'tax', '') <> '' then
      select t.bukku_id into v_tax from public.tax_codes t where t.code = e->>'tax';
    end if;
    if v_tax is null and v_sst > 0 then
      select t.bukku_id into v_tax from public.tax_codes t
       where t.active and t.rate = v_sst and t.bukku_id is not null
       order by (t.code ilike 'SV%') desc, t.code limit 1;
    end if;
    v_sku := null;
    if coalesce(e->>'slug', '') <> '' then
      select nullif(btrim(s.sku), '') into v_sku from public.services s where s.slug = e->>'slug';
    end if;
    v_out := v_out || jsonb_strip_nulls(jsonb_build_object('label', public.quote_line_label(q.totals, e),
      'qty', coalesce((e->>'qty')::numeric, 1), 'unit', v_unit, 'sst', v_sst, 'tax', v_tax, 'sku', v_sku,
      'pct', case when v_pct <> 0 then v_pct end, 'month', v_month,
      '_g', case when v_month and v_pct <> 0 then v_sst::text || '|' || v_pct::text end,
      '_v', coalesce((e->>'qty')::numeric, 1) * v_rate));
  end loop;
  for g in
    select x->>'_g' as k, max((x->>'pct')::numeric) as p, sum((x->>'_v')::numeric) as gsub,
           sum((x->>'qty')::numeric * (x->>'unit')::numeric) as billed, max(i) as last
      from jsonb_array_elements(v_out) with ordinality t(x, i)
     where x ? '_g' group by x->>'_g'
  loop
    v_amt := g.gsub + round(g.gsub * g.p / 100, 2) - g.billed;
    if v_amt <> 0 then
      v_last := g.last::int - 1;
      v_q := (v_out->v_last->>'qty')::numeric;
      v_amt := round(v_q * (v_out->v_last->>'unit')::numeric + v_amt, 2);
      v_out := jsonb_set(v_out, array[v_last::text], (v_out->v_last) || jsonb_build_object('qty', 1, 'unit', v_amt,
        'label', case when v_q <> 1 then trim(to_char(v_q, 'FM999990.##')) || ' × ' else '' end || (v_out->v_last->>'label')));
    end if;
  end loop;
  select coalesce(jsonb_agg((x - '_g') - '_v' order by i), '[]'::jsonb) into v_out
    from jsonb_array_elements(v_out) with ordinality t(x, i);
  return v_out;
end $$;
revoke all on function public.quotation_cycle_lines(uuid, integer, text) from public, anon, authenticated;

-- END OF QUOTATION ADVERTISING PER BRAND ---------------------------------------

select public.functions_tidy();
