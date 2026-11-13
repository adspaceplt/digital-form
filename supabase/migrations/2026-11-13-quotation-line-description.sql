-- =====================================================================
-- QUOTATION LINE DESCRIPTION
-- 2026-11-13, the user: a line's description in Build quote is the Rate
-- Card's until the team changes it for that one quotation; the card is
-- changed only by publishing it. `quote_adjust` takes the edit `detail`
-- (one to twelve points, each 300 at most), keeps the card's as
-- `list_detail`, and every reader of the line (the PDF, /quote/) prints it.
-- =====================================================================
create or replace function public.quote_adjust(p_price jsonb, p_edits jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_t jsonb := coalesce(p_price->'totals', '{}'::jsonb);
  v_term int := coalesce((v_t->>'term')::int, 1);
  v_lines jsonb := '[]'::jsonb;
  v_l jsonb; v_e jsonb; v_k text; v_n int := 0; v_hit boolean;
  v_qty numeric; v_rate numeric; v_mo int;
  v_pct numeric := coalesce((v_t->>'term_pct')::numeric, 0);
  v_sst_pct numeric := coalesce((v_t->>'sst_pct')::numeric, 0);
  v_tot jsonb;
  v_plan boolean := false;
  v_basis text;
  v_switched boolean := false;
  v_det jsonb;
begin
  if p_price ? 'error' or jsonb_typeof(p_price->'lines') is distinct from 'array' then return p_price; end if;
  if p_edits is not null and jsonb_typeof(p_edits) not in ('object', 'null') then
    return jsonb_build_object('error', 'bad-edit');
  end if;
  -- A line at RM 0 beside a plan is read as part of it (Include in plan).
  v_plan := exists (select 1 from jsonb_array_elements(p_price->'lines') x where x->>'kind' = 'plan');
  for v_l in select * from jsonb_array_elements(p_price->'lines') loop
    v_e := null;
    v_k := (v_l->>'kind') || '|' || coalesce(v_l->>'slug', '') || '|' || (v_l->>'label');
    v_qty := (v_l->>'qty')::numeric; v_rate := (v_l->>'rate')::numeric;
    v_mo := case when v_l->>'basis' = 'month' then v_term else 1 end;
    v_hit := false;
    if jsonb_typeof(p_edits) = 'object' and jsonb_typeof(p_edits->v_k) = 'object' then
      v_e := p_edits->v_k;
      if (v_e ? 'qty' and coalesce(v_e->>'qty', '') !~ '^[0-9]{1,4}$')
         or (v_e ? 'rate' and coalesce(v_e->>'rate', '') !~ '^[0-9]{1,7}(\.[0-9]{1,2})?$')
         or (v_e ? 'basis' and (coalesce(v_e->>'basis', '') not in ('month', 'once') or v_l->>'basis' <> 'once'))
         or (v_e ? 'months' and (coalesce(case when v_e->>'basis' = 'month' then 'month' end, v_l->>'basis') <> 'month'
                                 or coalesce(v_e->>'months', '') !~ '^[0-9]{1,2}$'))
         or (v_e ? 'incl' and jsonb_typeof(v_e->'incl') is distinct from 'boolean')
         or (v_e ? 'tax' and coalesce(v_e->>'tax', '') !~ '^([A-Za-z0-9._ -]{1,30})?$')
         or (v_e ? 'detail' and (jsonb_typeof(v_e->'detail') is distinct from 'array'
             or jsonb_array_length(v_e->'detail') not between 1 and 12
             or exists (select 1 from jsonb_array_elements(v_e->'detail') d
                         where jsonb_typeof(d) <> 'string' or length(btrim(d #>> '{}')) not between 1 and 300))) then
        return jsonb_build_object('error', 'bad-edit', 'line', v_l->>'label');
      end if;
      if (v_e ? 'qty' and (v_e->>'qty')::int < 1) or (v_e ? 'months' and (v_e->>'months')::int not between 1 and 36) then
        return jsonb_build_object('error', 'bad-edit', 'line', v_l->>'label');
      end if;
      /* A one-off item of the Rate Card billed by the month (2026-11-12,
         the user: nine graphics a month with no plan): Monthly over the
         term, its months typed as any monthly line's. */
      if v_e->>'basis' = 'month' and v_l->>'basis' = 'once' then
        v_l := v_l || jsonb_build_object('basis', 'month', 'was_once', true);
        v_mo := v_term; v_hit := true; v_switched := true;
      end if;
      if v_e ? 'qty' and (v_e->>'qty')::numeric <> v_qty then v_qty := (v_e->>'qty')::numeric; v_hit := true; end if;
      if v_e ? 'rate' and (v_e->>'rate')::numeric <> v_rate then
        v_l := v_l || jsonb_build_object('list_rate', v_rate);
        v_rate := (v_e->>'rate')::numeric; v_hit := true;
      end if;
      if v_e ? 'months' and (v_e->>'months')::int <> v_mo then v_mo := (v_e->>'months')::int; v_hit := true; end if;
      /* The line's points as the team wrote them for this quotation
         (2026-11-13), the card's kept as list_detail. */
      if v_e ? 'detail' then
        v_det := (select jsonb_agg(btrim(d #>> '{}') order by n) from jsonb_array_elements(v_e->'detail') with ordinality x(d, n));
        if v_det is distinct from coalesce(v_l->'detail', '[]'::jsonb) then
          v_l := v_l || jsonb_build_object('list_detail', coalesce(v_l->'detail', '[]'::jsonb), 'detail', v_det);
          v_hit := true;
        end if;
      end if;
      /* A line's own tax code (2026-10-22), its rate read from tax_codes by
         quote_tax_edits; an empty one keeps the quotation's SST. */
      if coalesce(v_e->>'tax', '') <> '' then
        if jsonb_typeof(v_e->'tax_pct') is distinct from 'number' then
          return jsonb_build_object('error', 'bad-tax', 'line', v_l->>'label');
        end if;
        v_l := v_l || jsonb_build_object('tax_code', v_e->>'tax', 'sst', (v_e->>'tax_pct')::numeric);
        v_hit := true;
      end if;
    end if;
    if v_hit then v_n := v_n + 1; end if;
    v_l := v_l - 'in_plan';
    if v_plan and v_l->>'kind' is distinct from 'plan' and v_l->>'basis' = 'month' and v_rate = 0
       and coalesce(v_e->>'incl', 'true') <> 'false' then
      v_l := v_l || jsonb_build_object('in_plan', true);
    end if;
    v_l := v_l || jsonb_build_object('key', v_k, 'qty', v_qty, 'rate', v_rate, 'months', v_mo,
                                     'amount', round(v_qty * v_rate, 2));
    v_lines := v_lines || jsonb_build_array(v_l);
  end loop;
  if v_n = 0 then
    return p_price || jsonb_build_object('lines', v_lines, 'adjusted', 0);
  end if;
  /* Lines that were all one-off took no term percentage; one made Monthly
     takes the term's (quote_base's `term_pct_if`). */
  if v_switched and coalesce((v_t->>'term_pct')::numeric, 0) = 0 and not exists (
       select 1 from jsonb_array_elements(p_price->'lines') x where x->>'basis' = 'month') then
    v_pct := coalesce((v_t->>'term_pct_if')::numeric, 0);
    v_t := v_t || jsonb_build_object('term_pct', v_pct);
  end if;
  -- The figures, from the one calculation every quotation and letter shares.
  v_tot := public.quote_totals(v_lines, v_term, v_pct, v_sst_pct);
  return p_price || jsonb_build_object('lines', v_lines, 'adjusted', v_n,
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment'));
end $$;
revoke all on function public.quote_adjust(jsonb, jsonb) from public, anon, authenticated;
-- END OF QUOTATION LINE DESCRIPTION -------------------------------------

select public.functions_tidy();
