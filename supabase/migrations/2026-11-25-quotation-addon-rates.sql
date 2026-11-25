-- ===========================================================================
-- QUOTATION ADD-ON RATES (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25 (the approved board PdfQuotationBlendV7): the
-- quotation states the rates of the add-ons a client may ask for in any
-- month of the term, as a list of rates and never a priced line or a
-- total. The team ticks which in Build quote's Extras step.
--
-- WHAT CHANGED
--   * `quote_with_addons(snap, price, sel, console)` (internal): `sel.addons`,
--     up to 200 keys the team ticked: a Rate Card add-on's slug, or
--     `extra:{slug}` for a package's rate for one more content piece. Kept
--     in the totals as `addons`, a row each `{key, kind, group, name, rate,
--     unit}`: a package's extras first (`kind` extra, its rate the
--     package's, the content's name and unit), then the card's add-ons in
--     the card's order (`kind` addon, its group, name, unit and rate from
--     the quotation's own Rate Card, in S$ where the client is billed in
--     S$). A key the card or the quotation no longer holds is left out;
--     a key that is no text, or more than 200, is `bad-addons`. No `addons`
--     key: no list, every quotation made before as it was. Never added to
--     any figure, and a website selection never holds one.
--   * `quote_compose` (restated): its answer passes through it.
--
-- ORDER: this file (connector), then the pages (Pages deploy). Until the
-- pages send `addons`, nothing changes; an old tab sends none. Safe to run
-- twice.
-- ROLLBACK: run `quote_compose` from QUOTATION PACKAGES again;
-- `quote_with_addons` is then read by nothing. A quotation made with its
-- list keeps it in its totals, which the pages draw only where present.
-- ===========================================================================

-- QUOTATION ADD-ON RATES -------------------------------------------------------

/* The rates of the add-ons a quotation states, as the team ticked them. */
create or replace function public.quote_with_addons(p_snap jsonb, p_price jsonb, p_sel jsonb, p_console boolean)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_out jsonb := '[]'::jsonb;
  x jsonb;
  s jsonb;
  v_slug text;
  v_seen text[] := '{}';
begin
  if not p_console or p_price ? 'error' or jsonb_typeof(p_sel->'addons') is null or jsonb_typeof(p_sel->'addons') = 'null' then
    return p_price;
  end if;
  if jsonb_typeof(p_sel->'addons') <> 'array' or jsonb_array_length(p_sel->'addons') > 200
     or exists (select 1 from jsonb_array_elements(p_sel->'addons') e where jsonb_typeof(e) <> 'string' or length(e #>> '{}') > 90) then
    return jsonb_build_object('error', 'bad-addons');
  end if;
  -- a package's rate for one more content piece, as the package states it,
  -- in the package's own order
  for x in select e
             from jsonb_array_elements(coalesce(p_price->'lines', '[]'::jsonb)) with ordinality l(v, i),
                  jsonb_array_elements(case when jsonb_typeof(l.v->'extra') = 'array' then l.v->'extra' else '[]'::jsonb end) with ordinality e(e, j)
            where l.v->>'kind' = 'package'
            order by l.i, e.j loop
    v_slug := x->>'slug';
    if (p_sel->'addons') ? ('extra:' || v_slug) and not (('extra:' || v_slug) = any (v_seen)) then
      s := public.quote_svc(p_snap, v_slug);
      v_out := v_out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('key', 'extra:' || v_slug, 'kind', 'extra',
        'name', coalesce(x->>'label', s->>'name'), 'rate', (x->>'rate')::numeric, 'unit', s->>'unit')));
      v_seen := v_seen || ('extra:' || v_slug);
    end if;
  end loop;
  -- the card's own add-ons, in the card's order
  for s in select e from jsonb_array_elements(coalesce(p_snap->'services', '[]'::jsonb)) e
            where e->'spec'->>'role' = 'addon' and coalesce((e->>'active')::boolean, true)
              and jsonb_typeof(e->'rate') = 'number' and (p_sel->'addons') ? (e->>'slug') loop
    if (s->>'slug') = any (v_seen) then continue; end if;
    v_out := v_out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('key', s->>'slug', 'kind', 'addon',
      'group', coalesce(nullif(btrim(s->'spec'->>'group'), ''), 'Add-ons'), 'name', s->>'name', 'rate', (s->>'rate')::numeric, 'unit', s->>'unit')));
    v_seen := v_seen || (s->>'slug');
  end loop;
  return jsonb_set(p_price, '{totals,addons}', v_out);
end $$;
revoke all on function public.quote_with_addons(jsonb, jsonb, jsonb, boolean) from public, anon, authenticated;

create or replace function public.quote_compose(p_snap jsonb, p_sel jsonb, p_console boolean)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_keys constant text[] := array['plan', 'mix', 'platforms', 'extra', 'langs', 'translate', 'budget', 'once',
                                  'edits', 'custom', 'order', 'packages'];
  v_b jsonb; v_s jsonb; v_p jsonb; v_t jsonb; v_first jsonb;
  v_lines jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_names jsonb := '[]'::jsonb; v_rates jsonb := '[]'::jsonb;
  v_i int := 0; v_adj int := 0; v_term int; v_pct numeric := 0; v_budget numeric := 0; v_name text;
  v_tot jsonb;
  v_off boolean := false;
begin
  -- Packages are the team's alone (QUOTATION PACKAGES): /quote/ never offers one.
  if not p_console and (jsonb_typeof(p_sel->'packages') = 'array'
     or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p_sel->'brands') = 'array' then p_sel->'brands' else '[]'::jsonb end) b
                 where jsonb_typeof(b) = 'object' and jsonb_typeof(b->'packages') = 'array')) then
    return jsonb_build_object('error', 'bad-package');
  end if;
  -- The term discount, the team's choice per quotation; absent prices as before.
  if p_console and p_sel ? 'term_disc' and jsonb_typeof(p_sel->'term_disc') <> 'null' then
    if jsonb_typeof(p_sel->'term_disc') <> 'boolean' then return jsonb_build_object('error', 'bad-term'); end if;
    v_off := not (p_sel->>'term_disc')::boolean;
  end if;
  if jsonb_typeof(p_sel->'brands') is null or jsonb_typeof(p_sel->'brands') = 'null' then
    v_p := public.quote_custom(public.quote_packages(p_snap, public.quote_adjust(public.quote_base(p_snap, p_sel), public.quote_tax_edits(p_sel->'edits')),
                                                     case when p_console then p_sel else '{}'::jsonb end),
                               case when p_console then p_sel else '{}'::jsonb end);
    return public.quote_with_addons(p_snap, case when v_off then public.quote_term_off(v_p) else v_p end, p_sel, p_console);
  end if;
  if not p_console or jsonb_typeof(p_sel->'brands') <> 'array' or jsonb_array_length(p_sel->'brands') not between 1 and 10 then
    return jsonb_build_object('error', 'bad-brands');
  end if;
  for v_b in select * from jsonb_array_elements(p_sel->'brands') loop
    v_name := case when jsonb_typeof(v_b) = 'object' and jsonb_typeof(v_b->'name') = 'string' then btrim(v_b->>'name') end;
    if v_name is null or length(v_name) not between 1 and 120 then
      return jsonb_build_object('error', 'bad-brands', 'brand', v_i);
    end if;
    -- the brand's own choices, on the quotation's term
    select coalesce(jsonb_object_agg(k, v_b->k), '{}'::jsonb) into v_s from unnest(v_keys) k where v_b ? k;
    v_s := v_s || jsonb_build_object('term', p_sel->'term');
    v_p := public.quote_custom(public.quote_packages(p_snap, public.quote_adjust(public.quote_base(p_snap, v_s), public.quote_tax_edits(v_s->'edits')), v_s), v_s);
    if v_off then v_p := public.quote_term_off(v_p); end if;
    if v_p ? 'error' then return v_p || jsonb_build_object('brand', v_i, 'brand_name', v_name); end if;
    v_t := coalesce(v_p->'totals', '{}'::jsonb);
    if v_first is null then v_first := v_t; end if;
    v_pct := case when coalesce((v_t->>'term_pct')::numeric, 0) <> 0 then (v_t->>'term_pct')::numeric else v_pct end;
    v_budget := v_budget + coalesce((v_t->>'budget')::numeric, 0);
    v_lines := v_lines || coalesce((select jsonb_agg(l || jsonb_build_object('brand', v_i) order by n)
                                      from jsonb_array_elements(v_p->'lines') with ordinality x(l, n)), '[]'::jsonb);
    v_req := v_req || coalesce(v_p->'on_request', '[]'::jsonb);
    v_names := v_names || jsonb_build_array(jsonb_build_object('name', v_name));
    -- each brand's own figures, for the builder's list
    v_rates := v_rates || jsonb_build_array(jsonb_build_object('name', v_name, 'extra_rates', coalesce(v_p->'extra_rates', '{}'::jsonb),
      'month', v_t->'month', 'once', v_t->'once', 'term_pct', v_t->'term_pct', 'term_rows', v_t->'term_rows'));
    v_adj := v_adj + coalesce((v_p->>'adjusted')::int, 0);
    v_i := v_i + 1;
  end loop;
  if jsonb_array_length(v_lines) = 0 and jsonb_array_length(v_req) = 0 then return jsonb_build_object('error', 'empty'); end if;
  v_term := coalesce((v_first->>'term')::int, 1);
  -- The figures, from the one calculation every quotation and letter shares.
  v_tot := public.quote_totals(v_lines, v_term, v_pct, coalesce((v_first->>'sst_pct')::numeric, 0));
  return public.quote_with_addons(p_snap, jsonb_build_object('lines', v_lines, 'on_request', v_req, 'adjusted', v_adj,
    'extra_rates', coalesce(v_rates->0->'extra_rates', '{}'::jsonb), 'brands', v_rates,
    'totals', v_first || jsonb_build_object('term_pct', v_pct, 'budget', v_budget, 'brands', v_names,
      'month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment', 'term_rows', v_tot->'term_rows')), p_sel, p_console);
end $$;
revoke all on function public.quote_compose(jsonb, jsonb, boolean) from public, anon, authenticated;

-- END OF QUOTATION ADD-ON RATES ------------------------------------------------

select public.functions_tidy();
