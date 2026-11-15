-- ===========================================================================
-- QUOTATION PER-LINE TERMS (2026-11-15)
-- ===========================================================================
-- WHY: the user, 2026-11-15: "per line percentage". A monthly line running
-- months other than the term took the term's percentage; a quotation also
-- priced on today's Rate Card and S$ rate whatever its Date.
--
-- WHAT IT CHANGES
--   * Each monthly line takes the term percentage of its own months' band
--     (`quote_line_pcts`, `quote_bands`); `quote_totals` adds each line's
--     percentage on its own subtotal and answers `term_rows`, one row a
--     percentage. A line runs no longer than the term (`over-term`).
--   * A quotation is priced on the Rate Card version chosen
--     (`p_sel.card`, `bad-card`), else the one live on its Date
--     (`quote_card(date, text)`, `quote_card_versions`, `rate_card_at`),
--     and on the S$ rate in force on its Date (`quote_fx(uuid, date)`).
--   * A website quotation takes no line edits on Edit.
--   * Approval confirms each line at its own percentage.
--
-- ORDER: this file, then the pages. A page served before reads `term_pct`
-- as before; `term_rows` is read only where present. Safe to run twice.
--
-- ROLLBACK: run the QUOTATION SECTIONS and QUOTATIONS ADVANCED bands of
-- schema.sql again, then revoke rate_card_at(text).
-- ===========================================================================

-- QUOTATION PER-LINE TERMS ----------------------------------------------------

/* Each monthly line's own term percentage (2026-11-15, the user: "per line
   percentage"): the band of its own months, from the term settings the
   quotation is priced on (`bands`); a one-off line takes none. A line with
   no months runs the quotation's term. */
create or replace function public.quote_line_pcts(p_lines jsonb, p_bands jsonb, p_term int)
returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(case when e->>'basis' = 'month'
           then e || jsonb_build_object('pct', public.quote_term_pct(p_bands, coalesce((e->>'months')::int, p_term)))
           else e - 'pct' end order by n), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality x(e, n)
$$;
revoke all on function public.quote_line_pcts(jsonb, jsonb, int) from public, anon, authenticated;

/* The term settings a quotation's lines are priced on, kept in its totals. */
create or replace function public.quote_bands(p_set jsonb)
returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_object_agg(k, p_set->k), '{}'::jsonb)
    from unnest(array['term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24']) k
   where p_set ? k
$$;
revoke all on function public.quote_bands(jsonb) from public, anon, authenticated;

create or replace function public.quote_totals(p_lines jsonb, p_term int, p_pct numeric, p_sst numeric)
returns jsonb
language sql immutable set search_path = public as $$
  /* Each monthly line takes its own term percentage (`pct`, 2026-11-15),
     else the quotation's (`p_pct`): a quotation made before keeps its
     figures. Each percentage's adjustment is rounded once, and SST once a
     rate, on the subtotal and the adjustments of that rate. */
  with l as (
    select e->>'basis' = 'month' as m,
           coalesce((e->>'qty')::numeric, 0) * coalesce((e->>'rate')::numeric, 0) as v,
           greatest(1, coalesce((e->>'months')::int, p_term, 1)) as mo,
           coalesce((e->>'sst')::numeric, p_sst) as r,
           case when e->>'basis' = 'month' then coalesce((e->>'pct')::numeric, p_pct, 0) else 0 end as p
      from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
  ), gp as (
    -- a rate and a percentage's own subtotals
    select r, p,
           coalesce(sum(v) filter (where m), 0) as gsub,
           coalesce(sum(round(v, 2) * mo) filter (where m), 0) as gspan,
           coalesce(sum(v) filter (where not m), 0) as gonce,
           min(mo) filter (where m) as mmin, max(mo) filter (where m) as mmax
      from l group by r, p
  ), gq as (
    select r, p, gsub, gspan, gonce, mmin, mmax, round(gsub * p / 100, 2) as goff from gp
  ), gt as (
    select coalesce(sum(round(x.sub_r * x.r / 100, 2)), 0) as sst
      from (select r, sum(gsub + goff) as sub_r from gq group by r) x
  ), go as (
    select coalesce(sum(round(gonce * r / 100, 2)), 0) as osst
      from (select r, sum(gonce) as gonce from gq group by r) y
  ), gs as (
    select coalesce(sum(round(gspan * (1 + p / 100) * (1 + r / 100), 2)), 0) as span_incl,
           coalesce(sum(round(gspan * (1 + p / 100), 2)), 0) as span_excl,
           coalesce(sum(goff), 0) as off
      from gq
  ), tp as (
    -- the adjustment a percentage, for its own row where they differ
    select coalesce(jsonb_agg(jsonb_build_object('pct', p, 'amount', a,
             'months', case when lo = hi then lo end) order by p), '[]'::jsonb) as terms
      from (select p, sum(goff) as a, min(mmin) as lo, max(mmax) as hi
              from gq where gsub > 0 and p <> 0 group by p) z
  ), s as (
    select coalesce(sum(v) filter (where m), 0) as sub,
           coalesce(bool_and(mo = p_term) filter (where m), true) as even,
           coalesce(bool_or(m), false) as month,
           coalesce(sum(v) filter (where not m), 0) as once
      from l
  ), u as (
    select s.*, gt.sst, go.osst, gs.span_incl, gs.span_excl, gs.off, tp.terms
      from s, gt, go, gs, tp
  )
  select jsonb_build_object(
    'month', case when month then jsonb_build_object('subtotal', sub, 'term', off, 'excl', sub + off, 'sst', sst, 'incl', sub + off + sst) end,
    'once', case when once > 0 then jsonb_build_object('subtotal', once, 'sst', osst, 'incl', once + osst) end,
    'even', even, 'span_excl', case when month then span_excl else 0 end, 'span_incl', case when month then span_incl else 0 end,
    'term_rows', terms,
    'commitment', case when not month then 0 when even then (sub + off + sst) * p_term else span_incl end + once + osst)
  from u
$$;
revoke all on function public.quote_totals(jsonb, integer, numeric, numeric) from public, anon, authenticated;

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
begin
  v_term := case when coalesce(p_sel->>'term', '') ~ '^\d{1,2}$' then (p_sel->>'term')::int else 6 end;
  v_if := public.quote_term_pct(v_set, v_term);
  if v->>'error' is distinct from 'empty' or jsonb_typeof(p_sel->'custom') is distinct from 'array'
     or jsonb_array_length(p_sel->'custom') = 0 then
    if v ? 'totals' then
      v := jsonb_set(v, '{totals,term_pct_if}', to_jsonb(v_if));
      -- the term settings each line's own percentage is read from (2026-11-15)
      v := jsonb_set(v, '{totals,bands}', public.quote_bands(v_set));
      v := jsonb_set(v, '{lines}', public.quote_line_pcts(v->'lines', v_set, v_term));
    end if;
    return v;
  end if;
  select coalesce(bool_or(x->>'basis' = 'month'), false) into v_month from jsonb_array_elements(p_sel->'custom') x;
  if v_month and v_term = 1 then return jsonb_build_object('error', 'bad-term'); end if;
  v_pct := case when v_month then v_if else 0 end;
  return jsonb_build_object('lines', '[]'::jsonb, 'on_request', '[]'::jsonb, 'extra_rates', '{}'::jsonb,
    'totals', jsonb_build_object('term', v_term, 'term_pct', v_pct, 'term_pct_if', v_if, 'sst_pct', coalesce((v_set->>'sst_pct')::numeric, 0), 'budget', 0,
                                 'bands', public.quote_bands(v_set)));
end $$;
revoke all on function public.quote_base(jsonb, jsonb) from public, anon, authenticated;

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
      -- a line runs no longer than the commitment (2026-11-15)
      if v_e ? 'months' and (v_e->>'months')::int > v_term then
        return jsonb_build_object('error', 'over-term', 'line', v_l->>'label', 'term', v_term);
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
  -- each monthly line's own percentage, its months as edited (2026-11-15)
  if v_t ? 'bands' then v_lines := public.quote_line_pcts(v_lines, v_t->'bands', v_term); end if;
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
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment', 'term_rows', v_tot->'term_rows'));
end $$;
revoke all on function public.quote_adjust(jsonb, jsonb) from public, anon, authenticated;

create or replace function public.quote_custom(p_price jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_t jsonb := coalesce(p_price->'totals', '{}'::jsonb);
  v_term int := coalesce((v_t->>'term')::int, 1);
  v_lines jsonb := p_price->'lines';
  r jsonb;
  d jsonb;
  i int := 0;
  v_mo int;
  v_start text;
  v_tot jsonb;
  v_any boolean := false;
begin
  if p_price ? 'error' or jsonb_typeof(p_price->'lines') is distinct from 'array' then return p_price; end if;
  if jsonb_typeof(p_sel->'custom') is not null and jsonb_typeof(p_sel->'custom') <> 'null' then
    if jsonb_typeof(p_sel->'custom') <> 'array' or jsonb_array_length(p_sel->'custom') > 30 then
      return jsonb_build_object('error', 'bad-custom');
    end if;
    for r in select * from jsonb_array_elements(p_sel->'custom') loop
      i := i + 1;
      if jsonb_typeof(r) <> 'object'
         or length(btrim(coalesce(r->>'label', ''))) not between 1 and 120
         or coalesce(r->>'qty', '') !~ '^\d{1,4}$' or (r->>'qty')::int < 1
         or coalesce(r->>'rate', '') !~ '^\d{1,7}(\.\d{1,2})?$'
         or coalesce(r->>'basis', '') not in ('month', 'once')
         or (jsonb_typeof(r->'detail') is not null and jsonb_typeof(r->'detail') not in ('array', 'null'))
         or (jsonb_typeof(r->'detail') = 'array' and jsonb_array_length(r->'detail') > 12)
         or (coalesce(r->>'renews', '') <> '' and r->>'renews' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
        return jsonb_build_object('error', 'bad-custom', 'line', coalesce(r->>'label', i::text));
      end if;
      if jsonb_typeof(r->'detail') = 'array' then
        for d in select * from jsonb_array_elements(r->'detail') loop
          if jsonb_typeof(d) <> 'string' or length(d #>> '{}') > 300 then
            return jsonb_build_object('error', 'bad-custom', 'line', r->>'label');
          end if;
        end loop;
      end if;
      v_mo := 1;
      if r->>'basis' = 'month' then
        if coalesce(r->>'months', '') !~ '^\d{1,2}$' or (r->>'months')::int not between 1 and 36 then
          return jsonb_build_object('error', 'bad-custom', 'line', r->>'label');
        end if;
        v_mo := (r->>'months')::int;
        -- a line runs no longer than the commitment (2026-11-15)
        if v_mo > v_term then return jsonb_build_object('error', 'over-term', 'line', r->>'label', 'term', v_term); end if;
      end if;
      v_start := nullif(r->>'start', '');
      if v_start is not null and (v_start !~ '^\d{4}-\d{2}-\d{2}$' or public.doc_day_of(v_start) = date '0001-01-01') then
        return jsonb_build_object('error', 'bad-custom', 'line', r->>'label');
      end if;
      v_lines := v_lines || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'kind', 'custom', 'key', 'custom|' || i || '|' || btrim(r->>'label'), 'label', btrim(r->>'label'),
        'detail', coalesce(r->'detail', '[]'::jsonb), 'qty', (r->>'qty')::numeric, 'rate', (r->>'rate')::numeric,
        'basis', r->>'basis', 'months', v_mo, 'amount', round((r->>'qty')::numeric * (r->>'rate')::numeric, 2),
        'start', v_start, 'renews', nullif(r->>'renews', ''))));
      v_any := true;
    end loop;
  end if;
  if not v_any then return p_price; end if;
  /* Each custom monthly line takes the percentage of its own months
     (2026-11-15): a one-off item beside it no longer takes the term's
     percentage away from it. */
  if v_t ? 'bands' then v_lines := public.quote_line_pcts(v_lines, v_t->'bands', v_term); end if;
  v_tot := public.quote_totals(v_lines, v_term, coalesce((v_t->>'term_pct')::numeric, 0), coalesce((v_t->>'sst_pct')::numeric, 0));
  return p_price || jsonb_build_object('lines', v_lines,
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment', 'term_rows', v_tot->'term_rows'));
end $$;
revoke all on function public.quote_custom(jsonb, jsonb) from public, anon, authenticated;

/* The S$ rate in force on the quotation's own date (2026-11-15), as its SST
   and terms are. */
create or replace function public.quote_fx(p_client uuid, p_at date)
returns numeric
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from public.clients c where c.id = p_client and c.market = 'SG' and c.bill_sgd)
              then coalesce(nullif(public.app_setting('fx_sgd', coalesce(p_at, (now() at time zone 'Asia/Kuala_Lumpur')::date)), 0), 0) end
$$;
revoke all on function public.quote_fx(uuid, date) from public, anon, authenticated;

/* The Rate Card a quotation is priced on (2026-11-15, the user: "choose
   which rate card"): the version named, else the version live on the
   quotation's date, else the first; the settings in force on that date. */
create or replace function public.quote_card(p_at date, p_version text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'version', v.version,
           'snapshot', v.snapshot || jsonb_build_object('settings',
             coalesce(v.snapshot->'settings', '{}'::jsonb) ||
             coalesce((select jsonb_object_agg(k, public.app_setting(k, p_at))
                         from unnest(array['sst_pct', 'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24']) k
                        where public.app_setting(k, p_at) is not null), '{}'::jsonb)))
    from public.rate_card_versions v
   where (nullif(p_version, '') is not null and v.version = p_version)
      or (nullif(p_version, '') is null and v.id = coalesce(
            (select x.id from public.rate_card_versions x
              where x.published_at < ((p_at + 1)::timestamp at time zone 'Asia/Kuala_Lumpur')
              order by x.published_at desc limit 1),
            (select x.id from public.rate_card_versions x order by x.published_at limit 1)))
   limit 1
$$;
revoke all on function public.quote_card(date, text) from public, anon, authenticated;

create or replace function public.quote_card(p_at date)
returns jsonb
language sql stable security definer set search_path = public as $$
  select public.quote_card(p_at, null)
$$;
revoke all on function public.quote_card(date) from public, anon, authenticated;

/* Every version a quotation may be priced on, newest first, for Build quote. */
create or replace function public.quote_card_versions()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('version', v.version, 'published_at', v.published_at)
           order by v.published_at desc), '[]'::jsonb)
    from public.rate_card_versions v
$$;
revoke all on function public.quote_card_versions() from public, anon, authenticated;

create or replace function public.quote_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_on date := public.doc_day_of(p_sel->>'date');
  v_card jsonb;
  v_cl uuid;
  v_fx numeric;
begin
  -- Priced on the quotation's own date (2026-11-12), today where none.
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  v_on := coalesce(v_on, (now() at time zone 'Asia/Kuala_Lumpur')::date);
  v_card := public.quote_card(v_on, nullif(btrim(coalesce(p_sel->>'card', '')), ''));
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', case when nullif(btrim(coalesce(p_sel->>'card', '')), '') is not null then 'bad-card' else 'no-card' end); end if;
  if coalesce(p_sel->>'client', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and public.client_scope_ok('client', (p_sel->>'client')::uuid, 'view') then
    v_cl := (p_sel->>'client')::uuid;
  end if;
  v_fx := public.quote_fx(v_cl, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- Custom lines and starts (2026-11-12) priced with the rest, before S$.
  return public.quote_fx_out(public.quote_custom(public.quote_adjust(public.quote_base(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_cl, v_on), v_fx),
           p_sel - 'client' - 'date'), public.quote_tax_edits(p_sel->'edits')), p_sel), v_fx)
         || jsonb_build_object('version', v_card->>'version', 'versions', public.quote_card_versions());
end $$;

create or replace function public.quotation_make(p_client uuid, p_sel jsonb, p_idem text, p_source text,
                                                 p_by text, p_contact jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c public.clients;
  v_on date := case when p_source = 'console' and jsonb_typeof(p_sel) = 'object' then public.doc_day_of(p_sel->>'date') end;
  v_card jsonb;
  v_p jsonb;
  v_q public.quotations;
  v_now timestamptz := now();
  v_days int;
  v_fx numeric;
  v_x jsonb;
  v_b jsonb;
  v_sel jsonb := case when jsonb_typeof(p_sel) is distinct from 'object' then p_sel
                      when p_source = 'console' then p_sel - 'client' - 'date'
                      else p_sel - 'edits' - 'client' - 'date' end;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem and q.client_id = p_client;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  /* The quotation's own date (2026-11-12, the user: a document may be
     backdated): its reference's month, its validity, and the SST and terms
     in force; a team's alone, today where none is chosen. */
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  if v_on is not null and v_on <> (v_now at time zone 'Asia/Kuala_Lumpur')::date then
    v_now := (v_on::timestamp + (v_now at time zone 'Asia/Kuala_Lumpur')::time) at time zone 'Asia/Kuala_Lumpur';
  end if;
  v_on := (v_now at time zone 'Asia/Kuala_Lumpur')::date;
  -- the Rate Card chosen in Build quote, else the one live on the date (2026-11-15)
  v_card := public.quote_card(v_on, case when p_source = 'console' then nullif(btrim(coalesce(p_sel->>'card', '')), '') end);
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_p := public.quote_fx_out(public.quote_custom(public.quote_adjust(public.quote_base(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel), public.quote_tax_edits(v_sel->'edits')), case when p_source = 'console' then v_sel else '{}'::jsonb end), v_fx);
  if v_p ? 'error' then return v_p; end if;
  /* The advertising budget and the payment terms (2026-11-12): a team's
     own; a website quotation takes none and NET 7. */
  v_x := public.quote_extras(case when p_source = 'console' then v_sel else '{}'::jsonb end);
  if v_x ? 'error' then return v_x; end if;
  if p_source = 'console' then
    v_b := public.quote_client_extras(v_c.id, v_p->'lines', v_sel);
    if v_b ? 'error' then return v_b; end if;
    v_x := v_x || v_b;
  end if;
  /* A quotation holds at least one priced line (2026-10-29): a selection of
     items quoted on request alone (a KOL campaign, a custom creator list)
     made a quotation with no line and no figure. */
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_days := coalesce((v_x->>'valid_days')::int, public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  begin
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key)
  values (public.quote_ref(v_c.name, v_now), v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, v_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request') || v_x, p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end)
  returning * into v_q;
  -- Two presses at once with one key: the second answers the first's.
  exception when unique_violation then
    select * into v_q from public.quotations q where q.idem = p_idem and q.client_id = p_client;
    if p_idem is null or v_q.id is null then raise; end if;
    return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true);
  end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_by, 'Website'), 'client.quotation', v_c.name,
          v_q.ref || ' sent · ' || coalesce('Monthly incl. SST ' || case when v_fx is null then 'RM ' else 'S$ ' end ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

create or replace function public.quotation_edit(p_id uuid, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_c public.clients;
  v_on date := public.doc_day_of(p_sel->>'date');
  v_card jsonb;
  v_ref text;
  v_was_ref text;
  v_p jsonb;
  v_fx numeric;
  v_now timestamptz := now();
  v_days int;
  v_sel jsonb;
  v_was numeric;
  v_is numeric;
  v_cur text;
  v_n int;
  v_doc text;
  v_x jsonb;
  v_b jsonb;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  if v_on is not null and v_on <> (v_now at time zone 'Asia/Kuala_Lumpur')::date then
    v_now := (v_on::timestamp + (v_now at time zone 'Asia/Kuala_Lumpur')::time) at time zone 'Asia/Kuala_Lumpur';
  end if;
  v_on := (v_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_card := public.quote_card(v_on, nullif(btrim(coalesce(p_sel->>'card', '')), ''));
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  if v_q.signed_at is not null or v_q.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = v_q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if v_q.sent_out_at is not null or v_q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  -- A quotation a letter or service lines came from keeps its figures
  -- (2026-11-07), as its removal is refused then: Edit makes its revision.
  select count(*) into v_n from public.client_services s where s.quotation_id = v_q.id;
  if v_n > 0 then return jsonb_build_object('error', 'lines', 'count', v_n); end if;
  select d.number into v_doc from public.client_documents d
   where d.lines @> jsonb_build_array(jsonb_build_object('quotation_id', v_q.id::text))
   order by d.created_at limit 1;
  if v_doc is not null then return jsonb_build_object('error', 'letter', 'number', v_doc); end if;
  select * into v_c from public.clients where id = v_q.client_id;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- As the team builds it: their edits kept (quotation_make's console path);
  -- a website quotation is never adjusted, as quotation_make holds (audit
  -- 2026-11-15).
  v_sel := case when v_q.source = 'console' then p_sel - 'client' - 'date' else p_sel - 'client' - 'date' - 'edits' end;
  v_p := public.quote_fx_out(public.quote_custom(public.quote_adjust(public.quote_base(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel), public.quote_tax_edits(v_sel->'edits')), case when v_q.source = 'console' then v_sel else '{}'::jsonb end), v_fx);
  if v_p ? 'error' then return v_p; end if;
  v_x := public.quote_extras(case when v_q.source = 'console' then v_sel else '{}'::jsonb end);
  if v_x ? 'error' then return v_x; end if;
  if v_q.source = 'console' then
    v_b := public.quote_client_extras(v_c.id, v_p->'lines', v_sel);
    if v_b ? 'error' then return v_b; end if;
    v_x := v_x || v_b;
  end if;
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_was := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_days := coalesce((v_x->>'valid_days')::int, public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  /* A team's quotation dated into another month takes that month's
     reference (it has not been sent); the one it held is kept, never
     issued again. */
  v_ref := v_q.ref; v_was_ref := v_q.ref;
  if v_q.source = 'console' and v_q.ref !~ ('^ADP/QT' || to_char(v_on, 'YYMM') || '-') then
    v_ref := public.quote_ref(v_q.brand, v_now);
    insert into public.quotation_refs_kept (ref) values (v_q.ref) on conflict do nothing;
  end if;
  update public.quotations
     set ref = v_ref, version = v_card->>'version', version_id = (v_card->>'id')::uuid, selection = v_sel,
         lines = v_p->'lines', totals = v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request') || v_x,
         -- A team's quotation is dated when it is made ready; a website one
         -- keeps the day it was asked for (its validity runs from its send).
         issued_at = case when v_q.source = 'console' then v_now else issued_at end,
         valid_until = case when v_q.source = 'console' then (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days else valid_until end
   where id = v_q.id
  returning * into v_q;
  v_is := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_cur := case when v_fx is null then 'RM ' else 'S$ ' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_c.name,
          case when v_ref <> v_was_ref then v_was_ref || ' → ' else '' end || v_q.ref || ' edited · ' ||
          coalesce(v_cur || to_char(v_was, 'FM999,999,990.00'), 'not set') || ' → ' ||
          coalesce(v_cur || to_char(v_is, 'FM999,999,990.00'), 'not set') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref);
end $$;
revoke all on function public.quotation_edit(uuid, jsonb) from public, anon;

create or replace function public.quotation_review(p_id uuid, p_ok boolean, p_note text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  c  public.clients;
  co jsonb;
  v_note text := btrim(coalesce(p_note, ''));
  v_billing text := 'kept';
  v_lines int := 0;
  v_l jsonb;
  v_admin boolean;
  v_renewed int := 0;
  v_sid uuid;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is null or q.returned_at is not null then return jsonb_build_object('error', 'not-submitted'); end if;
  -- A colleague with no role is no admin: a null here would let anyone through.
  v_admin := coalesce(me.is_admin, false) or coalesce(me.role, '') = 'admin';
  if q.reviewer_id is distinct from me.id and not v_admin then return jsonb_build_object('error', 'not-reviewer'); end if;

  if not coalesce(p_ok, false) then
    if length(v_note) < 2 or length(v_note) > 1000 then return jsonb_build_object('error', 'note-required'); end if;
    update public.quotations set returned_at = now(), return_note = v_note, returned_by = me.name where id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', q.brand, q.ref || ' · sent back by ' || me.name || ': ' || v_note);
    perform public.quote_sign_tell(array[public.quote_sign_member(q.submitted_by)], 'quote.returned',
      'Quotation sent back · ' || q.brand, q.ref || ' · ' || v_note, q.client_id, q.id::text || ':' || now()::text);
    return jsonb_build_object('ok', true, 'returned', true);
  end if;

  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  select * into c from public.clients where id = q.client_id for update;
  v_lines := 0;
  co := q.signed->'company';
  if exists (select 1 from public.bukku_links b where b.kind = 'client' and b.record_id = c.id and b.held_at is not null) then
    v_billing := 'held';
  elsif q.totals ? 'bill_to' then
    v_billing := 'kept';
  elsif coalesce(btrim(c.legal_name), '') = '' and coalesce(btrim(c.company_no), '') = '' and coalesce(btrim(c.billing_address), '') = '' then
    if not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'billing-access'); end if;
    update public.clients
       set legal_name = co->>'legal_name', company_no = co->>'company_no',
           company_no_old = coalesce(co->>'company_no_old', company_no_old), tin = coalesce(co->>'tin', tin),
           sst_no = coalesce(co->>'sst_no', sst_no), billing_address = co->>'billing_address',
           finance_email = coalesce(co->>'finance_email', finance_email)
     where id = c.id;
    v_billing := 'filled';
  end if;

  update public.client_services set state = 'confirmed'
   where quotation_id = q.id and archived_at is null and state <> 'confirmed';
  select count(*) into v_lines from public.client_services where quotation_id = q.id and archived_at is null;
  /* A renewal (2026-11-12) confirms the client's own line for its new
     term, rate and start, never a second line beside it. */
  for v_l in select * from jsonb_array_elements(q.lines) loop
    if coalesce(v_l->>'renews', '') <> '' then
      update public.client_services
         set qty = (v_l->>'qty')::numeric, rate = (v_l->>'rate')::numeric, state = 'confirmed',
             tenure = case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
             term_adjust = v_l->>'basis' = 'month', term_pct = case when v_l->>'basis' = 'month' then coalesce((v_l->>'pct')::numeric, (q.totals->>'term_pct')::numeric) else 0 end,
             start_on = coalesce(nullif(v_l->>'start', '')::date, start_on), quotation_id = q.id, note = 'Renewed by quotation ' || q.ref,
             detail = coalesce(nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''), detail)
       where id = (v_l->>'renews')::uuid and client_id = q.client_id and archived_at is null;
      if found then v_renewed := v_renewed + 1; end if;
    end if;
  end loop;
  if v_lines = 0 then
    for v_l in select * from jsonb_array_elements(q.lines) loop
      if coalesce(v_l->>'renews', '') <> '' then continue; end if;
      insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                          tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
      values (q.client_id,
              case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
              v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
              case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'confirmed',
              'Quotation ' || q.ref,
              case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
              v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then coalesce((v_l->>'pct')::numeric, (q.totals->>'term_pct')::numeric) else 0 end,
              nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
              q.id, nullif(v_l->>'tax_code', ''))
      returning id into v_sid;
      if coalesce(v_l->>'start', '') <> '' then
        update public.client_services set start_on = (v_l->>'start')::date where id = v_sid;
      end if;
      v_lines := v_lines + 1;
    end loop;
  end if;

  update public.quotations set reviewed_at = now(), reviewed_by = me.name, reviewed_role = nullif(btrim(coalesce(me.designation, '')), '')
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · reviewed and approved by ' || me.name ||
          case when q.reviewer_id is distinct from me.id then ' in place of ' || coalesce(q.reviewer_name, 'the reviewer') else '' end ||
          ' · ' || (v_lines + v_renewed) || case when v_lines + v_renewed = 1 then ' service line confirmed · ' else ' service lines confirmed · ' end ||
          case v_renewed when 0 then '' when 1 then '1 renewed · ' else v_renewed || ' renewed · ' end ||
          case v_billing when 'filled' then 'Billing filled from the signed quotation' when 'held' then 'Billing not changed, as Bukku keeps this client''s billing details'
               else 'Billing not changed' end);
  perform public.quote_sign_tell(array_remove(array[public.quote_sign_member(q.submitted_by), public.quote_sign_member(c.owner)], me.id),
    'quote.reviewed', 'Quotation approved · ' || q.brand, q.ref || ' · by ' || me.name, q.client_id, q.id::text);
  return jsonb_build_object('ok', true, 'billing', v_billing, 'lines', v_lines + v_renewed);
end $$;
revoke all on function public.quotation_review(uuid, boolean, text) from public, anon;

/* A Rate Card version for Build quote (2026-11-15): the one named, else the
   newest, with every version a quotation may be priced on. */
create or replace function public.rate_card_at(p_version text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'version', v.version, 'valid_until', v.valid_until,
           'published_at', v.published_at, 'published_by', v.published_by, 'snapshot', v.snapshot,
           'versions', public.quote_card_versions())
    from public.rate_card_versions v
   where public.is_team() and (public.allowed('services', 'view') or public.allowed('clients.services', 'view')
                                or public.allowed('clients.quotes', 'view'))
     and (nullif(p_version, '') is null or v.version = p_version)
   order by v.published_at desc
   limit 1
$$;
revoke all on function public.rate_card_at(text) from public, anon;
grant execute on function public.rate_card_at(text) to authenticated;

-- END OF QUOTATION PER-LINE TERMS ---------------------------------------------

select public.functions_tidy();
