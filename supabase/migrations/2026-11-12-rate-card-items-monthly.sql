-- =====================================================================
-- RATE CARD ITEMS BILLED BY THE MONTH
-- 2026-11-12, the user: a one-off item of the Rate Card (a graphic, a reel)
-- may be quoted as Monthly in Build quote, with no plan and no line typed
-- by hand: `quote_adjust` takes the edit `basis` month on a one-off line,
-- prices it over the term (its months typed as any monthly line's) and
-- marks it `was_once`, so Build quote offers One-off again.
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
         or (v_e ? 'tax' and coalesce(v_e->>'tax', '') !~ '^([A-Za-z0-9._ -]{1,30})?$') then
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

/* A quotation of custom lines alone (a renewal with no plan, 2026-11-12):
   where nothing on the Rate Card is chosen, the term, its percentage and
   SST as quote_price would read them, and no line yet; quote_custom adds
   the lines and the totals. Every answer carries the term's percentage as
   if a line ran by the month (`term_pct_if`), which a one-off item made
   Monthly in quote_adjust takes. */
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
  v_if := case when v_term <= 3 then coalesce((v_set->>'term_1_3')::numeric, 0)
               when v_term <= 5 then coalesce((v_set->>'term_4_5')::numeric, 0)
               when v_term <= 11 then coalesce((v_set->>'term_6_11')::numeric, 0)
               when v_term <= 17 then coalesce((v_set->>'term_12_23')::numeric, 0)
               when v_term <= 23 then coalesce((v_set->>'term_18_23')::numeric, (v_set->>'term_12_23')::numeric, 0)
               else coalesce((v_set->>'term_24')::numeric, 0) end;
  if v->>'error' is distinct from 'empty' or jsonb_typeof(p_sel->'custom') is distinct from 'array'
     or jsonb_array_length(p_sel->'custom') = 0 then
    if v ? 'totals' then v := jsonb_set(v, '{totals,term_pct_if}', to_jsonb(v_if)); end if;
    return v;
  end if;
  select coalesce(bool_or(x->>'basis' = 'month'), false) into v_month from jsonb_array_elements(p_sel->'custom') x;
  if v_month and v_term = 1 then return jsonb_build_object('error', 'bad-term'); end if;
  v_pct := case when v_month then v_if else 0 end;
  return jsonb_build_object('lines', '[]'::jsonb, 'on_request', '[]'::jsonb, 'extra_rates', '{}'::jsonb,
    'totals', jsonb_build_object('term', v_term, 'term_pct', v_pct, 'term_pct_if', v_if, 'sst_pct', coalesce((v_set->>'sst_pct')::numeric, 0), 'budget', 0));
end $$;
revoke all on function public.quote_base(jsonb, jsonb) from public, anon, authenticated;

-- =====================================================================
-- SERVICES START ON APPROVAL
-- 2026-11-12, the user: a signed quotation's lines become the client's
-- service lines with a start, so the months they cover can be read when
-- a content month is made. Approve asks Services start; each confirmed
-- line of the quotation with no start of its own takes it.
-- =====================================================================
create or replace function public.quotation_lines_start(p_id uuid, p_start date)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q public.quotations;
  v_n int;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_start is null or p_start < date '2023-08-14' or p_start > date '2099-12-31' then return jsonb_build_object('error', 'bad-date'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  update public.client_services set start_on = p_start
   where quotation_id = q.id and client_id = q.client_id and archived_at is null and start_on is null;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.edited', q.brand, q.ref || ' · services start ' || public.register_day(p_start) || ' · ' || v_n ||
            case when v_n = 1 then ' line' else ' lines' end);
  end if;
  return jsonb_build_object('ok', true, 'lines', v_n);
end $$;
revoke all on function public.quotation_lines_start(uuid, date) from public, anon;
grant execute on function public.quotation_lines_start(uuid, date) to authenticated;

select public.functions_tidy();
