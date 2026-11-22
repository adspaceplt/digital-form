-- ===========================================================================
-- QUOTATION INVOICES PAID (2026-11-22)
-- ===========================================================================
-- WHY: the user, 2026-11-22, approving the Bukku structure mockup (Part 1,
-- item 5; "proceed all as recommended"): each billing cycle the portal
-- created in Bukku reads Paid or Unpaid beside it, from the copy the nightly
-- run already keeps (`bukku_docs`, kind `invoice`), by the Bukku id
-- `quotation_invoice_done` filed. A cycle finance has not approved in Bukku
-- yet is not in the copy and stays a draft.
--
-- WHAT IT CHANGES
--   * `quotation_invoices_of(p_id)`: read at Clients: Quotations View as
--     well as Billing View (`denied` below both). The amounts, the
--     advertising budget's contact and its account answer at Billing View
--     alone; a row's `paid` (true or false) and `paid_on` come from the
--     copy where its invoice is held there and not gone. Every refusal
--     before it is kept (`denied`, `not-found` outside client scope,
--     `not-reviewed`).
--
-- ORDER: this file, then the pages. A page from before reads the same
-- answer with two keys more. Nothing is written; nothing changes in Bukku.
-- Rollback: run `2026-11-17-quotation-invoices.sql`'s `quotation_invoices_of`
-- again. Safe to run twice.
-- ===========================================================================

create or replace function public.quotation_invoices_of(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  v_start date;
  v_n int;
  v_rows jsonb := '[]'::jsonb;
  i int; k text; v_lines jsonb; v_sum numeric; r public.quotation_invoices;
  v_day date;
  v_bill boolean;
  v_doc public.bukku_docs;
begin
  if (public.ops_me()).id is null
     or not (public.allowed('clients.billing', 'view') or public.allowed('clients.quotes', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  v_bill := public.allowed('clients.billing', 'view');
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  v_start := public.quotation_start(q.id);
  v_n := public.quotation_cycles(q.id);
  for i in 1 .. v_n loop
    v_day := case when v_start is not null then (v_start + make_interval(months => i - 1))::date end;
    foreach k in array array['service', 'budget'] loop
      v_lines := public.quotation_cycle_lines(q.id, i, k);
      if jsonb_array_length(v_lines) = 0 then continue; end if;
      select coalesce(sum(round((x->>'qty')::numeric * (x->>'unit')::numeric, 2)), 0) into v_sum from jsonb_array_elements(v_lines) x;
      select * into r from public.quotation_invoices x where x.quotation_id = q.id and x.cycle = i and x.kind = k;
      v_doc := null;
      if r.bukku_id is not null then
        select * into v_doc from public.bukku_docs d where d.kind = 'invoice' and d.doc_id = r.bukku_id and not d.gone;
      end if;
      v_rows := v_rows || jsonb_strip_nulls(jsonb_build_object('cycle', i, 'kind', k, 'date', v_day,
        'until', case when v_day is not null then ((v_start + make_interval(months => i))::date - 1) end,
        'amount', case when v_bill then v_sum end, 'number', r.number, 'bukku_id', r.bukku_id, 'made_at', r.made_at,
        'creating', r.claimed_at is not null and r.claimed_at > now() - interval '10 minutes' and r.number is null,
        'paid', case when v_doc.doc_id is not null then v_doc.balance <= 0 end,
        'paid_on', case when v_doc.doc_id is not null and v_doc.balance <= 0 then v_doc.paid_on end));
    end loop;
  end loop;
  return jsonb_strip_nulls(jsonb_build_object('ok', true, 'ref', q.ref, 'start', v_start, 'cycles', v_n,
    'currency', coalesce(q.totals->>'currency', 'MYR'), 'rows', v_rows, 'billing', v_bill,
    'debtor', case when v_bill then (select jsonb_build_object('contact_id', d.contact_id, 'code', d.code, 'name', d.name) from public.client_ad_debtors d where d.client_id = q.client_id) end,
    'budget_account', case when v_bill then (select b.budget_account_code from public.bukku_settings b where b.id = 1) end));
end $$;
revoke all on function public.quotation_invoices_of(uuid) from public, anon;
grant execute on function public.quotation_invoices_of(uuid) to authenticated;

-- END OF QUOTATION INVOICES PAID ---------------------------------------------
select public.functions_tidy();
