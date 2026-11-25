-- ===========================================================================
-- QUOTATION PACKAGES (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25 (the approved boards "Build quote, step by
-- step"): a client may be quoted a package, content planning and production
-- at one price set by the team (a Video Production Package of twelve reels
-- and four graphics a month), beside or instead of a plan or Rate Card
-- items; and the term discount is the team's choice per quotation.
--
-- WHAT CHANGED
--   * `quote_packages(snap, price, sel)` (internal): `sel.packages`, 1 to 5,
--     each a `name` (1 to 120), a `basis` (`month` or `once`), its `months`
--     (a monthly package's, 1 to 36 and no more than the term; the term
--     where none), its `price` (the team's, RM 0 allowed), its `items` (1
--     to 30 Rate Card lines of the quotation's card, each a `slug` once and
--     a `qty` of 1 to 999, never a plan nor a line quoted on request; a
--     content piece's `extra`, the rate for one more in the same month,
--     the card's where none) and its `incl` (up to 20 `{text, on}`: ticked
--     lines print as included, the rest under Not included). Each package
--     is ONE priced line, `kind` package: qty 1 at its price, its `detail`
--     the contents (`12 × Reels, up to 60 seconds`) then the ticked lines,
--     `excluded`, `extra` (each content piece's rate for one more),
--     `contents` (slug, name, qty, the piece's kind; never a rate) and
--     `list_amount` (the contents at the card's rates). Totals, SST, each
--     line's term percentage and the commitment are `quote_totals`', as
--     every line's. Refused `bad-package` (with the package's name) or
--     `over-term`.
--   * `quote_base` (restated): a selection of packages alone is priced as
--     one of custom lines alone is (a monthly package on a one-month term
--     `bad-term`).
--   * `quote_term_off(price)` (internal) and `sel.term_disc`: false takes
--     every term DISCOUNT off (a line's negative percentage made 0); a
--     surcharge for a short term stays. Absent or true prices as before,
--     so every quotation made before keeps its figures. Anything else is
--     `bad-term`. Kept in the totals as `term_off`.
--   * `quote_compose` (restated): packages priced per brand as everything
--     else (its keys gain `packages`), before custom lines, so Move up and
--     Move down reach them; a website selection holding packages is
--     refused `bad-package` (console only: /quote/ never offers one).
--   * `quote_files_cap` (restated): a package's graphics and reels count
--     towards the files, as the plan's and the one-time content do.
--   Nothing else moves: a package line leaves the quotation as any other
--   (a service line on approval named `{brand} · {package}` where several
--   brands, each cycle's invoice line to Bukku from it), and the PDF and
--   the link print it as one line, its inclusions under it.
--
-- ORDER: this file (connector), then the pages (Pages deploy). Nothing
-- sends `packages` or `term_disc` until the pages do, and a selection
-- without either is priced byte for byte as before (`tests/sql.js`). An old
-- tab meanwhile sends neither. Safe to run twice.
-- ROLLBACK: run `quote_base` from QUOTATION PER-LINE TERMS, `quote_compose`
-- from QUOTATION BRANDS and `quote_files_cap` from QUOTE FILES CAPPED again;
-- `quote_packages` and `quote_term_off` are then read by nothing. A
-- quotation made with a package keeps its lines and totals as kept.
-- ===========================================================================

-- QUOTATION PACKAGES -----------------------------------------------------------

/* A package: what the client receives, at one price the team sets. */
create or replace function public.quote_packages(p_snap jsonb, p_price jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_t jsonb := coalesce(p_price->'totals', '{}'::jsonb);
  v_term int := coalesce((v_t->>'term')::int, 1);
  v_lines jsonb := p_price->'lines';
  r jsonb; it jsonb; inc jsonb; s jsonb;
  i int := 0;
  v_mo int;
  v_name text;
  v_list numeric;
  v_det jsonb; v_out jsonb; v_cont jsonb; v_extra jsonb;
  v_tot jsonb;
begin
  if p_price ? 'error' or jsonb_typeof(p_price->'lines') is distinct from 'array' then return p_price; end if;
  if jsonb_typeof(p_sel->'packages') is null or jsonb_typeof(p_sel->'packages') = 'null' then return p_price; end if;
  if jsonb_typeof(p_sel->'packages') <> 'array' or jsonb_array_length(p_sel->'packages') > 5 then
    return jsonb_build_object('error', 'bad-package');
  end if;
  for r in select * from jsonb_array_elements(p_sel->'packages') loop
    i := i + 1;
    v_name := case when jsonb_typeof(r) = 'object' and jsonb_typeof(r->'name') = 'string' then btrim(r->>'name') end;
    if v_name is null or length(v_name) not between 1 and 120
       or coalesce(r->>'basis', '') not in ('month', 'once')
       or coalesce(r->>'price', '') !~ '^\d{1,7}(\.\d{1,2})?$'
       or jsonb_typeof(r->'items') is distinct from 'array' or jsonb_array_length(r->'items') not between 1 and 30
       or (jsonb_typeof(r->'incl') is not null and jsonb_typeof(r->'incl') not in ('array', 'null'))
       or (jsonb_typeof(r->'incl') = 'array' and jsonb_array_length(r->'incl') > 20) then
      return jsonb_build_object('error', 'bad-package', 'line', coalesce(v_name, i::text));
    end if;
    v_mo := 1;
    if r->>'basis' = 'month' then
      if coalesce(r->>'months', '') = '' then
        v_mo := v_term;
      elsif r->>'months' !~ '^\d{1,2}$' or (r->>'months')::int not between 1 and 36 then
        return jsonb_build_object('error', 'bad-package', 'line', v_name);
      else
        v_mo := (r->>'months')::int;
      end if;
      -- a line runs no longer than the commitment (2026-11-15)
      if v_mo > v_term then return jsonb_build_object('error', 'over-term', 'line', v_name, 'term', v_term); end if;
    end if;
    v_list := 0; v_det := '[]'::jsonb; v_out := '[]'::jsonb; v_cont := '[]'::jsonb; v_extra := '[]'::jsonb;
    for it in select * from jsonb_array_elements(r->'items') loop
      s := case when jsonb_typeof(it) = 'object' then public.quote_svc(p_snap, it->>'slug') end;
      if s is null or coalesce(s->'spec'->>'role', '') = 'plan' or jsonb_typeof(s->'rate') is distinct from 'number'
         or coalesce(it->>'qty', '') !~ '^\d{1,3}$' or (it->>'qty')::int < 1
         or (coalesce(it->>'extra', '') <> '' and it->>'extra' !~ '^\d{1,7}(\.\d{1,2})?$')
         or exists (select 1 from jsonb_array_elements(v_cont) c where c->>'slug' = s->>'slug') then
        return jsonb_build_object('error', 'bad-package', 'line', v_name);
      end if;
      v_list := v_list + (it->>'qty')::int * (s->>'rate')::numeric;
      v_cont := v_cont || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('slug', s->>'slug', 'label', s->>'name',
                  'qty', (it->>'qty')::int, 'piece', public.quote_piece_class(s->'spec'->>'kind'))));
      v_det := v_det || jsonb_build_array(((it->>'qty')::int)::text || ' × ' || (s->>'name'));
      -- the rate for one more piece in the same month: a content piece's alone
      if s->'spec'->>'role' = 'content' then
        v_extra := v_extra || jsonb_build_array(jsonb_build_object('slug', s->>'slug', 'label', s->>'name',
                     'rate', coalesce(nullif(it->>'extra', '')::numeric, (s->>'rate')::numeric)));
      end if;
    end loop;
    if jsonb_typeof(r->'incl') = 'array' then
      for inc in select * from jsonb_array_elements(r->'incl') loop
        if jsonb_typeof(inc) <> 'object' or jsonb_typeof(inc->'text') is distinct from 'string'
           or length(btrim(inc->>'text')) not between 1 and 300 or jsonb_typeof(inc->'on') is distinct from 'boolean' then
          return jsonb_build_object('error', 'bad-package', 'line', v_name);
        end if;
        if (inc->>'on')::boolean then v_det := v_det || jsonb_build_array(btrim(inc->>'text'));
        else v_out := v_out || jsonb_build_array(btrim(inc->>'text')); end if;
      end loop;
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'kind', 'package', 'key', 'package|' || i || '|' || v_name, 'label', v_name, 'detail', v_det,
      'excluded', case when jsonb_array_length(v_out) > 0 then v_out end,
      'extra', case when jsonb_array_length(v_extra) > 0 then v_extra end,
      'contents', v_cont, 'list_amount', round(v_list, 2),
      'qty', 1, 'rate', (r->>'price')::numeric, 'basis', r->>'basis', 'months', v_mo,
      'amount', round((r->>'price')::numeric, 2))));
  end loop;
  if i = 0 then return p_price; end if;
  -- each monthly package takes the percentage of its own months, as a custom line does
  if v_t ? 'bands' then v_lines := public.quote_line_pcts(v_lines, v_t->'bands', v_term); end if;
  v_tot := public.quote_totals(v_lines, v_term, coalesce((v_t->>'term_pct')::numeric, 0), coalesce((v_t->>'sst_pct')::numeric, 0));
  return p_price || jsonb_build_object('lines', v_lines,
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment', 'term_rows', v_tot->'term_rows'));
end $$;
revoke all on function public.quote_packages(jsonb, jsonb, jsonb) from public, anon, authenticated;

/* The term discount left off (`term_disc` false): a line's negative term
   percentage made 0; a surcharge for a short term stays. */
create or replace function public.quote_term_off(p_price jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_t jsonb := coalesce(p_price->'totals', '{}'::jsonb);
  v_lines jsonb;
  v_tot jsonb;
  v_pct numeric := greatest(coalesce((v_t->>'term_pct')::numeric, 0), 0);
begin
  if p_price ? 'error' or jsonb_typeof(p_price->'lines') is distinct from 'array' then return p_price; end if;
  select coalesce(jsonb_agg(case when e->>'basis' = 'month' and coalesce((e->>'pct')::numeric, (v_t->>'term_pct')::numeric, 0) < 0
                                 then e || jsonb_build_object('pct', 0) else e end order by n), '[]'::jsonb)
    into v_lines
    from jsonb_array_elements(p_price->'lines') with ordinality x(e, n);
  v_tot := public.quote_totals(v_lines, coalesce((v_t->>'term')::int, 1), v_pct, coalesce((v_t->>'sst_pct')::numeric, 0));
  return p_price || jsonb_build_object('lines', v_lines,
    'totals', v_t || jsonb_build_object('term_pct', v_pct, 'term_off', true, 'month', v_tot->'month', 'once', v_tot->'once',
                                        'commitment', v_tot->'commitment', 'term_rows', v_tot->'term_rows'));
end $$;
revoke all on function public.quote_term_off(jsonb) from public, anon, authenticated;

create or replace function public.quote_base(p_snap jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v jsonb := public.quote_price(p_snap, p_sel);
  v_set jsonb := coalesce(p_snap->'settings', '{}'::jsonb);
  v_term int;
  v_month boolean;
  v_pct numeric;
  v_if numeric;
  -- custom lines and packages (QUOTATION PACKAGES), each priced without a plan
  v_more jsonb := case when jsonb_typeof(p_sel->'custom') = 'array' then p_sel->'custom' else '[]'::jsonb end
               || case when jsonb_typeof(p_sel->'packages') = 'array' then p_sel->'packages' else '[]'::jsonb end;
begin
  v_term := case when coalesce(p_sel->>'term', '') ~ '^\d{1,2}$' then (p_sel->>'term')::int else 6 end;
  v_if := public.quote_term_pct(v_set, v_term);
  if v->>'error' is distinct from 'empty' or jsonb_array_length(v_more) = 0 then
    if v ? 'totals' then
      v := jsonb_set(v, '{totals,term_pct_if}', to_jsonb(v_if));
      -- the term settings each line's own percentage is read from (2026-11-15)
      v := jsonb_set(v, '{totals,bands}', public.quote_bands(v_set));
      v := jsonb_set(v, '{lines}', public.quote_line_pcts(v->'lines', v_set, v_term));
    end if;
    return v;
  end if;
  select coalesce(bool_or(jsonb_typeof(x) = 'object' and x->>'basis' = 'month'), false) into v_month from jsonb_array_elements(v_more) x;
  if v_month and v_term = 1 then return jsonb_build_object('error', 'bad-term'); end if;
  v_pct := case when v_month then v_if else 0 end;
  return jsonb_build_object('lines', '[]'::jsonb, 'on_request', '[]'::jsonb, 'extra_rates', '{}'::jsonb,
    'totals', jsonb_build_object('term', v_term, 'term_pct', v_pct, 'term_pct_if', v_if, 'sst_pct', coalesce((v_set->>'sst_pct')::numeric, 0), 'budget', 0,
                                 'bands', public.quote_bands(v_set)));
end $$;
revoke all on function public.quote_base(jsonb, jsonb) from public, anon, authenticated;

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
    return case when v_off then public.quote_term_off(v_p) else v_p end;
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
  return jsonb_build_object('lines', v_lines, 'on_request', v_req, 'adjusted', v_adj,
    'extra_rates', coalesce(v_rates->0->'extra_rates', '{}'::jsonb), 'brands', v_rates,
    'totals', v_first || jsonb_build_object('term_pct', v_pct, 'budget', v_budget, 'brands', v_names,
      'month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment', 'term_rows', v_tot->'term_rows'));
end $$;
revoke all on function public.quote_compose(jsonb, jsonb, boolean) from public, anon, authenticated;

/* The graphics and reels a selection makes: the plan's content option and
   additional content pieces each month, a package's contents, and the
   one-time content chosen. */
create or replace function public.quote_files_cap(p_sel jsonb, p_snap jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_g int := 0;
  v_r int := 0;
  v_plan jsonb;
  v_mix jsonb;
  v_i int := 0;
  v_k text;
  v_c text;
  v_n int;
  v_s jsonb;
  v_o jsonb;
begin
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('graphic', 0, 'reel', 0); end if;
  v_plan := public.quote_svc(p_snap, p_sel->>'plan');
  if v_plan->'spec'->>'role' = 'plan' and jsonb_typeof(v_plan->'spec'->'mix') = 'array'
     and jsonb_array_length(v_plan->'spec'->'mix') > 0 then
    if coalesce(p_sel->>'mix', '0') ~ '^[0-9]$' then v_i := coalesce((p_sel->>'mix')::int, 0); end if;
    if v_i >= jsonb_array_length(v_plan->'spec'->'mix') then v_i := 0; end if;
    v_mix := v_plan->'spec'->'mix'->v_i;
    if jsonb_typeof(v_mix) = 'object' then
      for v_k in select jsonb_object_keys(v_mix) loop
        v_c := public.quote_piece_class(v_k);
        v_n := case when coalesce(v_mix->>v_k, '') ~ '^[0-9]{1,3}$' then (v_mix->>v_k)::int else 0 end;
        if v_c = 'graphic' then v_g := v_g + v_n; elsif v_c = 'reel' then v_r := v_r + v_n; end if;
      end loop;
    end if;
    if jsonb_typeof(p_sel->'extra') = 'object' then
      for v_k in select jsonb_object_keys(p_sel->'extra') loop
        v_s := public.quote_svc(p_snap, v_k);
        if v_s->'spec'->>'role' = 'content' and coalesce(p_sel->'extra'->>v_k, '') ~ '^[0-9]{1,3}$' then
          v_c := public.quote_piece_class(v_s->'spec'->>'kind');
          v_n := (p_sel->'extra'->>v_k)::int;
          if v_c = 'graphic' then v_g := v_g + v_n; elsif v_c = 'reel' then v_r := v_r + v_n; end if;
        end if;
      end loop;
    end if;
  end if;
  -- a package's contents (QUOTATION PACKAGES, 2026-11-25)
  if jsonb_typeof(p_sel->'packages') = 'array' then
    for v_o in select it from jsonb_array_elements(p_sel->'packages') pk,
                    jsonb_array_elements(case when jsonb_typeof(pk) = 'object' and jsonb_typeof(pk->'items') = 'array' then pk->'items' else '[]'::jsonb end) it loop
      v_s := public.quote_svc(p_snap, v_o->>'slug');
      if v_s->'spec'->>'role' = 'content' and coalesce(v_o->>'qty', '') ~ '^[0-9]{1,3}$' then
        v_c := public.quote_piece_class(v_s->'spec'->>'kind');
        v_n := (v_o->>'qty')::int;
        if v_c = 'graphic' then v_g := v_g + v_n; elsif v_c = 'reel' then v_r := v_r + v_n; end if;
      end if;
    end loop;
  end if;
  if jsonb_typeof(p_sel->'once') = 'array' then
    for v_o in select * from jsonb_array_elements(p_sel->'once') loop
      v_s := public.quote_svc(p_snap, v_o->>'slug');
      if v_s->'spec'->>'role' = 'content' and coalesce(v_o->>'qty', '') ~ '^[0-9]{1,3}$' then
        v_c := public.quote_piece_class(v_s->'spec'->>'kind');
        v_n := (v_o->>'qty')::int;
        if v_c = 'graphic' then v_g := v_g + v_n; elsif v_c = 'reel' then v_r := v_r + v_n; end if;
      end if;
    end loop;
  end if;
  return jsonb_build_object('graphic', v_g, 'reel', v_r);
end $$;
revoke all on function public.quote_files_cap(jsonb, jsonb) from public, anon, authenticated;

-- END OF QUOTATION PACKAGES ---------------------------------------------------

select public.functions_tidy();
