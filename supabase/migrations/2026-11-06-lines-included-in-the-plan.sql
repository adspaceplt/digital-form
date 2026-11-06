-- ===========================================================================
-- LINES INCLUDED IN THE PLAN (2026-11-06)
-- ===========================================================================
-- WHY (the user, 2026-11-06, option A): "optionally hide 0.00 so it
-- includes together as a plan instead breaking down as free".
--
-- WHAT IT CHANGES
--   `quote_adjust` marks a line `in_plan` where the quotation holds a plan,
--   the line is not the plan and its rate is 0, unless the team unticked
--   Include in plan (the line's edit `incl: false`; any other value of
--   `incl` is refused `bad-edit`). The quotation's PDF and /quote/ list such
--   a line under the plan's inclusions, not as a row. Totals are unchanged.
--   A quotation priced before keeps its lines until it is edited.
--
-- ORDER: this file, then the pages (a page served before shows the row at
-- RM 0 as before). Safe to run twice.
--
-- ROLLBACK: run quote_adjust from 2026-10-22-tax-codes-per-line.sql again.
-- ===========================================================================

-- LINES INCLUDED IN THE PLAN ------------------------------------------------

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
         or (v_e ? 'months' and (v_l->>'basis' <> 'month' or coalesce(v_e->>'months', '') !~ '^[0-9]{1,2}$'))
         or (v_e ? 'incl' and jsonb_typeof(v_e->'incl') is distinct from 'boolean')
         or (v_e ? 'tax' and coalesce(v_e->>'tax', '') !~ '^([A-Za-z0-9._ -]{1,30})?$') then
        return jsonb_build_object('error', 'bad-edit', 'line', v_l->>'label');
      end if;
      if (v_e ? 'qty' and (v_e->>'qty')::int < 1) or (v_e ? 'months' and (v_e->>'months')::int not between 1 and 36) then
        return jsonb_build_object('error', 'bad-edit', 'line', v_l->>'label');
      end if;
      if v_e ? 'qty' and (v_e->>'qty')::numeric <> v_qty then v_qty := (v_e->>'qty')::numeric; v_hit := true; end if;
      if v_e ? 'rate' and (v_e->>'rate')::numeric <> v_rate then
        v_l := v_l || jsonb_build_object('list_rate', v_rate);
        v_rate := (v_e->>'rate')::numeric; v_hit := true;
      end if;
      if v_e ? 'months' and (v_e->>'months')::int <> v_mo then v_mo := (v_e->>'months')::int; v_hit := true; end if;
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
    if v_plan and v_l->>'kind' is distinct from 'plan' and v_rate = 0
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
  -- The figures, from the one calculation every quotation and letter shares.
  v_tot := public.quote_totals(v_lines, v_term, v_pct, v_sst_pct);
  return p_price || jsonb_build_object('lines', v_lines, 'adjusted', v_n,
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment'));
end $$;
revoke all on function public.quote_adjust(jsonb, jsonb) from public, anon, authenticated;

-- END OF LINES INCLUDED IN THE PLAN -----------------------------------------

select public.functions_tidy();
