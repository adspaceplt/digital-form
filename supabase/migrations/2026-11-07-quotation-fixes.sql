-- ===========================================================================
-- QUOTATION FIXES — a one-off item at RM 0 stays its own line, never under
-- the plan's monthly inclusions; Edit in place is refused on a quotation a
-- Letter of Offer or service lines came from, as Delete is. 2026-11-07.
-- Safe to run twice. Rollback: run quote_adjust from
-- 2026-11-06-lines-included-in-the-plan.sql and quotation_edit from
-- 2026-11-06-quotation-edit-until-sent.sql again.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/sql.js compares the two.
-- ===========================================================================

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
  -- The figures, from the one calculation every quotation and letter shares.
  v_tot := public.quote_totals(v_lines, v_term, v_pct, v_sst_pct);
  return p_price || jsonb_build_object('lines', v_lines, 'adjusted', v_n,
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment'));
end $$;
revoke all on function public.quote_adjust(jsonb, jsonb) from public, anon, authenticated;

create or replace function public.quotation_edit(p_id uuid, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_c public.clients;
  v_card jsonb := public.quote_card();
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
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
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
  -- (2026-11-07), as quotation_delete holds it: Edit makes its revision.
  select count(*) into v_n from public.client_services s where s.quotation_id = v_q.id;
  if v_n > 0 then return jsonb_build_object('error', 'lines', 'count', v_n); end if;
  select d.number into v_doc from public.client_documents d
   where d.lines @> jsonb_build_array(jsonb_build_object('quotation_id', v_q.id::text))
   order by d.created_at limit 1;
  if v_doc is not null then return jsonb_build_object('error', 'letter', 'number', v_doc); end if;
  select * into v_c from public.clients where id = v_q.client_id;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- As the team builds it: their edits kept (quotation_make's console path).
  v_sel := p_sel - 'client';
  v_p := public.quote_fx_out(public.quote_adjust(public.quote_price(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id), v_fx),
           v_sel), public.quote_tax_edits(v_sel->'edits')), v_fx);
  if v_p ? 'error' then return v_p; end if;
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_was := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  update public.quotations
     set version = v_card->>'version', version_id = (v_card->>'id')::uuid, selection = v_sel,
         lines = v_p->'lines', totals = v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request'),
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
          v_q.ref || ' edited · ' ||
          coalesce(v_cur || to_char(v_was, 'FM999,999,990.00'), 'not set') || ' → ' ||
          coalesce(v_cur || to_char(v_is, 'FM999,999,990.00'), 'not set') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref);
end $$;
revoke all on function public.quotation_edit(uuid, jsonb) from public, anon;
grant execute on function public.quotation_edit(uuid, jsonb) to authenticated;

-- END OF QUOTATION FIXES ----------------------------------------------------

select public.functions_tidy();
