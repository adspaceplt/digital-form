-- ===========================================================================
-- QUOTATION LINES OF OUR OWN (2026-11-16)
-- ===========================================================================
-- WHY: the user, 2026-11-16: the quotation is "too tightly controlled"; a
-- client's own requirements need a line named, a title and an order of the
-- team's own, while the figures stay the database's.
--
-- WHAT IT CHANGES
--   * A line takes a name of its own for one quotation (the edit `name`, 1
--     to 120; the card's kept as `list_label`), as its description does.
--   * The quotation takes a title (`p_sel.title`, 120 at most, `bad-title`),
--     kept in its totals and printed over the lines.
--   * The lines take the order the team arranged (`p_sel.order`, the lines'
--     keys, `quote_order`, `bad-order`); the figures never move.
--   * A sent quotation's Activity line names the Rate Card in capitals.
--
-- ORDER: this file, then the pages. A page served before sends none of the
-- three and reads a quotation as before. Safe to run twice.
--
-- ROLLBACK: run the QUOTATION PER-LINE TERMS band of supabase/schema.sql
-- again (it restates every function here but quote_extras, whose last band is
-- QUOTATIONS ADVANCED), then drop function public.quote_order(jsonb, jsonb).
-- ===========================================================================


-- QUOTATION LINES OF OUR OWN -------------------------------------------------

/* The order the team arranged a quotation's lines in (2026-11-16): each
   line named in `order` by its key takes that place, the rest keep theirs
   after them. The figures never move. */
create or replace function public.quote_order(p_price jsonb, p_order jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_lines jsonb;
begin
  if p_price ? 'error' or jsonb_typeof(p_price->'lines') is distinct from 'array'
     or p_order is null or jsonb_typeof(p_order) = 'null' then
    return p_price;
  end if;
  if jsonb_typeof(p_order) <> 'array' or jsonb_array_length(p_order) > 100
     or exists (select 1 from jsonb_array_elements(p_order) o where jsonb_typeof(o) <> 'string' or length(o #>> '{}') > 300) then
    return jsonb_build_object('error', 'bad-order');
  end if;
  select coalesce(jsonb_agg(l order by coalesce(
           (select min(n) from jsonb_array_elements_text(p_order) with ordinality y(k, n) where y.k = l->>'key'), 100000 + i)), '[]'::jsonb)
    into v_lines
    from jsonb_array_elements(p_price->'lines') with ordinality x(l, i);
  return p_price || jsonb_build_object('lines', v_lines);
end $$;
revoke all on function public.quote_order(jsonb, jsonb) from public, anon, authenticated;

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
                         where jsonb_typeof(d) <> 'string' or length(btrim(d #>> '{}')) not between 1 and 300)))
         or (v_e ? 'name' and (jsonb_typeof(v_e->'name') is distinct from 'string'
             or length(btrim(v_e->>'name')) not between 1 and 120)) then
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
      /* The line's name as the team wrote it for this quotation
         (2026-11-16, the user: "if we really need some changes for this
         particular client"), the card's kept as list_label; the line's key
         stays the card's, so its other edits still find it. */
      if v_e ? 'name' and btrim(v_e->>'name') <> v_l->>'label' then
        v_l := v_l || jsonb_build_object('list_label', v_l->>'label', 'label', btrim(v_e->>'name'));
        v_hit := true;
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
  if not v_any then return public.quote_order(p_price, p_sel->'order'); end if;
  /* Each custom monthly line takes the percentage of its own months
     (2026-11-15): a one-off item beside it no longer takes the term's
     percentage away from it. */
  if v_t ? 'bands' then v_lines := public.quote_line_pcts(v_lines, v_t->'bands', v_term); end if;
  v_tot := public.quote_totals(v_lines, v_term, coalesce((v_t->>'term_pct')::numeric, 0), coalesce((v_t->>'sst_pct')::numeric, 0));
  return public.quote_order(p_price || jsonb_build_object('lines', v_lines,
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment', 'term_rows', v_tot->'term_rows')),
    p_sel->'order');
end $$;
revoke all on function public.quote_custom(jsonb, jsonb) from public, anon, authenticated;

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
    if jsonb_typeof(p_sel->'ads') <> 'array' or jsonb_array_length(p_sel->'ads') > 6 then
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
                  'budget', v_amt, 'months', v_mo, 'amount', v_amt * coalesce(v_mo, 1)));
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
          ' · Rate Card v.' || v_q.version ||
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
          ' · Rate Card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref);
end $$;
revoke all on function public.quotation_edit(uuid, jsonb) from public, anon;

-- END OF QUOTATION LINES OF OUR OWN ------------------------------------------

select public.functions_tidy();
