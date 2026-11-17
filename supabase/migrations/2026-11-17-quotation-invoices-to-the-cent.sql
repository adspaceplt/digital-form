-- ===========================================================================
-- QUOTATION INVOICES TO THE CENT (2026-11-17)
-- ===========================================================================
-- WHY: the review of the releases since #1134 (2026-11-17, the user: "fix
-- all"), findings 5 and 10 (finding 4 is bukku-sync's exact reference).
--
-- WHAT IT CHANGES
--   * `quotation_invoice_prep` locks the quotation's row before it reads
--     the cycle's claim: two presses at once on a cycle not yet started
--     waited on no row and both made a draft in Bukku.
--   * `quotation_cycle_lines`: each term percentage and SST rate's lines
--     total as the signed quotation totals them (the adjustment rounded
--     once on their subtotal, `quote_totals`); where unit prices rounded one
--     by one leave a few sen off, the group's last line carries the
--     difference as one amount (3 × RM 333.33 at +5% billed RM 1,049.99,
--     never RM 1,050.00).
--
-- ORDER: this file (connector), then bukku-sync. Safe to run twice.
--
-- ROLLBACK: run the two functions from QUOTATION INVOICES again.
-- ===========================================================================


-- QUOTATION INVOICES TO THE CENT — one draft a press, billed as the quotation totals it.

/* The lines one cycle bills. A monthly line bills each cycle up to its
   months; a one-off line the first cycle alone. Each is priced at its rate
   after its own term percentage; where rounding a unit price leaves a few
   sen off the quotation's own total for that percentage and SST rate
   (rounded once on its subtotal), the last line of the group carries the
   difference, billed as one amount;
   its SKU is the Rate Card line's, its tax Bukku's code for its rate. The
   advertising budget: each platform's monthly amount up to its months, a
   one-off amount the first cycle, no tax. */
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
          v_out := v_out || jsonb_build_object('label', 'Advertising budget · ' ||
            case lower(coalesce(e->>'platform', '')) when 'meta' then 'Meta' when 'tiktok' then 'TikTok' when 'google' then 'Google'
              when 'xhs' then 'rednote' when 'rednote' then 'rednote' else initcap(coalesce(e->>'platform', 'Other')) end,
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
    v_out := v_out || jsonb_strip_nulls(jsonb_build_object('label', coalesce(nullif(btrim(e->>'label'), ''), 'Service'),
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


/* One cycle's draft asked for: everything bukku-sync sends, read as the
   caller, the press held ten minutes; the quotation's row is locked
   first, so two presses at once on a cycle not yet started hold one. */
create or replace function public.quotation_invoice_prep(p_id uuid, p_cycle int, p_kind text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q public.quotations;
  r public.quotation_invoices;
  b public.bukku_settings;
  v_start date; v_day date; v_lines jsonb; v_contact bigint; v_ent uuid; v_cur text; v_fx numeric := 1;
  v_ref text;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind is null or p_kind not in ('service', 'budget') or p_cycle is null or p_cycle < 1 or p_cycle > 36 then
    return jsonb_build_object('error', 'bad-request');
  end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  if q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  -- A signed quotation withdrawn (QUOTATION WAYS OUT) makes no further invoice.
  if q.withdrawn_at is not null then return jsonb_build_object('error', 'withdrawn'); end if;
  v_start := public.quotation_start(q.id);
  if v_start is null then return jsonb_build_object('error', 'no-start'); end if;
  if p_cycle > public.quotation_cycles(q.id) then return jsonb_build_object('error', 'bad-request'); end if;
  v_lines := public.quotation_cycle_lines(q.id, p_cycle, p_kind);
  if jsonb_array_length(v_lines) = 0 then return jsonb_build_object('error', 'nothing'); end if;
  select * into b from public.bukku_settings where id = 1;
  if p_kind = 'budget' then
    if b.budget_account_code is null then return jsonb_build_object('error', 'no-budget-account'); end if;
    select d.contact_id into v_contact from public.client_ad_debtors d where d.client_id = q.client_id;
  end if;
  if v_contact is null then
    v_ent := nullif(q.totals->'bill_to'->>'entity_id', '')::uuid;
    if v_ent is not null then
      select l.contact_id into v_contact from public.bukku_links l where l.kind = 'entity' and l.record_id = v_ent;
    end if;
    if v_contact is null then
      select l.contact_id into v_contact from public.bukku_links l where l.kind = 'client' and l.record_id = q.client_id;
    end if;
    if v_contact is null then
      v_contact := (public.bukku_shared('client', q.client_id)->>'contact_id')::bigint;
    end if;
  end if;
  if v_contact is null then return jsonb_build_object('error', 'not-linked'); end if;
  if p_kind = 'service' and exists (select 1 from jsonb_array_elements(v_lines) x where (x->>'sst')::numeric > 0 and x->>'tax' is null) then
    return jsonb_build_object('error', 'no-tax-code');
  end if;
  v_cur := case when q.totals->>'currency' = 'SGD' then 'SGD' else 'MYR' end;
  if v_cur = 'SGD' then
    v_fx := nullif(coalesce((q.totals->>'fx')::numeric, 0), 0);
    if v_fx is null then return jsonb_build_object('error', 'no-fx'); end if;
  end if;
  select * into r from public.quotation_invoices x where x.quotation_id = q.id and x.cycle = p_cycle and x.kind = p_kind for update;
  if r.number is not null then return jsonb_build_object('error', 'invoiced', 'number', r.number); end if;
  if r.claimed_at is not null and r.claimed_at > now() - interval '10 minutes' then return jsonb_build_object('error', 'creating'); end if;
  insert into public.quotation_invoices (quotation_id, cycle, kind, claimed_at, claimed_by)
  values (q.id, p_cycle, p_kind, now(), me.id)
  on conflict (quotation_id, cycle, kind) do update set claimed_at = now(), claimed_by = me.id;
  v_day := (v_start + make_interval(months => p_cycle - 1))::date;
  -- Bukku's second number names the quotation and the cycle, so one is found again.
  v_ref := left(q.ref || ' · ' || to_char(v_day, 'YYYY-MM-DD') || case when p_kind = 'budget' then ' · Ads' else '' end, 50);
  return jsonb_build_object('ok', true, 'contact_id', v_contact, 'ref', v_ref, 'date', v_day,
    'until', ((v_start + make_interval(months => p_cycle))::date - 1), 'currency', v_cur, 'fx', v_fx,
    'kind', p_kind, 'lines', v_lines, 'account_code', case when p_kind = 'budget' then b.budget_account_code end,
    'description', left(q.brand || ' · ' || q.ref || ' · ' || public.register_day(v_day) ||
      case when p_kind = 'budget' then ' · Advertising budget' else '' end, 200));
end $$;
revoke all on function public.quotation_invoice_prep(uuid, integer, text) from public, anon;
grant execute on function public.quotation_invoice_prep(uuid, integer, text) to authenticated;


-- END OF QUOTATION INVOICES TO THE CENT ---------------------------------------

select public.functions_tidy();
